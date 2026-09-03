import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";
import { callAnthropicWithSentinel, BudgetExceededError } from "./_shared/anthropic-sentinel.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const ANTHROPIC_MODEL = "claude-sonnet-5";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

const EA_ORDER = ["PIER_Rules", "LinkedIn_Message_Architect", "Lead_and_ICP_Brief", "OUTREACH_QUICK_REFERENCE", "PIER_Response_Bank"];

// T1: drafts are signed by whoever asked for them. This was hardcoded to "Oli" when Pier
// had one user; there are now two (Oliver Müller, Jack Stevens) and a draft Jack generates
// must not go out signed as Oli.
//
// Resolution order:
//   1. body.requesting_user  - the logged-in user, passed by the Lovable UI
//   2. the contact's owner_user_id -> that user's display name. owner_user_id is CANON for
//      ownership (the older account_owner column is migration reference data only). This is
//      what makes the chained CR-accepted path correct: nobody is "requesting" it, so the
//      draft is signed by whoever owns the contact.
//   3. "Oli" - last-resort legacy default, logged as a warning so it is visible.
const NICKNAMES: Record<string, string> = { oliver: "Oli" };
// Split on whitespace AND . _ - so an email local-part degrades sensibly:
// "oliver.muller" -> "Oliver" rather than the whole handle. Capitalise the first
// letter because local-parts are lowercase and the name is used mid-sentence and
// as a sign-off.
function firstNameOf(display: string): string {
  const first = (display ?? "").trim().split(/[\s._-]+/).filter(Boolean)[0] ?? "";
  if (!first) return "";
  const nick = NICKNAMES[first.toLowerCase()];
  if (nick) return nick;
  return first.charAt(0).toUpperCase() + first.slice(1);
}
// deno-lint-ignore no-explicit-any
async function resolveSender(supa: any, requesting: string, ownerUserId: string | null): Promise<string> {
  const fromBody = firstNameOf(requesting);
  if (fromBody) return fromBody;
  if (ownerUserId) {
    try {
      const { data } = await supa.auth.admin.getUserById(ownerUserId);
      const meta = data?.user?.user_metadata ?? {};
      // first_name is the convention already used on some accounts, so prefer it
      // over the full-name fields; fall back to the email local-part last.
      const display = meta.first_name ?? meta.name ?? meta.full_name ?? meta.display_name
        ?? (data?.user?.email ?? "").split("@")[0];
      const fromOwner = firstNameOf(String(display ?? ""));
      if (fromOwner) return fromOwner;
    } catch (e) {
      console.warn(JSON.stringify({ event: "sender_lookup_failed", message: (e as Error).message }));
    }
  }
  console.warn(JSON.stringify({ event: "sender_defaulted", detail: "No requesting_user and no resolvable owner; defaulting to Oli." }));
  return "Oli";
}
const basicVoiceFallback = (sender: string) => `You are ${sender} at Pier Insurance, writing a first LinkedIn DM to a contact who just accepted your connection request. Voice: direct, warm, specific, peer-to-peer. No corporate jargon, no em-dashes/en-dashes. Keep it short (ideally under 600 characters). Reference something concrete about their company. End with a light, low-friction question. Sign off '${sender}'.`;
// Highest-priority behavioural contract, appended AFTER the EA docs so it is the last thing the
// model reads. Fixes the failure mode where a contact with prior outreach made the model emit
// meta-commentary ("I have already sent a message on ...") instead of a usable DM.
// Bundle B T4: this directive claims priority over everything above it, so it must agree
// with the trigger. Hardcoding "LinkedIn DM" here made it contradict the Intent line on
// every InMail chaser, and the directive would have won.
function forwardDirective(m: { channel: string; touch_type: string; intent: string }, sender: string): string {
  return [
  "",
  "",
  "===== DRAFTING DIRECTIVE (overrides everything above on output format) =====",
  `You are producing ONE ${m.channel} message - a "${m.touch_type}" - that ${sender} will paste and send right now.`,
  `- Intent for this specific message: ${m.intent}`,
  "- Output ONLY a JSON object, no markdown fence, with exactly these keys:",
  '  {"message": "...", "narrative": "...", "guardrails": ["..."]}',
  "- `message` is the body that will be pasted and sent, verbatim. Never put meta-commentary, notes to the operator, questions about whether to send, or reasoning inside `message`.",
  "- `narrative` is 1-2 sentences for the OPERATOR only, never seen by the prospect: why this contact, why now, what this touch is trying to do.",
  "- `guardrails` is 0-4 short strings, each a thing NOT to do on this specific touch (e.g. \"do not restate the 40% figure they already ignored\"). Prohibitions only, never advice.",
  "- NEVER reference the drafting process or the contact's message history in the body. Banned openings include anything like \"I have already sent\", \"Before drafting\", \"Since you previously\", \"I notice we last spoke\", \"flagging a few\".",
  "- PREVIOUS OUTREACH is background only: it tells you what has already been said so you do not repeat it. Always write forward.",
  "- If prior outreach exists (a reply, or a message with no reply, or an old thread): write a natural NEW message that moves things forward. If they went quiet, use a light re-engagement angle with a fresh hook. No guilt, no \"just following up\", no mention of the gap.",
  "- If context is thin, still write a short, human, specific-as-possible message. Never refuse, never apologise, never explain yourself in the output.",
  ].join("\n");
}
const BANNED = ["—", "–", "circle back", "touch base", "synergise", "synergize", "unlock", "hope this finds", "just following up", "reach out to explore", "quick one", "leveraging", "excited to connect", "we're uniquely positioned", "best-in-class"];

