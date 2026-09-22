// Edge Function: intake-refresh (F22A.8, 2026-09-22)
//
// The "Refresh now" strip on Today. One button per intake. The chain is:
//   button -> this function -> PhantomBuster agents/launch -> the phantom runs -> the phantom calls ITS OWN Make
//   webhook -> Make posts to Supabase.
// This function NEVER calls a Make webhook: that would replay the listener with no new data. It only launches the
// phantom, exactly as send-approved-draft does (the PhantomBuster key never reaches the browser).
//
// Rules:
//   - one manual run per intake per 15 minutes (RATE_LIMIT_MIN);
//   - ONE AT A TIME across all four intakes: refused while any intake run is in flight here OR any of the four
//     phantoms has a running container (they share Oliver's LinkedIn session, one container per agent);
//   - honest outcomes: running | finished + found (N rows) | finished + nothing_found (0 rows) | failed + reason.
//
// Actions (JSON body.action): status | launch { intake } | poll { run_id }. Auth: internal class (Lovable JWT).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorizeRequest } from "./_shared/authorize.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const PHANTOMBUSTER_API_KEY = Deno.env.get("PHANTOMBUSTER_API_KEY") ?? "";
const RATE_LIMIT_MIN = 15;
const STALE_MIN = 30; // a run still "running" after this long is treated as finished-unknown for the lock

const INTAKES: Record<string, { agent: string; label: string }> = {
  sales_nav_leads: { agent: "2343586699386601", label: "Sales Nav leads" },
  connection_acceptances: { agent: "5421527801446685", label: "Connection acceptances" },
  sales_nav_inbox: { agent: "7307653238072765", label: "Sales Navigator inbox" },
  linkedin_inbox: { agent: "2840951049581867", label: "LinkedIn inbox" },
};

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

async function pb(path: string, init?: RequestInit) {
  const r = await fetch(`https://api.phantombuster.com/api/v2/${path}`, { ...init, headers: { "X-Phantombuster-Key-1": PHANTOMBUSTER_API_KEY, "content-type": "application/json", ...(init?.headers ?? {}) } });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`phantombuster_http_${r.status}: ${JSON.stringify(d).slice(0, 200)}`);
  return d;
}
// deno-lint-ignore no-explicit-any
function rowsOf(container: any): number {
  let ro = container?.resultObject;
  if (typeof ro === "string") { try { ro = JSON.parse(ro); } catch { ro = null; } }
  return Array.isArray(ro) ? ro.length : 0;
}
/** Latest container of an agent: { status, endedAt } or null. */
async function latestContainer(agentId: string): Promise<{ id: string; status: string; endedAt: number | null } | null> {
  const d = await pb(`containers/fetch-all?agentId=${agentId}&limit=1`);
  const c = (d?.containers ?? [])[0];
  return c ? { id: String(c.id), status: String(c.status ?? ""), endedAt: c.endedAt ? Number(c.endedAt) : null } : null;
}

