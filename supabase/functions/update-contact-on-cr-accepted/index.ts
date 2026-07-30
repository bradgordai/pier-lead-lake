// Edge Function: update-contact-on-cr-accepted
//
// Called by Make.com after the "Recently Connected" phantom fires, once per newly
// accepted LinkedIn connection. Flow: verify shared secret -> look up the contact by
// linkedin_url within the team -> if it's a Pier lead (has a Sales Nav list) flip
// connection_status to 'Accepted' and stamp last_contacted; otherwise ignore. Draft
// generation is deliberately NOT triggered here (that ships as a separate Edge
// Function, generate-draft-from-context).
//
// Security / conventions (mirrors upsert-contact-from-sales-nav):
//   - service_role is used ONLY to construct the Supabase client at boot (below).
//     Every query is explicitly scoped to PIER_TEAM_ID because service_role bypasses RLS.
//   - Custom auth: callers present `Authorization: Bearer <MAKE_SHARED_SECRET>`.
//     Deployed with verify_jwt=false so this Bearer reaches the handler.
//   - DB errors are caught and returned as 500; the function never throws to the runtime.
//   - The connection_status flip is an UPDATE on contacts, so the existing
//     fn_audit_entity trigger records an "Updated <name>" audit_log row automatically —
//     no manual audit write is needed here.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const MAKE_SHARED_SECRET = Deno.env.get("MAKE_SHARED_SECRET") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";

// service_role client — constructed once at boot; only used via the client API.
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// deno-lint-ignore no-explicit-any
const json = (status: number, body: any) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function normalizeUrl(u: string): string {
  return (u ?? "").trim().replace(/\/+$/, "");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  // Config presence (also serves as a secret-wiring check).
  if (!MAKE_SHARED_SECRET) return json(500, { error: "server_misconfigured", detail: "MAKE_SHARED_SECRET not set" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured", detail: "PIER_TEAM_ID not set" });

  // Shared-secret auth.
  const authz = req.headers.get("authorization") ?? "";
  const token = authz.startsWith("Bearer ") ? authz.slice(7) : "";
  if (token !== MAKE_SHARED_SECRET) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  const profileUrl = String(body?.profileUrl ?? "").trim();
  if (!profileUrl) return json(400, { error: "missing_required_fields", detail: "profileUrl is required" });
  const linkedinUrl = normalizeUrl(profileUrl);

  try {
    // Look up the contact within the team.
    const { data: contact, error: lookupErr } = await supabase
      .from("contacts")
      .select("id, connection_status, sn_lists, company_id")
      .eq("team_id", PIER_TEAM_ID)
      .eq("linkedin_url", linkedinUrl)
      .limit(1)
      .maybeSingle();
    if (lookupErr) throw lookupErr;

    // Not a Pier lead (could be a personal CR) — ignore.
    if (!contact) {
      console.log(JSON.stringify({ event: "ignored", reason: "not_in_pier_pipeline", url: linkedinUrl }));
      return json(200, { status: "ignored", reason: "not_in_pier_pipeline" });
    }

    // Must have come from a Sales Nav list to count as a Pier target.
    const lists = Array.isArray(contact.sn_lists) ? contact.sn_lists : [];
    if (lists.length === 0) {
      console.log(JSON.stringify({ event: "ignored", reason: "no_sales_nav_source", contact_id: contact.id }));
      return json(200, { status: "ignored", reason: "no_sales_nav_source" });
    }

    // Flip to Accepted + stamp last_contacted.
    const previousStatus = contact.connection_status;
    const today = new Date().toISOString().slice(0, 10);
    const { error: updErr } = await supabase
      .from("contacts")
      .update({ connection_status: "Accepted", last_contacted: today, updated_at: new Date().toISOString() })
      .eq("id", contact.id)
      .eq("team_id", PIER_TEAM_ID);
    if (updErr) throw updErr;

    console.log(JSON.stringify({ event: "connection_accepted", contact_id: contact.id, previous_status: previousStatus }));

    // Chain into generate-draft-from-context. The connection flip is the primary success;
    // draft generation is best-effort and never fails the request.
    let draft: unknown = null;
    try {
      const draftResp = await fetch(`${SUPABASE_URL}/functions/v1/generate-draft-from-context`, {
        method: "POST",
        headers: { authorization: `Bearer ${MAKE_SHARED_SECRET}`, "content-type": "application/json" },
        body: JSON.stringify({ contact_id: contact.id, trigger_reason: "cr_accepted" }),
      });
      draft = await draftResp.json().catch(() => ({ ok: false, http: draftResp.status }));
      console.log(JSON.stringify({ event: "draft_triggered", http: draftResp.status }));
    } catch (e) {
      console.error(JSON.stringify({ event: "draft_trigger_failed", message: (e as Error).message ?? String(e) }));
      draft = { error: "draft_trigger_failed" };
    }

    return json(200, {
      status: "updated",
      contact_id: contact.id,
      previous_status: previousStatus,
      action: "connection_accepted",
      draft,
    });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
