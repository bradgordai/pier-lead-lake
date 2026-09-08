// Edge Function: capture-and-classify-reply  (v17, F8 2026-09-08)
//
// Every LinkedIn inbox message reaches this function: from Make "Pier Inbox Watcher"
// (scenario 9704543, fed by the Inbox Scraper phantom's webhook every 4 hours), from the
// on-demand "Sync LinkedIn replies" button, and from backfill replays of past phantom runs.
//
// WHY v16 EXISTS. The phantom hands us LinkedIn's anonymised sender URL (/in/ACoAA...), a
// participant entity URN and a thread URL, never the public slug. v15 matched on the slug
// only, returned {status:"orphan"} for everyone else and stored nothing, so every live reply
// since the 4 Sep migration was dropped. v16 never drops a message:
//
//   MATCHING LADDER
//   (a) alias: any identifier in the payload (sender URL, entity URN, participant URLs,
//       thread URL) already learned onto contacts.linkedin_aliases -> exact match.
//   (b) slug: a public /in/<slug> in the payload against linkedin_slug / linkedin_url.
//   (c) name: firstnameFrom + lastnameFrom (diacritics folded) scoped to the team; auto-filed
//       only when exactly one candidate AND (we sent them something in the last 60 days OR
//       occupationFrom overlaps their stored title / company).
//   (d) otherwise the message lands in unmatched_replies (the Reconciliation queue). Never dropped.
//
//   ALIAS LEARNING: every successful match (auto or human assign) persists the payload's
//   identifiers onto the contact, so that sender exact-matches forever after.
//
//   OWN MESSAGES (isLastMessageFromMe=true) are Oliver's. No classify, no draft, no alert.
//   The phantom names Oliver as the sender, so the name rung reads the greeting in the body
//   ("Hi Joan", "Hallo Herr Siebel") and files only when exactly one live contact carries
//   that name AND we sent them something within 60 days of the message. Otherwise queued
//   with the candidates. Filed messages become outbound touches, which keeps threads
//   current with what Oli sends by hand and feeds sent_body.
//
//   Messages with no text (an image, a document, a reaction) are queued with a placeholder,
//   never dropped.
//
//   IDEMPOTENCY: outreach_log.external_key = sha256(threadUrl|lastMessageDate|body), unique
//   per team. Replays and the watcher re-sending the same inbox snapshot are no-ops.
//
// Actions (JSON body.action):
//   (none)            one inbox message from Make, the v15 contract, plus the new fields
//   assign            { unmatched_id, contact_id, user_id }   human match from the queue
//   dismiss           { unmatched_id }
//   sync_inbox        launch the Inbox Scraper phantom, returns container_id
//   sync_status       { container_id } -> running | done + counts (processes the result object)
//   replay_containers { container_ids[] } -> counts (backfill)
//
// Auth: scoped bearer, inbound class (Make) or internal class (Lovable). verify_jwt=false.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";
import { callAnthropicWithSentinel, BudgetExceededError } from "./_shared/anthropic-sentinel.ts";
import { contactNotesBlock, mergeAiStateOfPlay } from "./_shared/conversation-summary.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const PHANTOMBUSTER_API_KEY = Deno.env.get("PHANTOMBUSTER_API_KEY") ?? "";
const ANTHROPIC_MODEL = "claude-sonnet-5";
const PHANTOM_INBOX = "2840951049581867"; // Pier Linkedin Inbox Scraper
const OLI_LINKEDIN_SLUG = (Deno.env.get("OLI_LINKEDIN_SLUG") ?? "").toLowerCase().trim();
// Oliver's own anonymised identifier as the phantom reports it. Never learned as a contact alias.
const OLI_OPAQUE_ID = "acoaach9i3abg4iqwa2sko7j9tefp8s0qlgrfqk";
const OLI_USER_ID = "6d282957-f63b-49d6-a4de-5a9a947b4284";

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
  "confidence": 0-100,
  "state_of_play": ["2-4 short bullets for the operator's contact notes: where the conversation now stands, the key facts from this reply (who they are, what they said, what is open, any referral or date they gave) and what we are waiting for. Plain facts, no advice."]
}

CONTACT NOTES in the request are context, never permission: the gates always override anything a note says, and a note tied to a date that has passed is history, not a live instruction.

