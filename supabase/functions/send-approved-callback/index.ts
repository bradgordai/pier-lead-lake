// Edge Function: send-approved-callback
//
// PhantomBuster posts here when a send phantom finishes, so the outreach_log row can move
// from 'Scheduled' to its terminal state. Wired as the phantom's completion webhook
// (Option B in the spec: phantom -> Edge Function directly, no Make hop).
//
// Auth: scoped bearer via ./_shared/authorize.ts, caller class "inbound" (PhantomBuster
// webhook). Accepts INBOUND_WEBHOOK_SECRET, and MAKE_SHARED_SECRET during the transition
// with a deprecation warning. Security audit CRITICAL 2.
//
// PhantomBuster's completion payload shape varies by script and is not contractually
// stable, so the run id is picked out of several plausible keys and the success/failure
// verdict is derived defensively: anything that is not an explicit success signal is
// treated as a failure, because wrongly marking a message 'Sent' is worse than wrongly
// marking it 'Cancelled' (a Cancelled row gets reviewed; a Sent one does not).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

// deno-lint-ignore no-explicit-any
function pick(o: any, keys: string[]): string {
  for (const k of keys) {
    const v = o?.[k];
    if (typeof v === "string" && v.trim()) return v.trim();
    if (typeof v === "number") return String(v);
  }
  return "";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured", detail: "PIER_TEAM_ID not set" });

  if (!authorize(req, "inbound", "send-approved-callback")) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  // Log the observed shape (keys only, no values) so the real payload contract can be
  // confirmed from the first live run without leaking message text or cookies.
  try { console.log(JSON.stringify({ event: "callback_shape", keys: Object.keys(body ?? {}) })); } catch { /* noop */ }

  const runId = pick(body, ["containerId", "container_id", "phantom_run_id", "runId", "id"]);
  if (!runId) return json(400, { error: "missing_required_fields", detail: "containerId required" });

  const exitCode = body?.exitCode;
  const endType = String(body?.exitMessage ?? body?.lastEndType ?? body?.status ?? "").toLowerCase();
  // Success only on an explicit good signal; everything else is a failure.
  const succeeded = (exitCode === 0 || exitCode === "0") && !/error|fail|timeout|abort/.test(endType);

  try {
    const { data: row, error: fErr } = await supabase.from("outreach_log")
      .select("id, send_status").eq("team_id", PIER_TEAM_ID).eq("phantom_run_id", runId).limit(1).maybeSingle();
    if (fErr) throw fErr;
    if (!row) {
      console.log(JSON.stringify({ event: "orphan_callback", run_id: runId }));
      return json(200, { status: "orphan", reason: "no_outreach_log_row_for_run" });
    }

    const patch = succeeded
      ? { send_status: "Sent", draft_status: "sent", sent_at_actual: new Date().toISOString(), send_error: null }
      : { send_status: "Cancelled", send_error: `phantom_failed exit=${String(exitCode ?? "")} ${endType}`.trim().slice(0, 500) };

    const { error: uErr } = await supabase.from("outreach_log").update(patch).eq("id", row.id).eq("team_id", PIER_TEAM_ID);
    if (uErr) throw uErr;

    console.log(JSON.stringify({ event: succeeded ? "send_confirmed" : "send_failed", id: row.id, run_id: runId, exit_code: exitCode ?? null }));
    return json(200, { status: succeeded ? "confirmed" : "failed", outreach_log_id: row.id, phantom_run_id: runId });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
