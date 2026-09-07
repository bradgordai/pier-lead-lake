// Edge Function: ai-edit-draft  (Batch C / C7 / T4)
//
// Applies an operator's edit instruction to an EXISTING draft and rewrites the body in
// place, stacking a numbered revision. Replaces the Lovable AI Gateway path (Gemini) so
// every model call Pier makes goes through Anthropic and the cost sentinel, and so the
// rewrite is done with the same EA documents the original draft was written from.
//
// Rules:
//   - Rewrites, never appends. The body that comes back IS the new draft.
//   - Revision 0 is the original body (written the first time a draft is edited), then
//     each edit is revision N+1 with its instruction. draft_revisions is the history.
//   - The C5 refusal gates do NOT apply here: editing an existing draft is allowed,
//     generating a new one is what is gated (C7).
//   - A Sent or Scheduled row cannot be edited: sent_body is immutable truth (C6).
//   - Register and language are preserved: contacts.formality (Formal = Sie / Informal = du)
//     and contacts.language_code are passed explicitly so the rewrite cannot drift.
//   - The EA block is built EXACTLY as generate-draft-from-context builds it (same docs,
//     same order, same separators) so the two functions share one prompt cache.
//
// Auth: INTERNAL_APP_SECRET (internal class), verify_jwt=false.
// Body: { outreach_log_id, instruction, requesting_user?, dry_run? }
// Returns: { ok, revision_number, message_body, usage, estimated_cost_gbp }
//       or { status: "budget_exceeded" } / { error }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";
import { callAnthropicWithSentinel, BudgetExceededError } from "./_shared/anthropic-sentinel.ts";
// F6.6: the contact notes block (next_action, background_notes, conversation_summary) is part of
// the edit context, with the two rules stated (gates override notes; note dates matter). v3.
import { contactNotesBlock } from "./_shared/conversation-summary.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const ANTHROPIC_MODEL = "claude-sonnet-5";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

// Must match generate-draft-from-context exactly: same docs, same order, same framing.
const EA_ORDER = ["PIER_Rules", "LinkedIn_Message_Architect", "Lead_and_ICP_Brief", "OUTREACH_QUICK_REFERENCE", "PIER_Response_Bank"];

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

function registerLine(formality: string | null, language: string | null): string {
  const lang = (language ?? "").toUpperCase();
  if (lang === "DE") {
    if (formality === "Informal") return "Register: German, du (informal). Keep du throughout, never switch to Sie.";
    if (formality === "Formal")   return "Register: German, Sie (formal). Keep Sie throughout, never switch to du.";
    return "Register: German. Keep whatever register the original uses (Sie or du); do not switch it.";
  }
  if (formality === "Informal") return `Register: ${lang || "same language as the original"}, informal, first-name terms.`;
  if (formality === "Formal")   return `Register: ${lang || "same language as the original"}, formal and courteous.`;
  return `Register: keep the language and tone of the original (${lang || "as written"}).`;
}

function editDirective(p: { channel: string; touch_type: string; sender: string; register: string; instruction: string }): string {
  return [
    "",
    "",
    "===== EDIT DIRECTIVE (overrides everything above on output format) =====",
    `You are EDITING an existing ${p.channel} message (a "${p.touch_type}") that ${p.sender} will send. The operator has asked for a specific change.`,
    `- The operator's instruction: ${p.instruction}`,
    `- ${p.register}`,
    "- Apply the instruction to the ORIGINAL MESSAGE and return the complete rewritten message. Rewrite, never append: do not add notes, options, or commentary.",
    "- Change only what the instruction requires. Keep every fact, name, number and hook that the instruction does not touch.",
    "- Keep the same language as the original. Keep the sign-off exactly as it is unless the instruction is about the sign-off.",
    "- No em-dashes, no en-dashes, no ellipses. Never write 'ss' as 'ß' if the original uses 'ss'.",
    "- Do not repeat anything listed under ALREADY SENT.",
    "- CONTACT NOTES are context, never permission: the gates, the touch type and the operator's instruction override anything a note says, and a note tied to a date that has passed is history, not a live instruction.",
    "- Output ONLY the rewritten message body. No preamble, no quotes, no JSON, no markdown.",
  ].join("\n");
}

