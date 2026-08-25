// Edge Function: capture-and-classify-reply
//
// Called by Make.com after the "Pier Inbox Watcher" phantom fires, once per new
// inbox message. Flow: verify shared secret -> keep inbound only (skip Oli's own
// outbound) -> match sender to a contact by canonical linkedin_slug -> insert a
// Reply row in outreach_log -> classify sentiment/intent/outcome with Anthropic
// Sonnet -> write the classification back -> elevate a warm contact to
// "In conversation" -> return a status for Make to log.
//
// Security / conventions (mirrors update-contact-on-cr-accepted):
//   - service_role is used ONLY to construct the Supabase client at boot (below).
//     Every query is explicitly scoped to PIER_TEAM_ID because service_role
//     bypasses RLS. No service_role in request-path business logic.
//   - Custom auth: callers present `Authorization: Bearer <MAKE_SHARED_SECRET>`.
//     Deployed with verify_jwt=false so this Bearer reaches the handler.
//   - Anthropic failure is non-fatal: the reply is still captured and marked
//     reply_classification='Uncategorised', confidence=0. The function never
//     throws to the runtime; DB errors return 500.
//
// Schema reconciliations (the spec asked for shapes the live schema forbids; see
// migrations/007_outreach_log.sql and 002_enums.sql). Chosen to match how the 21
// existing touch_type='Reply' rows already look, so filters/UI treat them alike:
//   - send_status is NOT NULL (no NULL as the spec wanted). Set 'Sent' to mirror
//     existing Reply rows. ('Sent' is imperfect for an inbound message but is the
//     least-wrong existing enum value and keeps Reply rows uniform.)
//   - draft_status is NOT NULL DEFAULT 'pending_review' (no NULL). Left at
//     'pending_review' to mirror existing Reply rows; agent_produced=false keeps
//     it out of the agent-draft review queue.
//   - migrated_legacy=false (these are live-captured, not Excel-migrated).
//   - thread_id is UUID-typed; a raw LinkedIn thread token (e.g. "2-abc==") is not
//     a UUID and cannot be stored. Only a genuine UUID substring is kept, else NULL.
//   - outreach_log has no `direction` column, so the prior-thread fetch infers
//     inbound/outbound from touch_type instead of selecting a nonexistent column.
//   - The reply text is written to BOTH message_body (row content / UI) and
//     reply_content (so downstream generate-draft-from-context renders it under
//     "Reply:" rather than misattributing it to Oli).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const MAKE_SHARED_SECRET = Deno.env.get("MAKE_SHARED_SECRET") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const ANTHROPIC_MODEL = "claude-sonnet-5";
// Optional: Oli's own public LinkedIn slug, so his outbound messages are skipped
// even if the phantom mislabels direction. Safe to leave unset (the slug-match
// step already returns "orphan" for anyone who is not a Pier contact).
const OLI_LINKEDIN_SLUG = (Deno.env.get("OLI_LINKEDIN_SLUG") ?? "").toLowerCase().trim();

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

const EA_NAMES = ["PIER_Rules", "Customer_Journey_Architect", "PIER_Response_Bank"];

const CLASSIFY_INSTRUCTIONS = `
===== CLASSIFICATION TASK (return JSON only) =====
You are classifying an inbound LinkedIn reply Oli Muller (Pier Insurance) received from a prospect. Use the PIER_Rules, Customer_Journey_Architect, and PIER_Response_Bank documents above to inform your judgement.

Given the prior thread context + this new reply, return ONLY a JSON object:
{
  "reply_classification": "Positive interest" | "Neutral" | "Objection" | "Not interested" | "Out of office" | "Wrong person" | "Do not contact" | "Booked meeting" | "Uncategorised",
  "outcome": "Replied / Accepted" | "Rejected / Bounced" | "Withdrawn" | "No reply" | "Awaiting reply",
  "reasoning": "one-sentence justification",
  "confidence": 0-100
}

Never invent values. If ambiguous, use "Uncategorised" and confidence < 50. Output the JSON object and nothing else.`;

