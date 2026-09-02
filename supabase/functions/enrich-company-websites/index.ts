// enrich-company-websites
// Task 8 (UX sweep): find official company websites via the Apify Google Search
// actor and either auto-write HIGH-confidence hits to companies.website_url
// (insert-only, never overwrite) or queue MEDIUM/LOW guesses to
// company_enrichment_queue for Oli to review.
//
// Auth: scoped-secret Bearer (INTERNAL_APP_SECRET; legacy MAKE_SHARED_SECRET still
// accepted during the transition), verify_jwt=false.
// Needs env: APIFY_TOKEN (set in Supabase → Edge Functions → Secrets).
//
// Body:
//   { "mode": "missing", "limit": 40 }        enrich up to N null-website companies
//   { "company_ids": ["uuid", ...] }          enrich a specific set (bulk-select)
//
// Returns: { scanned, auto_written, queued, skipped_existing, apify_cost_hint }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { authorize } from "./_shared/authorize.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APIFY_TOKEN = Deno.env.get("APIFY_TOKEN") ?? "";
const PIER_TEAM_ID = "ef73c15e-4d6f-4159-bcfa-cc76b5ae4972";
const ACTOR = "apify/google-search-scraper";
const MAX_PER_RUN = 60;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

const BLOCKLIST = new Set([
  "linkedin", "facebook", "instagram", "x", "twitter", "youtube", "tiktok", "amazon",
  "ebay", "backmarket", "alibaba", "trustpilot", "f6s", "listafirme", "glassdoor",
  "indeed", "crunchbase", "wikipedia", "pinterest", "reddit", "yelp", "bloomberg",
  "companieshouse", "opencorporates", "quidco", "yahoo", "google", "apple", "play", "maps",
]);
const CC_SLDS = new Set([
  "co.uk", "com.au", "co.jp", "co.nz", "com.br", "co.za", "co.in", "com.tr",
  "com.mx", "co.kr", "com.sg", "com.hk", "org.uk", "gov.uk", "ac.uk",
]);
const TRACK = new Set(["srsltid", "gclid", "fbclid", "ref", "gad_source", "gclsrc", "mc_cid", "mc_eid", "igshid", "_hsenc", "_hsmi", "yclid"]);
const CORP = /\b(ltd|limited|gmbh|inc|llc|bv|srl|sa|ag|as|plc|co|corp|corporation|group|holdings?|international|solutions?|technology|technologies|mobile|mobiles|the)\b/gi;

const alnum = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");
const normName = (name: string) =>
  alnum(name.replace(/\(.*?\)/g, " ").replace(/[^A-Za-z0-9 ]/g, " ").replace(CORP, " "));

