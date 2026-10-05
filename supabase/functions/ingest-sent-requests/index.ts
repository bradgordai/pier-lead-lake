// ingest-sent-requests (F26 Task 2, 2026-10-05)
//
// One POST per run of the PhantomBuster Sent Request Extractor (7326870632604661), the WHOLE pending list in one
// call. LinkedIn's pending-invitation list becomes the source of truth for contacts.connection_status = 'Request sent'.
// All logic is in public.fn_ingest_sent_requests (migration 167) so it can be dry-run and cannot be bypassed:
//   matched profileUrl  -> Request sent, evidence = raw "Sent 2 weeks ago" label, cr_pending_min_age_days
//   absent Request sent -> Not connected (never Accepted / Already connected; never a status set after the run)
//   no contact row      -> unmatched_sent_requests (Reconciliation tab)
//
// Accepted body shapes (Make maps whichever it has; ONE call per run either way):
//   [ {profileUrl, sentDate, timestamp, ...}, ... ]              array of extractor rows (after an Array Aggregate)
//   { "rows": [ ... ] }
//   { "resultObject": "<JSON string of the rows>", ... }          PhantomBuster's own webhook body, passed straight on
// ?dry_run=1 returns the summary and persists nothing.
//
// Auth: inbound class (Make / PhantomBuster) or internal class (cron, EF-to-EF). Deployed with verify_jwt=false.
// Nothing here sends anything to LinkedIn.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";

const FN = "ingest-sent-requests";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// deno-lint-ignore no-explicit-any
const json = (status: number, body: any) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

// deno-lint-ignore no-explicit-any
function extractRows(body: any): any[] | null {
  if (Array.isArray(body)) {
    // An Array Aggregate of webhook bundles can wrap each row one level down; unwrap a lone object value.
    return body.flatMap((r) => (r && typeof r === "object" && !("profileUrl" in r) && Array.isArray(r.rows)) ? r.rows : [r]);
  }
  if (body && Array.isArray(body.rows)) return body.rows;
  if (body && Array.isArray(body.resultObject)) return body.resultObject;
  if (body && typeof body.resultObject === "string") {
    try {
      const parsed = JSON.parse(body.resultObject);
      return Array.isArray(parsed) ? parsed : null;
    } catch { return null; }
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!(authorize(req, "inbound", FN) || authorize(req, "internal", FN))) return json(401, { error: "unauthorized" });
  if (!PIER_TEAM_ID) return json(500, { error: "PIER_TEAM_ID not set" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "body_not_json" }); }
  const rows = extractRows(body);
  if (!rows) return json(400, { error: "no_rows", detail: "Send an array of extractor rows, {rows:[...]}, or PhantomBuster's {resultObject}." });

  const dryRun = new URL(req.url).searchParams.get("dry_run") === "1";
  const { data, error } = await supabase.rpc("fn_ingest_sent_requests", {
    p_team_id: PIER_TEAM_ID, p_rows: rows, p_dry_run: dryRun, p_force_sweep: false,
  });

  if (error) {
    if (dryRun && error.message === "DRY_RUN_ROLLBACK") {
      let summary: unknown = error.details;
      try { summary = JSON.parse(error.details ?? ""); } catch { /* keep raw */ }
      console.log(JSON.stringify({ event: "dry_run", function_name: FN, rows_in: rows.length }));
      return json(200, { ok: true, dry_run: true, summary });
    }
    console.error(JSON.stringify({ event: "ingest_failed", function_name: FN, rows_in: rows.length, message: error.message }));
    return json(500, { error: "ingest_failed", message: error.message });
  }

  console.log(JSON.stringify({ event: "ingested", function_name: FN, rows_in: rows.length,
    matched: data?.matched, unmatched: data?.unmatched, demoted: data?.demoted, absent_sweep: data?.absent_sweep }));
  return json(200, { ok: true, summary: data });
});