const VALID_RC = new Set([
  "Positive interest", "Neutral", "Objection", "Not interested",
  "Out of office", "Wrong person", "Do not contact", "Booked meeting", "Uncategorised",
]);
const VALID_OUTCOME = new Set([
  "Awaiting reply", "Replied / Accepted", "No reply", "Rejected / Bounced", "Withdrawn",
]);
// Outreach statuses that must NOT be overwritten by the warm-elevation step:
// 'Do not contact'/'Not relevant' are consent/qualification states (see migration 018);
// 'Left company' is a hard stop. Elevating any of these would be wrong or unsafe.
const NO_ELEVATE = new Set(["Do not contact", "Not relevant", "Left company"]);

// Canonical LinkedIn slug from a public /in/{slug} URL (matches migration 031's regex).
function extractSlug(url: string): string | null {
  const m = /linkedin\.com\/in\/([^/?#]+)/i.exec(url ?? "");
  return m ? m[1] : null;
}
// A real UUID substring (thread_id is UUID-typed); LinkedIn thread tokens rarely qualify.
function extractUuid(s: string): string | null {
  const m = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.exec(s ?? "");
  return m ? m[0] : null;
}
// First non-empty string among the given keys (handles the phantom's varying field names).
// deno-lint-ignore no-explicit-any
function pick(obj: any, keys: string[]): string {
  for (const k of keys) {
    const v = obj?.[k];
    if (typeof v === "string" && v.trim()) return v.trim();
    if (typeof v === "number") return String(v);
  }
  return "";
}

function classifyFromText(text: string): { reply_classification: string; outcome: string; reasoning: string; confidence: number } | null {
  try {
    let t = text.trim().replace(/^```[a-z]*\s*/i, "").replace(/```$/i, "").trim();
    const brace = t.match(/\{[\s\S]*\}/);
    if (brace) t = brace[0];
    const obj = JSON.parse(t);
    const rc = VALID_RC.has(obj?.reply_classification) ? obj.reply_classification : "Uncategorised";
    // Every message this function processes is an inbound reply, so a received-reply
    // outcome is the sensible default when the model omits or fumbles it.
    const outcome = VALID_OUTCOME.has(obj?.outcome) ? obj.outcome : "Replied / Accepted";
    let confidence = Number(obj?.confidence);
    if (!Number.isFinite(confidence)) confidence = 0;
    confidence = Math.max(0, Math.min(100, Math.round(confidence)));
    if (rc === "Uncategorised") confidence = Math.min(confidence, 49);
    const reasoning = typeof obj?.reasoning === "string" ? obj.reasoning.slice(0, 500) : "";
    return { reply_classification: rc, outcome, reasoning, confidence };
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  if (!MAKE_SHARED_SECRET) return json(500, { error: "server_misconfigured", detail: "MAKE_SHARED_SECRET not set" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured", detail: "PIER_TEAM_ID not set" });

  const authz = req.headers.get("authorization") ?? "";
  const token = authz.startsWith("Bearer ") ? authz.slice(7) : "";
  if (token !== MAKE_SHARED_SECRET) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  // Log the observed payload shape so Brad can confirm the phantom's real field
  // names (the LinkedIn Inbox Scraper varies). Keys only - no message content.
  try { console.log(JSON.stringify({ event: "inbox_message_shape", keys: Object.keys(body ?? {}) })); } catch { /* noop */ }

  // Tolerant field extraction (spec: handle common alternates gracefully).
  // PB LinkedIn Inbox Scraper native field names appended to each alternates list (2026-08-25).
  const senderProfileUrl = pick(body, ["senderProfileUrl", "profileUrl", "senderUrl", "publicProfileUrl", "senderProfile", "authorProfileUrl", "lastMessageFromUrl"]);
  const messageBody = pick(body, ["messageBody", "message", "text", "messageText", "snippet", "body"]);
  const messageDateRaw = pick(body, ["messageDate", "timestamp", "date", "messageDateTime", "time", "sentAt", "lastMessageDate"]);
  const threadIdRaw = pick(body, ["threadId", "thread", "threadUrl", "conversationUrl", "conversationId"]);
  const directionRaw = pick(body, ["direction", "messageDirection", "type"]).toLowerCase();
  const senderFirstName = pick(body, ["senderFirstName", "firstName", "fromFirstName", "firstnameFrom"]);
  const senderLastName = pick(body, ["senderLastName", "lastName", "fromLastName", "lastnameFrom"]);

  if (!senderProfileUrl || !messageBody) {
    return json(400, { error: "missing_required_fields", detail: "senderProfileUrl and messageBody are required" });
  }

  // PB sometimes returns lastMessageFromUrl as a non-public URL; fall back to the
  // linkedInUrls array and try each until a slug parses.
  let slug = extractSlug(senderProfileUrl);
  if (!slug && Array.isArray(body?.linkedInUrls)) {
    for (const u of body.linkedInUrls) {
      const s = extractSlug(typeof u === "string" ? u : "");
      if (s) { slug = s; break; }
    }
  }
  const slugLower = slug ? slug.toLowerCase() : "";

  // Filter to inbound only. Skip clear outbound directions or Oli's own slug.
  const OUTBOUND = new Set(["sent", "outbound", "out", "outgoing", "from_me", "self"]);
  const isOwn = !!OLI_LINKEDIN_SLUG && slugLower === OLI_LINKEDIN_SLUG;
  // PB Inbox Scraper marks Oli's own outbound messages with isLastMessageFromMe.
  const isFromMeBool = body?.isLastMessageFromMe === true || String(body?.isLastMessageFromMe).toLowerCase() === "true";
  if (isOwn || OUTBOUND.has(directionRaw) || isFromMeBool) {
    console.log(JSON.stringify({ event: "skipped", reason: "outbound_or_own", direction: directionRaw, is_own: isOwn, is_from_me_bool: isFromMeBool }));
    return json(200, { status: "skipped", reason: "outbound_or_own" });
  }

  try {
    // Match the sender to a Pier contact by canonical slug (case-insensitive).
    if (!slug) {
      console.log(JSON.stringify({ event: "orphan", reason: "unparseable_sender_url", url: senderProfileUrl }));
      return json(200, { status: "orphan", reason: "unparseable_sender_url" });
    }
    const { data: contact, error: cErr } = await supabase
      .from("contacts")
      .select("id, contact_id, company_id, connection_status, outreach_status, first_name, last_name")
      .eq("team_id", PIER_TEAM_ID).ilike("linkedin_slug", slug).limit(1).maybeSingle();
    if (cErr) throw cErr;

    if (!contact) {
      console.log(JSON.stringify({ event: "orphan", reason: "sender_not_in_pipeline", slug: slugLower }));
      return json(200, { status: "orphan", reason: "sender_not_in_pipeline" });
    }

    // Insert the reply row first, so the message is captured even if the
    // classification call later fails.
    const parsedDate = messageDateRaw && !Number.isNaN(Date.parse(messageDateRaw))
      ? new Date(messageDateRaw).toISOString()
      : new Date().toISOString();
    const today = new Date().toISOString().slice(0, 10);
    const threadUuid = extractUuid(threadIdRaw);

    const insertRow = {
      team_id: PIER_TEAM_ID,
      touch_id: `reply-${crypto.randomUUID()}`,
      contact_ref: contact.contact_id ?? null,
      contact_id: contact.id,
      company_id: contact.company_id ?? null,
      channel: "LinkedIn DM",
      touch_type: "Reply",
      message_body: messageBody,
      reply_content: messageBody,
      reply_received_at: parsedDate,
      thread_id: threadUuid,
      draft_status: "pending_review",
      send_status: "Sent",
      migrated_legacy: false,
      agent_produced: false,
      touch_date: today,
    };
    const { data: inserted, error: insErr } = await supabase
      .from("outreach_log").insert(insertRow).select("id").single();
    if (insErr) throw insErr;
    const touchRowId = inserted.id;

    // Prior thread for classification context (exclude the row we just inserted).
    // outreach_log has no `direction` column, so infer sender from touch_type.
    const { data: prevRows } = await supabase
      .from("outreach_log")
      .select("touch_date, channel, touch_type, message_body, reply_content")
      .eq("team_id", PIER_TEAM_ID).eq("contact_id", contact.id).neq("id", touchRowId)
      .gte("created_at", new Date(Date.now() - 90 * 86400000).toISOString())
      .order("touch_date", { ascending: true }).limit(10);
    const priorThread = (prevRows ?? []).map((r) => {
      const who = r.touch_type === "Reply" ? "PROSPECT" : "OLI";
      const parts = [`- ${r.touch_date ?? ""} [${r.channel ?? ""}/${r.touch_type ?? ""}] ${who}`];
      if (r.message_body) parts.push(`  ${String(r.message_body).slice(0, 400)}`);
      if (r.reply_content && r.reply_content !== r.message_body) parts.push(`  (reply: ${String(r.reply_content).slice(0, 400)})`);
      return parts.join("\n");
    }).join("\n");

    // Load EA classification docs (graceful if any are missing/inactive).
    let systemPrompt = "";
    try {
      const { data: docs, error: dErr } = await supabase
        .from("pier_ea_documents").select("name, content")
        .eq("team_id", PIER_TEAM_ID).eq("is_active", true).in("name", EA_NAMES);
      if (dErr) throw dErr;
      const byName = new Map(((docs ?? []) as Array<{ name: string; content: string }>).map((d) => [d.name, d.content]));
      const parts: string[] = [];
      for (const n of EA_NAMES) { const c = byName.get(n); if (c) parts.push(`===== ${n} =====\n${c}`); }
      systemPrompt = parts.join("\n\n");
      if (parts.length === 0) console.warn(JSON.stringify({ event: "ea_docs_empty" }));
    } catch (e) {
      console.warn(JSON.stringify({ event: "ea_docs_load_failed", message: (e as Error).message }));
      systemPrompt = "";
    }
    systemPrompt = systemPrompt + "\n\n" + CLASSIFY_INSTRUCTIONS;

    const userPrompt = `CONTACT: ${contact.first_name ?? senderFirstName} ${contact.last_name ?? senderLastName}\n\nPRIOR THREAD (oldest first; OLI = Oli's outbound, PROSPECT = their replies):\n${priorThread || "(no prior messages on record)"}\n\nNEW INBOUND REPLY TO CLASSIFY\nFrom: ${contact.first_name ?? senderFirstName} ${contact.last_name ?? senderLastName}\nReceived: ${parsedDate}\nMessage:\n${messageBody}\n\nReturn ONLY the JSON classification object.`;

    // Classify. Any failure -> Uncategorised/0, never crash.
    let cls = { reply_classification: "Uncategorised", outcome: "Replied / Accepted", reasoning: "", confidence: 0 };
    let genError = "";
    try {
      if (!ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY missing");
      const resp = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: ANTHROPIC_MODEL, max_tokens: 512, thinking: { type: "disabled" }, system: systemPrompt, messages: [{ role: "user", content: userPrompt }] }),
      });
      const data = await resp.json();
      if (!resp.ok) { genError = `http_${resp.status}: ${JSON.stringify(data).slice(0, 300)}`; throw new Error("anthropic_http_" + resp.status); }
      const text = ((data?.content ?? []) as Array<{ type: string; text?: string }>).filter((b) => b.type === "text").map((b) => b.text ?? "").join("").trim();
      const parsed = classifyFromText(text);
      if (!parsed) { genError = `unparseable: ${text.slice(0, 200)}`; throw new Error("classification_unparseable"); }
      cls = parsed;
      console.log(JSON.stringify({ event: "classified", usage: data?.usage, reply_classification: cls.reply_classification, outcome: cls.outcome, confidence: cls.confidence }));
    } catch (e) {
      if (!genError) genError = (e as Error).message ?? String(e);
      console.error(JSON.stringify({ event: "classification_failed", message: genError }));
    }

    // Write the classification back onto the captured row.
    const { error: updErr } = await supabase
      .from("outreach_log")
      .update({ reply_classification: cls.reply_classification, outcome: cls.outcome })
      .eq("id", touchRowId).eq("team_id", PIER_TEAM_ID);
    if (updErr) throw updErr;

    // Elevate to a warm state on a clearly-positive reply, but never override a
    // consent/qualification/hard-stop status.
    let elevated = false;
    if ((cls.reply_classification === "Positive interest" || cls.reply_classification === "Booked meeting")
        && !NO_ELEVATE.has(String(contact.outreach_status))
        && contact.outreach_status !== "In conversation") {
      const { error: elErr } = await supabase
        .from("contacts").update({ outreach_status: "In conversation" })
        .eq("id", contact.id).eq("team_id", PIER_TEAM_ID);
      if (elErr) throw elErr;
      elevated = true;
    }

    console.log(JSON.stringify({ event: "captured_and_classified", touch_id: touchRowId, contact_id: contact.id, reply_classification: cls.reply_classification, elevated }));
    return json(200, {
      status: "captured_and_classified",
      touch_id: touchRowId,
      contact_id: contact.id,
      reply_classification: cls.reply_classification,
      outcome: cls.outcome,
      confidence: cls.confidence,
      ai_reasoning: cls.reasoning,
      elevated,
      gen_error: genError || undefined,
    });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
