// Edge Function: send-approved-draft
//
// Pushes ONE approved outreach_log draft out to LinkedIn via PhantomBuster.
// Called by the Lovable "Send now" button with { outreach_log_id }.
//
// Auth (Brad's decision 2026-08-26): reuses MAKE_SHARED_SECRET rather than a new
// SEND_APPROVED_SECRET, so there is one shared secret across every Pier Edge Function
// and the Lovable server functions hardcode it the same way regenerateDraftsFn does.
//
// Security / conventions (mirrors capture-and-classify-reply):
//   - service_role builds the client at boot only; every query is scoped to PIER_TEAM_ID.
//   - verify_jwt=false so the Bearer reaches the handler.
//   - The LinkedIn sessionCookie is NEVER handled or logged by this function. We read the
//     phantom's own saved argument, override only the recipient + message, and hand it
//     straight back. The cookie round-trips untouched and never appears in a log line.
//
// Schema reconciliations vs the Send-Approved spec (verified against the live phantoms
// 2026-08-26 — the spec's assumed argument shape is wrong for BOTH phantoms):
//   - Message Sender (5691059901018698, "LinkedIn Message Sender.js") takes
//     `spreadsheetUrl` (a single profile URL or a sheet), NOT a `profileUrls` array.
//   - Auto Connect (7500783933729451, "LinkedIn Auto Connect.js") takes
//     `inputType: "profileUrl"` + `profileUrl` (singular), NOT `profileUrls`.
//   - Neither accepts `numberOfProfilesPerLaunch`.
//   - The spec's CR capacity query filters touch_type='Initial', which is not a member of
//     the outreach_type enum at all (the CR value is 'Connection request'). Capacity is
//     therefore counted by channel + send_status, which is what the limit actually means.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const PHANTOMBUSTER_API_KEY = Deno.env.get("PHANTOMBUSTER_API_KEY") ?? "";

// TEST_MODE defaults to TRUE, deliberately diverging from the spec's "default false".
// A missing or misspelled env var must fail safe: the cost of an unintended send to a real
// prospect is far higher than the cost of a test send landing in Brad's own inbox.
// Set TEST_MODE="false" explicitly to go live.
const TEST_MODE = (Deno.env.get("TEST_MODE") ?? "true").toLowerCase() !== "false";

// Exact allowed test recipient. Compared with startsWith after normalising the trailing
// slash. This is the last line of defence before a launch.
const BRAD_TEST_URL = "https://www.linkedin.com/in/bradley-gordon-749861170";

const PHANTOM_DM = "5691059901018698";  // Pier LinkedIn Message Sender
const PHANTOM_CR = "7500783933729451";  // Pier LinkedIn Auto Connect

const DM_DAILY_LIMIT = 15;
const CR_WEEKLY_LIMIT = 120;

// Statuses that must never receive an automated send.
const NO_SEND = new Set(["Do not contact", "Left company", "Not relevant"]);

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

