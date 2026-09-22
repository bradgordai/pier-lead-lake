// Edge Function: score-company (F22B.1(i), 2026-09-23) — THE SCORING SUB-AGENT.
//
// Scoring runs here and only here: a dedicated agent called when a company needs scoring, never inline in a
// general prompt. The agent (Claude) only READS the company's research and returns observations: the sizing rung
// and device figure, the GAP and LOCK-IN readings, and the four wedge tests. Every POINT is computed in this file,
// deterministically, from those observations, so each number can be explained and re-run.
//
// Model: 260904_PIER_lead_scoring_model_v01_OM_C2.md v03, with Brad's override of section 4.3 (23 Sep 2026):
//   UNASSESSED COMPONENTS SCORE ZERO; score is raw points over 100; assessed_points and research_upside stored.
//   Exception (model 4.2 + Brad F22B.1(d)): an unknown incumbent takes the neutral 14/30, not counted as assessed.
//
// Invocation (POST, internal class: INTERNAL_APP_SECRET or a Pier team member's JWT):
//   { company_ids: [uuid | "C123", ...], dry_run: true, run_label }   dry run: computes + logs to
//        company_score_runs, never writes company_scores
//   { company_ids: [...], dry_run: false }                             scores those companies
//   { mode: "dirty", limit: 10 }                                       re-scores dirty AGENT scores (hourly cron)
//   { mode: "unscored", limit: N, approved_full_run: true }            the full first run; refused without the flag
// Oliver's imported scores (source oliver_board_v01) are never overwritten unless force_rescore_oliver is true.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorizeRequest } from "./_shared/authorize.ts";
import { callAnthropicWithSentinel, BudgetExceededError } from "./_shared/anthropic-sentinel.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const MODEL = "claude-sonnet-5";
const MODEL_VERSION = "lead_scoring_model_v03+brad_unassessed_zero/score-company v1";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

// ---- The model's constants, in one place (lead_scoring_model v03 s4, sizing standard s5-s6) ----
const GWP_PER_POLICY_GBP = 40;        // s3.1, agreed 5 Aug 2026
const ATTACH_ONLINE = 0.08;           // sizing s5, bottom of 8-12%
const ATTACH_INSTORE = 0.25;          // sizing s5, bottom of 25-30%
const BANDS: Array<[number, string, number]> = [[250_000, "XL", 40], [50_000, "L", 30], [10_000, "M", 20], [0, "S", 10]];
const UNKNOWN_INCUMBENT_POINTS = 14;  // s4.2 "Unknown ... scores 14 of 30"
const WEDGE_STALE_DAYS = 180;         // s4.2b
const WEDGE_STALE_PENALTY = 4;
const WEDGE_STALE_FLOOR = 2;

