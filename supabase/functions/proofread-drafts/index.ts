// Edge Function: proofread-drafts (F22B.9(e), 2026-09-23) — i098: typos and grammar are flagged BEFORE Oliver reads.
//
// The drafter's lint (preLint) checks banned words, German ae/oe/ue transliteration and length only: it never looked
// at spelling, grammar or register, so a draft full of mistakes still scored 100 (i084). This function reads each
// pending draft once (and again after an edit) and stores FLAGS on outreach_log.proofread_flags. It NEVER changes the
// text. Cheap model (Haiku), capped per run, driven by the cron job 'proofread-drafts' every 15 minutes, which makes
// no HTTP call when nothing is waiting.
//
// POST (internal class) { limit?: number (<= 25), ids?: uuid[] }
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorizeRequest } from "./_shared/authorize.ts";
import { callAnthropicWithSentinel, BudgetExceededError } from "./_shared/anthropic-sentinel.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const MODEL = "claude-haiku-4-5-20251001";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

const SYSTEM = `You proofread short B2B LinkedIn messages (German or English) written for Oliver Müller of Pier Insurance.
Report ONLY real problems a native speaker would fix before sending:
- spelling mistakes and typos;
- grammar faults (agreement, case, word order, missing words);
- mixed register in German: "Sie" and "du/ihr/euch" in the same message, or a greeting that does not match the body;
- German written without umlauts (ae/oe/ue/ss for ä/ö/ü/ß) outside Swiss usage;
- a doubled or dangling sign-off, a leftover placeholder like [Name] or {{company}}.
Do NOT flag style, tone, length, product claims or anything you merely prefer. Do NOT rewrite the message.
Return ONLY JSON: {"flags":[{"kind":"spelling|grammar|register|umlaut|signoff|placeholder","excerpt":"verbatim, max 60 chars","issue":"max 15 words","suggestion":"max 10 words"}]}
Return {"flags":[]} when the message is clean.`;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID || !ANTHROPIC_API_KEY) return json(500, { error: "server_misconfigured" });
  const auth = await authorizeRequest(req, "internal", "proofread-drafts", supabase);
  if (!auth.ok) return json(401, { error: "unauthorized" });
  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try { body = await req.json(); } catch { /* empty body is fine */ }
  const limit = Math.min(Math.max(Number(body?.limit ?? 20), 1), 25);
  const ids: string[] = Array.isArray(body?.ids) ? body.ids.map(String).slice(0, 25) : [];

  let q = supabase.from("outreach_log").select("id, message_body, draft_language, channel, touch_type, updated_at, proofread_at")
    .eq("team_id", PIER_TEAM_ID).eq("draft_status", "pending_review").not("message_body", "is", null);
  if (ids.length) q = q.in("id", ids);
  const { data: rows, error } = await q.order("created_at", { ascending: true }).limit(200);
  if (error) return json(500, { error: "read_failed", detail: error.message });
  // Not yet proofread, or edited since the last proofread.
  const todo = (rows ?? []).filter((r) => !r.proofread_at || Date.parse(r.updated_at) > Date.parse(r.proofread_at) + 1000).slice(0, limit);

  const results: Array<Record<string, unknown>> = [];
  for (const r of todo) {
    try {
      const res = await callAnthropicWithSentinel({
        model: MODEL, max_tokens: 600, thinking: { type: "disabled" }, system: SYSTEM,
        messages: [{ role: "user", content: `Language: ${r.draft_language ?? "unknown"}. Channel: ${r.channel}. Message:\n\n${r.message_body}` }],
        function_name: "proofread-drafts", team_id: PIER_TEAM_ID, request_context: { outreach_log_id: r.id },
        supabase, anthropic_api_key: ANTHROPIC_API_KEY,
      });
      const m = res.content.match(/\{[\s\S]*\}/);
      // deno-lint-ignore no-explicit-any
      const parsed: any = m ? JSON.parse(m[0]) : { flags: [] };
      // deno-lint-ignore no-explicit-any
      const flags = (Array.isArray(parsed?.flags) ? parsed.flags : []).filter((f: any) => typeof f?.excerpt === "string" && typeof f?.issue === "string")
        // deno-lint-ignore no-explicit-any
        .slice(0, 12).map((f: any) => ({ kind: String(f.kind ?? "other").slice(0, 20), excerpt: String(f.excerpt).slice(0, 80),
          issue: String(f.issue).slice(0, 140), suggestion: f.suggestion ? String(f.suggestion).slice(0, 100) : null }));
      // Stamp only if the body is still the one that was read (no race with an edit).
      await supabase.from("outreach_log").update({ proofread_flags: flags, proofread_at: new Date().toISOString(), proofread_model: MODEL })
        .eq("id", r.id).eq("message_body", r.message_body);
      results.push({ id: r.id, flags: flags.length, cost_gbp: res.estimated_cost_gbp });
    } catch (e) {
      results.push({ id: r.id, error: (e as Error).message });
      if (e instanceof BudgetExceededError) break;
    }
  }
  return json(200, { checked: results.length, waiting_after: Math.max(0, (rows ?? []).length - todo.length), results });
});
