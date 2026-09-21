// Edge Function: update-contact-on-cr-accepted  (F14.2 2026-09-14: heartbeat; F15.4 2026-09-15: event-driven, transition-only)
//
// Called by Make.com after the "Recently Connected" phantom fires, once per newly
// accepted LinkedIn connection. Flow: verify shared secret -> look up the contact
// (by canonical linkedin_slug first, then linkedin_url) within the team -> if it's a
// Pier lead (has a Sales Nav list) and is NOT already Accepted, flip connection_status to
// 'Accepted', stamp last_contacted (the acceptance date), refund the InMail credit and
// draft the first message immediately (matrix r4: Initial message / LinkedIn DM, through
// fn_evaluate_gates inside the drafter). Otherwise ignore.
//
// F15.4: the phantom reports the same acceptance on every run, so before this the watcher
// re-stamped last_contacted every day and re-asked for a draft every day (27 re-stamps on
// 15 Sep). Now only a real transition to Accepted does anything; a repeat is logged and ignored.
//
// Auth: INBOUND_WEBHOOK_SECRET (inbound class), verify_jwt=false. service_role client at boot,
// every query scoped to PIER_TEAM_ID.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const OUTBOUND_SECRET = Deno.env.get("INTERNAL_APP_SECRET") || Deno.env.get("MAKE_SHARED_SECRET") || "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
async function heartbeat(rows: number, ok = true, err?: string): Promise<void> {
  try {
    const { error } = await supabase.rpc("fn_heartbeat", { p_source: "connection_watcher", p_rows: rows, p_ok: ok, p_error: err ?? null });
    if (error) console.error(JSON.stringify({ event: "heartbeat_failed", source: "connection_watcher", message: error.message }));
  } catch (e) { console.error(JSON.stringify({ event: "heartbeat_failed", source: "connection_watcher", message: (e as Error).message })); }
}

// deno-lint-ignore no-explicit-any
const json = (status: number, body: any) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function normalizeUrl(u: string): string {
  return (u ?? "").trim().replace(/\/+$/, "");
}
function extractSlug(url: string): string | null {
  const m = /linkedin\.com\/in\/([^/?#]+)/i.exec(url ?? "");
  return m ? m[1] : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured", detail: "PIER_TEAM_ID not set" });
  if (!authorize(req, "inbound", "update-contact-on-cr-accepted")) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  await heartbeat(1);

  const profileUrl = String(body?.profileUrl ?? "").trim();
  if (!profileUrl) return json(400, { error: "missing_required_fields", detail: "profileUrl is required" });
  const linkedinUrl = normalizeUrl(profileUrl);
  const slug = extractSlug(profileUrl);

  try {
    // deno-lint-ignore no-explicit-any
    let contact: any = null;
    if (slug) {
      const r = await supabase
        .from("contacts").select("id, connection_status, sn_lists, company_id, cr_accepted_at")
        .eq("team_id", PIER_TEAM_ID).eq("linkedin_slug", slug).limit(1).maybeSingle();
      if (r.error) throw r.error;
      contact = r.data;
    }
    if (!contact) {
      const r = await supabase
        .from("contacts").select("id, connection_status, sn_lists, company_id, cr_accepted_at")
        .eq("team_id", PIER_TEAM_ID).eq("linkedin_url", linkedinUrl).limit(1).maybeSingle();
      if (r.error) throw r.error;
      contact = r.data;
    }

    if (!contact) {
      console.log(JSON.stringify({ event: "ignored", reason: "not_in_pier_pipeline", slug, url: linkedinUrl }));
      return json(200, { status: "ignored", reason: "not_in_pier_pipeline" });
    }

    const lists = Array.isArray(contact.sn_lists) ? contact.sn_lists : [];
    if (lists.length === 0) {
      console.log(JSON.stringify({ event: "ignored", reason: "no_sales_nav_source", contact_id: contact.id }));
      return json(200, { status: "ignored", reason: "no_sales_nav_source" });
    }

    // F15.4: a repeat report of an acceptance already recorded is not an event. Nothing is
    // re-stamped and nothing is re-drafted; the pending draft (if any) already exists.
    const previousStatus = String(contact.connection_status ?? "");
    if (previousStatus === "Accepted" || previousStatus === "Already connected") {
      console.log(JSON.stringify({ event: "ignored", reason: "already_accepted", contact_id: contact.id, previous_status: previousStatus }));
      return json(200, { status: "ignored", reason: "already_accepted", contact_id: contact.id, previous_status: previousStatus });
    }

    // F16.5 (2026-09-20): this point is reached only on a genuine transition (the F15.4 guard above
    // returned for Accepted / Already connected), so the same write stamps cr_accepted_at and
    // attributes the status. A repeat report never gets here, so it never re-stamps; an earlier
    // stamp (accepted, withdrawn, accepted again) is kept, never overwritten.
    const nowIso = new Date().toISOString();
    const today = nowIso.slice(0, 10);
    const { error: updErr } = await supabase
      .from("contacts")
      .update({ connection_status: "Accepted", cr_accepted_at: contact.cr_accepted_at ?? nowIso, connection_status_source: "phantom_recently_connected", last_contacted: today, updated_at: nowIso })
      .eq("id", contact.id)
      .eq("team_id", PIER_TEAM_ID);
    if (updErr) throw updErr;

    console.log(JSON.stringify({ event: "connection_accepted", contact_id: contact.id, previous_status: previousStatus }));

    let inmailRefund: number | null = null;
    try {
      const { data: bal, error: lErr } = await supabase.rpc("fn_ledger_inmail_accept_refund", { p_contact_id: contact.id, p_user_id: null });
      if (lErr) console.error(JSON.stringify({ event: "inmail_refund_failed", contact_id: contact.id, message: lErr.message }));
      else inmailRefund = bal as number | null;
    } catch (e) {
      console.error(JSON.stringify({ event: "inmail_refund_failed", contact_id: contact.id, message: (e as Error).message }));
    }

    // Matrix r4: first message after CR accepted, drafted NOW. The drafter routes it (DM, Initial
    // message, or a chaser if a DM already went out), runs fn_evaluate_gates, and dedupes.
    let draft: unknown = null;
    try {
      const draftResp = await fetch(`${SUPABASE_URL}/functions/v1/generate-draft-from-context`, {
        method: "POST",
        headers: { authorization: `Bearer ${OUTBOUND_SECRET}`, "content-type": "application/json" },
        body: JSON.stringify({ contact_id: contact.id, trigger_reason: "cr_accepted" }),
      });
      draft = await draftResp.json().catch(() => ({ ok: false, http: draftResp.status }));
      console.log(JSON.stringify({ event: "draft_triggered", http: draftResp.status, contact_id: contact.id }));
    } catch (e) {
      console.error(JSON.stringify({ event: "draft_trigger_failed", message: (e as Error).message ?? String(e) }));
      draft = { error: "draft_trigger_failed" };
    }

    return json(200, {
      status: "updated",
      contact_id: contact.id,
      previous_status: previousStatus,
      action: "connection_accepted",
      inmail_refund_balance: inmailRefund,
      draft,
    });
  } catch (e) {
    await heartbeat(0, false, (e as Error).message ?? String(e));
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