const SYSTEM = `You are the Pier company-scoring agent. You READ one company's research record and report OBSERVATIONS as JSON.
You never compute points and never invent facts. If the record does not say it, it is not assessable.

Pier sells device protection (phones, laptops, tablets) through retailers' own checkouts and shops.

1. SIZE (sizing standard). The unit is monthly hardware device sales. Pick the highest rung the record supports:
 E1 stated/published unit count · E2 revenue x electronics share / ASP (ASP GBP 200 new, 150 refurbished) / 12 ·
 E3 headcount x GBP 250k / ASP / 12 · E4 monthly visits x 1.5% x 1.2 items x device share (phone specialist 0.8-0.9,
 computer/IT 0.5-0.7, full-line electronics 0.3-0.4, general merchandise 0.1-0.2) · E5 stores x devices per store
 (350 large electronics store, 100-150 small telecom/computer shop) · E0 unsized.
 BANNED: customer review counts. Subscriber counts are NOT devices sold (Aldi Talk, Congstar). Marketplace volume is
 not addressable: if the record says only a share goes through the own website, size the OWN channel.
 Split into online and in-store devices per month where the record allows (E4 is online only; add E5 in-store for shops).
 A vague word ("Medium", "TBC") is NOT a figure: E0.

2. GAP, 0-4: how much better Pier can be.
 4 no cover offered at all (observed on a walk) · 3 cover exists but excludes drop, liquid or theft · 3 self-funded
 guarantee, no IPID, no named insurer · 2 real insurance, one-off or annual billing · 1 monthly but buried placement
 or weak attach · 0 monthly, no excess, cancel anytime.
3. LOCK-IN, 0-4: how hard it is to leave. 4 CAPTIVE carrier: the named insurer shares the retailer's name AND an
 explicit carrier phrase ("provided by", "underwritten by", "Risikotraeger") names it · 3 deep integration, cover
 inline in the basket under own branding · 2 third-party inline, standard embed · 1 links out / redirects to the
 insurer · 0 nothing to displace. Self-carried risk ("carries that risk itself") is NOT captive.
 renewal_over_12m_known: true ONLY if the record states more than 12 months of contract term remain.
 GAP and LOCK-IN are assessable only if the record shows what the checkout or insurance offer actually is.
 Observable evidence beats a missing classification: a self-funded guarantee found on a walk sets gap 3.

4. WEDGE: the reason this company should talk to Pier, as written in the record (usp_notes and notes).
 present: "full" (60+ characters of substance) | "stub" (a short note) | "none".
 evidence: "dated_and_reopenable" (a URL, policy link or screenshot path AND a date) | "date_only" | "none".
 Claiming a walk is not evidence of one; the word "walk" alone is not evidence.
 walk_date: the most recent date of a checkout walk or first-hand observation, YYYY-MM-DD, or null.
 verbatim_quote: true only if the record quotes the company's own words verbatim.
 names_peril_or_insurer: true if it names an uncovered peril (drop, liquid, theft, loss, breakage) or the incumbent insurer.

Return ONLY this JSON, no prose:
{"size":{"assessable":bool,"rung":"E1|E2|E3|E4|E5|E0","devices_per_month_online":number|null,"devices_per_month_instore":number|null,"confidence":"high|medium|low|very low|floor only","basis":"one sentence naming the source and its date"},
 "gap":{"assessable":bool,"score":0-4|null,"basis":"one sentence, quote the record"},
 "lockin":{"assessable":bool,"score":0-4|null,"renewal_over_12m_known":bool,"basis":"one sentence"},
 "wedge":{"present":"full|stub|none","evidence":"dated_and_reopenable|date_only|none","walk_date":"YYYY-MM-DD"|null,"verbatim_quote":bool,"names_peril_or_insurer":bool,"basis":"one sentence"}}`;

const FIELDS = "id,team_id,company_id,company_name,root_domain,website_url,country,research_stage,last_refreshed,priority,opportunity_status,parent_group,category,refurbished_offered,insurance_offered,insurance_provider,insurance_structure_type,insurance_monthly_price,insurance_annual_price,insurance_product_types,coverage_summary,distribution_model,customer_journey,policy_url,usp_notes,additional_notes,annual_devices_sold,annual_devices_sold_evidence,employees,monthly_visits,estimated_revenue_gbp,source_urls,archived_at";

// deno-lint-ignore no-explicit-any
function recordText(c: any): string {
  const cut = (v: unknown, n: number) => (v == null || v === "" ? null : String(v).slice(0, n));
  const rec: Record<string, unknown> = {
    company: c.company_name, domain: c.root_domain ?? c.website_url, country: c.country, research_stage: c.research_stage,
    last_refreshed: c.last_refreshed, parent_group: c.parent_group, category: c.category, refurbished_offered: c.refurbished_offered,
    insurance_offered: cut(c.insurance_offered, 3000), insurance_provider: cut(c.insurance_provider, 2000),
    insurance_structure_type: c.insurance_structure_type, insurance_monthly_price: c.insurance_monthly_price,
    insurance_annual_price: c.insurance_annual_price, insurance_product_types: c.insurance_product_types,
    coverage_summary: cut(c.coverage_summary, 2000), distribution_model: cut(c.distribution_model, 800),
    customer_journey: cut(c.customer_journey, 1500), policy_url: c.policy_url, usp_notes: cut(c.usp_notes, 2500),
    annual_devices_sold: cut(c.annual_devices_sold, 800), annual_devices_sold_evidence: cut(c.annual_devices_sold_evidence, 800),
    employees: c.employees, monthly_visits: c.monthly_visits, estimated_revenue_gbp: c.estimated_revenue_gbp,
    source_urls: cut(c.source_urls, 800), additional_notes: cut(c.additional_notes, 6000),
  };
  for (const k of Object.keys(rec)) if (rec[k] == null) delete rec[k];
  return JSON.stringify(rec);
}

