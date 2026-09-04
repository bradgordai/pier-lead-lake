// Edge Function: migration-classify  (Batch C Phase 2, step 5 - TEMPORARY)
//
// Haiku-classifies the frozen workbook's Outreach Log rows so the migration can route each
// one: real outbound messages become touches with bodies, notes become dated appends,
// company tasks go to the sourcing queue, CR events become touches + connection sync.
// Sentinel-wrapped (cost logged, budget fail-closed). Writes staging_wb_outreach.
// classification + migration_note only; never touches live tables.
//
// Auth: INTERNAL_APP_SECRET. Body: { run_id, batches?: 12, batch_size?: 25 }
// Each call processes up to `batches` unclassified batches and returns progress, so the
// caller loops until remaining = 0.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";
import { callAnthropicWithSentinel, BudgetExceededError } from "./_shared/anthropic-sentinel.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODEL = "claude-haiku-4-5-20251001";
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

const CLASSES = ["message", "cr_event", "inbound", "note", "task", "register", "draft_unsent", "ambiguous"];

const SYSTEM = `You classify rows from a B2B LinkedIn outreach log kept in a spreadsheet. Each row has a Type, Channel, Send Status, Outcome and a "Message Body / Notes" cell that may hold a real message that was sent, an internal note, a placeholder, or nothing.

Return ONLY a JSON array, one object per input row, in the same order, with exactly these keys:
- "ref": the Touch ID as given
- "class": one of ${JSON.stringify(CLASSES)}
  message      = an OUTBOUND message that was actually SENT (DM, InMail, email, CR note with real text). The body cell contains the real message text.
  cr_event     = a connection request sent / accepted / withdrawn event, or a blank CR (no message text). Includes "CR blank", "Connection request", "CR-accept", "Withdrawn".
  inbound      = a REPLY or message RECEIVED from the contact (their words), or a record of an inbound acknowledgment.
  note         = an internal note about the contact or thread (status, observation, reminder) that is NOT a message body and NOT a task.
  task         = a to-do for the team (e.g. "Company task", source contacts, verify insurance, find URL).
  register     = a bookkeeping row: "Thread verified empty", "Touch (register)", thread check with no text, placeholder for a message whose text was not captured.
  draft_unsent = a drafted or scheduled message that was NOT sent (Send Status Draft/Scheduled) with real draft text.
  ambiguous    = cannot tell.
- "has_body": true if the body cell contains the actual words of a message (sent or received), false if it is a note/placeholder/description in square brackets/empty.
- "poq": true ONLY if the text is a message to the contact that PROMISES TO STOP contacting them (e.g. "this is my last message", "letzte Nachricht von mir", "I will leave it there", "das war's dann von mir"). A scheduled future check-in is NOT a promise to stop.
- "why": at most 12 words.

Rules: a bracketed description like "[Blank CR sent]" or "[90-day re-engagement draft - ...]" is NOT a body (has_body false). Text in German, French, Italian or Dutch counts as a body when it is the message itself. Do not invent rows; output exactly one object per input row.`;

