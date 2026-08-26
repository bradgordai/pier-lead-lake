// Edge Function: send-approved-callback
//
// Terminal state for a send. Called by the Make scenario "Pier Send Callback", which both
// PhantomBuster phantoms notify on completion. Make forwards:
//   { containerId, agentId, exitCode, exitMessage, resultObject }
//
// Auth: Bearer via ./_shared/authorize.ts (caller class "inbound"), OR `?auth=<secret>` as
// an alternative. PhantomBuster's own notifications.webhook field is a bare URL with no
// header configuration, so a phantom pointed straight at this endpoint could never send a
// Bearer. The query-param path exists so that still works. Make itself uses the Bearer.
//
// ---------------------------------------------------------------------------
// WHY resultObject DECIDES SUCCESS, NOT exitCode
//
// PhantomBuster exits 0 on a no-op. Verified live 2026-08-26: container 3731377894543956
// finished in 4 seconds with exitCode 0, endType "finished", and the log line
// "Spreadsheet is empty OR everyone is processed" - it had silently SKIPPED the recipient
// because that profile was already messaged in an earlier run. resultObject was null.
// A real send (container 1793456300808120) took 114s and returned a populated array.
//
// Treating exitCode 0 as success would therefore mark a row 'Sent' for a message that was
// never delivered - the worst failure this function can have, because a Sent row is never
// reviewed again. Success requires a NON-EMPTY resultObject array.
//
// resultObject arrives either as a real array or as a JSON string depending on whether Make
// parsed it, so it is normalised before the check. Getting that wrong in the other
// direction would report a genuine send as skipped.
// ---------------------------------------------------------------------------

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

/** Bearer, or ?auth=<secret> for callers that cannot set headers. */
function authorized(req: Request): boolean {
  if (authorize(req, "inbound", "send-approved-callback")) return true;
  const q = new URL(req.url).searchParams.get("auth") ?? "";
  if (!q) return false;
  const scoped = Deno.env.get("INBOUND_WEBHOOK_SECRET") ?? "";
  const legacy = Deno.env.get("MAKE_SHARED_SECRET") ?? "";
  if (scoped && q === scoped) return true;
  if (legacy && q === legacy) {
    console.warn(JSON.stringify({ event: "deprecated_secret_used", function_name: "send-approved-callback", via: "query_param" }));
    return true;
  }
  return false;
}

/**
 * Normalise resultObject to an array. PhantomBuster returns a JSON string; Make may or may
 * not have parsed it. Anything that is not a parseable array becomes [].
 */
// deno-lint-ignore no-explicit-any
function toArray(v: any): unknown[] {
  if (Array.isArray(v)) return v;
  if (typeof v === "string") {
    const t = v.trim();
    if (!t || t === "null") return [];
    try {
      const parsed = JSON.parse(t);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
}

// deno-lint-ignore no-explicit-any
async function logAudit(action: string, entityId: string, summary: string, after: any) {
  try {
    await supabase.from("audit_log").insert({
      team_id: PIER_TEAM_ID,
      entity_type: "outreach_log",
      entity_id: entityId,
      action,
      summary,
      after_value: after ?? null,
      source: "phantombuster_callback",
    });
  } catch (e) {
    // Never let audit failure mask the state change.
    console.error(JSON.stringify({ event: "audit_log_failed", action, message: (e as Error).message }));
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured", detail: "PIER_TEAM_ID not set" });
  if (!authorized(req)) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  try { console.log(JSON.stringify({ event: "callback_shape", keys: Object.keys(body ?? {}) })); } catch { /* noop */ }

  const runId = pick(body, ["containerId", "container_id", "phantom_run_id", "runId", "id"]);
  if (!runId) return json(400, { error: "missing_required_fields", detail: "containerId required" });

  const exitCodeRaw = body?.exitCode;
  const exitCode = Number(exitCodeRaw);
  const exitMessage = String(body?.exitMessage ?? body?.lastEndType ?? "").trim();
  const results = toArray(body?.resultObject);

  try {
    const { data: row, error: fErr } = await supabase.from("outreach_log")
      .select("id, contact_ref, send_status, draft_status")
      .eq("team_id", PIER_TEAM_ID).eq("phantom_run_id", runId).limit(1).maybeSingle();
    if (fErr) throw fErr;
    if (!row) {
      console.log(JSON.stringify({ event: "orphan_callback", run_id: runId }));
      return json(200, { status: "orphan", reason: "no_outreach_log_row_for_run" });
    }

    // --- Non-zero exit: the run itself failed ---
    if (!Number.isFinite(exitCode) || exitCode !== 0) {
      const err = exitMessage || `phantom_failed exit=${String(exitCodeRaw ?? "")}`;
      const { error: uErr } = await supabase.from("outreach_log")
        .update({ send_status: "Cancelled", send_error: err.slice(0, 500) })
        .eq("id", row.id).eq("team_id", PIER_TEAM_ID);
      if (uErr) throw uErr;
      await logAudit("send_failed", row.id, `Send failed: ${err}`.slice(0, 300), { phantom_run_id: runId, exit_code: exitCodeRaw, exit_message: exitMessage });
      console.error(JSON.stringify({ event: "send_failed", id: row.id, run_id: runId, exit_code: exitCodeRaw }));
      return json(200, { status: "send_failed", outreach_log_id: row.id, phantom_run_id: runId, error: err });
    }

    // --- exit 0 but nothing produced: the phantom skipped (duplicate / empty input) ---
    if (results.length === 0) {
      const { error: uErr } = await supabase.from("outreach_log")
        .update({ send_status: "Cancelled", send_error: "phantom_skipped_duplicate_or_empty" })
        // draft_status deliberately left at 'approved' so Oli can decide whether to resend
        // or send by hand. The message never went out; it is not 'sent'.
        .eq("id", row.id).eq("team_id", PIER_TEAM_ID);
      if (uErr) throw uErr;
      await logAudit("send_skipped", row.id, "LinkedIn skipped this send (already messaged recently, or empty input). Draft left in Approved.", { phantom_run_id: runId, exit_code: 0, exit_message: exitMessage });
      console.warn(JSON.stringify({ event: "send_skipped", id: row.id, run_id: runId }));
      return json(200, { status: "send_skipped", outreach_log_id: row.id, phantom_run_id: runId, reason: "phantom_skipped_duplicate_or_empty" });
    }

    // --- exit 0 with a populated result: a real send ---
    const { error: uErr } = await supabase.from("outreach_log")
      .update({ send_status: "Sent", draft_status: "sent", sent_at_actual: new Date().toISOString(), send_error: null })
      .eq("id", row.id).eq("team_id", PIER_TEAM_ID);
    if (uErr) throw uErr;
    await logAudit("send_completed", row.id, `Sent via LinkedIn (${results.length} recipient${results.length === 1 ? "" : "s"}).`, { phantom_run_id: runId, exit_code: 0, results: results.length });
    console.log(JSON.stringify({ event: "send_completed", id: row.id, run_id: runId, results: results.length }));
    return json(200, { status: "send_completed", outreach_log_id: row.id, phantom_run_id: runId, results: results.length });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