function countOccurrences(h: string, n: string): number { if (!n) return 0; let c = 0, i = 0; while ((i = h.indexOf(n, i)) !== -1) { c++; i += n.length; } return c; }

// B6: raise a reconciliation handover instead of drafting. Never throws - a failure to
// log the note must not turn into a 500 on the ingest chain that called us.
// deno-lint-ignore no-explicit-any
async function raiseReconciliationNote(contactId: string, triggerReason: string, reasons: string[], contact: any): Promise<void> {
  try {
    await supabase.from("agent_handover").insert({
      team_id: PIER_TEAM_ID,
      from_agent: "outbound",
      to_agent: "reconciliation",
      request_type: "update_contact_status",
      entity_type: "contact",
      entity_id: contactId,
      status: "open",
      payload: {
        note: "accepted but marked not relevant",
        detail: `Draft suppressed on trigger '${triggerReason}': ${reasons.join(", ")}. The connection/trigger says engage; the contact record says do not.`,
        trigger_reason: triggerReason,
        reasons,
        outreach_status: contact?.outreach_status ?? null,
        connection_status: contact?.connection_status ?? null,
      },
    });
  } catch (e) {
    console.error(JSON.stringify({ event: "reconciliation_note_failed", contact_id: contactId, message: (e as Error).message ?? String(e) }));
  }
}

