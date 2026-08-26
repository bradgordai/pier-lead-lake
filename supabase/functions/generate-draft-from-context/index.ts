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
const BASIC_VOICE_FALLBACK = "You are Oli (Oliver Mueller) at Pier Insurance, writing a first LinkedIn DM to a contact who just accepted your connection request. Voice: direct, warm, specific, peer-to-peer. No corporate jargon, no em-dashes/en-dashes. Keep it short (ideally under 600 characters). Reference something concrete about their company. End with a light, low-friction question. Sign off 'Oli'. Output ONLY the message body.";
// Highest-priority behavioural contract, appended AFTER the EA docs so it is the last thing the
// model reads. Fixes the failure mode where a contact with prior outreach made the model emit
// meta-commentary ("I have already sent a message on ...") instead of a usable DM.
// Bundle B T4: this directive claims priority over everything above it, so it must agree
// with the trigger. Hardcoding "LinkedIn DM" here made it contradict the Intent line on
// every InMail chaser, and the directive would have won.
function forwardDirective(m: { channel: string; touch_type: string; intent: string }): string {
  return [
  "",
  "",
  "===== DRAFTING DIRECTIVE (overrides everything above on output format) =====",
  `You are producing ONE ${m.channel} message - a "${m.touch_type}" - that Oli will paste and send right now.`,
  `- Intent for this specific message: ${m.intent}`,
  "- Output ONLY the message body. Never write meta-commentary, notes to the operator, questions about whether to send, or explanations of your reasoning.",
  "- NEVER reference the drafting process or the contact's message history in the body. Banned openings include anything like \"I have already sent\", \"Before drafting\", \"Since you previously\", \"I notice we last spoke\", \"flagging a few\".",
  "- PREVIOUS OUTREACH is background only: it tells you what has already been said so you do not repeat it. Always write forward.",
  "- If prior outreach exists (a reply, or a message with no reply, or an old thread): write a natural NEW message that moves things forward. If they went quiet, use a light re-engagement angle with a fresh hook. No guilt, no \"just following up\", no mention of the gap.",
  "- If context is thin, still write a short, human, specific-as-possible message. Never refuse, never apologise, never explain yourself in the output.",
  ].join("\n");
}
const BANNED = ["—", "–", "circle back", "touch base", "synergise", "synergize", "unlock", "hope this finds", "just following up", "reach out to explore", "quick one", "leveraging", "excited to connect", "we're uniquely positioned", "best-in-class"];

