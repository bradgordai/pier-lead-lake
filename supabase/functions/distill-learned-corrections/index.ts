// Edge Function: distill-learned-corrections (F22B.6, 2026-09-23) — raw corrections become durable rules.
//
// Reads the training-enabled draft_feedback added since the last run (signal_type 'draft_quality' only: feedback about
// a contact who has left, is the wrong person or a referral never teaches the drafter anything about writing), and on
// request the historic rejected drafts and hand edits held in outreach_log. One Claude call sorts every correction into
//   - a WRITING rule: durable, compact, general ("German output uses real umlauts, never ae/oe/ue"), or
//   - a SYSTEM issue: a state, timing, routing or data problem that no prompt can fix (left company, cooldown,
//     unsynced history, not connected, out of scope). These are reported, never written into the prompt.
// It merges the writing rules into the existing active rules (condensing, never just appending), scoped by touch_type
// and channel, under CHAR_CEILING. Each rule keeps the feedback / touch ids that produced it (learned_correction_rules).
// The rendered text becomes voice_assets 'learned_corrections' (layer 5) with a bumped version.
//
// NOT WIRED: generate-draft-from-context does not load layer 5 until Brad approves (F22B.6(g)). The weekly cron job
// is created inactive; the first run is manual.
//
// POST (internal class) { dry_run?: boolean, include_legacy?: boolean, triggered_by?: string }
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorizeRequest } from "./_shared/authorize.ts";
import { callAnthropicWithSentinel } from "./_shared/anthropic-sentinel.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const MODEL = "claude-sonnet-5";
const CHAR_CEILING = 4000;           // the whole rendered layer; condense rather than exceed
const SYSTEM_REASON_CODES = new Set(["group_sibling_engaged"]); // refusals written by the gates, not by a person

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });
const ws = (s: unknown) => String(s ?? "").replace(/\s+/g, " ").trim();

