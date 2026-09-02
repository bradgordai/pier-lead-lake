// Edge Function: chase-engine  (Batch B, B5)
//
// Runs daily (weekday mornings, Europe/London). Finds contacts due a chaser, drafts one
// each via generate-draft-from-context, and advances the per-contact chase state.
//
// NOTHING IS EVER SENT FROM HERE. Every draft lands draft_status='pending_review' under
// its own touch_type and waits for Oli. The engine only decides WHO is due and WHAT KIND
// of touch it is.
//
// Rules come from team_settings (chase_interval_days=7, chaser_cap=2, cooldown_days=90);
// they are read at run time, never hardcoded, so changing the setting changes the engine.
//
// Due-detection lives in SQL (migration 053: fn_chase_candidates / fn_chase_exhausted) so
// it can be inspected without invoking the function. The SQL recomputes the clock from
// outreach_log rather than trusting contacts.chase_*, so the engine is correct even before
// tonight's catch-up migration populates those columns - but it WRITES those same columns,
// so migration and engine share one source of truth (the 052 contract).
//
// Auth: INTERNAL_APP_SECRET (internal class), verify_jwt=false.
// Body (all optional): { "limit": 25, "dry_run": true }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const INTERNAL_SECRET = Deno.env.get("INTERNAL_APP_SECRET") || Deno.env.get("MAKE_SHARED_SECRET") || "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

const DEFAULT_CAP_PER_RUN = 25;
// Drafting is a ~6s model call each. Sequential x25 would exceed the function timeout, so
// a small concurrency window keeps a full run inside it without hammering the API.
const CONCURRENCY = 4;

function addDays(d: Date, n: number): string {
  const x = new Date(d.getTime());
  x.setUTCDate(x.getUTCDate() + n);
  return x.toISOString().slice(0, 10);
}