function preLint(message: string): { score: number; pass: boolean; violations: unknown[] } {
  const lower = message.toLowerCase();
  const violations: unknown[] = [];
  let bannedHits = 0;
  for (const term of BANNED) {
    const c = countOccurrences(lower, term.toLowerCase());
    if (c > 0) { bannedHits += c; const label = term === "—" ? "em-dash" : term === "–" ? "en-dash" : term; violations.push({ type: "banned_word", term: label, count: c }); }
  }
  const len = message.length;
  let score = 100 - 5 * bannedHits;
  if (len > 800) { score -= 10; violations.push({ type: "length", chars: len, note: "over LinkedIn DM soft cap (800)" }); }
  const hardFail = len > 2000;
  if (hardFail) violations.push({ type: "length_hard", chars: len, note: "over hard cap (2000)" });
  score = Math.max(0, score);
  return { score, pass: score >= 70 && !hardFail, violations };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured" });
  if (!authorize(req, "internal", "generate-draft-from-context")) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const contactId = String(body?.contact_id ?? "").trim();
  const triggerReason = String(body?.trigger_reason ?? "cr_accepted").trim();
  const requestingUser = String(body?.requesting_user ?? "").trim();
  const dryRun = body?.dry_run === true;
  if (!contactId) return json(400, { error: "missing_required_fields", detail: "contact_id required" });

  // Bundle B T4: the trigger decides which kind of touch this draft is, which in turn
  // drives channel + touch_type on the row, the dedup key, and what we tell Sonnet it is
  // writing. Unknown triggers fall back to the CR-accepted opener, which is the historical
  // behaviour and the only trigger anything in production sends today.
  //
  // `intent` is handed to the model so a chaser doesn't get written as a first touch.
  // touch_type values come from the outreach_type enum (migration 038).
  const TRIGGER_MAP: Record<string, { channel: string; touch_type: string; intent: string }> = {
    cr_accepted: { channel: "LinkedIn DM", touch_type: "Initial message",
      intent: "They have just accepted your connection request. Write the first message on a brand-new thread." },
    inmail_cold: { channel: "LinkedIn inMail", touch_type: "Initial message",
      intent: "This is a cold InMail to someone you are not connected to. No prior relationship - earn the reply." },
    // C1: channel here is a PLACEHOLDER for chasers. It is overridden below from the
    // contact's connection state: an accepted contact is chased over free LinkedIn DM,
    // never InMail. Chasing someone we are already connected to over InMail spends a
    // credit for nothing, which is the bug that caused the 2026-09-03 quarantine.
    chaser_1: { channel: "LinkedIn DM", touch_type: "Chaser 1",
      intent: "First chase. The earlier message went unanswered. Add one new angle; do not repeat the opener and do not guilt them." },
    chaser_2: { channel: "LinkedIn DM", touch_type: "Chaser 2",
      intent: "Second chase. Shorter than the first chase. One concrete, easy-to-answer question." },
    chaser_3: { channel: "LinkedIn DM", touch_type: "Chaser 3",
      intent: "Final chase. Brief and gracious - leave the door open and make clear this is the last nudge." },
    follow_up: { channel: "LinkedIn DM", touch_type: "Follow up",
      intent: "They have replied and the conversation is live. Continue it naturally - this is not an opener." },
  };
  // Copied so the C1 channel override below cannot mutate the shared map.
  const mapped = { ...(TRIGGER_MAP[triggerReason] ?? TRIGGER_MAP["cr_accepted"]) };

  try {
    const { data: contact, error: cErr } = await supabase.from("contacts")
      .select("id, contact_id, first_name, last_name, job_title, seniority, function, location, linkedin_url, company_id, connection_status, owner_user_id, outreach_status, archived_at, do_not_contact")
      .eq("team_id", PIER_TEAM_ID).eq("id", contactId).maybeSingle();
    if (cErr) throw cErr;
    if (!contact) return json(404, { error: "contact_not_found" });

    // C5 REFUSAL GATES. Oli requirement 5a: the draft call must be able to return a
    // REFUSAL, not just a draft. All eight gates live in fn_evaluate_gates (migration 055)
    // so the drafter, the chase engine and the catch-up scan cannot drift apart - the one
    // set of rules that must never drift is consent.
    //
    // C1: an accepted contact is chased over FREE LinkedIn DM. Resolved before the gate
    // call because the per-channel allowance depends on which channel we would actually use.
    const isChaser = triggerReason.startsWith("chaser_");
    const chaserChannel = String(contact.connection_status ?? "") === "Accepted"
      ? "LinkedIn DM" : "LinkedIn inMail";
    if (isChaser) mapped.channel = chaserChannel;

    const requested = triggerReason === "follow_up" ? "reply"
                    : isChaser ? "chaser"
                    : "initial_message";

    const { data: gateRows, error: gateErr } = await supabase.rpc("fn_evaluate_gates", {
      p_team_id: PIER_TEAM_ID, p_contact_id: contact.id,
      p_channel: mapped.channel, p_requested: requested,
    });
    if (gateErr) throw gateErr;
    const gate = (gateRows ?? [])[0];
    if (gate) {
      // A refusal is a first-class RESULT, not an error: HTTP 200 with refused:true.
      // Lovable renders reason_human on the card in place of a draft.
      if (!dryRun) {
        await supabase.from("refusals").insert({
          team_id: PIER_TEAM_ID, contact_id: contact.id, company_id: contact.company_id ?? null,
          reason_code: gate.reason_code, reason_human: gate.reason_human,
          channel: mapped.channel, requested,
          context: { ...(gate.context ?? {}), trigger_reason: triggerReason },
        });
        // Only a consent contradiction deserves a human's attention: the CR-accepted
        // trigger says engage while the record says stop. Data-quality refusals are
        // self-explanatory and would just be noise in the reconciliation queue.
        if (gate.reason_code === "dnc_or_opted_out" || gate.reason_code === "promise_of_quiet") {
          await raiseReconciliationNote(contact.id, triggerReason, [gate.reason_code], contact);
        }
      }
      console.log(JSON.stringify({ event: "draft_refused", contact_id: contact.id, reason_code: gate.reason_code, trigger_reason: triggerReason, channel: mapped.channel, dry_run: dryRun }));
      return json(200, {
        refused: true, reason_code: gate.reason_code, reason_human: gate.reason_human,
        contact_id: contact.id, channel: mapped.channel, requested, dry_run: dryRun,
      });
    }

    const sender = await resolveSender(supabase, requestingUser, contact.owner_user_id ?? null);
    console.log(JSON.stringify({ event: "sender_resolved", sender, from_body: !!requestingUser, contact_id: contact.id }));

    // Dedup guard: if an agent-produced pending_review draft already exists for this
    // contact + channel + touch_type, do not create a duplicate. Every 4h Connection
    // Watcher run would otherwise blindly create a new draft on unchanged acceptance.
    //
    // Keyed on the MAPPED pair, not a hardcoded one, so Chaser 2 does not dedup against
    // Chaser 1 (or against the opener) and silently cancel the rest of the cadence.
    const { data: existingDraft } = await supabase.from("outreach_log")
      .select("id, touch_id, created_at")
      .eq("team_id", PIER_TEAM_ID)
      .eq("contact_id", contact.id)
      .eq("channel", mapped.channel)
      .eq("touch_type", mapped.touch_type)
      .eq("draft_status", "pending_review")
      .eq("agent_produced", true)
      .limit(1)
      .maybeSingle();
    if (existingDraft && !dryRun) {
      console.log(JSON.stringify({ event: "dedup_skipped", contact_id: contact.id, existing_touch_id: existingDraft.id, existing_created_at: existingDraft.created_at }));
      return json(200, { status: "dedup_skipped", existing_touch_id: existingDraft.id, message: "Draft already exists in Pending Review, not creating duplicate" });
    }

    // deno-lint-ignore no-explicit-any
    let company: any = null;
    if (contact.company_id) {
      const { data: co } = await supabase.from("companies")
        .select("company_name, country, category, priority, industry, product_line, insurance_offered, insurance_provider, coverage_summary, usp_notes, additional_notes, estimated_revenue_gbp, employees, monthly_visits, archived_at")
        .eq("id", contact.company_id).maybeSingle();
      company = co ?? null;
    }
    if (company?.archived_at) {
      // Archived company maps onto the closed reason-code set as dnc_or_opted_out: the
      // company is out of scope, so the contact is excluded from outreach.
      if (!dryRun) {
        await supabase.from("refusals").insert({
          team_id: PIER_TEAM_ID, contact_id: contact.id, company_id: contact.company_id ?? null,
          reason_code: "dnc_or_opted_out",
          reason_human: `${company.company_name ?? "The company"} is archived, so this contact is out of scope.`,
          channel: mapped.channel, requested: triggerReason,
          context: { company_archived_at: company.archived_at },
        });
        await raiseReconciliationNote(contact.id, triggerReason, ["company_archived"], contact);
      }
      console.log(JSON.stringify({ event: "draft_refused", contact_id: contact.id, reason_code: "dnc_or_opted_out", detail: "company_archived", dry_run: dryRun }));
      return json(200, { refused: true, reason_code: "dnc_or_opted_out",
        reason_human: `${company.company_name ?? "The company"} is archived, so this contact is out of scope.`,
        contact_id: contact.id, dry_run: dryRun });
    }

    const { data: prevRows } = await supabase.from("outreach_log")
      .select("touch_date, channel, touch_type, message_body, sent_body, subject_line, reply_content, sent_by")
      .eq("team_id", PIER_TEAM_ID).eq("contact_id", contactId).order("touch_date", { ascending: true }).limit(50);
    // Only the last 30 days count as "live" thread context; older messages are summarised as a
    // re-engagement note so stale threads never derail the draft (older = stale, ignore the detail).
    const allPrev = prevRows ?? [];
    const cutoff = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10);
    const recent = allPrev.filter((r) => String(r.touch_date ?? "") >= cutoff);
    const older = allPrev.filter((r) => String(r.touch_date ?? "") < cutoff);
    // Render each historical touch exactly once, correctly attributed by sender.
    // touch_type='Reply' rows are INBOUND (from the contact); capture-and-classify
    // writes the reply text into BOTH message_body and reply_content, so render only
    // reply_content (fallback message_body for legacy rows) and never label it "Oli".
    // Every non-Reply touch is OUTBOUND from Oli. This fixes the previous double-render
    // where a Reply row appeared as both "Oli: <text>" and "Reply: <text>".
    const them = contact.first_name ? String(contact.first_name) : "the contact";
    const renderMsg = (r: typeof allPrev[number]) => {
      const date = r.touch_date ?? "";
      if (r.touch_type === "Reply") {
        const body = String(r.reply_content ?? r.message_body ?? "").slice(0, 500);
        return `- ${date} Reply from ${them}: ${body}`;
      }
      const subj = r.subject_line ? `[${r.subject_line}] ` : "";
      // C6: prefer what was ACTUALLY sent (including edits) over the working draft,
      // so the no-repetition check compares against reality.
      const body = String(r.sent_body ?? r.message_body ?? "").slice(0, 500);
      // Historical touches are attributed to whoever actually sent them, not to the
      // current requester - otherwise Jack would appear to have sent Oli's old messages.
      const who = String(r.sent_by ?? "").trim() || "us";
      return `- ${date} ${who}: ${subj}${body}`;
    };
    let threadText: string;
    if (allPrev.length === 0) {
      // No history at all. Describe that honestly and let the trigger's intent say what
      // kind of first touch this is - a cold InMail is not "someone who just accepted".
      threadText = `(none on record - no prior outreach to this contact. ${mapped.intent})`;
    } else if (recent.length === 0) {
      const last = older[older.length - 1]?.touch_date ?? "unknown";
      threadText = `(no messages in the last 30 days; ${older.length} earlier message(s), most recent ${last}. Treat this as RE-ENGAGEMENT: write a fresh forward nudge, do NOT reuse a first-touch opener, do NOT mention the time gap.)`;
    } else {
      const olderNote = older.length ? `(plus ${older.length} earlier message(s) before ${cutoff}, omitted as stale - do not repeat those openers)\n` : "";
      threadText = olderNote + recent.map(renderMsg).join("\n");
    }

    let systemPrompt = "";
    let eaDocsLoaded = false;
    try {
      const { data: docs, error: dErr } = await supabase.from("pier_ea_documents").select("name, content")
        .eq("team_id", PIER_TEAM_ID).eq("is_active", true).in("name", EA_ORDER);
      if (dErr) throw dErr;
      const byName = new Map(((docs ?? []) as Array<{ name: string; content: string }>).map((d) => [d.name, d.content]));
      const parts: string[] = [];
      for (const n of EA_ORDER) { const c = byName.get(n); if (c) parts.push(`===== ${n} =====\n${c}`); }
      systemPrompt = parts.length === 0 ? basicVoiceFallback(sender) : parts.join("\n\n");
      eaDocsLoaded = parts.length > 0;
      if (parts.length === 0) console.warn(JSON.stringify({ event: "ea_docs_empty" }));
    } catch (e) {
      console.warn(JSON.stringify({ event: "ea_docs_load_failed", message: (e as Error).message }));
      systemPrompt = basicVoiceFallback(sender);
    }

    // B2 PROMPT CACHING. The EA documents are ~39k tokens and identical on every call;
    // the drafting directive is not (it interpolates channel, touch_type, intent, sender).
    // So the EA block carries the cache_control breakpoint and the directive sits AFTER it
    // as a separate block - put the directive inside the cached block and the prefix
    // changes per touch type, which would miss the cache on nearly every call.
    //
    // Only cached when the EA docs actually loaded: the fallback voice is small and
    // varies by sender, so caching it would pay the 1.25x write premium for no reads.
    const directive = forwardDirective(mapped, sender);
    // deno-lint-ignore no-explicit-any
    const systemParam: any = eaDocsLoaded
      ? [
          { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
          { type: "text", text: directive },
        ]
      : systemPrompt + directive;
    // Kept for the failure log line below, which reports prompt size.
    systemPrompt = systemPrompt + directive;

    const path = "A";
    const arc = "A";
    const insuranceActive = !!company && ((String(company.insurance_offered ?? "").toLowerCase() === "yes") || !!(company.insurance_provider && String(company.insurance_provider).trim()));
    const isCsuite = /c-?suite|chief|founder|ceo|cfo|coo|cto/i.test(String(contact.seniority ?? ""));
    const frame = insuranceActive ? "Discovery" : (isCsuite ? "Ally" : "Peer");

    const co = company ?? {};
    const userPrompt = `DRAFT REQUEST\n\nTrigger: ${triggerReason}\nMessage type: ${mapped.touch_type} via ${mapped.channel}\nChannel: ${mapped.channel}\nIntent: ${mapped.intent}\nPath: ${path}\nFrame: ${frame}\nArc: ${arc}\n\nCONTACT\nName: ${contact.first_name ?? ""} ${contact.last_name ?? ""}\nTitle: ${contact.job_title ?? ""}\nSeniority: ${contact.seniority ?? ""}\nFunction: ${contact.function ?? ""}\nLocation: ${contact.location ?? ""}\nLinkedIn URL: ${contact.linkedin_url ?? ""}\n\nCOMPANY\nName: ${co.company_name ?? ""}\nCountry: ${co.country ?? ""}\nCategory: ${Array.isArray(co.category) ? co.category.join(", ") : (co.category ?? "")}\nPriority: ${co.priority ?? ""}\nIndustry: ${co.industry ?? ""}\nProduct line: ${co.product_line ?? ""}\nInsurance offered: ${co.insurance_offered ?? ""}\nInsurance provider: ${co.insurance_provider ?? ""}\nCoverage summary: ${co.coverage_summary ?? ""}\nUSP notes: ${co.usp_notes ?? ""}\nAdditional notes: ${co.additional_notes ?? ""}\nEstimated revenue: ${co.estimated_revenue_gbp ?? ""}\nEmployees: ${co.employees ?? ""}\nMonthly visits: ${co.monthly_visits ?? ""}\n\nPREVIOUS OUTREACH (background only - never mention it in the message)\n${threadText}\n\nTASK\nWrite the single ${mapped.channel} message ${sender} should send to this contact now, applying the loaded PIER_Rules, LinkedIn_Message_Architect, Lead_and_ICP_Brief, OUTREACH_QUICK_REFERENCE, and PIER_Response_Bank. This message is a "${mapped.touch_type}": ${mapped.intent} If prior outreach exists, write a natural forward message (re-engagement) - never a first-touch opener and never a comment on the history.\n\nSign off: ${sender}\n\nReturn ONLY the JSON object described in the drafting directive. The "message" value is what ${sender} sends: no preamble, no meta-commentary, no notes about prior messages, no subject line.`;

    let messageBody = "";
    let draftNarrative: string | null = null;
    let draftGuardrails: string[] = [];
    let generationFailed = false;
    let genError = "";
    // deno-lint-ignore no-explicit-any
    let usage: any = null;
    let costGbp = 0;
    try {
      if (!ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY missing");
      // Routed through the sentinel: logs cost per call to api_call_log and refuses once
      // today's spend hits the daily budget (fail-closed, security audit F-10).
      const result = await callAnthropicWithSentinel({
        model: ANTHROPIC_MODEL,
        max_tokens: 1024,
        thinking: { type: "disabled" },
        system: systemParam,
        messages: [{ role: "user", content: userPrompt }],
        function_name: "generate-draft-from-context",
        team_id: PIER_TEAM_ID,
        request_context: { contact_id: contact.id, trigger_reason: triggerReason, touch_type: mapped.touch_type, sender, purpose: "draft_generation", dry_run: dryRun },
        supabase,
        anthropic_api_key: ANTHROPIC_API_KEY,
      });
      usage = result.usage;
      costGbp = result.estimated_cost_gbp;
      // B7: the model now returns {message, narrative, guardrails}. Parse defensively -
      // if it ever regresses to bare prose, treat the whole output as the message rather
      // than failing the draft, because a draft with no narrative is still usable.
      const rawOut = result.content.replace(/^```[a-z]*\s*/i, "").replace(/```$/i, "").trim();
      try {
        const m = rawOut.match(/\{[\s\S]*\}/);
        const parsed = JSON.parse(m ? m[0] : rawOut);
        messageBody = String(parsed?.message ?? "").trim();
        draftNarrative = typeof parsed?.narrative === "string" ? parsed.narrative.trim() : null;
        draftGuardrails = Array.isArray(parsed?.guardrails)
          ? parsed.guardrails.filter((g: unknown) => typeof g === "string" && g.trim()).slice(0, 4).map((g: string) => g.trim())
          : [];
        if (!messageBody) throw new Error("json_missing_message");
      } catch {
        console.warn(JSON.stringify({ event: "envelope_parse_fallback", contact_id: contact.id }));
        messageBody = rawOut;
        draftNarrative = null;
        draftGuardrails = [];
      }
      if (!messageBody) { genError = "empty_generation"; throw new Error("empty_generation"); }
    } catch (e) {
      // Budget block is NOT a generation failure: return without writing a placeholder
      // draft, so a blocked day does not fill Pending Review with junk rows to clean up.
      if (e instanceof BudgetExceededError) {
        console.error(JSON.stringify({ event: "draft_blocked_by_budget", contact_id: contact.id, message: e.message }));
        return json(200, { status: "budget_exceeded", detail: e.message, contact_id: contact.id });
      }
      generationFailed = true;
      if (!genError) genError = (e as Error).message ?? String(e);
      console.error(JSON.stringify({ event: "generation_failed", message: genError, system_len: systemPrompt.length }));
      messageBody = "[Draft generation failed, please write manually]";
    }

    const lint = generationFailed ? { score: 0, pass: false, violations: [{ type: "generation_error", note: "Anthropic call failed; placeholder inserted" }] as unknown[] } : preLint(messageBody);

    // B2 verification path: dry_run exercises the full generation (so cache behaviour is
    // real) but writes NO row. Used to measure the cached/uncached split without leaving
    // test drafts in Pending Review for Oli to clean up.
    if (dryRun) {
      console.log(JSON.stringify({ event: "draft_dry_run", contact_id: contact.id, usage, estimated_cost_gbp: costGbp }));
      return json(200, { status: "dry_run", contact_id: contact.id, sender, usage, estimated_cost_gbp: costGbp, narrative: draftNarrative, guardrails: draftGuardrails, message_preview: messageBody.slice(0, 300), lint_score: lint.score });
    }

    const today = new Date().toISOString().slice(0, 10);
    const insertRow = {
      team_id: PIER_TEAM_ID, touch_id: `agent-${crypto.randomUUID()}`, contact_ref: contact.contact_id ?? null, contact_id: contact.id, company_id: contact.company_id ?? null,
      channel: mapped.channel, touch_type: mapped.touch_type, message_body: messageBody, subject_line: null,
      draft_status: "pending_review", send_status: "Draft", agent_produced: true,
      pre_lint_pass: lint.pass, voice_contract_violations: lint.violations, lint_score: lint.score,
      path, recommended_frame: frame, recommended_arc: arc, touch_date: today, sent_by: sender,
      draft_narrative: draftNarrative, draft_guardrails: draftGuardrails,
    };
    const { data: inserted, error: insErr } = await supabase.from("outreach_log").insert(insertRow).select("id").single();
    if (insErr) throw insErr;

    console.log(JSON.stringify({ event: "draft_created", touch_id: inserted.id, contact_id: contact.id, sender, lint_score: lint.score, pass: lint.pass, generation_failed: generationFailed }));
    return json(200, { status: generationFailed ? "generation_failed" : "created", touch_id: inserted.id, sender, message_preview: messageBody.slice(0, 200), narrative: draftNarrative, guardrails: draftGuardrails, usage, estimated_cost_gbp: costGbp, pre_lint_pass: lint.pass, lint_score: lint.score, path, frame, gen_error: genError || undefined });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