/** Refresh one in-flight run from PhantomBuster and persist the honest outcome. */
// deno-lint-ignore no-explicit-any
async function settle(run: any): Promise<any> {
  if (!run?.container_id || (run.status !== "running" && run.status !== "launching")) return run;
  try {
    const c = await pb(`containers/fetch?id=${encodeURIComponent(run.container_id)}&withResultObject=true`);
    const st = String(c?.status ?? "");
    if (st !== "finished") {
      if (st === "unknown" || st === "launch error") {
        const { data } = await supabase.from("intake_runs").update({ status: "failed", outcome: "error", error: `phantom ${st}`, finished_at: new Date().toISOString() }).eq("id", run.id).select("*").single();
        return data;
      }
      return { ...run, status: "running" };
    }
    const exit = Number(c?.exitCode ?? 0);
    if (exit !== 0) {
      const { data } = await supabase.from("intake_runs").update({ status: "failed", outcome: "error", error: `phantom exit ${exit}: ${String(c?.exitMessage ?? "").slice(0, 200)}`, finished_at: new Date().toISOString() }).eq("id", run.id).select("*").single();
      return data;
    }
    const n = rowsOf(c);
    const { data } = await supabase.from("intake_runs").update({ status: "finished", outcome: n > 0 ? "found" : "nothing_found", result_count: n, finished_at: new Date().toISOString() }).eq("id", run.id).select("*").single();
    return data;
  } catch (e) {
    return { ...run, poll_error: (e as Error).message };
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured" });
  const auth = await authorizeRequest(req, "internal", "intake-refresh", supabase);
  if (!auth.ok) return json(401, { error: "unauthorized" });
  if (!PHANTOMBUSTER_API_KEY) return json(500, { error: "server_misconfigured", detail: "PHANTOMBUSTER_API_KEY not set" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const action = String(body?.action ?? "status");

  try {
    if (action === "poll") {
      const { data: run } = await supabase.from("intake_runs").select("*").eq("team_id", PIER_TEAM_ID).eq("id", String(body?.run_id ?? "")).maybeSingle();
      if (!run) return json(404, { error: "run_not_found" });
      return json(200, { run: await settle(run) });
    }

    // Settle every open run first so the lock and the strip read the truth.
    const { data: open } = await supabase.from("intake_runs").select("*").eq("team_id", PIER_TEAM_ID).in("status", ["launching", "running"]);
    for (const r of open ?? []) {
      const ageMin = (Date.now() - Date.parse(r.launched_at)) / 60000;
      if (ageMin > STALE_MIN) {
        await supabase.from("intake_runs").update({ status: "failed", outcome: "error", error: `no result after ${STALE_MIN} minutes`, finished_at: new Date().toISOString() }).eq("id", r.id);
      } else await settle(r);
    }

    if (action === "status") {
      const out: Record<string, unknown> = {};
      for (const [key, cfg] of Object.entries(INTAKES)) {
        const { data: last } = await supabase.from("intake_runs").select("*").eq("team_id", PIER_TEAM_ID).eq("intake", key).order("launched_at", { ascending: false }).limit(1).maybeSingle();
        let latest = null;
        try { latest = await latestContainer(cfg.agent); } catch { latest = null; }
        const nextAllowed = last ? new Date(Date.parse(last.launched_at) + RATE_LIMIT_MIN * 60000).toISOString() : null;
        out[key] = { label: cfg.label, last_manual_run: last ?? null, phantom_last_container: latest, next_manual_allowed_at: nextAllowed && Date.parse(nextAllowed) > Date.now() ? nextAllowed : null };
      }
      const busy = Object.entries(out).find(([, v]) => {
        const x = v as { last_manual_run: { status: string } | null; phantom_last_container: { status: string } | null };
        return x.last_manual_run?.status === "running" || x.last_manual_run?.status === "launching" || x.phantom_last_container?.status === "running";
      });
      return json(200, { intakes: out, busy_intake: busy ? busy[0] : null, rate_limit_minutes: RATE_LIMIT_MIN });
    }

    if (action === "launch") {
      const intake = String(body?.intake ?? "");
      const cfg = INTAKES[intake];
      if (!cfg) return json(400, { error: "unknown_intake" });
      // Rate limit: one manual run per intake per 15 minutes.
      const { data: last } = await supabase.from("intake_runs").select("launched_at").eq("team_id", PIER_TEAM_ID).eq("intake", intake).order("launched_at", { ascending: false }).limit(1).maybeSingle();
      if (last && Date.now() - Date.parse(last.launched_at) < RATE_LIMIT_MIN * 60000) {
        return json(200, { status: "rate_limited", next_allowed_at: new Date(Date.parse(last.launched_at) + RATE_LIMIT_MIN * 60000).toISOString() });
      }
      // One at a time: any open manual run, or any of the four phantoms currently running.
      const { data: stillOpen } = await supabase.from("intake_runs").select("intake").eq("team_id", PIER_TEAM_ID).in("status", ["launching", "running"]).limit(1).maybeSingle();
      if (stillOpen) return json(200, { status: "busy", busy_intake: stillOpen.intake, reason: "another intake is running" });
      for (const [k, c] of Object.entries(INTAKES)) {
        const lc = await latestContainer(c.agent).catch(() => null);
        if (lc && (lc.status === "running" || lc.status === "starting")) return json(200, { status: "busy", busy_intake: k, reason: `${c.label} phantom is already running` });
      }
      if (body?.dry_run === true) return json(200, { status: "would_launch", intake, agent_id: cfg.agent });
      const { data: run, error: insErr } = await supabase.from("intake_runs").insert({ team_id: PIER_TEAM_ID, intake, agent_id: cfg.agent, status: "launching", launched_by: auth.user_id }).select("*").single();
      if (insErr) throw insErr;
      try {
        const agent = await pb(`agents/fetch?id=${cfg.agent}`);
        const argument = JSON.parse(String(agent?.argument ?? "{}"));
        const launched = await pb("agents/launch", { method: "POST", body: JSON.stringify({ id: cfg.agent, argument }) });
        const containerId = String(launched?.containerId ?? "");
        if (!containerId) throw new Error("no container id returned");
        const { data: upd } = await supabase.from("intake_runs").update({ status: "running", container_id: containerId }).eq("id", run.id).select("*").single();
        console.log(JSON.stringify({ event: "intake_launched", intake, container_id: containerId, by: auth.user_id }));
        return json(200, { status: "running", run: upd });
      } catch (e) {
        const msg = (e as Error).message ?? String(e);
        await supabase.from("intake_runs").update({ status: "failed", outcome: "error", error: msg.slice(0, 300), finished_at: new Date().toISOString() }).eq("id", run.id);
        return json(200, { status: "failed", error: msg });
      }
    }
    return json(400, { error: "unknown_action" });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message }));
    return json(500, { error: "internal_error", detail: (e as Error).message });
  }
});