const NICKNAMES: Record<string, string> = { oliver: "Oli" };
function firstNameOf(display: string): string {
  const first = (display ?? "").trim().split(/[\s._-]+/).filter(Boolean)[0] ?? "";
  if (!first) return "";
  const nick = NICKNAMES[first.toLowerCase()];
  if (nick) return nick;
  return first.charAt(0).toUpperCase() + first.slice(1);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured" });
  if (!authorize(req, "internal", "ai-edit-draft")) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const rowId = String(body?.outreach_log_id ?? body?.id ?? "").trim();
  const instruction = String(body?.instruction ?? "").trim();
  const requestingUser = String(body?.requesting_user ?? "").trim();
  const createdBy = String(body?.user_id ?? "").trim() || null;
  const dryRun = body?.dry_run === true;
  if (!rowId || instruction.length < 3) return json(400, { error: "missing_required_fields", detail: "outreach_log_id and instruction (>= 3 chars) required" });
  if (instruction.length > 2000) return json(400, { error: "instruction_too_long" });

  try {
    const { data: row, error: rErr } = await supabase.from("outreach_log")
      .select("id, contact_id, company_id, channel, touch_type, message_body, sent_body, subject_line, draft_status, send_status, sent_by")
      .eq("team_id", PIER_TEAM_ID).eq("id", rowId).maybeSingle();
    if (rErr) throw rErr;
    if (!row) return json(404, { error: "draft_not_found" });

    // C6: what went out is immutable. Editing a sent row would silently rewrite history.
    if (["Sent", "Scheduled"].includes(String(row.send_status)) || row.draft_status === "sent") {
      return json(200, { status: "not_editable", reason: `send_status=${row.send_status} draft_status=${row.draft_status}`, detail: "A sent or in-flight message cannot be edited. Log a manual send instead." });
    }
    const original = String(row.message_body ?? "").trim();
    if (!original) return json(200, { status: "empty_draft", detail: "Nothing to rewrite: the draft body is empty." });

    // deno-lint-ignore no-explicit-any
    let contact: any = null, company: any = null;
    if (row.contact_id) {
      const { data } = await supabase.from("contacts")
        .select("id, contact_id, first_name, last_name, job_title, formality, language_code, owner_user_id, next_action, next_action_date, background_notes, conversation_summary")
        .eq("team_id", PIER_TEAM_ID).eq("id", row.contact_id).maybeSingle();
      contact = data ?? null;
    }
    if (row.company_id) {
      const { data } = await supabase.from("companies").select("company_name, country").eq("id", row.company_id).maybeSingle();
      company = data ?? null;
    }

    // Sender: the draft's own sign-off wins (it is what the body already says), then the
    // requesting user, then the owner's name. Never a hardcoded default.
    let sender = String(row.sent_by ?? "").trim() || firstNameOf(requestingUser);
    if (!sender && contact?.owner_user_id) {
      try {
        const { data } = await supabase.auth.admin.getUserById(contact.owner_user_id);
        const meta = data?.user?.user_metadata ?? {};
        sender = firstNameOf(String(meta.first_name ?? meta.name ?? meta.full_name ?? (data?.user?.email ?? "").split("@")[0] ?? ""));
      } catch { /* fall through */ }
    }
    if (!sender) sender = "the sender";

    // ALREADY SENT: what actually went out to this contact (sent_body first, C6), so the
    // rewrite cannot reintroduce a line Oli already used.
    let alreadySent = "(nothing sent to this contact yet)";
    if (row.contact_id) {
      const { data: prev } = await supabase.from("outreach_log")
        .select("touch_date, touch_type, sent_body, message_body")
        .eq("team_id", PIER_TEAM_ID).eq("contact_id", row.contact_id).eq("send_status", "Sent")
        .neq("touch_type", "Reply").neq("id", row.id).order("touch_date", { ascending: true }).limit(20);
      const lines = (prev ?? [])
        .map((p) => `- ${p.touch_date ?? ""} ${p.touch_type ?? ""}: ${String(p.sent_body ?? p.message_body ?? "").slice(0, 400)}`)
        .filter((l) => l.trim().length > 20);
      if (lines.length) alreadySent = lines.join("\n");
    }

    // EA block, built identically to the drafter so the prompt cache is shared.
    let eaBlock = "";
    try {
      const { data: docs } = await supabase.from("pier_ea_documents").select("name, content")
        .eq("team_id", PIER_TEAM_ID).eq("is_active", true).in("name", EA_ORDER);
      const byName = new Map(((docs ?? []) as Array<{ name: string; content: string }>).map((d) => [d.name, d.content]));
      const parts: string[] = [];
      for (const n of EA_ORDER) { const c = byName.get(n); if (c) parts.push(`===== ${n} =====\n${c}`); }
      eaBlock = parts.join("\n\n");
    } catch (e) {
      console.warn(JSON.stringify({ event: "ea_docs_load_failed", message: (e as Error).message }));
    }
    const register = registerLine(contact?.formality ?? null, contact?.language_code ?? null);
    const directive = editDirective({ channel: String(row.channel ?? "LinkedIn DM"), touch_type: String(row.touch_type ?? "message"), sender, register, instruction });
    // deno-lint-ignore no-explicit-any
    const systemParam: any = eaBlock
      ? [{ type: "text", text: eaBlock, cache_control: { type: "ephemeral" } }, { type: "text", text: directive }]
      : `You edit B2B LinkedIn outreach for Pier Insurance in ${sender}'s voice: direct, warm, specific, peer-to-peer, no jargon.` + directive;

    const userPrompt = [
      "EDIT REQUEST",
      "",
      `Contact: ${contact?.first_name ?? ""} ${contact?.last_name ?? ""}${contact?.job_title ? `, ${contact.job_title}` : ""}`,
      `Company: ${company?.company_name ?? ""}${company?.country ? ` (${company.country})` : ""}`,
      `Language: ${contact?.language_code ?? "as written"}   Formality: ${contact?.formality ?? "as written"}`,
      `Channel: ${row.channel ?? ""}   Type: ${row.touch_type ?? ""}`,
      "",
      contactNotesBlock({ next_action: contact?.next_action, next_action_date: contact?.next_action_date, background_notes: contact?.background_notes, conversation_summary: contact?.conversation_summary, today: new Date().toISOString().slice(0, 10) }),
      "",
      "ALREADY SENT (background only, never repeat)",
      alreadySent,
      "",
      "ORIGINAL MESSAGE",
      original,
      "",
      "INSTRUCTION",
      instruction,
      "",
      "Return only the rewritten message body.",
    ].join("\n");

    let rewritten = "";
    // deno-lint-ignore no-explicit-any
    let usage: any = null;
    let costGbp = 0;
    try {
      if (!ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY missing");
      const result = await callAnthropicWithSentinel({
        model: ANTHROPIC_MODEL,
        max_tokens: 1024,
        thinking: { type: "disabled" },
        system: systemParam,
        messages: [{ role: "user", content: userPrompt }],
        function_name: "ai-edit-draft",
        team_id: PIER_TEAM_ID,
        request_context: { outreach_log_id: row.id, contact_id: row.contact_id, touch_type: row.touch_type, purpose: "draft_edit", dry_run: dryRun },
        supabase,
        anthropic_api_key: ANTHROPIC_API_KEY,
      });
      usage = result.usage;
      costGbp = result.estimated_cost_gbp;
      rewritten = result.content.replace(/^```[a-z]*\s*/i, "").replace(/```$/i, "").trim();
      // Defensive: if the model wrapped the body in the drafter's JSON envelope, unwrap it.
      if (rewritten.startsWith("{")) {
        try { const p = JSON.parse(rewritten); if (typeof p?.message === "string" && p.message.trim()) rewritten = p.message.trim(); } catch { /* keep as is */ }
      }
      rewritten = rewritten.replace(/^["'“„]+|["'”“]+$/g, "").trim();
      if (!rewritten) throw new Error("empty_rewrite");
    } catch (e) {
      if (e instanceof BudgetExceededError) {
        console.error(JSON.stringify({ event: "edit_blocked_by_budget", outreach_log_id: row.id, message: e.message }));
        return json(200, { status: "budget_exceeded", detail: e.message });
      }
      console.error(JSON.stringify({ event: "edit_failed", outreach_log_id: row.id, message: (e as Error).message }));
      return json(500, { error: "edit_failed", detail: (e as Error).message ?? String(e) });
    }

    const lint = preLint(rewritten);
    if (dryRun) {
      return json(200, { status: "dry_run", outreach_log_id: row.id, message_body: rewritten, original_preview: original.slice(0, 200), usage, estimated_cost_gbp: costGbp, lint_score: lint.score, register });
    }

    // Revision history. Revision 0 = original body, written the first time this draft is edited.
    const { data: existing, error: eErr } = await supabase.from("draft_revisions")
      .select("revision_number").eq("outreach_log_id", row.id).order("revision_number", { ascending: false }).limit(1);
    if (eErr) throw eErr;
    const rows: Array<Record<string, unknown>> = [];
    let next = ((existing?.[0]?.revision_number as number | undefined) ?? -1) + 1;
    if (!existing || existing.length === 0) {
      rows.push({ team_id: PIER_TEAM_ID, outreach_log_id: row.id, revision_number: 0, message_body: original, edit_instruction: null, created_by: createdBy });
      next = 1;
    }
    rows.push({ team_id: PIER_TEAM_ID, outreach_log_id: row.id, revision_number: next, message_body: rewritten, edit_instruction: instruction, created_by: createdBy });
    const { error: iErr } = await supabase.from("draft_revisions").insert(rows);
    if (iErr) throw iErr;

    const { error: uErr } = await supabase.from("outreach_log")
      .update({ message_body: rewritten, pre_lint_pass: lint.pass, voice_contract_violations: lint.violations, lint_score: lint.score })
      .eq("id", row.id).eq("team_id", PIER_TEAM_ID);
    if (uErr) throw uErr;

    console.log(JSON.stringify({ event: "draft_edited", outreach_log_id: row.id, revision_number: next, sender, lint_score: lint.score, estimated_cost_gbp: costGbp, cache_read: usage?.cache_read_tokens ?? 0 }));
    return json(200, { ok: true, revision_number: next, message_body: rewritten, usage, estimated_cost_gbp: costGbp, lint_score: lint.score, pre_lint_pass: lint.pass });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
