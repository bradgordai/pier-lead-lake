// Edge Function: enrich-contact-metadata
//
// Fills a contact's function / seniority / language_code when they are NULL.
//   - function + seniority: classified by claude-sonnet-5 from job_title (+ country,
//     company for context), constrained to the existing DB enums (no enum expansion).
//   - language_code: derived DETERMINISTICALLY from country (falling back to the last
//     segment of `location`) — Germany/Austria -> DE, France -> FR, everything else
//     (incl. Netherlands, Sweden, UK) -> EN. Not sent to the model.
//
// Only NULL fields are ever written; existing non-null values are preserved.
//
// Modes (POST body):
//   { "contact_id": "<uuid>" }            -> enrich that one contact (used by the
//                                            upsert-contact-from-sales-nav ingest chain).
//   { "backfill": true, "limit": 10 }     -> enrich up to `limit` team contacts that
//                                            have any of the three fields NULL. One
//                                            batched model call. Repeat until 0 remain.
//
// Conventions mirror the other functions: service_role only at boot, every query
// team-scoped to PIER_TEAM_ID, shared-secret Bearer auth, verify_jwt=false,
// claude-sonnet-5 with thinking disabled and no temperature.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const MAKE_SHARED_SECRET = Deno.env.get("MAKE_SHARED_SECRET") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const ANTHROPIC_MODEL = "claude-sonnet-5";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

// Allowed output sets — the live DB enums (function_type has 12 values incl. Strategy).
const FUNCTION_VALUES = ["Alliances / BD", "Marketing", "Product", "Engineering", "Sales", "Finance", "Operations", "Legal", "HR", "Executive", "Other", "Strategy"];
const SENIORITY_VALUES = ["C-suite", "Senior", "Director", "Manager", "Other"];
const FUNCTION_SET = new Set(FUNCTION_VALUES);
const SENIORITY_SET = new Set(SENIORITY_VALUES);

// Deterministic country -> language_code. Only Germany/Austria -> DE, France -> FR;
// everything else (Netherlands, Sweden, UK, unknown) -> EN. Netherlands is EN by decision.
function deriveLanguage(country: string | null, location: string | null): string {
  let src = (country ?? "").trim();
  if (!src && location) src = String(location).split(",").pop()?.trim() ?? "";
  const s = src.toLowerCase();
  if (/germany|deutschland|austria|österreich|osterreich/.test(s)) return "DE";
  if (/france|frankreich/.test(s)) return "FR";
  return "EN";
}

type Row = {
  id: string;
  job_title: string | null;
  country: string | null;
  location: string | null;
  function: string | null;
  seniority: string | null;
  language_code: string | null;
  // deno-lint-ignore no-explicit-any
  company?: any;
};

const SYSTEM_PROMPT = "You are a precise B2B contact classifier for a CRM. For each contact you choose exactly one `function` and one `seniority`, using ONLY the allowed enum values given. Output ONLY a JSON array and nothing else.";

function buildUserPrompt(rows: Row[]): string {
  const items = rows.map((r) => ({
    id: r.id,
    job_title: r.job_title ?? "",
    country: (r.country ?? (r.location ? String(r.location).split(",").pop()?.trim() : "")) ?? "",
    company: (r.company?.company_name ?? "") as string,
  }));
  return [
    `Allowed function values (choose exactly one): ${FUNCTION_VALUES.join(", ")}`,
    `Allowed seniority values (choose exactly one): ${SENIORITY_VALUES.join(", ")}`,
    "",
    "Mapping guidance:",
    "- Corporate strategy / strategy / corporate development titles -> function Strategy.",
    "- Customer Success / post-sale account management -> function Operations.",
    "- Alliances, partnerships, business development -> function Alliances / BD.",
    "- Procurement / buying / sourcing / supply chain -> function Operations.",
    "- Founder / CEO / C-level / Geschäftsführer / Vorstand / President -> seniority C-suite (function Executive unless a clearer function such as Sales/Product/Marketing fits).",
    "- 'VP' / Vice President titles -> seniority Director.",
    "- Head of / Director titles -> seniority Director; Lead/Senior Manager -> Senior; Manager -> Manager.",
    "- Individual contributor with no management scope -> seniority Other.",
    "- If a field is genuinely unclear, use Other.",
    "",
    "Classify each contact below. Return ONLY a JSON array; each element must be",
    '{"id":"<id>","function":"<one allowed function>","seniority":"<one allowed seniority>"}.',
    "",
    "Contacts:",
    JSON.stringify(items),
  ].join("\n");
}