// LinkedIn messages are plain text; HTML would render literally in the DM.
const stripHtml = (s: string) =>
  (s ?? "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

const trimSlash = (u: string) => (u ?? "").trim().replace(/\/+$/, "");

// Monday 00:00 of the current week, London-ish (UTC date arithmetic is close enough for a
// weekly cap and avoids a tz dependency; the cap is a guard rail, not an invoice).
function mondayIso(): string {
  const d = new Date();
  const dow = d.getUTCDay() === 0 ? 7 : d.getUTCDay();
  d.setUTCDate(d.getUTCDate() - (dow - 1));
  return d.toISOString().slice(0, 10);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured", detail: "PIER_TEAM_ID not set" });

  if (!authorize(req, "internal", "send-approved-draft")) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const rowId = String(body?.outreach_log_id ?? "").trim();
  if (!rowId) return json(400, { error: "missing_required_fields", detail: "outreach_log_id required" });

  try {
    const { data: row, error: rErr } = await supabase.from("outreach_log")
      .select("id, contact_id, channel, touch_type, message_body, draft_status, send_status")
      .eq("team_id", PIER_TEAM_ID).eq("id", rowId).maybeSingle();
    if (rErr) throw rErr;
    if (!row) return json(404, { error: "draft_not_found" });

    if (row.draft_status !== "approved" || !["Draft", "Ready"].includes(String(row.send_status))) {
      console.log(JSON.stringify({ event: "not_sendable", id: rowId, draft_status: row.draft_status, send_status: row.send_status, test_mode: TEST_MODE }));
      return json(200, { status: "not_sendable", reason: `draft_status=${row.draft_status} send_status=${row.send_status}`, test_mode: TEST_MODE });
    }

    const { data: contact, error: cErr } = await supabase.from("contacts")
      .select("id, first_name, last_name, linkedin_url, linkedin_slug, outreach_status")
      .eq("team_id", PIER_TEAM_ID).eq("id", row.contact_id).maybeSingle();
    if (cErr) throw cErr;
    if (!contact) return json(404, { error: "contact_not_found" });

    if (NO_SEND.has(String(contact.outreach_status))) {
      console.log(JSON.stringify({ event: "blocked_by_outreach_status", id: rowId, outreach_status: contact.outreach_status, test_mode: TEST_MODE }));
      return json(200, { status: "blocked", reason: `outreach_status=${contact.outreach_status}`, test_mode: TEST_MODE });
    }

    const channel = String(row.channel);
    if (channel === "LinkedIn inMail") return json(200, { status: "inmail_not_wired", detail: "InMail send is a separate build", test_mode: TEST_MODE });
    if (channel !== "LinkedIn DM" && channel !== "LinkedIn CR") return json(200, { status: "channel_not_supported", channel, test_mode: TEST_MODE });

    // Capacity guard runs BEFORE any launch, and applies in TEST_MODE too — the platform
    // limit is per LinkedIn account and a test send consumes real quota.
    if (channel === "LinkedIn DM") {
      const today = new Date().toISOString().slice(0, 10);
      const { count } = await supabase.from("outreach_log").select("id", { count: "exact", head: true })
        .eq("team_id", PIER_TEAM_ID).eq("channel", "LinkedIn DM").eq("send_status", "Sent").gte("touch_date", today);
      if ((count ?? 0) >= DM_DAILY_LIMIT) {
        console.warn(JSON.stringify({ event: "capacity_exceeded", channel: "dm", count, limit: DM_DAILY_LIMIT, test_mode: TEST_MODE }));
        return json(200, { status: "capacity_exceeded", channel: "dm", count: count ?? 0, limit: DM_DAILY_LIMIT, test_mode: TEST_MODE });
      }
    } else {
      const { count } = await supabase.from("outreach_log").select("id", { count: "exact", head: true })
        .eq("team_id", PIER_TEAM_ID).eq("channel", "LinkedIn CR").eq("send_status", "Sent").gte("touch_date", mondayIso());
      if ((count ?? 0) >= CR_WEEKLY_LIMIT) {
        console.warn(JSON.stringify({ event: "capacity_exceeded", channel: "cr", count, limit: CR_WEEKLY_LIMIT, test_mode: TEST_MODE }));
        return json(200, { status: "capacity_exceeded", channel: "cr", count: count ?? 0, limit: CR_WEEKLY_LIMIT, test_mode: TEST_MODE });
      }
    }

    const messageText = stripHtml(String(row.message_body ?? ""));
    if (!messageText && channel === "LinkedIn DM") return json(200, { status: "empty_message", test_mode: TEST_MODE });

    const realUrl = trimSlash(String(contact.linkedin_url ?? ""));
    const recipientUrl = TEST_MODE ? BRAD_TEST_URL : realUrl;

    // HARD GUARD. In TEST_MODE nothing but Brad's own profile may ever be launched at.
    // This is belt-and-braces on top of the assignment above: if a future edit ever lets a
    // real URL through while TEST_MODE is on, the launch aborts instead of sending.
    if (TEST_MODE && trimSlash(recipientUrl) !== BRAD_TEST_URL) {
      console.error(JSON.stringify({ event: "test_mode_recipient_violation", id: rowId, attempted: recipientUrl, test_mode: true }));
      return json(500, { error: "test_mode_recipient_violation", detail: "TEST_MODE is on and the recipient is not the designated test profile. Aborted without launching." });
    }
    if (!recipientUrl) return json(200, { status: "no_recipient_url", test_mode: TEST_MODE });

    if (!PHANTOMBUSTER_API_KEY) {
      console.error(JSON.stringify({ event: "phantombuster_key_missing", test_mode: TEST_MODE }));
      return json(500, { error: "server_misconfigured", detail: "PHANTOMBUSTER_API_KEY not set" });
    }

    const agentId = channel === "LinkedIn DM" ? PHANTOM_DM : PHANTOM_CR;

    // Read the phantom's saved argument and override ONLY the recipient + message, so the
    // sessionCookie / userAgent / proxy settings round-trip untouched. Launching with a
    // partial argument would drop the cookie and the run would fail to authenticate.
    let merged: Record<string, unknown> = {};
    try {
      const aResp = await fetch(`https://api.phantombuster.com/api/v2/agents/fetch?id=${agentId}`, {
        headers: { "X-Phantombuster-Key-1": PHANTOMBUSTER_API_KEY },
      });
      const aData = await aResp.json();
      if (!aResp.ok) throw new Error(`agent_fetch_http_${aResp.status}`);
      merged = JSON.parse(String(aData?.argument ?? "{}"));
    } catch (e) {
      console.error(JSON.stringify({ event: "agent_fetch_failed", message: (e as Error).message, test_mode: TEST_MODE }));
      return json(500, { error: "agent_fetch_failed", detail: (e as Error).message });
    }

    if (channel === "LinkedIn DM") {
      merged.spreadsheetUrl = recipientUrl;   // real key; NOT profileUrls
      merged.message = messageText;
    } else {
      merged.inputType = "profileUrl";
      merged.profileUrl = recipientUrl;       // real key; NOT profileUrls
      if (messageText) merged.message = messageText;
    }

    // Log the launch WITHOUT the argument (it carries the session cookie).
    console.log(JSON.stringify({ event: "launching", id: rowId, agent_id: agentId, channel, recipient: recipientUrl, test_mode: TEST_MODE, msg_len: messageText.length }));

    let containerId = "";
    try {
      const lResp = await fetch("https://api.phantombuster.com/api/v2/agents/launch", {
        method: "POST",
        headers: { "X-Phantombuster-Key-1": PHANTOMBUSTER_API_KEY, "content-type": "application/json" },
        body: JSON.stringify({ id: agentId, argument: merged }),
      });
      const lData = await lResp.json();
      if (!lResp.ok) throw new Error(`launch_http_${lResp.status}: ${JSON.stringify(lData).slice(0, 200)}`);
      containerId = String(lData?.containerId ?? "");
      if (!containerId) throw new Error("no_container_id_returned");
    } catch (e) {
      const msg = (e as Error).message ?? String(e);
      await supabase.from("outreach_log").update({ send_status: "Cancelled", send_error: msg })
        .eq("id", rowId).eq("team_id", PIER_TEAM_ID);
      console.error(JSON.stringify({ event: "launch_failed", id: rowId, message: msg, test_mode: TEST_MODE }));
      return json(500, { error: "launch_failed", detail: msg, test_mode: TEST_MODE });
    }

    // In flight. draft_status stays 'approved' until the callback confirms delivery.
    const { error: uErr } = await supabase.from("outreach_log")
      .update({ send_status: "Scheduled", phantom_run_id: containerId, sent_at_actual: null, send_error: null })
      .eq("id", rowId).eq("team_id", PIER_TEAM_ID);
    if (uErr) throw uErr;

    console.log(JSON.stringify({ event: "sent", id: rowId, phantom_run_id: containerId, channel, test_mode: TEST_MODE }));
    return json(200, { status: "sent", phantom_run_id: containerId, channel, test_mode: TEST_MODE, recipient_url: recipientUrl });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e), test_mode: TEST_MODE }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