type Candidate = {
  contact_id: string;
  company_id: string | null;
  chaser_number: number;
  route: string;
  last_outbound: string | null;
  days_since: number | null;
  priority: string | null;
  connection_status: string | null;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured", detail: "PIER_TEAM_ID not set" });
  if (!authorize(req, "internal", "chase-engine")) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try { body = await req.json(); } catch { /* empty body is fine for a cron */ }
  const dryRun = body?.dry_run === true;
  const limit = Math.max(1, Math.min(100, Number(body?.limit ?? DEFAULT_CAP_PER_RUN)));

  try {
    const { data: settings } = await supabase.from("team_settings")
      .select("chase_interval_days, chaser_cap, cooldown_days")
      .eq("team_id", PIER_TEAM_ID).maybeSingle();
    const intervalDays = Number(settings?.chase_interval_days ?? 7);
    const chaserCap = Number(settings?.chaser_cap ?? 2);
    const cooldownDays = Number(settings?.cooldown_days ?? 90);

    // ---------------- 1. exhausted cadences: cooldown + register row, never a 3rd chaser
    const { data: exhausted, error: exErr } = await supabase
      .rpc("fn_chase_exhausted", { p_team_id: PIER_TEAM_ID, p_limit: 200 });
    if (exErr) throw exErr;

    const today = new Date();
    const todayStr = today.toISOString().slice(0, 10);
    let exhaustedHandled = 0;
    for (const e of (exhausted ?? []) as Array<{ contact_id: string; company_id: string | null }>) {
      if (dryRun) { exhaustedHandled++; continue; }
      const cooldownUntil = addDays(today, cooldownDays);
      const { error: uErr } = await supabase.from("contacts").update({
        chase_state: "exhausted",
        cooldown_until: cooldownUntil,
        chase_next_due_at: null,
      }).eq("id", e.contact_id).eq("team_id", PIER_TEAM_ID);
      if (uErr) { console.error(JSON.stringify({ event: "exhaust_update_failed", contact_id: e.contact_id, message: uErr.message })); continue; }

      // Register row: a real touch_type='Other' entry marking the cadence closed, so the
      // history shows WHY chasing stopped instead of just going quiet. send_status 'Sent'
      // because it is a completed internal event, not a draft awaiting review.
      const { error: regErr } = await supabase.from("outreach_log").insert({
        team_id: PIER_TEAM_ID, touch_id: `chase-exhausted-${crypto.randomUUID()}`,
        contact_id: e.contact_id, company_id: e.company_id ?? null,
        // channel must be a member of outreach_channel; there is no "Internal" value,
        // and "Other" is the only non-messaging member. Verified against the live enum.
        channel: "Other", touch_type: "Other",
        message_body: `Chase cadence closed: ${chaserCap} chasers sent with no reply. Contact placed in cooldown until ${cooldownUntil}. No further chasers will be drafted.`,
        draft_status: "sent", send_status: "Sent", agent_produced: true,
        migrated_legacy: false, touch_date: todayStr,
      });
      if (regErr) console.error(JSON.stringify({ event: "register_row_failed", contact_id: e.contact_id, message: regErr.message }));
      exhaustedHandled++;
    }

    // ---------------- 2. due chasers
    const { data: candidates, error: cErr } = await supabase
      .rpc("fn_chase_candidates", { p_team_id: PIER_TEAM_ID, p_limit: limit });
    if (cErr) throw cErr;
    const list = (candidates ?? []) as Candidate[];

    // Total backlog, so the run can report how much is waiting behind the cap.
    const { data: allDue } = await supabase
      .rpc("fn_chase_candidates", { p_team_id: PIER_TEAM_ID, p_limit: 1000 });
    const backlog = ((allDue ?? []) as Candidate[]).length;

    const results: Array<Record<string, unknown>> = [];
    let drafted = 0, skipped = 0, failed = 0;

    async function handle(c: Candidate) {
      // A chaser beyond the cap must never be drafted. The SQL already excludes these;
      // this is a second guard because the cap is the one rule that must not fail open.
      if (c.chaser_number > chaserCap) {
        skipped++; results.push({ contact_id: c.contact_id, skipped: "over_cap", chaser_number: c.chaser_number });
        return;
      }
      const trigger = `chaser_${c.chaser_number}`;
      if (dryRun) {
        drafted++;
        results.push({ contact_id: c.contact_id, would_draft: trigger, route: c.route, priority: c.priority, days_since: c.days_since });
        return;
      }
      try {
        const resp = await fetch(`${SUPABASE_URL}/functions/v1/generate-draft-from-context`, {
          method: "POST",
          headers: { authorization: `Bearer ${INTERNAL_SECRET}`, "content-type": "application/json" },
          body: JSON.stringify({ contact_id: c.contact_id, trigger_reason: trigger }),
        });
        const out = await resp.json().catch(() => ({}));

        // Budget exhaustion is a stop signal for the whole run, not a per-contact failure.
        if (out?.status === "budget_exceeded") {
          failed++;
          results.push({ contact_id: c.contact_id, error: "budget_exceeded" });
          return;
        }
        if (out?.status === "created") {
          drafted++;
          // Advance the shared chase state (052 contract). chaser_count is NOT incremented
          // here: it counts SENT chasers, and this draft has not been sent or even approved.
          await supabase.from("contacts").update({
            chase_state: c.chaser_number === 1 ? "chaser_1_sent" : "chaser_2_sent",
            chase_last_outbound_at: c.last_outbound,
            chase_next_due_at: addDays(today, intervalDays),
          }).eq("id", c.contact_id).eq("team_id", PIER_TEAM_ID);
          results.push({ contact_id: c.contact_id, drafted: trigger, touch_id: out.touch_id, route: c.route, priority: c.priority });
        } else {
          skipped++;
          results.push({ contact_id: c.contact_id, skipped: out?.status ?? "unknown", reasons: out?.reasons });
        }
      } catch (e) {
        failed++;
        results.push({ contact_id: c.contact_id, error: (e as Error).message ?? String(e) });
      }
    }

    for (let i = 0; i < list.length; i += CONCURRENCY) {
      await Promise.all(list.slice(i, i + CONCURRENCY).map(handle));
    }

    const summary = {
      status: dryRun ? "dry_run" : "ok",
      rules: { chase_interval_days: intervalDays, chaser_cap: chaserCap, cooldown_days: cooldownDays },
      cap_per_run: limit,
      backlog_due_total: backlog,
      backlog_waiting_for_next_run: Math.max(0, backlog - list.length),
      considered: list.length,
      drafted, skipped, failed,
      exhausted_handled: exhaustedHandled,
      results,
    };
    console.log(JSON.stringify({ event: "chase_engine_run", ...summary, results: undefined }));
    return json(200, summary);
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
