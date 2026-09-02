// Edge Function: update-contact-on-cr-accepted
//
// Called by Make.com after the "Recently Connected" phantom fires, once per newly
// accepted LinkedIn connection. Flow: verify shared secret -> look up the contact
// (by canonical linkedin_slug first, then linkedin_url) within the team -> if it's a
// Pier lead (has a Sales Nav list) flip connection_status to 'Accepted' and stamp
// last_contacted, then best-effort chain generate-draft-from-context; otherwise ignore.
//
// URL handling (migration 031): the Sales Nav import stored /sales/lead/ in linkedin_url
// but the canonical /in/{slug} in linkedin_slug; the Recently Connected phantom emits a
// public /in/{slug} URL. So we extract the slug from the incoming profileUrl and match on
// linkedin_slug first, falling back to linkedin_url for rows that stored a /in/ URL directly.
//
// Security / conventions (mirrors upsert-contact-from-sales-nav):
//   - service_role is used ONLY to construct the Supabase client at boot (below).
//     Every query is explicitly scoped to PIER_TEAM_ID because service_role bypasses RLS.
//   - Custom auth: callers present `Authorization: Bearer <INBOUND_WEBHOOK_SECRET>`.
//     The legacy MAKE_SHARED_SECRET is still accepted during the transition and logs
//     `deprecated_secret_used` when it is what worked.
//     Deployed with verify_jwt=false so this Bearer reaches the handler.
//   - DB errors are caught and returned as 500; the function never throws to the runtime.
//   - The connection_status flip is an UPDATE on contacts, so the existing
//     fn_audit_entity trigger records an "Updated <name>" audit_log row automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// Outbound bearer for the chained call to generate-draft-from-context. Prefers the scoped
// internal secret; falls back to the legacy one so the chain keeps working mid-transition.
const OUTBOUND_SECRET = Deno.env.get("INTERNAL_APP_SECRET") || Deno.env.get("MAKE_SHARED_SECRET") || "";
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
// Canonical LinkedIn slug from a public /in/{slug} URL (matches migration 031's regex).
function extractSlug(url: string): string | null {
  const m = /linkedin\.com\/in\/([^/?#]+)/i.exec(url ?? "");
  return m ? m[1] : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured", detail: "PIER_TEAM_ID not set" });

  // Scoped-secret auth (security audit CRITICAL 2).
  if (!authorize(req, "inbound", "update-contact-on-cr-accepted")) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  const profileUrl = String(body?.profileUrl ?? "").trim();
  if (!profileUrl) return json(400, { error: "missing_required_fields", detail: "profileUrl is required" });
  const linkedinUrl = normalizeUrl(profileUrl);
  const slug = extractSlug(profileUrl); // Recently Connected always emits /in/ format

  try {
    // Look up the contact within the team: canonical slug first, then linkedin_url
    // (backward compatible for rows that stored a /in/ URL directly).
    // deno-lint-ignore no-explicit-any
    let contact: any = null;
    if (slug) {
      const r = await supabase
        .from("contacts").select("id, connection_status, sn_lists, company_id")
        .eq("team_id", PIER_TEAM_ID).eq("linkedin_slug", slug).limit(1).maybeSingle();
      if (r.error) throw r.error;
      contact = r.data;
    }
    if (!contact) {
      const r = await supabase
        .from("contacts").select("id, connection_status, sn_lists, company_id")
        .eq("team_id", PIER_TEAM_ID).eq("linkedin_url", linkedinUrl).limit(1).maybeSingle();
      if (r.error) throw r.error;
      contact = r.data;
    }

    // Not a Pier lead (could be a personal CR) — ignore.
    if (!contact) {
      console.log(JSON.stringify({ event: "ignored", reason: "not_in_pier_pipeline", slug, url: linkedinUrl }));
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
        headers: { authorization: `Bearer ${OUTBOUND_SECRET}`, "content-type": "application/json" },
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