const SYSTEM = `You maintain "learned_corrections", layer 5 of the Pier drafting prompt: COMPACT, DURABLE writing rules learned
from Oliver's corrections of AI drafts (LinkedIn DMs, InMails, connection-request notes, chasers; German and English).

For EVERY correction you receive, decide:
- WRITING: it tells the drafter how to write (language, register, tone, length, structure, wording, facts to never
  claim, sign-off). Turn it into a general rule a future draft can follow. One rule may cover many corrections.
- SYSTEM: it is about state, timing, routing or data, which a prompt cannot fix (the person left the company, is in
  cooldown, a promise of quiet, messages missing from the history, not connected, out of scope, too small, a parallel
  conversation at the same company, a CR not sent). Report it; never make it a rule.

Merge with the EXISTING rules: keep, reword, merge or drop them. Never duplicate. Keep the whole set under ${CHAR_CEILING}
characters: when it gets close, CONDENSE. A rule applies to every touch type and channel unless the evidence is specific
to one ("Chaser 1", "LinkedIn inMail", ...). Never invent a rule without a correction behind it.

Return ONLY JSON:
{"rules":[{"text":"...","touch_type":null|"...","channel":null|"...","sources":["<id>", ...]}],
 "system_issues":[{"source":"<id>","category":"left_company|cooldown_or_quiet|history_missing|not_connected|out_of_scope|parallel_contact|other","note":"at most 12 words"}]}
Keep every "note" to 12 words or fewer.`;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID || !ANTHROPIC_API_KEY) return json(500, { error: "server_misconfigured" });
  const auth = await authorizeRequest(req, "internal", "distill-learned-corrections", supabase);
  if (!auth.ok) return json(401, { error: "unauthorized" });
  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try { body = await req.json(); } catch { /* empty body is fine */ }
  const dryRun = body?.dry_run === true;
  const includeLegacy = body?.include_legacy === true;
  const triggeredBy = String(body?.triggered_by ?? (auth.user_id ? "manual_ui" : "manual")).slice(0, 40);

  const { data: asset } = await supabase.from("voice_assets").select("version").eq("id", "learned_corrections").maybeSingle();
  const versionBefore = String(asset?.version ?? "lc-v0");
  const { data: lastRun } = await supabase.from("learned_correction_runs").select("finished_at").eq("team_id", PIER_TEAM_ID)
    .eq("status", "done").order("finished_at", { ascending: false }).limit(1).maybeSingle();
  const since = lastRun?.finished_at ?? "1970-01-01T00:00:00Z";

  const { data: run, error: runErr } = await supabase.from("learned_correction_runs").insert({
    team_id: PIER_TEAM_ID, status: "running", triggered_by: triggeredBy, version_before: versionBefore, char_ceiling: CHAR_CEILING,
  }).select("id").single();
  if (runErr) return json(500, { error: "run_insert_failed", detail: runErr.message });

  try {
    // 1. New training-enabled feedback about the DRAFT (never about the contact's state).
    const { data: fb } = await supabase.from("draft_feedback")
      .select("id, touch_type, channel, language, action, reason_code, note, rejected_body, replacement_body, created_at")
      .eq("team_id", PIER_TEAM_ID).eq("use_for_training", true).eq("signal_type", "draft_quality").gt("created_at", since)
      .order("created_at", { ascending: true }).limit(200);
    const corrections: Array<Record<string, unknown>> = (fb ?? []).map((f) => ({
      id: `fb:${f.id}`, touch_type: f.touch_type, channel: f.channel, language: f.language, action: f.action,
      reason: f.reason_code, note: ws(f.note).slice(0, 400), rejected_excerpt: ws(f.rejected_body).slice(0, 500),
      replacement_excerpt: ws(f.replacement_body).slice(0, 500),
    }));
    // 2. Legacy history (first run only, on request): rejected drafts with a human reason, and real hand edits.
    let legacyCount = 0;
    if (includeLegacy) {
      const { data: rej } = await supabase.from("outreach_log")
        .select("id, touch_type, channel, draft_language, rejection_feedback, message_body")
        .eq("team_id", PIER_TEAM_ID).eq("draft_status", "rejected").not("rejection_feedback", "is", null).limit(300);
      for (const r of rej ?? []) {
        const rf = (r.rejection_feedback ?? {}) as Record<string, unknown>;
        const reason = String(rf.reason ?? "");
        if (SYSTEM_REASON_CODES.has(reason)) continue;
        corrections.push({ id: `touch:${r.id}`, touch_type: r.touch_type, channel: r.channel, language: r.draft_language,
          action: "rejected", reason, note: ws(rf.detail ?? rf.note).slice(0, 400), rejected_excerpt: ws(r.message_body).slice(0, 500) });
        legacyCount++;
      }
      const { data: ed } = await supabase.from("outreach_log")
        .select("id, touch_type, channel, draft_language, message_body, sent_body")
        .eq("team_id", PIER_TEAM_ID).eq("agent_produced", true).eq("send_status", "Sent").not("sent_body", "is", null).limit(1000);
      for (const e of ed ?? []) {
        if (!e.message_body || ws(e.message_body) === ws(e.sent_body)) continue; // whitespace-only differences are not edits
        corrections.push({ id: `touch:${e.id}`, touch_type: e.touch_type, channel: e.channel, language: e.draft_language,
          action: "edited_before_send", rejected_excerpt: ws(e.message_body).slice(0, 700), replacement_excerpt: ws(e.sent_body).slice(0, 700) });
        legacyCount++;
      }
    }

    const { data: existing } = await supabase.from("learned_correction_rules").select("id, rule_text, scope_touch_type, scope_channel")
      .eq("team_id", PIER_TEAM_ID).eq("status", "active");

    if (!corrections.length) {
      await supabase.from("learned_correction_runs").update({ status: dryRun ? "dry_run" : "done", finished_at: new Date().toISOString(),
        feedback_considered: 0, legacy_considered: 0, writing_rules: (existing ?? []).length, system_issues: [], version_after: versionBefore,
        output: { note: "nothing new to distil" } }).eq("id", run.id);
      return json(200, { run_id: run.id, status: "nothing_to_distil", rules: existing ?? [] });
    }

    const r = await callAnthropicWithSentinel({
      // v2: 2,000 truncated the first run (43 legacy corrections -> 2,000 output tokens, broken JSON).
      model: MODEL, max_tokens: 6000, thinking: { type: "disabled" }, system: SYSTEM,
      messages: [{ role: "user", content: JSON.stringify({ existing_rules: existing ?? [], corrections }) }],
      function_name: "distill-learned-corrections", team_id: PIER_TEAM_ID,
      request_context: { run_id: run.id, corrections: corrections.length, dry_run: dryRun }, supabase, anthropic_api_key: ANTHROPIC_API_KEY,
    });
    const m = r.content.match(/\{[\s\S]*\}/);
    if (!m) throw new Error("distiller returned no JSON");
    // deno-lint-ignore no-explicit-any
    const out: any = JSON.parse(m[0]);
    // deno-lint-ignore no-explicit-any
    const rules: any[] = Array.isArray(out?.rules) ? out.rules.filter((x: any) => typeof x?.text === "string" && x.text.trim()) : [];
    const issues = Array.isArray(out?.system_issues) ? out.system_issues : [];

    // Render grouped by scope and enforce the ceiling in code.
    const groupKey = (x: { touch_type: string | null; channel: string | null }) => `${x.touch_type ?? "All touch types"} / ${x.channel ?? "all channels"}`;
    const groups = new Map<string, string[]>();
    for (const x of rules) { const k = groupKey(x); groups.set(k, [...(groups.get(k) ?? []), `- ${ws(x.text)}`]); }
    const rendered = rules.length
      ? Array.from(groups.entries()).map(([k, v]) => `## ${k}\n${v.join("\n")}`).join("\n\n")
      : "(No writing rules learned yet. The corrections so far were about state, timing or data, not wording.)";
    if (rendered.length > CHAR_CEILING) throw new Error(`rendered layer ${rendered.length} chars exceeds ceiling ${CHAR_CEILING}`);
    const n = Number(/^lc-v(\d+)/.exec(versionBefore)?.[1] ?? 0) + 1;
    const versionAfter = `lc-v${n} (${new Date().toISOString().slice(0, 10)}; ${rules.length} rules; not wired)`;

    if (!dryRun) {
      await supabase.from("learned_correction_rules").update({ status: "deleted" }).eq("team_id", PIER_TEAM_ID).eq("status", "active");
      if (rules.length) {
        await supabase.from("learned_correction_rules").insert(rules.map((x) => {
          const src: string[] = Array.isArray(x.sources) ? x.sources.map(String) : [];
          return { team_id: PIER_TEAM_ID, rule_text: ws(x.text), scope_touch_type: x.touch_type ?? null, scope_channel: x.channel ?? null,
            source_feedback_ids: src.filter((s) => s.startsWith("fb:")).map((s) => s.slice(3)),
            source_touch_ids: src.filter((s) => s.startsWith("touch:")).map((s) => s.slice(6)), created_by_run: run.id };
        }));
      }
      await supabase.from("voice_assets").update({ body: rendered, version: versionAfter, updated_at: new Date().toISOString(),
        updated_by: `distill-learned-corrections run ${run.id}` }).eq("id", "learned_corrections");
    }
    await supabase.from("learned_correction_runs").update({ status: dryRun ? "dry_run" : "done", finished_at: new Date().toISOString(),
      feedback_considered: (fb ?? []).length, legacy_considered: legacyCount, writing_rules: rules.length, system_issues: issues,
      version_after: dryRun ? versionBefore : versionAfter, chars: rendered.length, estimated_cost_gbp: r.estimated_cost_gbp,
      output: { rules, rendered } }).eq("id", run.id);
    return json(200, { run_id: run.id, dry_run: dryRun, corrections: corrections.length, rules, system_issues: issues,
      rendered, chars: rendered.length, version_after: dryRun ? versionBefore : versionAfter, cost_gbp: r.estimated_cost_gbp });
  } catch (e) {
    const msg = (e as Error).message ?? String(e);
    await supabase.from("learned_correction_runs").update({ status: "failed", finished_at: new Date().toISOString(), error: msg.slice(0, 500) }).eq("id", run.id);
    return json(500, { error: "distill_failed", detail: msg, run_id: run.id });
  }
});