// deno-lint-ignore no-explicit-any
function parseAgent(text: string): any {
  const m = text.match(/\{[\s\S]*\}/);
  if (!m) throw new Error("agent returned no JSON");
  return JSON.parse(m[0]);
}

const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, n));
const num = (v: unknown) => (typeof v === "number" && isFinite(v) && v >= 0 ? v : null);

/** Every point, computed here from the agent's observations. Returns the row and the human working. */
// deno-lint-ignore no-explicit-any
function compute(c: any, a: any, territory: Map<string, { rank: number; points: number; note: string }>, today: Date) {
  const working: Record<string, unknown> = {};

  // GWP potential, 40
  let gwp_points = 0, gwp_assessed = false, gwp_value_gbp: number | null = null, gwp_band: string | null = null, devices: number | null = null;
  const on = num(a?.size?.devices_per_month_online), inst = num(a?.size?.devices_per_month_instore);
  if (a?.size?.assessable && a?.size?.rung && a.size.rung !== "E0" && (on !== null || inst !== null)) {
    gwp_assessed = true;
    devices = (on ?? 0) + (inst ?? 0);
    gwp_value_gbp = Math.round(((on ?? 0) * 12 * ATTACH_ONLINE + (inst ?? 0) * 12 * ATTACH_INSTORE) * GWP_PER_POLICY_GBP);
    const b = BANDS.find(([floor]) => (gwp_value_gbp as number) >= floor)!;
    gwp_band = b[1]; gwp_points = b[2];
    working.gwp = `${a.size.rung}: ${on ?? 0}/mo online x8% + ${inst ?? 0}/mo in-store x25%, x12 x GBP40 = GBP ${gwp_value_gbp}/yr -> band ${gwp_band} = ${gwp_points}/40`;
  } else working.gwp = "GWP: not assessed (unsized, E0) = 0/40";

  // Incumbent switchability, 30: switchability = GAP - LOCK-IN, -4..+4, 30 points scale linearly on it.
  let switch_points = UNKNOWN_INCUMBENT_POINTS, switch_assessed = false, gap: number | null = null, lockin: number | null = null, sw: number | null = null;
  if (a?.gap?.assessable && a?.lockin?.assessable && Number.isInteger(a.gap.score) && Number.isInteger(a.lockin.score)) {
    switch_assessed = true;
    gap = clamp(a.gap.score, 0, 4);
    lockin = clamp(a.lockin.score, 0, 4) + (a.lockin.renewal_over_12m_known ? 1 : 0);
    sw = clamp(gap - lockin, -4, 4);
    switch_points = Math.round(((sw + 4) * 30) / 8);
    working.switch = `gap ${gap} - lock-in ${lockin} = switchability ${sw} (range -4..+4) -> ${switch_points}/30`;
  } else working.switch = `incumbent: not checked (neutral ${UNKNOWN_INCUMBENT_POINTS}/30)`;

  // Territory, 15: the rank table only. Absent country = rank 0 and says so.
  let territory_points = 0, territory_assessed = false, territory_rank: number | null = null, territory_in_table: boolean | null = null;
  const country = (c.country ?? "").trim();
  if (country) {
    territory_assessed = true;
    const t = territory.get(country);
    if (t) { territory_rank = t.rank; territory_points = t.points; territory_in_table = true; working.territory = `${country}: rank ${t.rank} (${t.note}) = ${t.points}/15`; }
    else { territory_rank = 0; territory_points = territory.get("__rank0__")?.points ?? 3; territory_in_table = false; working.territory = `${country}: NOT IN THE RANK TABLE, scored rank 0 = ${territory_points}/15`; }
  } else working.territory = "territory: not assessed (no country) = 0/15";

  // Wedge quality, 15: four tests, minus 4 when the walk is over 180 days old, floored at 2.
  let wedge_points = 0, wedge_assessed = false, wedge_stale = false;
  const w = a?.wedge ?? {};
  const tests = {
    exists: w.present === "full" ? 5 : w.present === "stub" ? 2 : 0,
    evidenced: w.evidence === "dated_and_reopenable" ? 4 : w.evidence === "date_only" ? 2 : 0,
    quote_safe: w.present !== "none" && w.verbatim_quote ? 4 : 0,
    specific: w.present !== "none" && w.names_peril_or_insurer ? 2 : 0,
  };
  if (w.present === "full" || w.present === "stub") {
    wedge_assessed = true;
    const raw = tests.exists + tests.evidenced + tests.quote_safe + tests.specific;
    wedge_points = raw;
    let ageDays: number | null = null;
    if (w.walk_date && /^\d{4}-\d{2}-\d{2}$/.test(w.walk_date)) ageDays = Math.floor((today.getTime() - Date.parse(w.walk_date)) / 86400000);
    if (ageDays !== null && ageDays > WEDGE_STALE_DAYS) { wedge_stale = true; wedge_points = Math.max(WEDGE_STALE_FLOOR, raw - WEDGE_STALE_PENALTY); }
    working.wedge = `exists ${tests.exists} + evidenced ${tests.evidenced} + quote ${tests.quote_safe} + specific ${tests.specific} = ${raw}` +
      (wedge_stale ? `, walk ${ageDays} days old: -4, floor 2 -> ${wedge_points}/15` : ` -> ${wedge_points}/15`);
  } else if (c.research_stage === "Deep research done") {
    wedge_assessed = true;
    working.wedge = "wedge: researched, no wedge in the record = 0/15";
  } else working.wedge = "wedge: not assessed (no wedge written) = 0/15";

  const assessed_points = (gwp_assessed ? 40 : 0) + (switch_assessed ? 30 : 0) + (territory_assessed ? 15 : 0) + (wedge_assessed ? 15 : 0);
  const score = gwp_points + switch_points + territory_points + wedge_points;
  const unassessed = [!gwp_assessed && "GWP", !switch_assessed && "incumbent", !territory_assessed && "territory", !wedge_assessed && "wedge"].filter(Boolean);
  working.total = `${score}/100, ${assessed_points} of 100 points assessed` + (unassessed.length ? `, NOT ASSESSED: ${unassessed.join(", ")} (scored 0` + (!switch_assessed ? `; incumbent neutral 14` : "") + `)` : "") + `, research upside ${100 - assessed_points}`;

  return {
    row: {
      company_id: c.id, team_id: c.team_id, score, assessed_points,
      gwp_points, gwp_assessed, gwp_value_gbp, gwp_band, size_rung: a?.size?.rung ?? "E0", devices_per_month: devices, gwp_basis: a?.size?.basis ?? null,
      switch_points, switch_assessed, switch_gap: gap, switch_lockin: lockin, switchability: sw,
      switch_basis: switch_assessed ? `GAP: ${a.gap.basis ?? ""} | LOCK-IN: ${a.lockin.basis ?? ""}` : `incumbent: not checked (neutral ${UNKNOWN_INCUMBENT_POINTS}/30)`,
      territory_points, territory_assessed, territory_rank, territory_in_table, territory_basis: working.territory as string,
      wedge_points, wedge_assessed, wedge_tests: { ...tests, walk_date: w.walk_date ?? null, present: w.present ?? "none", evidence: w.evidence ?? "none" }, wedge_stale, wedge_basis: w.basis ?? null,
      source: "scoring_agent", model_version: MODEL_VERSION, scored_at: new Date().toISOString(),
      research_refreshed_at_scoring: c.last_refreshed, needs_rescore: false, rescore_reason: null,
      detail: { size_confidence: a?.size?.confidence ?? null, working },
    },
    working,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID || !ANTHROPIC_API_KEY) return json(500, { error: "server_misconfigured" });
  const auth = await authorizeRequest(req, "internal", "score-company", supabase);
  if (!auth.ok) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const mode = String(body?.mode ?? "ids");
  const dryRun = body?.dry_run === true;
  const limit = Math.min(Math.max(Number(body?.limit ?? 10), 1), 50);
  const runLabel = String(body?.run_label ?? mode).slice(0, 80);
  const forceOliver = body?.force_rescore_oliver === true;

  // Resolve the companies to score.
  // deno-lint-ignore no-explicit-any
  let companies: any[] = [];
  if (mode === "ids") {
    const ids: string[] = Array.isArray(body?.company_ids) ? body.company_ids.map(String).slice(0, 50) : [];
    if (!ids.length) return json(400, { error: "company_ids required" });
    const uuids = ids.filter((x) => /^[0-9a-f-]{36}$/i.test(x)), refs = ids.filter((x) => !/^[0-9a-f-]{36}$/i.test(x));
    if (uuids.length) { const { data } = await supabase.from("companies").select(FIELDS).eq("team_id", PIER_TEAM_ID).in("id", uuids); companies.push(...(data ?? [])); }
    if (refs.length) { const { data } = await supabase.from("companies").select(FIELDS).eq("team_id", PIER_TEAM_ID).in("company_id", refs); companies.push(...(data ?? [])); }
  } else if (mode === "dirty") {
    const { data: dirty } = await supabase.from("company_scores").select("company_id").eq("team_id", PIER_TEAM_ID)
      .eq("needs_rescore", true).eq("source", "scoring_agent").limit(limit);
    const ids = (dirty ?? []).map((r: { company_id: string }) => r.company_id);
    if (ids.length) { const { data } = await supabase.from("companies").select(FIELDS).in("id", ids); companies = data ?? []; }
  } else if (mode === "unscored") {
    if (body?.approved_full_run !== true) return json(400, { error: "full_run_not_approved", detail: "mode unscored needs approved_full_run: true (Brad's STOP after the dry run)" });
    const { data } = await supabase.from("v_company_score").select("company_id").eq("team_id", PIER_TEAM_ID)
      .eq("is_scored", false).order("research_priority_rank", { ascending: true, nullsFirst: false }).limit(limit);
    const ids = (data ?? []).map((r: { company_id: string }) => r.company_id);
    if (ids.length) { const { data: cs } = await supabase.from("companies").select(FIELDS).in("id", ids); companies = cs ?? []; }
  } else return json(400, { error: "unknown_mode" });

  const { data: terr } = await supabase.from("score_territory_ranks").select("country,rank,points,note");
  const territory = new Map<string, { rank: number; points: number; note: string }>();
  for (const t of terr ?? []) { territory.set(t.country, t); if (t.rank === 0 && !territory.has("__rank0__")) territory.set("__rank0__", t); }

  const { data: existing } = await supabase.from("company_scores").select("company_id,source").in("company_id", companies.map((c) => c.id).concat(["00000000-0000-0000-0000-000000000000"]));
  const oliverIds = new Set((existing ?? []).filter((e: { source: string }) => e.source === "oliver_board_v01").map((e: { company_id: string }) => e.company_id));

  const today = new Date();
  const results = [];
  for (const c of companies) {
    if (oliverIds.has(c.id) && !forceOliver) { results.push({ company: c.company_id, name: c.company_name, skipped: "oliver_import_kept" }); continue; }
    try {
      const r = await callAnthropicWithSentinel({
        model: MODEL,
        system: [{ type: "text", text: SYSTEM, cache_control: { type: "ephemeral" } }],
        messages: [{ role: "user", content: `Company research record:\n${recordText(c)}` }],
        max_tokens: 1200, thinking: { type: "disabled" },
        function_name: "score-company", team_id: c.team_id,
        request_context: { company_id: c.id, company_ref: c.company_id, dry_run: dryRun, run_label: runLabel },
        supabase, anthropic_api_key: ANTHROPIC_API_KEY,
      });
      const agent = parseAgent(r.content);
      const { row, working } = compute(c, agent, territory, today);
      await supabase.from("company_score_runs").insert({
        team_id: c.team_id, company_id: c.id, run_label: runLabel, dry_run: dryRun, agent_output: agent, working,
        score: row.score, assessed_points: row.assessed_points, estimated_cost_gbp: r.estimated_cost_gbp,
      });
      if (!dryRun) {
        const { error } = await supabase.from("company_scores").upsert(row, { onConflict: "company_id" });
        if (error) throw new Error(`write failed: ${error.message}`);
      }
      results.push({ company: c.company_id, name: c.company_name, score: row.score, assessed_points: row.assessed_points,
        research_upside: 100 - row.assessed_points, working, cost_gbp: r.estimated_cost_gbp, written: !dryRun });
    } catch (e) {
      const msg = (e as Error).message ?? String(e);
      await supabase.from("company_score_runs").insert({ team_id: c.team_id, company_id: c.id, run_label: runLabel, dry_run: dryRun, error: msg.slice(0, 500) });
      results.push({ company: c.company_id, name: c.company_name, error: msg });
      if (e instanceof BudgetExceededError) break;
    }
  }
  return json(200, { mode, dry_run: dryRun, scored: results.filter((r) => "score" in r).length, results });
});