async function classify(rows: Row[]): Promise<{ map: Map<string, { function: string; seniority: string }>; warnings: string[]; usage: unknown }> {
  const warnings: string[] = [];
  const map = new Map<string, { function: string; seniority: string }>();
  if (rows.length === 0) return { map, warnings, usage: null };
  if (!ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY missing");
  // Single contact fits comfortably in 300 tokens (per spec); a batch needs more room,
  // so the cap scales with the batch to avoid truncation (~60 tokens/contact + slack).
  const maxTokens = rows.length <= 1 ? 300 : Math.min(2048, 200 + rows.length * 70);
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: ANTHROPIC_MODEL, max_tokens: maxTokens, thinking: { type: "disabled" }, system: SYSTEM_PROMPT, messages: [{ role: "user", content: buildUserPrompt(rows) }] }),
  });
  const data = await resp.json();
  if (!resp.ok) throw new Error(`anthropic_http_${resp.status}: ${JSON.stringify(data).slice(0, 300)}`);
  const text = ((data?.content ?? []) as Array<{ type: string; text?: string }>).filter((b) => b.type === "text").map((b) => b.text ?? "").join("").trim();
  let arr: unknown;
  try {
    let t = text.replace(/^```[a-z]*\s*/i, "").replace(/```$/i, "").trim();
    const m = t.match(/\[[\s\S]*\]/);
    if (m) t = m[0];
    arr = JSON.parse(t);
  } catch {
    throw new Error(`classification_unparseable: ${text.slice(0, 200)}`);
  }
  for (const el of (Array.isArray(arr) ? arr : []) as Array<{ id?: string; function?: string; seniority?: string }>) {
    if (!el?.id) continue;
    let fn = el.function ?? "Other";
    let sn = el.seniority ?? "Other";
    if (!FUNCTION_SET.has(fn)) { warnings.push(`function "${fn}" not in enum for ${el.id}, defaulted Other`); fn = "Other"; }
    if (!SENIORITY_SET.has(sn)) { warnings.push(`seniority "${sn}" not in enum for ${el.id}, defaulted Other`); sn = "Other"; }
    map.set(el.id, { function: fn, seniority: sn });
  }
  return { map, warnings, usage: data?.usage };
}

async function enrichRows(rows: Row[]): Promise<{ updated: number; warnings: string[]; usage: unknown; results: Array<Record<string, unknown>> }> {
  // Only rows still missing function or seniority need the model; language is derived.
  const needModel = rows.filter((r) => r.function == null || r.seniority == null);
  const { map, warnings, usage } = await classify(needModel);
  let updated = 0;
  const results: Array<Record<string, unknown>> = [];
  for (const r of rows) {
    const patch: Record<string, string> = {};
    const cls = map.get(r.id);
    if (r.function == null && cls) patch.function = cls.function;
    if (r.seniority == null && cls) patch.seniority = cls.seniority;
    if (r.language_code == null) patch.language_code = deriveLanguage(r.country, r.location);
    if (Object.keys(patch).length === 0) { results.push({ id: r.id, skipped: true }); continue; }
    // Guard each patched column on IS NULL so a value curated between our SELECT and this
    // UPDATE is never clobbered; the write lands only while those columns are still null.
    let q = supabase.from("contacts").update(patch).eq("id", r.id).eq("team_id", PIER_TEAM_ID);
    for (const k of Object.keys(patch)) q = q.is(k, null);
    const { data: upd, error } = await q.select("id");
    if (error) { warnings.push(`update failed ${r.id}: ${error.message}`); results.push({ id: r.id, error: error.message }); continue; }
    if ((upd?.length ?? 0) === 0) { results.push({ id: r.id, skipped_concurrent: true }); continue; }
    updated += 1;
    results.push({ id: r.id, ...patch });
  }
  return { updated, warnings, usage, results };
}

const SELECT = "id, job_title, country, location, function, seniority, language_code, company:companies(company_name)";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!MAKE_SHARED_SECRET || !PIER_TEAM_ID) return json(500, { error: "server_misconfigured" });
  const authz = req.headers.get("authorization") ?? "";
  if ((authz.startsWith("Bearer ") ? authz.slice(7) : "") !== MAKE_SHARED_SECRET) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  try {
    if (body?.backfill === true) {
      const limit = Math.max(1, Math.min(25, Number(body?.limit ?? 10)));
      const { data, error } = await supabase.from("contacts").select(SELECT)
        .eq("team_id", PIER_TEAM_ID)
        .or("function.is.null,seniority.is.null,language_code.is.null")
        .order("created_at", { ascending: true }).limit(limit);
      if (error) throw error;
      const rows = (data ?? []) as unknown as Row[];
      if (rows.length === 0) return json(200, { status: "done", processed: 0, updated: 0, remaining: 0 });
      const { updated, warnings, usage, results } = await enrichRows(rows);
      const { count: remaining } = await supabase.from("contacts").select("id", { count: "exact", head: true })
        .eq("team_id", PIER_TEAM_ID).or("function.is.null,seniority.is.null,language_code.is.null");
      if (warnings.length) console.warn(JSON.stringify({ event: "enrich_warnings", warnings }));
      console.log(JSON.stringify({ event: "backfill_batch", processed: rows.length, updated, remaining, usage }));
      return json(200, { status: "ok", processed: rows.length, updated, remaining: remaining ?? null, warnings, results });
    }

    const contactId = String(body?.contact_id ?? "").trim();
    if (!contactId) return json(400, { error: "missing_required_fields", detail: "contact_id or backfill required" });
    const { data: c, error } = await supabase.from("contacts").select(SELECT)
      .eq("team_id", PIER_TEAM_ID).eq("id", contactId).maybeSingle();
    if (error) throw error;
    if (!c) return json(404, { error: "contact_not_found" });
    const row = c as unknown as Row;
    if (row.function != null && row.seniority != null && row.language_code != null) {
      return json(200, { status: "skipped", reason: "already_enriched", contact_id: contactId });
    }
    const { updated, warnings, usage, results } = await enrichRows([row]);
    if (warnings.length) console.warn(JSON.stringify({ event: "enrich_warnings", warnings }));
    console.log(JSON.stringify({ event: "enrich_one", contact_id: contactId, updated, usage }));
    return json(200, { status: "ok", contact_id: contactId, updated, warnings, result: results[0] ?? null });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