// Mode 'country': infer a company's country from its website domain + name for rows the
// ccTLD rule could not settle (.com/.eu/.net). Marked country_inferred=true; never unlocks email.
async function inferCountries(runId: string): Promise<Response> {
  const { data: rows, error } = await supabase.from("companies")
    .select("id, company_id, company_name, website_url, headquarter_location, additional_notes")
    .is("country", null).not("website_url", "is", null).limit(60);
  if (error) return json(500, { error: error.message });
  if (!rows || rows.length === 0) return json(200, { status: "ok", done: 0, remaining: 0 });
  const input = rows.map((r) => ({ ref: r.company_id, name: r.company_name, website: r.website_url, hq: r.headquarter_location, notes: String(r.additional_notes ?? "").slice(0, 200) }));
  const sys = `You infer the HOME COUNTRY of a company from its name, website domain, HQ text and notes. Return ONLY a JSON array in input order: {"ref":..., "country": "<country name in English, e.g. Germany, Austria, Switzerland, UK, France, Netherlands, Italy, Spain, Sweden, Denmark, Finland, Norway, Poland, Belgium, Ireland, Portugal, Czech Republic, United States> or null", "confidence": "high"|"medium"|"low"}. Use null when you cannot tell. Never guess from a generic .com alone without another signal.`;
  let done = 0, cost = 0;
  try {
    const res = await callAnthropicWithSentinel({ model: MODEL, max_tokens: 3000, system: sys, messages: [{ role: "user", content: JSON.stringify(input) }], function_name: "migration-classify", team_id: PIER_TEAM_ID, request_context: { run_id: runId, mode: "country", n: rows.length }, supabase, anthropic_api_key: ANTHROPIC_API_KEY });
    cost = res.estimated_cost_gbp;
    const txt = res.content.replace(/^```[a-z]*\s*/i, "").replace(/```$/i, "").trim();
    const m = txt.match(/\[[\s\S]*\]/);
    const parsed = JSON.parse(m ? m[0] : txt) as Array<Record<string, unknown>>;
    for (const p of parsed) {
      const r = rows.find((x) => x.company_id === String(p.ref));
      const country = typeof p.country === "string" && p.country.trim() ? p.country.trim() : null;
      if (!r || !country || p.confidence === "low") {
        if (r) await supabase.from("migration_audit").insert({ run_id: runId, phase: "phase2_companies", entity: "companies", source_ref: r.company_id, action: "country_inference_unresolved", target_id: r.id, detail: { country, confidence: p.confidence } });
        continue;
      }
      await supabase.from("companies").update({ country, country_inferred: true }).eq("id", r.id);
      await supabase.from("migration_audit").insert({ run_id: runId, phase: "phase2_companies", entity: "companies", source_ref: r.company_id, action: "country_inferred_haiku", target_id: r.id, detail: { country, confidence: p.confidence, website: r.website_url } });
      done++;
    }
  } catch (e) {
    if (e instanceof BudgetExceededError) return json(200, { status: "budget_exceeded" });
    return json(500, { error: (e as Error).message });
  }
  const { count } = await supabase.from("companies").select("id", { count: "exact", head: true }).is("country", null).not("website_url", "is", null);
  return json(200, { status: "ok", done, considered: rows.length, estimated_cost_gbp: cost, remaining: count ?? 0 });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!authorize(req, "internal", "migration-classify")) return json(401, { error: "unauthorized" });
  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try { body = await req.json(); } catch { /* defaults */ }
  const runId = String(body?.run_id ?? "").trim();
  if (body?.mode === "country") return await inferCountries(runId);
  const batches = Math.max(1, Math.min(30, Number(body?.batches ?? 12)));
  const batchSize = Math.max(5, Math.min(40, Number(body?.batch_size ?? 25)));
  if (!runId) return json(400, { error: "run_id required" });

  let done = 0, failed = 0, cost = 0;
  try {
    for (let b = 0; b < batches; b++) {
      const { data: rows, error } = await supabase.from("staging_wb_outreach")
        .select("id, touch_ref, contact_ref, touch_date, channel, touch_type, send_status, outcome, message_body, raw")
        .eq("run_id", runId).is("classification", null).order("row_num", { ascending: true }).limit(batchSize);
      if (error) throw error;
      if (!rows || rows.length === 0) break;

      const input = rows.map((r) => ({
        ref: r.touch_ref, type: r.touch_type, channel: r.channel, send_status: r.send_status,
        outcome: (r.outcome ?? "").slice(0, 160), next_action: String(r.raw?.["Next Action"] ?? "").slice(0, 120),
        body: (r.message_body ?? "").slice(0, 700),
      }));
      let parsed: Array<Record<string, unknown>> = [];
      try {
        const res = await callAnthropicWithSentinel({
          model: MODEL, max_tokens: 4000, system: SYSTEM,
          messages: [{ role: "user", content: "ROWS:\n" + JSON.stringify(input) }],
          function_name: "migration-classify", team_id: PIER_TEAM_ID,
          request_context: { run_id: runId, batch_first_ref: rows[0].touch_ref, n: rows.length, purpose: "workbook_outreach_classification" },
          supabase, anthropic_api_key: ANTHROPIC_API_KEY,
        });
        cost += res.estimated_cost_gbp;
        const txt = res.content.replace(/^```[a-z]*\s*/i, "").replace(/```$/i, "").trim();
        const m = txt.match(/\[[\s\S]*\]/);
        parsed = JSON.parse(m ? m[0] : txt);
      } catch (e) {
        if (e instanceof BudgetExceededError) return json(200, { status: "budget_exceeded", done, failed, cost });
        // Mark the batch so the loop cannot spin on a poison batch; leave a note for a retry pass.
        for (const r of rows) {
          await supabase.from("staging_wb_outreach").update({ classification: "error", migration_note: `classify_failed: ${(e as Error).message}`.slice(0, 300) }).eq("id", r.id);
        }
        failed += rows.length;
        continue;
      }
      const byRef = new Map(parsed.map((p) => [String(p.ref ?? ""), p]));
      for (const r of rows) {
        const p = byRef.get(String(r.touch_ref));
        const cls = p && CLASSES.includes(String(p.class)) ? String(p.class) : "ambiguous";
        const note = p ? JSON.stringify({ has_body: !!p.has_body, poq: !!p.poq, why: String(p.why ?? "").slice(0, 120) }) : "model_omitted_row";
        await supabase.from("staging_wb_outreach").update({ classification: cls, migration_note: note }).eq("id", r.id);
        done++;
      }
    }
    const { count } = await supabase.from("staging_wb_outreach").select("id", { count: "exact", head: true }).eq("run_id", runId).is("classification", null);
    return json(200, { status: "ok", done, failed, estimated_cost_gbp: Number(cost.toFixed(4)), remaining: count ?? 0 });
  } catch (e) {
    return json(500, { error: (e as Error).message ?? String(e), done, failed });
  }
});