Never invent values. If ambiguous, use "Uncategorised" and confidence < 50. Output the JSON object and nothing else.`;

const VALID_RC = new Set(["Positive interest", "Neutral", "Objection", "Not interested", "Out of office", "Wrong person", "Do not contact", "Booked meeting", "Uncategorised"]);
const VALID_OUTCOME = new Set(["Awaiting reply", "Replied / Accepted", "No reply", "Rejected / Bounced", "Withdrawn"]);
const NO_ELEVATE = new Set(["Do not contact", "Not relevant", "Left company"]);

// ---------------------------------------------------------------- small helpers
// deno-lint-ignore no-explicit-any
function pick(obj: any, keys: string[]): string {
  for (const k of keys) {
    const v = obj?.[k];
    if (typeof v === "string" && v.trim()) return v.trim();
    if (typeof v === "number") return String(v);
  }
  return "";
}
const norm = (s: string) => String(s ?? "").trim().toLowerCase().replace(/\/+$/, "");
const foldAscii = (s: string) => String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/ß/g, "ss");
const normName = (s: string) => foldAscii(s).toLowerCase().replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim();
/** The counterparty's name as addressed in the opening line of Oliver's own message. */
function greetingName(body: string): { kind: "first" | "last"; name: string } | null {
  const first = String(body ?? "").trim().split(/\r?\n/)[0] ?? "";
  const m = /^(?:hi|hey|hello|hallo|hoi|moin|servus|dear|guten\s+tag|guten\s+morgen|liebe[rs]?|sehr\s+geehrte[rs]?)\s+(?:(herr|frau|mr|mrs|ms|dr)\.?\s+)?([^\s,!.:;]+)/i.exec(first);
  if (!m) return null;
  const name = m[2].replace(/[^\p{L}\p{M}'-]/gu, "");
  if (name.length < 2) return null;
  return { kind: m[1] ? "last" : "first", name };
}
async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function extractSlug(url: string): string | null {
  const m = /linkedin\.com\/in\/([^/?#]+)/i.exec(url ?? "");
  if (!m) return null;
  // Anonymised identifiers are not slugs.
  if (/^acoaa/i.test(m[1])) return null;
  return m[1];
}
function extractUuid(s: string): string | null {
  const m = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.exec(s ?? "");
  return m ? m[0] : null;
}
function isOli(id: string): boolean {
  const n = norm(id);
  return n.includes(OLI_OPAQUE_ID) || (!!OLI_LINKEDIN_SLUG && n.includes(`/in/${OLI_LINKEDIN_SLUG}`));
}
function toBool(v: unknown): boolean { return v === true || String(v).toLowerCase() === "true"; }
function toList(v: unknown): string[] {
  if (Array.isArray(v)) return v.map((x) => String(x ?? "").trim()).filter(Boolean);
  if (typeof v === "string") return v.split(/[,\s]+/).map((x) => x.trim()).filter((x) => x.startsWith("http"));
  return [];
}

type Payload = {
  message: string; threadUrl: string; timestamp: string; lastMessageDate: string;
  firstnameFrom: string; lastnameFrom: string; occupationFrom: string;
  lastMessageFromUrl: string; lastMessageFromEntityUrn: string; linkedInUrls: string[];
  isLastMessageFromMe: boolean; readStatus: boolean;
};
// deno-lint-ignore no-explicit-any
function parsePayload(body: any): Payload {
  return {
    message: pick(body, ["message", "messageBody", "text", "messageText", "snippet", "body"]),
    threadUrl: pick(body, ["threadUrl", "threadId", "thread", "conversationUrl", "conversationId"]),
    timestamp: pick(body, ["timestamp"]),
    lastMessageDate: pick(body, ["lastMessageDate", "messageDate", "date", "messageDateTime", "sentAt"]),
    firstnameFrom: pick(body, ["firstnameFrom", "senderFirstName", "firstName"]),
    lastnameFrom: pick(body, ["lastnameFrom", "senderLastName", "lastName"]),
    occupationFrom: pick(body, ["occupationFrom", "occupation", "headline"]),
    lastMessageFromUrl: pick(body, ["lastMessageFromUrl", "senderProfileUrl", "profileUrl", "senderUrl", "publicProfileUrl"]),
    lastMessageFromEntityUrn: pick(body, ["lastMessageFromEntityUrn", "entityUrn"]),
    linkedInUrls: toList(body?.linkedInUrls),
    isLastMessageFromMe: toBool(body?.isLastMessageFromMe),
    readStatus: toBool(body?.readStatus),
  };
}
/** Identifiers that can name the COUNTERPARTY of this thread. Oliver's own ids are excluded. */
function counterpartyIds(p: Payload): string[] {
  const ids = new Set<string>();
  if (!p.isLastMessageFromMe) {
    if (p.lastMessageFromUrl) ids.add(norm(p.lastMessageFromUrl));
    if (p.lastMessageFromEntityUrn) ids.add(norm(p.lastMessageFromEntityUrn));
  }
  for (const u of p.linkedInUrls) ids.add(norm(u));
  if (p.threadUrl) ids.add(norm(p.threadUrl));
  return Array.from(ids).filter((x) => x && !isOli(x));
}
async function externalKey(p: Payload): Promise<string> {
  return await sha256Hex(`${norm(p.threadUrl)}|${p.lastMessageDate || p.timestamp}|${p.message.trim()}`);
}
function messageDateIso(p: Payload): string {
  const raw = p.lastMessageDate || p.timestamp;
  return raw && !Number.isNaN(Date.parse(raw)) ? new Date(raw).toISOString() : new Date().toISOString();
}

// ---------------------------------------------------------------- alias learning
// deno-lint-ignore no-explicit-any
async function learnAliases(contactId: string, ids: string[], current?: any): Promise<void> {
  const fresh = ids.map(norm).filter((x) => x && !isOli(x));
  if (!fresh.length) return;
  let existing: string[] = Array.isArray(current) ? current : [];
  if (!Array.isArray(current)) {
    const { data } = await supabase.from("contacts").select("linkedin_aliases").eq("id", contactId).maybeSingle();
    existing = Array.isArray(data?.linkedin_aliases) ? data!.linkedin_aliases : [];
  }
  const merged = Array.from(new Set([...existing.map(norm), ...fresh]));
  if (merged.length === existing.length) return;
  await supabase.from("contacts").update({ linkedin_aliases: merged }).eq("id", contactId).eq("team_id", PIER_TEAM_ID);
}

// ---------------------------------------------------------------- matching ladder
type Candidate = { contact_id: string; full_name: string; job_title: string | null; company_name: string | null; last_outbound: string | null; score: number };
type Match = { contactId: string | null; rung: "alias" | "slug" | "name" | "none"; candidates: Candidate[] };

function occupationOverlap(occupation: string, title: string | null, company: string | null): boolean {
  const occ = normName(occupation);
  if (!occ) return false;
  const words = (s: string) => normName(s).split(" ").filter((w) => w.length > 3);
  const co = normName(company ?? "");
  if (co && occ.includes(co)) return true;
  const hits = words(title ?? "").filter((w) => occ.includes(w));
  return hits.length >= 2 || (hits.length === 1 && words(title ?? "").length === 1);
}

async function matchContact(p: Payload): Promise<Match> {
  const ids = counterpartyIds(p);
  // (a) alias
  if (ids.length) {
    const { data } = await supabase.rpc("fn_match_contact_by_alias", { p_team_id: PIER_TEAM_ID, p_ids: ids });
    if (data) return { contactId: String(data), rung: "alias", candidates: [] };
  }
  // (b) public slug anywhere in the payload
  const urls = [p.lastMessageFromUrl, ...p.linkedInUrls].filter(Boolean);
  for (const u of urls) {
    const slug = extractSlug(u);
    if (!slug || isOli(u)) continue;
    const { data } = await supabase.from("contacts").select("id")
      .eq("team_id", PIER_TEAM_ID).is("archived_at", null)
      .or(`linkedin_slug.ilike.${slug},linkedin_url.ilike.%/in/${slug}%,linkedin_sales_nav_url.ilike.%/in/${slug}%`)
      .limit(1).maybeSingle();
    if (data?.id) return { contactId: data.id, rung: "slug", candidates: [] };
  }
  // (c) name. For a prospect's message the phantom gives us their name; for Oliver's own
  //     message the only name is the greeting in the body.
  const msgAt = Date.parse(messageDateIso(p));
  const isRecent = (lastOutbound: string | null) =>
    !!lastOutbound && Math.abs(msgAt - Date.parse(lastOutbound)) <= 60 * 86400000;
  // deno-lint-ignore no-explicit-any
  const toCands = (rows: any[], useOcc: boolean): Candidate[] => rows.map((r) => {
    const recent = isRecent(r.last_outbound ?? null);
    const occ = useOcc && occupationOverlap(p.occupationFrom, r.job_title, r.company_name);
    return {
      contact_id: r.id, full_name: `${r.first_name ?? ""} ${r.last_name ?? ""}`.trim(), job_title: r.job_title ?? null,
      company_name: r.company_name ?? null, last_outbound: r.last_outbound ?? null,
      score: 50 + (recent ? 30 : 0) + (occ ? 20 : 0),
    };
  }).sort((a, b) => b.score - a.score);

  if (p.isLastMessageFromMe) {
    const g = greetingName(p.message);
    if (!g) return { contactId: null, rung: "none", candidates: [] };
    const fn = g.kind === "last" ? "fn_match_contacts_by_name" : "fn_match_contacts_by_first_name";
    const args = g.kind === "last"
      ? { p_team_id: PIER_TEAM_ID, p_last: g.name, p_last_ascii: foldAscii(g.name) }
      : { p_team_id: PIER_TEAM_ID, p_first: g.name, p_first_ascii: foldAscii(g.name) };
    const { data: rows } = await supabase.rpc(fn, args);
    // deno-lint-ignore no-explicit-any
    const cands = toCands((rows ?? []) as any[], false);
    // A greeting is weaker evidence than a full name: file only with a recent outbound.
    if (cands.length === 1 && cands[0].score >= 80) return { contactId: cands[0].contact_id, rung: "name", candidates: cands };
    return { contactId: null, rung: "none", candidates: cands.slice(0, 5) };
  }

  if (!p.lastnameFrom) return { contactId: null, rung: "none", candidates: [] };
  const { data: rows } = await supabase.rpc("fn_match_contacts_by_name", { p_team_id: PIER_TEAM_ID, p_last: p.lastnameFrom, p_last_ascii: foldAscii(p.lastnameFrom) });
  const wantFirst = normName(p.firstnameFrom);
  // deno-lint-ignore no-explicit-any
  const cands = toCands(((rows ?? []) as any[])
    .filter((r) => !wantFirst || normName(r.first_name ?? "") === wantFirst || normName(r.first_name ?? "").startsWith(wantFirst.split(" ")[0])), true);
  if (cands.length === 1 && cands[0].score >= 70) return { contactId: cands[0].contact_id, rung: "name", candidates: cands };
  return { contactId: null, rung: "none", candidates: cands.slice(0, 5) };
}

// ---------------------------------------------------------------- Move to Monday alert (B8)
async function raiseMoveToMondayAlert(companyId: string | null, touchRowId: string): Promise<void> {
  if (!companyId) return;
  try {
    const { data: open } = await supabase.from("company_alerts").select("id, trigger_count")
      .eq("team_id", PIER_TEAM_ID).eq("company_id", companyId).eq("alert_type", "move_to_monday").eq("status", "open").limit(1).maybeSingle();
    if (open) {
      await supabase.from("company_alerts").update({ last_seen_at: new Date().toISOString(), trigger_count: (open.trigger_count ?? 1) + 1, triggered_by_touch_id: touchRowId }).eq("id", open.id);
      return;
    }
    await supabase.from("company_alerts").insert({ team_id: PIER_TEAM_ID, company_id: companyId, alert_type: "move_to_monday", status: "open", triggered_by_touch_id: touchRowId });
  } catch (e) {
    console.error(JSON.stringify({ event: "move_to_monday_alert_failed", company_id: companyId, message: (e as Error).message ?? String(e) }));
  }
}

// ---------------------------------------------------------------- classification
function classifyFromText(text: string): { reply_classification: string; outcome: string; reasoning: string; confidence: number; state_of_play: string[] } | null {
  try {
    let t = text.trim().replace(/^```[a-z]*\s*/i, "").replace(/```$/i, "").trim();
    const brace = t.match(/\{[\s\S]*\}/);
    if (brace) t = brace[0];
    const obj = JSON.parse(t);
    const rc = VALID_RC.has(obj?.reply_classification) ? obj.reply_classification : "Uncategorised";
    const outcome = VALID_OUTCOME.has(obj?.outcome) ? obj.outcome : "Replied / Accepted";
    let confidence = Number(obj?.confidence);
    if (!Number.isFinite(confidence)) confidence = 0;
    confidence = Math.max(0, Math.min(100, Math.round(confidence)));
    if (rc === "Uncategorised") confidence = Math.min(confidence, 49);
    const reasoning = typeof obj?.reasoning === "string" ? obj.reasoning.slice(0, 500) : "";
    const state_of_play = Array.isArray(obj?.state_of_play)
      ? obj.state_of_play.filter((b: unknown) => typeof b === "string" && String(b).trim()).slice(0, 4).map((b: string) => b.trim()) : [];
    return { reply_classification: rc, outcome, reasoning, confidence, state_of_play };
  } catch { return null; }
}

// deno-lint-ignore no-explicit-any
async function classify(contact: any, touchRowId: string, messageBody: string, receivedIso: string) {
  const { data: prevRows } = await supabase.from("outreach_log")
    .select("touch_date, channel, touch_type, message_body, reply_content, sent_body")
    .eq("team_id", PIER_TEAM_ID).eq("contact_id", contact.id).neq("id", touchRowId)
    .gte("created_at", new Date(Date.now() - 90 * 86400000).toISOString())
    .order("touch_date", { ascending: true }).limit(10);
  const priorThread = (prevRows ?? []).map((r) => {
    const who = r.touch_type === "Reply" ? "PROSPECT" : "OLI";
    const body = r.touch_type === "Reply" ? (r.reply_content ?? r.message_body) : (r.sent_body ?? r.message_body);
    return `- ${r.touch_date ?? ""} [${r.channel ?? ""}/${r.touch_type ?? ""}] ${who}\n  ${String(body ?? "").slice(0, 400)}`;
  }).join("\n");

  let systemPrompt = "";
  let eaDocsLoaded = false;
  try {
    const { data: docs } = await supabase.from("pier_ea_documents").select("name, content").eq("team_id", PIER_TEAM_ID).eq("is_active", true).in("name", EA_NAMES);
    const byName = new Map(((docs ?? []) as Array<{ name: string; content: string }>).map((d) => [d.name, d.content]));
    const parts: string[] = [];
    for (const n of EA_NAMES) { const c = byName.get(n); if (c) parts.push(`===== ${n} =====\n${c}`); }
    systemPrompt = parts.join("\n\n");
    eaDocsLoaded = parts.length > 0;
  } catch (e) { console.warn(JSON.stringify({ event: "ea_docs_load_failed", message: (e as Error).message })); }
  systemPrompt = systemPrompt + "\n\n" + CLASSIFY_INSTRUCTIONS;
  // deno-lint-ignore no-explicit-any
  const systemParam: any = eaDocsLoaded ? [{ type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } }] : systemPrompt;
  const today = new Date().toISOString().slice(0, 10);
  const notesBlock = contactNotesBlock({ next_action: contact.next_action, next_action_date: contact.next_action_date, background_notes: contact.background_notes, conversation_summary: contact.conversation_summary, today });
  const name = `${contact.first_name ?? ""} ${contact.last_name ?? ""}`.trim();
  const userPrompt = `CONTACT: ${name}\n\n${notesBlock}\n\nPRIOR THREAD (oldest first; OLI = Oli's outbound, PROSPECT = their replies):\n${priorThread || "(no prior messages on record)"}\n\nNEW INBOUND REPLY TO CLASSIFY\nFrom: ${name}\nReceived: ${receivedIso}\nMessage:\n${messageBody}\n\nReturn ONLY the JSON classification object.`;

  let cls = { reply_classification: "Uncategorised", outcome: "Replied / Accepted", reasoning: "", confidence: 0, state_of_play: [] as string[] };
  let genError = "";
  try {
    if (!ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY missing");
    const result = await callAnthropicWithSentinel({
      model: ANTHROPIC_MODEL, max_tokens: 512, thinking: { type: "disabled" }, system: systemParam,
      messages: [{ role: "user", content: userPrompt }], function_name: "capture-and-classify-reply", team_id: PIER_TEAM_ID,
      request_context: { contact_id: contact.id, touch_id: touchRowId, purpose: "reply_classification" }, supabase, anthropic_api_key: ANTHROPIC_API_KEY,
    });
    const parsed = classifyFromText(result.content);
    if (!parsed) { genError = `unparseable: ${result.content.slice(0, 200)}`; throw new Error("classification_unparseable"); }
    cls = parsed;
  } catch (e) {
    if (e instanceof BudgetExceededError) genError = `budget_blocked: ${e.message}`;
    else if (!genError) genError = (e as Error).message ?? String(e);
    console.error(JSON.stringify({ event: "classification_failed", touch_id: touchRowId, message: genError }));
  }
  return { cls, genError };
}

// ---------------------------------------------------------------- filing
type FileResult = { outcome: "filed_inbound" | "filed_own_message" | "duplicate"; touch_id: string | null; classification?: string };

async function existingByKey(key: string): Promise<string | null> {
  const { data } = await supabase.from("outreach_log").select("id").eq("team_id", PIER_TEAM_ID).eq("external_key", key).limit(1).maybeSingle();
  return data?.id ?? null;
}

/** Oliver's own message: record it as an outbound touch on the thread if it is not already there. */
async function fileOwnMessage(contactId: string, p: Payload, key: string): Promise<FileResult> {
  const dup = await existingByKey(key);
  if (dup) return { outcome: "duplicate", touch_id: dup };
  const body = p.message.trim();
  const when = messageDateIso(p);
  const day = when.slice(0, 10);
  // A manually logged or migrated touch on the same day with the same opening text is the same message.
  const { data: same } = await supabase.from("outreach_log").select("id")
    .eq("team_id", PIER_TEAM_ID).eq("contact_id", contactId).neq("touch_type", "Reply").eq("touch_date", day)
    .ilike("message_body", `${body.slice(0, 40).replace(/[%_]/g, "")}%`).limit(1).maybeSingle();
  if (same?.id) {
    await supabase.from("outreach_log").update({ external_key: key }).eq("id", same.id);
    return { outcome: "duplicate", touch_id: same.id };
  }
  const { data: contact } = await supabase.from("contacts").select("contact_id, company_id, chase_state, chase_last_outbound_at").eq("id", contactId).maybeSingle();
  const { count: prior } = await supabase.from("outreach_log").select("id", { count: "exact", head: true })
    .eq("team_id", PIER_TEAM_ID).eq("contact_id", contactId).neq("touch_type", "Reply").eq("send_status", "Sent");
  const { data: ins, error } = await supabase.from("outreach_log").insert({
    team_id: PIER_TEAM_ID, touch_id: `inbox-${crypto.randomUUID()}`, contact_ref: contact?.contact_id ?? null, contact_id: contactId,
    company_id: contact?.company_id ?? null, channel: "LinkedIn DM", touch_type: (prior ?? 0) > 0 ? "Follow up" : "Initial message",
    message_body: body, sent_body: body, subject_line: null, draft_status: "sent", send_status: "Sent", sent_by: "Oliver",
    sent_at_actual: when, touch_date: day, agent_produced: false, migrated_legacy: false, external_key: key,
    thread_id: extractUuid(p.threadUrl),
  }).select("id").single();
  if (error) throw error;
  // Oli answered: the chase restarts from this outbound.
  const patch: Record<string, unknown> = { last_contacted: day };
  if (contact?.chase_state === "replied") patch.chase_state = "awaiting_reply";
  await supabase.from("contacts").update(patch).eq("id", contactId).eq("team_id", PIER_TEAM_ID);
  return { outcome: "filed_own_message", touch_id: ins.id };
}

/** A prospect's reply: verbatim touch, classification, notes, chase state, chaser supersede, alert. */
async function fileInbound(contactId: string, p: Payload, key: string): Promise<FileResult> {
  const dup = await existingByKey(key);
  if (dup) return { outcome: "duplicate", touch_id: dup };
  const body = p.message.trim();
  const when = messageDateIso(p);
  const day = when.slice(0, 10);
  // Legacy rows (pre-F8) carry no external_key; the same reply on the same day with the same
  // opening text is the same reply.
  const { data: same } = await supabase.from("outreach_log").select("id")
    .eq("team_id", PIER_TEAM_ID).eq("contact_id", contactId).eq("touch_type", "Reply").eq("touch_date", day)
    .ilike("reply_content", `${body.slice(0, 40).replace(/[%_]/g, "")}%`).limit(1).maybeSingle();
  if (same?.id) {
    await supabase.from("outreach_log").update({ external_key: key }).eq("id", same.id);
    return { outcome: "duplicate", touch_id: same.id };
  }
  const { data: contact, error: cErr } = await supabase.from("contacts")
    .select("id, contact_id, company_id, first_name, last_name, connection_status, outreach_status, next_action, next_action_date, background_notes, conversation_summary")
    .eq("team_id", PIER_TEAM_ID).eq("id", contactId).maybeSingle();
  if (cErr || !contact) throw cErr ?? new Error("contact_not_found");

  const { data: inserted, error: insErr } = await supabase.from("outreach_log").insert({
    team_id: PIER_TEAM_ID, touch_id: `reply-${crypto.randomUUID()}`, contact_ref: contact.contact_id ?? null, contact_id: contact.id,
    company_id: contact.company_id ?? null, channel: "LinkedIn DM", touch_type: "Reply", message_body: body, reply_content: body,
    reply_received_at: when, thread_id: extractUuid(p.threadUrl), draft_status: "pending_review", send_status: "Sent",
    migrated_legacy: false, agent_produced: false, touch_date: day, external_key: key,
  }).select("id").single();
  if (insErr) throw insErr;
  const touchRowId = inserted.id;

  const { cls, genError } = await classify(contact, touchRowId, body, when);
  await supabase.from("outreach_log").update({ reply_classification: cls.reply_classification, outcome: cls.outcome }).eq("id", touchRowId);

  // Notes: refresh the AI state of play under the marker.
  if (cls.state_of_play.length) {
    try {
      const merged = mergeAiStateOfPlay(contact.conversation_summary, cls.state_of_play, `${day}, reply classified: ${cls.reply_classification}`);
      await supabase.from("contacts").update({ conversation_summary: merged }).eq("id", contact.id).eq("team_id", PIER_TEAM_ID);
    } catch (e) { console.error(JSON.stringify({ event: "conversation_summary_update_failed", contact_id: contact.id, message: (e as Error).message })); }
  }

  // Chase state: a reply ends the chase (fn_chase_candidates and fn_evaluate_gates both honour this).
  const patch: Record<string, unknown> = { chase_state: "replied", chase_next_due_at: null };
  if ((cls.reply_classification === "Positive interest" || cls.reply_classification === "Booked meeting")
      && !NO_ELEVATE.has(String(contact.outreach_status)) && contact.outreach_status !== "In conversation") {
    patch.outreach_status = "In conversation";
  }
  await supabase.from("contacts").update(patch).eq("id", contact.id).eq("team_id", PIER_TEAM_ID);

  // Supersede any pending chaser draft: the chase is over.
  const { data: pend } = await supabase.from("outreach_log").select("id, touch_type")
    .eq("team_id", PIER_TEAM_ID).eq("contact_id", contact.id).eq("draft_status", "pending_review").in("touch_type", ["Chaser 1", "Chaser 2", "Chaser 3"]);
  for (const d of pend ?? []) {
    await supabase.from("outreach_log").update({ draft_status: "superseded", rejection_feedback: { reason: "reply_received", detail: `Superseded: the contact replied on ${day} (reply touch ${touchRowId}).` } }).eq("id", d.id);
    try {
      await supabase.from("audit_log").insert({ team_id: PIER_TEAM_ID, entity_type: "outreach_log", entity_id: d.id, action: "superseded",
        summary: `${d.touch_type} draft superseded: the contact replied on ${day}.`, after_value: { reply_touch_id: touchRowId }, source: "capture-and-classify-reply" });
    } catch { /* audit must never mask the state change */ }
  }

  await raiseMoveToMondayAlert(contact.company_id ?? null, touchRowId);
  console.log(JSON.stringify({ event: "captured_and_classified", touch_id: touchRowId, contact_id: contact.id, reply_classification: cls.reply_classification, gen_error: genError || undefined }));
  return { outcome: "filed_inbound", touch_id: touchRowId, classification: cls.reply_classification };
}

async function queueOrphan(p: Payload, key: string, candidates: Candidate[]): Promise<"queued" | "already_queued"> {
  const { error } = await supabase.from("unmatched_replies").insert({
    team_id: PIER_TEAM_ID, external_key: key, thread_url: p.threadUrl || null, sender_url: p.lastMessageFromUrl || null,
    sender_urn: p.lastMessageFromEntityUrn || null, sender_first_name: p.firstnameFrom || null, sender_last_name: p.lastnameFrom || null,
    sender_occupation: p.occupationFrom || null, message_body: p.message.trim(), message_at: messageDateIso(p), is_from_me: p.isLastMessageFromMe,
    payload: p, candidates, status: "open",
  });
  if (error) {
    if (String(error.code) === "23505") return "already_queued";
    throw error;
  }
  return "queued";
}

type Counts = { processed: number; matched: number; own_threaded: number; queued: number; duplicates: number; skipped: number };
const zero = (): Counts => ({ processed: 0, matched: 0, own_threaded: 0, queued: 0, duplicates: 0, skipped: 0 });

/** One inbox message through the ladder. Returns the outcome for the counts and for Make. */
// deno-lint-ignore no-explicit-any
async function processPayload(body: any, counts: Counts): Promise<Record<string, unknown>> {
  const p = parsePayload(body);
  counts.processed++;
  if (!p.message && !p.threadUrl) { counts.skipped++; return { status: "skipped", reason: "empty_payload" }; }
  if (!p.message) p.message = "(no text: an image, a document or a reaction)";
  const key = await externalKey(p);
  const dup = await existingByKey(key);
  if (dup) { counts.duplicates++; return { status: "duplicate", touch_id: dup }; }
  const m = await matchContact(p);
  if (m.contactId) {
    await learnAliases(m.contactId, counterpartyIds(p));
    const r = p.isLastMessageFromMe ? await fileOwnMessage(m.contactId, p, key) : await fileInbound(m.contactId, p, key);
    if (r.outcome === "duplicate") counts.duplicates++;
    else if (r.outcome === "filed_own_message") counts.own_threaded++;
    else counts.matched++;
    // If an earlier pass queued this message, the queue entry is now resolved.
    await supabase.from("unmatched_replies").update({ status: "assigned", assigned_contact_id: m.contactId, assigned_at: new Date().toISOString(), created_touch_id: r.touch_id })
      .eq("team_id", PIER_TEAM_ID).eq("external_key", key).eq("status", "open");
    return { status: r.outcome, contact_id: m.contactId, touch_id: r.touch_id, rung: m.rung, reply_classification: r.classification };
  }
  const q = await queueOrphan(p, key, m.candidates);
  if (q === "queued") counts.queued++; else counts.duplicates++;
  return { status: q, reason: "no_match", candidates: m.candidates.length, is_from_me: p.isLastMessageFromMe };
}

// ---------------------------------------------------------------- PhantomBuster
async function pb(path: string, init?: RequestInit) {
  const r = await fetch(`https://api.phantombuster.com/api/v2/${path}`, { ...init, headers: { "X-Phantombuster-Key-1": PHANTOMBUSTER_API_KEY, "content-type": "application/json", ...(init?.headers ?? {}) } });
  const d = await r.json();
  if (!r.ok) throw new Error(`phantombuster_http_${r.status}: ${JSON.stringify(d).slice(0, 200)}`);
  return d;
}
// deno-lint-ignore no-explicit-any
function resultRows(container: any): any[] {
  let ro = container?.resultObject;
  if (typeof ro === "string") { try { ro = JSON.parse(ro); } catch { ro = []; } }
  return Array.isArray(ro) ? ro : [];
}
async function processContainer(containerId: string, counts: Counts): Promise<number> {
  const c = await pb(`containers/fetch?id=${encodeURIComponent(containerId)}&withResultObject=true`);
  const rows = resultRows(c);
  for (const row of rows) {
    try { await processPayload(row, counts); }
    catch (e) { counts.skipped++; console.error(JSON.stringify({ event: "replay_row_failed", container_id: containerId, message: (e as Error).message })); }
  }
  return rows.length;
}

// ---------------------------------------------------------------- handler
Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured", detail: "PIER_TEAM_ID not set" });
  if (!authorize(req, "inbound", "capture-and-classify-reply") && !authorize(req, "internal", "capture-and-classify-reply")) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const action = String(body?.action ?? "").trim();

  try {
    if (action === "assign") {
      const unmatchedId = String(body?.unmatched_id ?? ""), contactId = String(body?.contact_id ?? ""), userId = String(body?.user_id ?? "") || null;
      const { data: row } = await supabase.from("unmatched_replies").select("*").eq("team_id", PIER_TEAM_ID).eq("id", unmatchedId).maybeSingle();
      if (!row) return json(404, { error: "unmatched_not_found" });
      const { data: contact } = await supabase.from("contacts").select("id").eq("team_id", PIER_TEAM_ID).eq("id", contactId).maybeSingle();
      if (!contact) return json(404, { error: "contact_not_found" });
      const p = parsePayload(row.payload ?? {});
      if (!p.message) p.message = String(row.message_body ?? "");
      await learnAliases(contactId, counterpartyIds(p));
      const r = p.isLastMessageFromMe ? await fileOwnMessage(contactId, p, row.external_key) : await fileInbound(contactId, p, row.external_key);
      await supabase.from("unmatched_replies").update({ status: "assigned", assigned_contact_id: contactId, assigned_by: userId, assigned_at: new Date().toISOString(), created_touch_id: r.touch_id }).eq("id", unmatchedId);
      // Any other queued message from the same sender now matches by alias; file them too.
      const ids = counterpartyIds(p);
      let siblings = 0;
      if (ids.length) {
        const { data: others } = await supabase.from("unmatched_replies").select("*").eq("team_id", PIER_TEAM_ID).eq("status", "open").neq("id", unmatchedId).limit(200);
        for (const o of others ?? []) {
          const op = parsePayload(o.payload ?? {});
          if (!op.message) op.message = String(o.message_body ?? "");
          if (!counterpartyIds(op).some((x) => ids.includes(x))) continue;
          try {
            const rr = op.isLastMessageFromMe ? await fileOwnMessage(contactId, op, o.external_key) : await fileInbound(contactId, op, o.external_key);
            await supabase.from("unmatched_replies").update({ status: "assigned", assigned_contact_id: contactId, assigned_by: userId, assigned_at: new Date().toISOString(), created_touch_id: rr.touch_id }).eq("id", o.id);
            siblings++;
          } catch (e) { console.error(JSON.stringify({ event: "sibling_assign_failed", id: o.id, message: (e as Error).message })); }
        }
      }
      return json(200, { ok: true, outcome: r.outcome, touch_id: r.touch_id, siblings_filed: siblings });
    }
    if (action === "dismiss") {
      const unmatchedId = String(body?.unmatched_id ?? "");
      const { error } = await supabase.from("unmatched_replies").update({ status: "dismissed" }).eq("team_id", PIER_TEAM_ID).eq("id", unmatchedId);
      if (error) throw error;
      return json(200, { ok: true });
    }
    if (action === "sync_inbox") {
      if (!PHANTOMBUSTER_API_KEY) return json(500, { error: "server_misconfigured", detail: "PHANTOMBUSTER_API_KEY not set" });
      const agent = await pb(`agents/fetch?id=${PHANTOM_INBOX}`);
      const argument = JSON.parse(String(agent?.argument ?? "{}"));
      const launched = await pb("agents/launch", { method: "POST", body: JSON.stringify({ id: PHANTOM_INBOX, argument }) });
      const containerId = String(launched?.containerId ?? "");
      if (!containerId) return json(500, { error: "launch_failed", detail: "no container id" });
      console.log(JSON.stringify({ event: "inbox_sync_launched", container_id: containerId }));
      return json(200, { status: "launched", container_id: containerId });
    }
    if (action === "sync_status") {
      const containerId = String(body?.container_id ?? "");
      const c = await pb(`containers/fetch?id=${encodeURIComponent(containerId)}&withResultObject=true`);
      const status = String(c?.status ?? "");
      if (status !== "finished") {
        if (status === "unknown" || status === "launch error" || (Number.isFinite(Number(c?.exitCode)) && Number(c?.exitCode) !== 0 && status !== "running" && status !== "starting")) {
          return json(200, { status: "failed", detail: `phantom ${status} exit=${c?.exitCode ?? "?"}` });
        }
        return json(200, { status: "running", phantom_status: status });
      }
      if (Number(c?.exitCode ?? 0) !== 0) return json(200, { status: "failed", detail: `phantom exit ${c?.exitCode}` });
      const counts = zero();
      for (const row of resultRows(c)) {
        try { await processPayload(row, counts); } catch (e) { counts.skipped++; console.error(JSON.stringify({ event: "sync_row_failed", message: (e as Error).message })); }
      }
      console.log(JSON.stringify({ event: "inbox_sync_done", container_id: containerId, counts }));
      return json(200, { status: "done", counts });
    }
    if (action === "replay_containers") {
      const ids: string[] = Array.isArray(body?.container_ids) ? body.container_ids.map(String) : [];
      const counts = zero();
      const perContainer: Record<string, number> = {};
      for (const id of ids) {
        try { perContainer[id] = await processContainer(id, counts); }
        catch (e) { perContainer[id] = -1; console.error(JSON.stringify({ event: "replay_container_failed", container_id: id, message: (e as Error).message })); }
      }
      console.log(JSON.stringify({ event: "replay_done", containers: ids.length, counts }));
      return json(200, { status: "done", counts, per_container: perContainer });
    }

    // Default: one message from Make. Same field tolerance as v15, plus the new identifiers.
    try { console.log(JSON.stringify({ event: "inbox_message_shape", keys: Object.keys(body ?? {}) })); } catch { /* noop */ }
    const p = parsePayload(body);
    if (!p.message && !p.threadUrl) return json(400, { error: "missing_required_fields", detail: "message or threadUrl is required" });
    const counts = zero();
    const out = await processPayload(body, counts);
    return json(200, { ...out, counts });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", action: action || "message", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