function countOccurrences(h: string, n: string): number { if (!n) return 0; let c = 0, i = 0; while ((i = h.indexOf(n, i)) !== -1) { c++; i += n.length; } return c; }

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
      intent: "They have just accepted Oli's connection request. Write the first message on a brand-new thread." },
    inmail_cold: { channel: "LinkedIn inMail", touch_type: "Initial message",
      intent: "This is a cold InMail to someone Oli is not connected to. No prior relationship - earn the reply." },
    chaser_1: { channel: "LinkedIn inMail", touch_type: "Chaser 1",
      intent: "First chase. The earlier message went unanswered. Add one new angle; do not repeat the opener and do not guilt them." },
    chaser_2: { channel: "LinkedIn inMail", touch_type: "Chaser 2",
      intent: "Second chase. Shorter than the first chase. One concrete, easy-to-answer question." },
    chaser_3: { channel: "LinkedIn inMail", touch_type: "Chaser 3",
      intent: "Final chase. Brief and gracious - leave the door open and make clear this is the last nudge." },
    follow_up: { channel: "LinkedIn DM", touch_type: "Follow up",
      intent: "They have replied and the conversation is live. Continue it naturally - this is not an opener." },
  };
  const mapped = TRIGGER_MAP[triggerReason] ?? TRIGGER_MAP["cr_accepted"];

  try {
    const { data: contact, error: cErr } = await supabase.from("contacts")
      .select("id, contact_id, first_name, last_name, job_title, seniority, function, location, linkedin_url, company_id, connection_status")
      .eq("team_id", PIER_TEAM_ID).eq("id", contactId).maybeSingle();
    if (cErr) throw cErr;
    if (!contact) return json(404, { error: "contact_not_found" });

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
    if (existingDraft) {
      console.log(JSON.stringify({ event: "dedup_skipped", contact_id: contact.id, existing_touch_id: existingDraft.id, existing_created_at: existingDraft.created_at }));
      return json(200, { status: "dedup_skipped", existing_touch_id: existingDraft.id, message: "Draft already exists in Pending Review, not creating duplicate" });
    }

    // deno-lint-ignore no-explicit-any
    let company: any = null;
    if (contact.company_id) {
      const { data: co } = await supabase.from("companies")
        .select("company_name, country, category, priority, industry, product_line, insurance_offered, insurance_provider, coverage_summary, usp_notes, additional_notes, estimated_revenue_gbp, employees, monthly_visits")
        .eq("id", contact.company_id).maybeSingle();
      company = co ?? null;
    }

    const { data: prevRows } = await supabase.from("outreach_log")
      .select("touch_date, channel, touch_type, message_body, subject_line, reply_content")
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
    const who = contact.first_name ? String(contact.first_name) : "the contact";
    const renderMsg = (r: typeof allPrev[number]) => {
      const date = r.touch_date ?? "";
      if (r.touch_type === "Reply") {
        const body = String(r.reply_content ?? r.message_body ?? "").slice(0, 500);
        return `- ${date} Reply from ${who}: ${body}`;
      }
      const subj = r.subject_line ? `[${r.subject_line}] ` : "";
      const body = String(r.message_body ?? "").slice(0, 500);
      return `- ${date} Oli: ${subj}${body}`;
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
    try {
      const { data: docs, error: dErr } = await supabase.from("pier_ea_documents").select("name, content")
        .eq("team_id", PIER_TEAM_ID).eq("is_active", true).in("name", EA_ORDER);
      if (dErr) throw dErr;
      const byName = new Map(((docs ?? []) as Array<{ name: string; content: string }>).map((d) => [d.name, d.content]));
      const parts: string[] = [];
      for (const n of EA_ORDER) { const c = byName.get(n); if (c) parts.push(`===== ${n} =====\n${c}`); }
      systemPrompt = parts.length === 0 ? BASIC_VOICE_FALLBACK : parts.join("\n\n");
      if (parts.length === 0) console.warn(JSON.stringify({ event: "ea_docs_empty" }));
    } catch (e) {
      console.warn(JSON.stringify({ event: "ea_docs_load_failed", message: (e as Error).message }));
      systemPrompt = BASIC_VOICE_FALLBACK;
    }
    // Behavioural contract always wins on output format, regardless of which voice source was used.
    systemPrompt = systemPrompt + forwardDirective(mapped);

    const path = "A";
    const arc = "A";
    const insuranceActive = !!company && ((String(company.insurance_offered ?? "").toLowerCase() === "yes") || !!(company.insurance_provider && String(company.insurance_provider).trim()));
    const isCsuite = /c-?suite|chief|founder|ceo|cfo|coo|cto/i.test(String(contact.seniority ?? ""));
    const frame = insuranceActive ? "Discovery" : (isCsuite ? "Ally" : "Peer");

    const co = company ?? {};
    const userPrompt = `DRAFT REQUEST\n\nTrigger: ${triggerReason}\nMessage type: ${mapped.touch_type} via ${mapped.channel}\nChannel: ${mapped.channel}\nIntent: ${mapped.intent}\nPath: ${path}\nFrame: ${frame}\nArc: ${arc}\n\nCONTACT\nName: ${contact.first_name ?? ""} ${contact.last_name ?? ""}\nTitle: ${contact.job_title ?? ""}\nSeniority: ${contact.seniority ?? ""}\nFunction: ${contact.function ?? ""}\nLocation: ${contact.location ?? ""}\nLinkedIn URL: ${contact.linkedin_url ?? ""}\n\nCOMPANY\nName: ${co.company_name ?? ""}\nCountry: ${co.country ?? ""}\nCategory: ${Array.isArray(co.category) ? co.category.join(", ") : (co.category ?? "")}\nPriority: ${co.priority ?? ""}\nIndustry: ${co.industry ?? ""}\nProduct line: ${co.product_line ?? ""}\nInsurance offered: ${co.insurance_offered ?? ""}\nInsurance provider: ${co.insurance_provider ?? ""}\nCoverage summary: ${co.coverage_summary ?? ""}\nUSP notes: ${co.usp_notes ?? ""}\nAdditional notes: ${co.additional_notes ?? ""}\nEstimated revenue: ${co.estimated_revenue_gbp ?? ""}\nEmployees: ${co.employees ?? ""}\nMonthly visits: ${co.monthly_visits ?? ""}\n\nPREVIOUS OUTREACH (background only - never mention it in the message)\n${threadText}\n\nTASK\nWrite the single ${mapped.channel} message Oli should send to this contact now, applying the loaded PIER_Rules, LinkedIn_Message_Architect, Lead_and_ICP_Brief, OUTREACH_QUICK_REFERENCE, and PIER_Response_Bank. This message is a "${mapped.touch_type}": ${mapped.intent} If prior outreach exists, write a natural forward message (re-engagement) - never a first-touch opener and never a comment on the history.\n\nSign off: Oli\n\nOutput ONLY the message body Oli will send. No preamble, no meta-commentary, no notes about prior messages, no subject line.`;

    let messageBody = "";
    let generationFailed = false;
    let genError = "";
    try {
      if (!ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY missing");
      // Routed through the sentinel: logs cost per call to api_call_log and refuses once
      // today's spend hits the daily budget (fail-closed, security audit F-10).
      const result = await callAnthropicWithSentinel({
        model: ANTHROPIC_MODEL,
        max_tokens: 1024,
        thinking: { type: "disabled" },
        system: systemPrompt,
        messages: [{ role: "user", content: userPrompt }],
        function_name: "generate-draft-from-context",
        team_id: PIER_TEAM_ID,
        request_context: { contact_id: contact.id, trigger_reason: triggerReason, touch_type: mapped.touch_type, purpose: "draft_generation" },
        supabase,
        anthropic_api_key: ANTHROPIC_API_KEY,
      });
      messageBody = result.content.replace(/^```[a-z]*\s*/i, "").replace(/```$/i, "").trim();
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

    const today = new Date().toISOString().slice(0, 10);
    const insertRow = {
      team_id: PIER_TEAM_ID, touch_id: `agent-${crypto.randomUUID()}`, contact_ref: contact.contact_id ?? null, contact_id: contact.id, company_id: contact.company_id ?? null,
      channel: mapped.channel, touch_type: mapped.touch_type, message_body: messageBody, subject_line: null,
      draft_status: "pending_review", send_status: "Draft", agent_produced: true,
      pre_lint_pass: lint.pass, voice_contract_violations: lint.violations, lint_score: lint.score,
      path, recommended_frame: frame, recommended_arc: arc, touch_date: today,
    };
    const { data: inserted, error: insErr } = await supabase.from("outreach_log").insert(insertRow).select("id").single();
    if (insErr) throw insErr;

    console.log(JSON.stringify({ event: "draft_created", touch_id: inserted.id, contact_id: contact.id, lint_score: lint.score, pass: lint.pass, generation_failed: generationFailed }));
    return json(200, { status: generationFailed ? "generation_failed" : "created", touch_id: inserted.id, message_preview: messageBody.slice(0, 200), pre_lint_pass: lint.pass, lint_score: lint.score, path, frame, gen_error: genError || undefined });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