function bigrams(s: string): Set<string> {
  const g = new Set<string>();
  if (s.length < 2) { if (s) g.add(s); return g; }
  for (let i = 0; i < s.length - 1; i++) g.add(s.slice(i, i + 2));
  return g;
}
function dice(a: string, b: string): number {
  const A = bigrams(a), B = bigrams(b);
  if (!A.size || !B.size) return 0;
  let inter = 0; for (const x of A) if (B.has(x)) inter++;
  return (2 * inter) / (A.size + B.size);
}
function hostOf(url: string): string {
  const m = url.match(/^https?:\/\/([^/?#]+)/i);
  return m ? m[1].toLowerCase().replace(/^www\./, "") : "";
}
function registrableRoot(host: string): string {
  host = host.replace(/^www\./, "");
  const p = host.split(".");
  if (p.length >= 3 && CC_SLDS.has(p.slice(-2).join("."))) return p[p.length - 3];
  if (p.length >= 2) return p[p.length - 2];
  return host;
}
function stripTracking(url: string): string {
  const m = url.match(/(https?:\/\/[^/?#]+)([^?#]*)(\?[^#]*)?/i);
  if (!m) return url;
  const schemeHost = m[1].toLowerCase();
  let path = m[2] || "";
  const query = m[3] || "";
  const keep: string[] = [];
  if (query) for (const kv of query.slice(1).split("&")) {
    const k = kv.split("=")[0].toLowerCase();
    if (TRACK.has(k) || k.startsWith("utm_")) continue;
    keep.push(kv);
  }
  if (path === "/" || path === "") path = "";
  return schemeHost + path + (keep.length ? "?" + keep.join("&") : "");
}
const rootUrl = (url: string) => (url.match(/^(https?:\/\/[^/?#]+)/i)?.[1].toLowerCase()) ?? url;
const hasSubpath = (url: string) => {
  const m = url.match(/^https?:\/\/[^/?#]+(\/[^?#]*)?/i);
  return ((m?.[1] ?? "").replace(/\//g, "").length) > 0;
};
const isBlocklisted = (host: string) => BLOCKLIST.has(registrableRoot(host));

function buildQuery(c: { company_name: string; country: string | null; hint: string | null }): string {
  const parts = [c.company_name.replace(/\(entity TBC\)/ig, "").replace(/—/g, " ").replace(/\s+/g, " ").trim().replace(/^[-\s]+|[-\s]+$/g, "")];
  if (c.country && c.country !== "Other") parts.push(c.country);
  if (c.hint) parts.push(c.hint);
  parts.push("official website");
  return parts.join(" ").replace(/\s+/g, " ").trim();
}

type Classified = { bucket: "HIGH" | "MEDIUM" | "LOW"; value: string; conf: number; sources: string[] };
function classify(name: string, organic: any[]): Classified {
  const orgs = (organic || []).filter((o) => o?.url).sort((a, b) => (a.position ?? 999) - (b.position ?? 999));
  const top5 = orgs.slice(0, 5);
  const sources = top5.map((o) => o.url as string);
  const nonBl = top5.filter((o) => !isBlocklisted(hostOf(o.url)));
  const nm = normName(name);
  if (!nonBl.length) return { bucket: "LOW", value: top5[0]?.url ? stripTracking(top5[0].url) : "", conf: 15, sources };
  const chosen = nonBl[0];
  const d = dice(alnum(registrableRoot(hostOf(chosen.url))), nm);
  const pos = chosen.position ?? 99;
  if (pos === 1 && d >= 0.6 && !hasSubpath(chosen.url))
    return { bucket: "HIGH", value: rootUrl(stripTracking(chosen.url)), conf: Math.max(60, Math.round(d * 100)), sources };
  if (pos <= 3 && d >= 0.30)
    return { bucket: "MEDIUM", value: stripTracking(chosen.url), conf: Math.round(d * 100), sources };
  return { bucket: "LOW", value: stripTracking(chosen.url), conf: Math.max(10, Math.round(d * 100)), sources };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  // Scoped-secret auth (security audit CRITICAL 2).
  if (!authorize(req, "internal", "enrich-company-websites")) return json(401, { error: "unauthorized" });
  if (!APIFY_TOKEN) return json(500, { error: "APIFY_TOKEN not configured", hint: "Set APIFY_TOKEN in Supabase → Edge Functions → Secrets" });

  let body: any = {};
  try { body = await req.json(); } catch { /* empty ok */ }
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

  // --- resolve target companies (null website only) ---
  let sel = supabase.from("companies")
    .select("id, company_name, country, industry, category")
    .eq("team_id", PIER_TEAM_ID).is("archived_at", null)
    .or("website_url.is.null,website_url.eq.");
  if (Array.isArray(body.company_ids) && body.company_ids.length) sel = sel.in("id", body.company_ids);
  const limit = Math.min(Number(body.limit) || MAX_PER_RUN, MAX_PER_RUN);
  const { data: companies, error: cErr } = await sel.limit(limit);
  if (cErr) return json(500, { error: "select_failed", detail: cErr.message });
  if (!companies?.length) return json(200, { scanned: 0, auto_written: 0, queued: 0, message: "no null-website companies to enrich" });

  const targets = companies.map((c: any) => ({
    id: c.id, company_name: c.company_name, country: c.country,
    hint: (c.industry ?? (Array.isArray(c.category) && c.category.length ? c.category[0] : null)) || null,
  }));
  const queryToIds = new Map<string, string[]>();
  const queries: string[] = [];
  const nameById = new Map<string, string>();
  for (const t of targets) {
    nameById.set(t.id, t.company_name);
    const q = buildQuery(t);
    const k = q.toLowerCase().replace(/\s+/g, " ").trim();
    if (!queryToIds.has(k)) { queryToIds.set(k, []); queries.push(q); }
    queryToIds.get(k)!.push(t.id);
  }

  // --- run Apify synchronously ---
  const runUrl = `https://api.apify.com/v2/acts/${ACTOR.replace("/", "~")}/run-sync-get-dataset-items?token=${APIFY_TOKEN}`;
  const apifyResp = await fetch(runUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ queries: queries.join("\n"), maxPagesPerQuery: 1, saveHtmlToKeyValueStore: false }),
  });
  if (!apifyResp.ok) return json(502, { error: "apify_failed", status: apifyResp.status, detail: (await apifyResp.text()).slice(0, 400) });
  const items: any[] = await apifyResp.json();

  // --- classify + write ---
  let autoWritten = 0, queued = 0, skippedExisting = 0;
  for (const it of items) {
    const term = (it?.searchQuery?.term ?? "").toLowerCase().replace(/\s+/g, " ").trim();
    const ids = queryToIds.get(term);
    if (!ids) continue;
    for (const cid of ids) {
      const cls = classify(nameById.get(cid) ?? term, it.organicResults ?? []);
      if (cls.bucket === "HIGH") {
        const { data: upd, error } = await supabase.from("companies")
          .update({ website_url: cls.value })
          .eq("id", cid).or("website_url.is.null,website_url.eq.")
          .select("id");
        if (error) continue;
        if (upd && upd.length) autoWritten++; else skippedExisting++;
      } else {
        const { error } = await supabase.from("company_enrichment_queue").insert({
          team_id: PIER_TEAM_ID, company_id: cid, suggested_field: "website_url",
          suggested_value: cls.value || "(no confident candidate found)",
          source_urls: cls.sources, confidence: cls.conf, actor: ACTOR, notes: `${cls.bucket} confidence`,
        });
        if (!error) queued++; // ON CONFLICT pending -> unique index throws; ignore dupes
      }
    }
  }
  console.log(JSON.stringify({ event: "enrich_websites_done", scanned: targets.length, autoWritten, queued, skippedExisting }));
  return json(200, { scanned: targets.length, auto_written: autoWritten, queued, skipped_existing: skippedExisting, apify_cost_hint_usd: (queries.length * 0.0025 + 0.001).toFixed(3) });
});
