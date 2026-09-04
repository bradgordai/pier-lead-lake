// Edge Function: chase-engine  (Batch B B5, reworked for Batch C C1/T2)
//
// Daily. Finds contacts due a chaser, evaluates every one through the C5 refusal gates,
// drafts the survivors via generate-draft-from-context, and advances chase state.
//
// NOTHING IS EVER SENT FROM HERE. Every draft lands draft_status='pending_review'.
//
// C1 ROUTES AND CAPS (Oli's correction 3a, 2026-09-02):
//   accepted_chase   connected already  -> FREE LinkedIn DM,  cap dm_chaser_cap  (3)
//   cr_not_accepted  CR never accepted  -> LinkedIn inMail,   cap inmail_chaser_cap (1)
//
// The InMail cap of 1 is deliberate and expensive to get wrong: one initial InMail plus one
// chaser is 2 credits per account, which reaches ~47 accounts per 95 credits against 31 at
// three. Chasing an ALREADY-CONNECTED contact over InMail spends a credit for nothing -
// that was the bug behind the 2026-09-03 06:15 quarantine, and the route split fixes it.
//
// Caps, routes and is_final all come from fn_chase_candidates (migration 056), which counts
// sent chasers PER CHANNEL. Counting across channels would let a DM chaser eat the InMail
// allowance.
//
// C5: every candidate goes through fn_evaluate_gates before any model call. A gate failure
// is written to `refusals` and NOT drafted - a refusal is a first-class outcome, not an error.
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
// Drafting is a ~6s model call. Sequential x25 would exceed the function timeout; a small
// concurrency window keeps a full run inside it. Also keeps the prompt cache warm.
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
  channel: string;
  cap: number;
  is_final: boolean;
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
  const limit = Math.max(1, Math.min(200, Number(body?.limit ?? DEFAULT_CAP_PER_RUN)));

  try {
    const { data: settings } = await supabase.from("team_settings")
      .select("chase_interval_days, dm_chaser_cap, inmail_chaser_cap, cooldown_days")
      .eq("team_id", PIER_TEAM_ID).maybeSingle();
    const intervalDays = Number(settings?.chase_interval_days ?? 7);
    const dmCap = Number(settings?.dm_chaser_cap ?? 3);
    const inmailCap = Number(settings?.inmail_chaser_cap ?? 1);
    const cooldownDays = Number(settings?.cooldown_days ?? 90);

    const today = new Date();
    const todayStr = today.toISOString().slice(0, 10);

    // ---------------- 1. exhausted cadences: cooldown + register row, never another chaser
    const { data: exhausted, error: exErr } = await supabase
      .rpc("fn_chase_exhausted", { p_team_id: PIER_TEAM_ID, p_limit: 200 });
    if (exErr) throw exErr;

    let exhaustedHandled = 0;
    for (const e of (exhausted ?? []) as Array<{ contact_id: string; company_id: string | null }>) {
      if (dryRun) { exhaustedHandled++; continue; }
      const cooldownUntil = addDays(today, cooldownDays);
      const { error: uErr } = await supabase.from("contacts").update({
        chase_state: "exhausted", cooldown_until: cooldownUntil, chase_next_due_at: null,
      }).eq("id", e.contact_id).eq("team_id", PIER_TEAM_ID);
      if (uErr) { console.error(JSON.stringify({ event: "exhaust_update_failed", contact_id: e.contact_id, message: uErr.message })); continue; }

      const { error: regErr } = await supabase.from("outreach_log").insert({
        team_id: PIER_TEAM_ID, touch_id: `chase-exhausted-${crypto.randomUUID()}`,
        contact_id: e.contact_id, company_id: e.company_id ?? null,
        // outreach_channel has no "Internal" member; "Other" is the only non-messaging one.
        channel: "Other", touch_type: "Other",
        message_body: `Chase cadence closed with no reply. Contact placed in cooldown until ${cooldownUntil}. No further chasers will be drafted.`,
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

    const { data: allDue } = await supabase
      .rpc("fn_chase_candidates", { p_team_id: PIER_TEAM_ID, p_limit: 5000 });
    const backlog = ((allDue ?? []) as Candidate[]).length;

    const results: Array<Record<string, unknown>> = [];
    const refusedByCode: Record<string, number> = {};
    let drafted = 0, refused = 0, skipped = 0, failed = 0;

    async function handle(c: Candidate) {
      // Second guard on the cap. fn_chase_candidates already excludes over-cap contacts;
      // the cap is the one rule that must not fail open, so it is checked twice.
      if (c.chaser_number > c.cap) {
        skipped++;
        results.push({ contact_id: c.contact_id, skipped: "over_cap", chaser_number: c.chaser_number, cap: c.cap, channel: c.channel });
        return;
      }

      // C5 gates, evaluated on the channel this chaser would actually use.
      const { data: gateRows, error: gErr } = await supabase.rpc("fn_evaluate_gates", {
        p_team_id: PIER_TEAM_ID, p_contact_id: c.contact_id,
        p_channel: c.channel, p_requested: "chaser",
      });
      if (gErr) { failed++; results.push({ contact_id: c.contact_id, error: gErr.message }); return; }
      const gate = (gateRows ?? [])[0];
      if (gate) {
        refused++;
        refusedByCode[gate.reason_code] = (refusedByCode[gate.reason_code] ?? 0) + 1;
        if (!dryRun) {
          await supabase.from("refusals").insert({
            team_id: PIER_TEAM_ID, contact_id: c.contact_id, company_id: c.company_id,
            reason_code: gate.reason_code, reason_human: gate.reason_human,
            channel: c.channel, requested: "chaser",
            context: { ...(gate.context ?? {}), source: "chase-engine", route: c.route, chaser_number: c.chaser_number },
          });
        }
        results.push({ contact_id: c.contact_id, refused: gate.reason_code, channel: c.channel, route: c.route });
        return;
      }

      const trigger = `chaser_${c.chaser_number}`;
      if (dryRun) {
        drafted++;
        results.push({ contact_id: c.contact_id, would_draft: trigger, route: c.route, channel: c.channel,
                       cap: c.cap, is_final: c.is_final, priority: c.priority, days_since: c.days_since });
        return;
      }
      try {
        const resp = await fetch(`${SUPABASE_URL}/functions/v1/generate-draft-from-context`, {
          method: "POST",
          headers: { authorization: `Bearer ${INTERNAL_SECRET}`, "content-type": "application/json" },
          // exit_shape marks the last chaser permitted on this route: no ask, leave the door
          // open. On the DM route that is chaser 3 (whose intent is already exit-shaped);
          // on the InMail route it is chaser 1, because the cap is 1.
          body: JSON.stringify({ contact_id: c.contact_id, trigger_reason: trigger, exit_shape: c.is_final }),
        });
        const out = await resp.json().catch(() => ({}));

        if (out?.refused) {
          // The drafter re-evaluates the gates; if it refuses, it has already logged the row.
          refused++;
          refusedByCode[out.reason_code] = (refusedByCode[out.reason_code] ?? 0) + 1;
          results.push({ contact_id: c.contact_id, refused: out.reason_code, via: "drafter" });
          return;
        }
        if (out?.status === "budget_exceeded") {
          failed++; results.push({ contact_id: c.contact_id, error: "budget_exceeded" });
          return;
        }
        if (out?.status === "created") {
          drafted++;
          // chaser_count is NOT incremented here: it counts SENT chasers, and this draft has
          // not been sent or even approved.
          await supabase.from("contacts").update({
            chase_state: c.chaser_number === 1 ? "chaser_1_sent" : "chaser_2_sent",
            chase_last_outbound_at: c.last_outbound,
            chase_next_due_at: addDays(today, intervalDays),
          }).eq("id", c.contact_id).eq("team_id", PIER_TEAM_ID);
          results.push({ contact_id: c.contact_id, drafted: trigger, touch_id: out.touch_id,
                         route: c.route, channel: c.channel, is_final: c.is_final });
        } else {
          skipped++;
          results.push({ contact_id: c.contact_id, skipped: out?.status ?? "unknown" });
        }
      } catch (e) {
        failed++;
        results.push({ contact_id: c.contact_id, error: (e as Error).message ?? String(e) });
      }
    }

    for (let i = 0; i < list.length; i += CONCURRENCY) {
      await Promise.all(list.slice(i, i + CONCURRENCY).map(handle));
    }

    const byRoute: Record<string, number> = {};
    for (const c of list) byRoute[`${c.route} (${c.channel}, cap ${c.cap})`] = (byRoute[`${c.route} (${c.channel}, cap ${c.cap})`] ?? 0) + 1;

    const summary = {
      status: dryRun ? "dry_run" : "ok",
      rules: { chase_interval_days: intervalDays, dm_chaser_cap: dmCap, inmail_chaser_cap: inmailCap, cooldown_days: cooldownDays },
      cap_per_run: limit,
      backlog_due_total: backlog,
      backlog_waiting_for_next_run: Math.max(0, backlog - list.length),
      considered: list.length,
      candidates_by_route: byRoute,
      drafted, refused, skipped, failed,
      refused_by_reason_code: refusedByCode,
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
