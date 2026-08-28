// parse-companies-query
// T5: the Companies "Ask" bar. Turns a plain-English question into the filter chips
// the Companies table already understands, so Oli can type "P1 companies in Germany"
// instead of opening four dropdowns.
//
// Auth: INTERNAL_APP_SECRET bearer (Lovable server fn -> here), verify_jwt=false.
// Body:  { "query": "P1 companies in Germany" }
// Reply: { "filters": { "priority": ["P1"], "country": ["Germany"] }, "unmatched": [] }
//        { "error": "unparsed", "unmatched": [...] }  when nothing usable came back
//
// The output shape is deliberately ChipFilters from the UI (Record<columnKey, string[]>,
// applied as {col, op:"in", values}). Inventing a second filter model here would have
// meant a translation layer that could drift from the table; this way the reply drops
// straight into setChips().
//
// Haiku, not Sonnet: this is short, structured, high-frequency classification. At
// $1/$5 per MTok it is a fifth of Sonnet's rate, and the whole job is vocabulary
// matching rather than writing.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";
import { callAnthropicWithSentinel, BudgetExceededError } from "./_shared/anthropic-sentinel.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODEL = "claude-haiku-4-5-20251001";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "content-type": "application/json" } });

// The filterable vocabulary, mirroring src/lib/columns.ts. Keys are the exact chip keys
// the Companies table filters on; values are the exact stored labels.
//
// Two keys are DERIVED and applied client-side (applyDerivedClientSide), not sent to
// Postgres - they are still valid chips, so they belong here.
const VOCAB: Record<string, readonly string[]> = {
  priority: ["P0", "P1", "P2", "P3", "OoS", "Competitor"],
  opportunity_status: ["To Review", "Prospect", "Contacted", "Active Lead", "Partner", "Out of Scope"],
  research_stage: ["Untouched", "Light triage", "Deep research done", "Outdated"],
  account_owner: ["Oliver Müller", "Phil", "Mark"],
  tracking: ["Live Partner", "Live Prospect", "In Lovable", "EUREFAS Member", "EUREFAS Founding Member", "No longer active"],
  category: ["Pure Online Phone Retailer", "Refurbished Specialist", "Electronics", "Multi-Category Retailer", "Operator", "Manufacturer", "Marketplace", "Comparison Site", "Industry Media", "Influencer", "Other"],
  industry: ["Mobile/Gadget Retail", "Refurb / Recommerce", "Telco", "Manufacturer", "Software", "Telco Infrastructure", "Industry Media", "Influencer", "Other"],
  product_line: ["Pier Protect", "Ticketplan", "TIGA", "Multiple", "Unknown"],
  refurbished_offered: ["Yes", "No", "Unknown"],
  sim_free_devices: ["Yes", "No", "Unknown"],
  __insurance_state__: ["Has insurance", "No insurance", "Unknown"],
  __size_tier__: ["Enterprise", "Mid-market", "SMB", "Startup", "Unknown"],
};
// country is free text in the schema, so its vocabulary is whatever is actually stored.
// Loaded per request rather than hardcoded: new markets get added by ingest, and a
// stale hardcoded list would silently refuse to filter on them.
async function liveCountries(): Promise<string[]> {
  const { data, error } = await supabase.from("companies")
    .select("country").eq("team_id", PIER_TEAM_ID).not("country", "is", null).limit(2000);
  if (error) {
    console.warn(JSON.stringify({ event: "country_load_failed", message: error.message }));
    return [];
  }
  return Array.from(new Set(((data ?? []) as Array<{ country: string }>).map((r) => r.country).filter(Boolean))).sort();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured" });
  if (!authorize(req, "internal", "parse-companies-query")) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const query = String(body?.query ?? "").trim();
  if (!query) return json(400, { error: "missing_required_fields", detail: "query required" });
  // Cheap abuse guard: this is a search box, not a prompt box.
  if (query.length > 300) return json(400, { error: "query_too_long", detail: "max 300 characters" });
  if (!ANTHROPIC_API_KEY) return json(500, { error: "ANTHROPIC_API_KEY not configured" });

  const countries = await liveCountries();
  const vocabLines = Object.entries(VOCAB)
    .map(([k, v]) => `  ${k}: ${v.join(" | ")}`)
    .concat([`  country: ${countries.join(" | ")}`])
    .join("\n");

  const system = `You convert a plain-English question about a B2B company database into filter chips.

Return ONLY valid minified JSON, no markdown, exactly:
{"filters":{"<key>":["<value>", ...]}, "unmatched":["<phrase>", ...]}

RULES
- Use ONLY the keys and values listed below, copied EXACTLY (same spelling, case, spacing and accents). Never invent a key or a value.
- Several values for one key mean OR ("P1 or P2" -> "priority":["P1","P2"]). Different keys mean AND.
- Put any part of the question you could not map into "unmatched" as a short phrase. Never guess.
- If nothing at all maps, return {"filters":{},"unmatched":["<the whole query>"]}.
- Ignore filler words like "companies", "accounts", "show me", "list", "find".

VOCABULARY
${vocabLines}

IMPORTANT MAPPINGS
- Insurance questions ("offers insurance", "has insurance", "no insurance", "uninsured") map to __insurance_state__. Never use insurance_offered: it is a free-text research field holding paragraphs of prose, so it cannot be matched exactly.
- Company size ("big", "enterprise", "small", "startups") maps to the __size_tier__ bands, which are employee-count bands: Enterprise 1000+, Mid-market 200-999, SMB 50-199, Startup under 50.
- "Untouched"/"not researched" -> research_stage. "Partner"/"prospect"/"active lead" -> opportunity_status.
- Owner names (Oliver, Oli, Phil, Mark) -> account_owner, using the exact stored label.
- A revenue or an exact employee number cannot be filtered on. Put that phrase in "unmatched".`;

  try {
    const result = await callAnthropicWithSentinel({
      model: MODEL,
      max_tokens: 400,
      system,
      messages: [{ role: "user", content: query }],
      function_name: "parse-companies-query",
      team_id: PIER_TEAM_ID,
      request_context: { query, purpose: "ask_bar_parse" },
      supabase,
      anthropic_api_key: ANTHROPIC_API_KEY,
    });

    let raw = result.content.replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/```\s*$/i, "").trim();
    // deno-lint-ignore no-explicit-any
    let parsed: any;
    try { parsed = JSON.parse(raw); } catch {
      console.warn(JSON.stringify({ event: "parse_failed", query, raw: raw.slice(0, 300) }));
      return json(200, { error: "unparsed", unmatched: [query] });
    }

    // Never trust the model's keys or values: validate everything against the vocabulary
    // before it reaches a query builder. Anything unrecognised is reported, not applied.
    const allowed: Record<string, readonly string[]> = { ...VOCAB, country: countries };
    const filters: Record<string, string[]> = {};
    const unmatched: string[] = Array.isArray(parsed?.unmatched)
      ? parsed.unmatched.filter((u: unknown) => typeof u === "string").slice(0, 10)
      : [];

    for (const [key, vals] of Object.entries(parsed?.filters ?? {})) {
      const vocab = allowed[key];
      if (!vocab) { unmatched.push(String(key)); continue; }
      const list = Array.isArray(vals) ? vals : [vals];
      const good = list
        .map((v) => String(v))
        .filter((v) => vocab.includes(v));
      const bad = list.map((v) => String(v)).filter((v) => !vocab.includes(v));
      for (const b of bad) unmatched.push(`${key}: ${b}`);
      if (good.length) filters[key] = Array.from(new Set(good));
    }

    const matchedCount = Object.keys(filters).length;
    console.log(JSON.stringify({
      event: "ask_parsed", query, matched_keys: matchedCount,
      unmatched_count: unmatched.length, cost_gbp: result.estimated_cost_gbp,
    }));

    if (matchedCount === 0) return json(200, { error: "unparsed", unmatched: unmatched.length ? unmatched : [query] });
    return json(200, { filters, unmatched });
  } catch (e) {
    if (e instanceof BudgetExceededError) {
      console.error(JSON.stringify({ event: "ask_blocked_by_budget", message: e.message }));
      return json(200, { error: "budget_exceeded", detail: e.message });
    }
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
