// Edge Function: chase-engine  (F16.1 2026-09-15: per-section refusal maps + reconciles flag; F15.2 routing matrix; F14.4 first message flag; F13.4 chaser_drafted)
//
// Daily. Finds contacts due a chaser, evaluates every one through the C5 refusal gates,
// drafts the survivors via generate-draft-from-context, and advances chase state.
// NOTHING IS EVER SENT FROM HERE. Every draft lands draft_status='pending_review'.
// Auth: INTERNAL_APP_SECRET (internal class), verify_jwt=false. Body (all optional): { "limit": 25, "dry_run": true }

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

async function refusalRow(contactId: string, companyId: string | null, gate: { reason_code: string; reason_human: string; context?: unknown }, channel: string, requested: string, extra: Record<string, unknown>, today: Date): Promise<void> {
  const since = new Date(today.getTime() - 24 * 3600 * 1000).toISOString();
  const { data: dup } = await supabase.from("refusals").select("id")
    .eq("team_id", PIER_TEAM_ID).eq("contact_id", contactId)
    .eq("reason_code", gate.reason_code).gte("created_at", since).limit(1).maybeSingle();
  if (dup) return;
  await supabase.from("refusals").insert({
    team_id: PIER_TEAM_ID, contact_id: contactId, company_id: companyId,
    reason_code: gate.reason_code, reason_human: gate.reason_human,
    channel, requested,
    context: { ...((gate.context as Record<string, unknown>) ?? {}), source: "chase-engine", ...extra },
  });
}

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
      .select("chase_interval_days, dm_chaser_cap, inmail_chaser_cap, cooldown_days, first_message_after_cr_enabled, first_message_cap_per_run, cold_inmail_openers_per_run, reply_sweep_per_run, max_drafts_per_run")
      .eq("team_id", PIER_TEAM_ID).maybeSingle();
    const firstMsgEnabled = settings?.first_message_after_cr_enabled === true || (dryRun && body?.include_first_messages === true);
    const firstMsgCap = Math.max(0, Math.min(50, Number(settings?.first_message_cap_per_run ?? 5)));
    const coldCap = Math.max(0, Math.min(50, Number(settings?.cold_inmail_openers_per_run ?? 5)));
    const intervalDays = Number(settings?.chase_interval_days ?? 7);
    const dmCap = Number(settings?.dm_chaser_cap ?? 3);
    const inmailCap = Number(settings?.inmail_chaser_cap ?? 1);
    const cooldownDays = Number(settings?.cooldown_days ?? 90);
    // F20.11(c): ONE ceiling on drafts per run across every route, so a backlog drains over days instead of
    // landing in Oliver's queue at once. Replies keep a reserve, because they run last and a warm conversation
    // outranks a cold one: the other routes may not spend the last `replyReserve` slots.
    const maxDrafts = Math.max(1, Math.min(200, Number((settings as Record<string, unknown> | null)?.max_drafts_per_run ?? 20)));
    const replyReserve = Math.min(5, maxDrafts);
    let draftedAll = 0, heldByBudget = 0;

    const today = new Date();
    const todayStr = today.toISOString().slice(0, 10);

    // ---------------- 1. exhausted cadences
    const { data: exhausted, error: exErr } = await supabase.rpc("fn_chase_exhausted", { p_team_id: PIER_TEAM_ID, p_limit: 200 });
    if (exErr) throw exErr;
    let exhaustedHandled = 0;
    for (const e of (exhausted ?? []) as Array<{ contact_id: string; company_id: string | null }>) {
      if (dryRun) { exhaustedHandled++; continue; }
      const cooldownUntil = addDays(today, cooldownDays);
      const { error: uErr } = await supabase.from("contacts").update({ chase_state: "exhausted", cooldown_until: cooldownUntil, chase_next_due_at: null }).eq("id", e.contact_id).eq("team_id", PIER_TEAM_ID);
      if (uErr) { console.error(JSON.stringify({ event: "exhaust_update_failed", contact_id: e.contact_id, message: uErr.message })); continue; }
      const { error: regErr } = await supabase.from("outreach_log").insert({
        team_id: PIER_TEAM_ID, touch_id: `chase-exhausted-${crypto.randomUUID()}`, contact_id: e.contact_id, company_id: e.company_id ?? null,
        channel: "Other", touch_type: "Other",
        message_body: `Chase cadence closed with no reply. Contact placed in cooldown until ${cooldownUntil}. No further chasers will be drafted.`,
        draft_status: "sent", send_status: "Sent", agent_produced: true, migrated_legacy: false, touch_date: todayStr,
      });
      if (regErr) console.error(JSON.stringify({ event: "register_row_failed", contact_id: e.contact_id, message: regErr.message }));
      exhaustedHandled++;
    }

    // ---------------- 2. due chasers
    const { data: candidates, error: cErr } = await supabase.rpc("fn_chase_candidates", { p_team_id: PIER_TEAM_ID, p_limit: limit });
    if (cErr) throw cErr;
    // Chasers run concurrently, so their ceiling is applied to how many are considered.
    const list = ((candidates ?? []) as Candidate[]).slice(0, Math.max(0, maxDrafts - replyReserve));
    const { data: allDue } = await supabase.rpc("fn_chase_candidates", { p_team_id: PIER_TEAM_ID, p_limit: 5000 });
    const backlog = ((allDue ?? []) as Candidate[]).length;

    const results: Array<Record<string, unknown>> = [];
    // F16.1(c): one refusal map PER SECTION. A shared map made the summary total 18 against 13 considered.
    const refusedByCode: Record<string, number> = {};
    const coldRefusedByCode: Record<string, number> = {};
    const firstRefusedByCode: Record<string, number> = {};
    let drafted = 0, refused = 0, skipped = 0, failed = 0;

    async function handle(c: Candidate) {
      if (c.chaser_number > c.cap) { skipped++; results.push({ contact_id: c.contact_id, skipped: "over_cap", chaser_number: c.chaser_number, cap: c.cap, channel: c.channel }); return; }
      const { data: gateRows, error: gErr } = await supabase.rpc("fn_evaluate_gates", { p_team_id: PIER_TEAM_ID, p_contact_id: c.contact_id, p_channel: c.channel, p_requested: "chaser" });
      if (gErr) { failed++; results.push({ contact_id: c.contact_id, error: gErr.message }); return; }
      const gate = (gateRows ?? [])[0];
      if (gate) {
        refused++;
        refusedByCode[gate.reason_code] = (refusedByCode[gate.reason_code] ?? 0) + 1;
        if (!dryRun) await refusalRow(c.contact_id, c.company_id, gate, c.channel, "chaser", { route: c.route, chaser_number: c.chaser_number }, today);
        results.push({ contact_id: c.contact_id, refused: gate.reason_code, channel: c.channel, route: c.route });
        return;
      }
      const trigger = `chaser_${c.chaser_number}`;
      if (dryRun) { drafted++; draftedAll++; results.push({ contact_id: c.contact_id, would_draft: trigger, route: c.route, channel: c.channel, cap: c.cap, is_final: c.is_final, priority: c.priority, days_since: c.days_since }); return; }
      try {
        const resp = await fetch(`${SUPABASE_URL}/functions/v1/generate-draft-from-context`, {
          method: "POST", headers: { authorization: `Bearer ${INTERNAL_SECRET}`, "content-type": "application/json" },
          body: JSON.stringify({ contact_id: c.contact_id, trigger_reason: trigger, exit_shape: c.is_final }),
        });
        const out = await resp.json().catch(() => ({}));
        if (out?.refused) { refused++; refusedByCode[out.reason_code] = (refusedByCode[out.reason_code] ?? 0) + 1; results.push({ contact_id: c.contact_id, refused: out.reason_code, via: "drafter" }); return; }
        if (out?.status === "budget_exceeded") { failed++; results.push({ contact_id: c.contact_id, error: "budget_exceeded" }); return; }
        if (out?.status === "created") {
          drafted++; draftedAll++;
          const producedChaser = String(out?.touch_type ?? "").startsWith("Chaser ");
          if (producedChaser) {
            await supabase.from("contacts").update({ chase_state: "chaser_drafted", chase_last_outbound_at: c.last_outbound, chase_next_due_at: addDays(today, intervalDays) }).eq("id", c.contact_id).eq("team_id", PIER_TEAM_ID);
          } else {
            console.error(JSON.stringify({ event: "routing_mismatch", contact_id: c.contact_id, asked: trigger, produced: out?.touch_type }));
          }
          results.push({ contact_id: c.contact_id, drafted: trigger, produced: out?.touch_type, touch_id: out.touch_id, route: c.route, channel: c.channel, is_final: c.is_final });
        } else { skipped++; results.push({ contact_id: c.contact_id, skipped: out?.status ?? "unknown" }); }
      } catch (e) { failed++; results.push({ contact_id: c.contact_id, error: (e as Error).message ?? String(e) }); }
    }
    for (let i = 0; i < list.length; i += CONCURRENCY) await Promise.all(list.slice(i, i + CONCURRENCY).map(handle));

    // ---------------- 3. first message after CR accepted (flag-gated, F14.4)
    let firstConsidered = 0, firstDrafted = 0, firstRefused = 0, firstFailed = 0;
    const firstResults: Array<Record<string, unknown>> = [];
    if (firstMsgEnabled && firstMsgCap > 0) {
      const { data: firsts, error: fErr } = await supabase.rpc("fn_first_message_candidates", { p_team_id: PIER_TEAM_ID, p_limit: firstMsgCap });
      if (fErr) console.error(JSON.stringify({ event: "first_message_candidates_failed", message: fErr.message }));
      for (const f of (firsts ?? []) as Array<{ contact_id: string; company_id: string | null; priority: string | null }>) {
        if (draftedAll >= maxDrafts - replyReserve) { heldByBudget++; continue; }
        firstConsidered++;
        const { data: gateRows, error: gErr } = await supabase.rpc("fn_evaluate_gates", { p_team_id: PIER_TEAM_ID, p_contact_id: f.contact_id, p_channel: "LinkedIn DM", p_requested: "initial_message" });
        if (gErr) { firstFailed++; firstResults.push({ contact_id: f.contact_id, error: gErr.message }); continue; }
        const gate = (gateRows ?? [])[0];
        if (gate) {
          firstRefused++; firstRefusedByCode[gate.reason_code] = (firstRefusedByCode[gate.reason_code] ?? 0) + 1;
          if (!dryRun) await refusalRow(f.contact_id, f.company_id, gate, "LinkedIn DM", "initial_message", { route: "first_message_after_cr" }, today);
          firstResults.push({ contact_id: f.contact_id, refused: gate.reason_code, route: "first_message_after_cr" });
          continue;
        }
        if (dryRun) { firstDrafted++; draftedAll++; firstResults.push({ contact_id: f.contact_id, would_draft: "first_message_after_cr", priority: f.priority }); continue; }
        try {
          const resp = await fetch(`${SUPABASE_URL}/functions/v1/generate-draft-from-context`, { method: "POST", headers: { authorization: `Bearer ${INTERNAL_SECRET}`, "content-type": "application/json" }, body: JSON.stringify({ contact_id: f.contact_id, trigger_reason: "cr_accepted" }) });
          const out = await resp.json().catch(() => ({}));
          if (out?.status === "created") { firstDrafted++; draftedAll++; firstResults.push({ contact_id: f.contact_id, drafted: "first_message_after_cr", touch_id: out.touch_id }); }
          else if (out?.refused) { firstRefused++; firstRefusedByCode[out.reason_code] = (firstRefusedByCode[out.reason_code] ?? 0) + 1; firstResults.push({ contact_id: f.contact_id, refused: out.reason_code, via: "drafter" }); }
          else { firstFailed++; firstResults.push({ contact_id: f.contact_id, error: out?.status ?? out?.error ?? "unknown" }); }
        } catch (e) { firstFailed++; firstResults.push({ contact_id: f.contact_id, error: (e as Error).message ?? String(e) }); }
      }
    }

    // ---------------- 4. r1 cold InMail openers (F15.2)
    let coldConsidered = 0, coldDrafted = 0, coldRefused = 0, coldFailed = 0;
    const coldResults: Array<Record<string, unknown>> = [];
    let coldBacklog = 0;
    if (coldCap > 0) {
      const { data: coldAll } = await supabase.rpc("fn_cold_inmail_candidates", { p_team_id: PIER_TEAM_ID, p_limit: 5000 });
      coldBacklog = ((coldAll ?? []) as unknown[]).length;
      const { data: colds, error: kErr } = await supabase.rpc("fn_cold_inmail_candidates", { p_team_id: PIER_TEAM_ID, p_limit: coldCap });
      if (kErr) console.error(JSON.stringify({ event: "cold_inmail_candidates_failed", message: kErr.message }));
      for (const k of (colds ?? []) as Array<{ contact_id: string; company_id: string | null; priority: string | null; connection_status: string | null }>) {
        if (draftedAll >= maxDrafts - replyReserve) { heldByBudget++; continue; }
        coldConsidered++;
        if (["Accepted", "Already connected"].includes(String(k.connection_status ?? ""))) { coldFailed++; coldResults.push({ contact_id: k.contact_id, error: "routing_invariant_violated: connected contact in cold InMail set" }); continue; }
        const { data: gateRows, error: gErr } = await supabase.rpc("fn_evaluate_gates", { p_team_id: PIER_TEAM_ID, p_contact_id: k.contact_id, p_channel: "LinkedIn inMail", p_requested: "initial_message" });
        if (gErr) { coldFailed++; coldResults.push({ contact_id: k.contact_id, error: gErr.message }); continue; }
        const gate = (gateRows ?? [])[0];
        if (gate) {
          coldRefused++; coldRefusedByCode[gate.reason_code] = (coldRefusedByCode[gate.reason_code] ?? 0) + 1;
          if (!dryRun) await refusalRow(k.contact_id, k.company_id, gate, "LinkedIn inMail", "initial_message", { route: "cold_inmail_open" }, today);
          coldResults.push({ contact_id: k.contact_id, refused: gate.reason_code, route: "cold_inmail_open" });
          continue;
        }
        if (dryRun) { coldDrafted++; draftedAll++; coldResults.push({ contact_id: k.contact_id, would_draft: "inmail_cold", priority: k.priority }); continue; }
        try {
          const resp = await fetch(`${SUPABASE_URL}/functions/v1/generate-draft-from-context`, { method: "POST", headers: { authorization: `Bearer ${INTERNAL_SECRET}`, "content-type": "application/json" }, body: JSON.stringify({ contact_id: k.contact_id, trigger_reason: "inmail_cold" }) });
          const out = await resp.json().catch(() => ({}));
          if (out?.status === "created") { coldDrafted++; draftedAll++; coldResults.push({ contact_id: k.contact_id, drafted: "inmail_cold", produced: out?.touch_type, touch_id: out.touch_id }); }
          else if (out?.refused) { coldRefused++; coldRefusedByCode[out.reason_code] = (coldRefusedByCode[out.reason_code] ?? 0) + 1; coldResults.push({ contact_id: k.contact_id, refused: out.reason_code, via: "drafter" }); }
          else { coldFailed++; coldResults.push({ contact_id: k.contact_id, error: out?.status ?? out?.error ?? "unknown" }); }
        } catch (e) { coldFailed++; coldResults.push({ contact_id: k.contact_id, error: (e as Error).message ?? String(e) }); }
      }
    }

    // ---------------- 5. r7 reply sweep (F18.2). Anyone at chase_state 'replied' whose last inbound has no
    // reply drafted since. Event-driven drafting only fires on a NEW inbound, so everyone who replied before
    // it shipped was invisible. fn_reply_candidates excludes archived companies and anyone held in the review
    // queue. Requested as 'reply' on the inbound channel; the drafter's trigger is follow_up. Capped per run.
    const replyCap = Math.max(0, Math.min(25, Number((settings as Record<string, unknown> | null)?.reply_sweep_per_run ?? 5)));
    let replyConsidered = 0, replyDrafted = 0, replyRefused = 0, replyFailed = 0, replyBacklog = 0;
    const replyRefusedByCode: Record<string, number> = {};
    const replyResults: Array<Record<string, unknown>> = [];
    if (replyCap > 0) {
      const { data: replyAll } = await supabase.rpc("fn_reply_candidates", { p_team_id: PIER_TEAM_ID, p_limit: 5000 });
      replyBacklog = ((replyAll ?? []) as unknown[]).length;
      const { data: replies, error: rpErr } = await supabase.rpc("fn_reply_candidates", { p_team_id: PIER_TEAM_ID, p_limit: replyCap });
      if (rpErr) console.error(JSON.stringify({ event: "reply_candidates_failed", message: rpErr.message }));
      for (const r of (replies ?? []) as Array<{ contact_id: string; company_id: string | null; inbound_channel: string | null; connection_status: string | null }>) {
        if (draftedAll >= maxDrafts) { heldByBudget++; continue; }
        replyConsidered++;
        const connected = ["Accepted", "Already connected"].includes(String(r.connection_status ?? ""));
        const channel = String(r.inbound_channel ?? "") === "Email" ? "Email" : connected ? "LinkedIn DM" : "LinkedIn inMail";
        const { data: gateRows, error: gErr } = await supabase.rpc("fn_evaluate_gates", { p_team_id: PIER_TEAM_ID, p_contact_id: r.contact_id, p_channel: channel, p_requested: "reply" });
        if (gErr) { replyFailed++; replyResults.push({ contact_id: r.contact_id, error: gErr.message }); continue; }
        const gate = (gateRows ?? [])[0];
        if (gate) {
          replyRefused++; replyRefusedByCode[gate.reason_code] = (replyRefusedByCode[gate.reason_code] ?? 0) + 1;
          if (!dryRun) await refusalRow(r.contact_id, r.company_id, gate, channel, "reply", { route: "reply_sweep" }, today);
          replyResults.push({ contact_id: r.contact_id, refused: gate.reason_code, route: "reply_sweep" });
          continue;
        }
        if (dryRun) { replyDrafted++; draftedAll++; replyResults.push({ contact_id: r.contact_id, would_draft: "follow_up", channel }); continue; }
        try {
          const resp = await fetch(`${SUPABASE_URL}/functions/v1/generate-draft-from-context`, { method: "POST", headers: { authorization: `Bearer ${INTERNAL_SECRET}`, "content-type": "application/json" }, body: JSON.stringify({ contact_id: r.contact_id, trigger_reason: "follow_up" }) });
          const out = await resp.json().catch(() => ({}));
          if (out?.status === "created") { replyDrafted++; draftedAll++; replyResults.push({ contact_id: r.contact_id, drafted: "follow_up", produced: out?.touch_type, channel: out?.channel, touch_id: out.touch_id }); }
          else if (out?.refused) { replyRefused++; replyRefusedByCode[out.reason_code] = (replyRefusedByCode[out.reason_code] ?? 0) + 1; replyResults.push({ contact_id: r.contact_id, refused: out.reason_code, via: "drafter" }); }
          else { replyFailed++; replyResults.push({ contact_id: r.contact_id, error: out?.status ?? out?.error ?? "unknown" }); }
        } catch (e) { replyFailed++; replyResults.push({ contact_id: r.contact_id, error: (e as Error).message ?? String(e) }); }
      }
    }

    const byRoute: Record<string, number> = {};
    for (const c of list) byRoute[`${c.route} (${c.channel}, cap ${c.cap})`] = (byRoute[`${c.route} (${c.channel}, cap ${c.cap})`] ?? 0) + 1;
    const sum = (m: Record<string, number>) => Object.values(m).reduce((x, y) => x + y, 0);

    const summary = {
      status: dryRun ? "dry_run" : "ok",
      rules: { chase_interval_days: intervalDays, dm_chaser_cap: dmCap, inmail_chaser_cap: inmailCap, cooldown_days: cooldownDays },
      cap_per_run: limit,
      max_drafts_per_run: maxDrafts, drafted_all_routes: draftedAll, held_by_run_budget: heldByBudget,
      backlog_due_total: backlog,
      backlog_waiting_for_next_run: Math.max(0, backlog - list.length),
      considered: list.length,
      candidates_by_route: byRoute,
      drafted, refused, skipped, failed,
      refused_by_reason_code: refusedByCode,
      exhausted_handled: exhaustedHandled,
      cold_inmail_openers: { cap_per_run: coldCap, backlog: coldBacklog, considered: coldConsidered, drafted: coldDrafted, refused: coldRefused, failed: coldFailed, refused_by_reason_code: coldRefusedByCode, results: coldResults },
      reply_sweep: { cap_per_run: replyCap, backlog: replyBacklog, considered: replyConsidered, drafted: replyDrafted, refused: replyRefused, failed: replyFailed, refused_by_reason_code: replyRefusedByCode, results: replyResults },
      first_message_after_cr: { enabled: firstMsgEnabled, cap_per_run: firstMsgCap, considered: firstConsidered, drafted: firstDrafted, refused: firstRefused, failed: firstFailed, refused_by_reason_code: firstRefusedByCode, results: firstResults },
      // F16.1(c): every section's reason-code total equals its refused count, and the chaser section adds up to considered.
      reconciles: sum(refusedByCode) === refused && sum(coldRefusedByCode) === coldRefused && sum(firstRefusedByCode) === firstRefused && sum(replyRefusedByCode) === replyRefused && drafted + refused + skipped + failed === list.length,
      results,
    };
    console.log(JSON.stringify({ event: "chase_engine_run", ...summary, results: undefined, cold_inmail_openers: { ...summary.cold_inmail_openers, results: undefined }, reply_sweep: { ...summary.reply_sweep, results: undefined }, first_message_after_cr: { ...summary.first_message_after_cr, results: undefined } }));
    return json(200, summary);
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
