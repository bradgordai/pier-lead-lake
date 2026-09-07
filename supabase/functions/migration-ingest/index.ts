// Edge Function: migration-ingest  (Batch C Phase 2, step 1 - TEMPORARY)
//
// Receives workbook rows and writes them VERBATIM into the staging_wb_* tables. Exists
// only because the MCP SQL path cannot carry a 4 MB workbook without pushing every byte
// through the model. Deleted at the end of the migration run.
//
// Gate: verify_jwt=true (the caller presents the project's publishable key) AND the
// request must name an ingest run that is OPEN in migration_audit
// (phase='ingest_gate', action='open', source_ref=<run id>). The gate row is inserted
// just before the upload and closed right after, so the function is inert outside that
// window even before it is deleted. It can only write to staging tables (allow-list).
//
// Body: { run_id, table, rows: [ { ...workbook row as JSON } ] }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

const ALLOWED = new Set(["staging_wb_companies", "staging_wb_contacts", "staging_wb_outreach", "staging_wb_pipeline", "staging_wb_eurefas", "staging_wb_competitor", "staging_wb_market", "staging_wb_monday"]);

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const runId = String(body?.run_id ?? "").trim();
  const table = String(body?.table ?? "").trim();
  const rows = Array.isArray(body?.rows) ? body.rows : [];
  if (!runId || !ALLOWED.has(table) || rows.length === 0) return json(400, { error: "bad_request" });

  const { data: gate } = await supabase.from("migration_audit").select("id")
    .eq("phase", "ingest_gate").eq("action", "open").eq("source_ref", runId).limit(1).maybeSingle();
  if (!gate) return json(403, { error: "ingest_gate_closed" });

  const payload = rows.map((r: Record<string, unknown>, i: number) => ({
    run_id: runId,
    row_num: Number.isFinite(Number(r.__row)) ? Number(r.__row) : i,
    raw: r,
  }));
  const { error } = await supabase.from(table).insert(payload);
  if (error) return json(500, { error: error.message });
  return json(200, { ok: true, inserted: payload.length, table });
});
