// Edge Function: upsert-contact-from-sales-nav
//
// Called by Make.com after the Sales Nav "List Export" phantom fires, once per lead.
// Flow: verify shared secret -> dedupe (canonical linkedin_slug first, then URL) ->
// resolve company (exact -> alias cache -> AI fuzzy match) -> insert contact.
//
// URL handling (migration 031): the Sales Nav phantom's `profileUrl` is the internal
// /sales/lead/ACw... format, which never matches the public /in/{slug} URL the
// "Recently Connected" phantom emits. So we prefer the phantom's `linkedInProfileUrl`
// (public /in/ URL) for linkedin_url storage, and extract a canonical `linkedin_slug`
// from whichever /in/ URL is available. If only a /sales/lead/ URL exists, linkedin_slug
// stays NULL (the contact won't match on accept until re-ingested with a public URL).
//
// Security / conventions:
//   - service_role is used ONLY to construct the Supabase client at boot (below).
//     Every query is explicitly scoped to PIER_TEAM_ID and company matches are
//     restricted to archived_at IS NULL, because service_role bypasses RLS.
//   - Custom auth: callers present `Authorization: Bearer <MAKE_SHARED_SECRET>`.
//     The function is deployed with verify_jwt=false so this Bearer reaches the handler.
//   - Anthropic failures never crash the function: any error/malformed response is
//     treated as an unmatched company.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const MAKE_SHARED_SECRET = Deno.env.get("MAKE_SHARED_SECRET") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const ANTHROPIC_MODEL = "claude-sonnet-5";

// service_role client — constructed once at boot; only used via the client API.
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// deno-lint-ignore no-explicit-any
const json = (status: number, body: any) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

// ---------- helpers ----------
function normalizeName(s: string): string {
  return (s ?? "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ");
}
function bigrams(s: string): Map<string, number> {
  const m = new Map<string, number>();
  const t = normalizeName(s).replace(/ /g, "");
  for (let i = 0; i < t.length - 1; i++) {
    const g = t.slice(i, i + 2);
    m.set(g, (m.get(g) ?? 0) + 1);
  }
  return m;
}
// Sørensen–Dice coefficient over character bigrams (0..1). Local, no pg_trgm needed.
function diceSimilarity(a: string, b: string): number {
  const A = bigrams(a), B = bigrams(b);
  if (A.size === 0 || B.size === 0) return 0;
  let overlap = 0, sizeA = 0, sizeB = 0;
  for (const [g, ca] of A) { const cb = B.get(g); if (cb) overlap += Math.min(ca, cb); sizeA += ca; }
  for (const cb of B.values()) sizeB += cb;
  return (2 * overlap) / (sizeA + sizeB);
}
function normalizeUrl(u: string): string {
  return (u ?? "").trim().replace(/\/+$/, "");
}
// Canonical LinkedIn slug from a public /in/{slug} URL (matches migration 031's regex).
// Returns null for /sales/lead/ or any non-/in/ URL.
function extractSlug(url: string): string | null {
  const m = /linkedin\.com\/in\/([^/?#]+)/i.exec(url ?? "");
  return m ? m[1] : null;
}
function uniquePush(arr: unknown, v: string): string[] {
  const base = Array.isArray(arr) ? (arr as string[]).slice() : [];
  if (v && !base.includes(v)) base.push(v);
  return base;
}

type Company = { id: string; company_id: string | null; company_name: string; country: string | null; industry: string | null };

// deno-lint-ignore no-explicit-any
async function aiMatch(companyName: string, contact: any, candidates: Company[]): Promise<{ matched: boolean; company_id: string | null; confidence: number; reasoning: string }> {
  const fallback = { matched: false, company_id: null, confidence: 0, reasoning: "fallback" };
  if (!ANTHROPIC_API_KEY) { console.error(JSON.stringify({ event: "anthropic_skip", reason: "ANTHROPIC_API_KEY missing" })); return fallback; }
  const candJson = candidates.map((c) => ({ company_id: c.id, name: c.company_name, country: c.country, industry: c.industry }));
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: ANTHROPIC_MODEL,
        max_tokens: 500,
        system:
          "You match LinkedIn contacts to companies. Given candidates + contact context, return ONLY JSON: {matched: bool, company_id: uuid or null, confidence: 0-100, reasoning: string}. Reason about country + industry + name similarity.",
        messages: [{ role: "user", content: JSON.stringify({ candidates: candJson, contact }) }],
      }),
    });
    const data = await resp.json();
    if (!resp.ok) { console.error(JSON.stringify({ event: "anthropic_http_error", status: resp.status, body: JSON.stringify(data).slice(0, 300) })); return fallback; }
    const text = ((data?.content ?? []) as Array<{ type: string; text?: string }>)
      .filter((b) => b.type === "text").map((b) => b.text ?? "").join("").trim();
    console.log(JSON.stringify({ event: "anthropic_ok", status: resp.status, model: ANTHROPIC_MODEL, usage: data?.usage, raw: text.slice(0, 300) }));
    const cleaned = text.replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/```$/i, "").trim();
    const parsed = JSON.parse(cleaned);
    const conf = Math.max(0, Math.min(100, Number(parsed?.confidence) || 0));
    return { matched: Boolean(parsed?.matched), company_id: parsed?.company_id ?? null, confidence: conf, reasoning: String(parsed?.reasoning ?? "") };
  } catch (e) {
    console.error(JSON.stringify({ event: "anthropic_exception", message: (e as Error).message }));
    return fallback;
  }
}

// Continue the existing P### contact_id series (data uses P001..P270; C-prefixed
// in the brief would fork a second scheme and clash with company Cnnn refs).
async function nextContactId(): Promise<string> {
  const { data, error } = await supabase
    .from("contacts").select("contact_id").eq("team_id", PIER_TEAM_ID).ilike("contact_id", "P%").limit(5000);
  if (error) throw error;
  let max = 0;
  for (const r of data ?? []) {
    const m = /^P(\d+)$/.exec((r as { contact_id: string }).contact_id ?? "");
    if (m) { const n = parseInt(m[1], 10); if (n > max) max = n; }
  }
  return "P" + String(max + 1).padStart(3, "0");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  // Config presence (also serves as a secret-wiring check).
  if (!MAKE_SHARED_SECRET) return json(500, { error: "server_misconfigured", detail: "MAKE_SHARED_SECRET not set" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured", detail: "PIER_TEAM_ID not set" });

  // Shared-secret auth.
  const authz = req.headers.get("authorization") ?? "";
  const token = authz.startsWith("Bearer ") ? authz.slice(7) : "";
  if (token !== MAKE_SHARED_SECRET) return json(401, { error: "unauthorized" });

  // Secret-gated health check for the Anthropic connection. Returns only the HTTP
  // status + Anthropic's own (key-free) response body — never the API key itself.
  if (req.headers.get("x-debug-anthropic") === "1") {
    const dbgModel = req.headers.get("x-debug-model") || ANTHROPIC_MODEL;
    let status = 0, raw = "", err = "";
    try {
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: dbgModel, max_tokens: 16, messages: [{ role: "user", content: "Reply with the word OK." }] }),
      });
      status = r.status; raw = (await r.text()).slice(0, 400);
    } catch (e) { err = (e as Error).message; }
    return json(200, { debug: true, anthropic_key_present: ANTHROPIC_API_KEY.length > 0, anthropic_status: status, model: dbgModel, error: err, raw });
  }

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  const profileUrl = String(body?.profileUrl ?? "").trim();
  const firstName = String(body?.firstName ?? "").trim();
  const lastName = String(body?.lastName ?? "").trim();
  if (!profileUrl || !firstName || !lastName) {
    return json(400, { error: "missing_required_fields", detail: "profileUrl, firstName, lastName are required" });
  }
  const headline = String(body?.headline ?? "").trim() || null;
  const companyName = String(body?.companyName ?? "").trim();
  const companyUrl = String(body?.companyUrl ?? "").trim() || null;
  const location = String(body?.location ?? "").trim() || null;
  const connectionDegree = String(body?.connectionDegree ?? "").trim();
  const listName = String(body?.listName ?? "").trim();

  // URL canonicalization (migration 031): prefer the public /in/ URL for storage + slug.
  const linkedInProfileUrl = String(body?.linkedInProfileUrl ?? "").trim();
  const storedLinkedinUrl = normalizeUrl(linkedInProfileUrl || profileUrl);
  const profileUrlNorm = normalizeUrl(profileUrl);
  const slug = extractSlug(linkedInProfileUrl) ?? extractSlug(profileUrl); // null if only /sales/lead/

  try {
    // ---------- 1. Dedupe: canonical slug first, then raw URL (backward compatible) ----------
    // deno-lint-ignore no-explicit-any
    let existing: any = null;
    if (slug) {
      const r = await supabase
        .from("contacts").select("id, contact_id, sn_lists, company_id, archived_at")
        .eq("team_id", PIER_TEAM_ID).eq("linkedin_slug", slug).limit(1).maybeSingle();
      if (r.error) throw r.error;
      existing = r.data;
    }
    if (!existing) {
      const r = await supabase
        .from("contacts").select("id, contact_id, sn_lists, company_id, archived_at")
        .eq("team_id", PIER_TEAM_ID).eq("linkedin_url", profileUrlNorm).limit(1).maybeSingle();
      if (r.error) throw r.error;
      existing = r.data;
    }

    if (existing) {
      // Assert: a live re-import should not be resolving a soft-deleted contact.
      if (existing.archived_at) console.warn(JSON.stringify({ event: "dedupe_on_archived_contact", contact_id: existing.id }));
      const nextLists = uniquePush(existing.sn_lists, listName);
      const { error: updErr } = await supabase
        .from("contacts").update({ sn_lists: nextLists, updated_at: new Date().toISOString() }).eq("id", existing.id);
      if (updErr) throw updErr;
      console.log(JSON.stringify({ event: "list_appended", contact_id: existing.id, sn_lists: nextLists }));
      return json(200, {
        status: "updated",
        contact_id: existing.id,
        company_id: existing.company_id ?? null,
        company_match_source: "unchanged",
        company_confidence: 0,
        action: "list_appended",
      });
    }

    // ---------- 2. Company resolution (new contacts only) ----------
    let companyId: string | null = null;
    let companyRef = ""; // company_ref is NOT NULL; '' when unmatched (approved)
    let matchSource: "exact-match" | "alias-cache" | "ai-reasoned" | "unmatched" = "unmatched";
    let confidence = 0;

    if (companyName) {
      const { data: companiesRaw, error: coErr } = await supabase
        .from("companies").select("id, company_id, company_name, country, industry")
        .eq("team_id", PIER_TEAM_ID).is("archived_at", null).limit(5000);
      if (coErr) throw coErr;
      const active = (companiesRaw ?? []) as Company[];
      const target = normalizeName(companyName);

      // a) exact (case-insensitive, normalized)
      const exact = active.find((c) => normalizeName(c.company_name) === target);
      if (exact) {
        companyId = exact.id; companyRef = exact.company_id ?? ""; matchSource = "exact-match"; confidence = 100;
      } else {
        // b) alias cache (must still point at an active company)
        const { data: aliasRows, error: aliasErr } = await supabase
          .from("company_aliases").select("alias, company_id").eq("team_id", PIER_TEAM_ID).ilike("alias", companyName).limit(20);
        if (aliasErr) throw aliasErr;
        const aliasHit = (aliasRows ?? []).find((a) => normalizeName((a as { alias: string }).alias) === target) as { company_id: string } | undefined;
        const aliasCompany = aliasHit ? active.find((c) => c.id === aliasHit.company_id) : undefined;
        if (aliasCompany) {
          companyId = aliasCompany.id; companyRef = aliasCompany.company_id ?? ""; matchSource = "alias-cache"; confidence = 90;
        } else {
          // c) AI fuzzy match over the top 5 candidates by Dice similarity
          const ranked = active
            .map((c) => ({ c, s: diceSimilarity(companyName, c.company_name) }))
            .sort((x, y) => y.s - x.s).slice(0, 5).map((x) => x.c);
          const ai = await aiMatch(companyName, { firstName, lastName, headline, companyName, companyUrl, location, connectionDegree }, ranked);
          const validPick = ai.matched && ai.company_id ? ranked.find((c) => c.id === ai.company_id) : undefined;
          if (validPick && ai.confidence >= 85) {
            companyId = validPick.id; companyRef = validPick.company_id ?? ""; matchSource = "ai-reasoned"; confidence = ai.confidence;
            // d) learn the alias (team_id, alias, company_id) — table has no source/confidence cols
            const { error: aliasInsErr } = await supabase
              .from("company_aliases").upsert({ team_id: PIER_TEAM_ID, alias: companyName, company_id: validPick.id }, { onConflict: "team_id,alias", ignoreDuplicates: true });
            if (aliasInsErr) console.error(JSON.stringify({ event: "alias_upsert_failed", message: aliasInsErr.message }));
          } else {
            matchSource = "unmatched"; confidence = ai.confidence ?? 0;
          }
          console.log(JSON.stringify({ event: "ai_match_result", input: companyName, matched: ai.matched, confidence: ai.confidence, source: matchSource, reasoning: ai.reasoning?.slice(0, 200) }));
        }
      }
    }

    // ---------- 3. Insert new contact (retry on contact_id collision) ----------
    const connectionStatus = connectionDegree === "1st degree" ? "Already connected" : "Not connected";
    const baseRow = {
      team_id: PIER_TEAM_ID,
      company_ref: companyRef,          // NOT NULL; '' when unmatched (approved)
      company_id: companyId,            // may be null
      first_name: firstName,
      last_name: lastName,
      job_title: headline,              // from headline
      location,
      linkedin_url: storedLinkedinUrl,  // prefer public /in/ URL (migration 031)
      linkedin_slug: slug,              // canonical slug; null if only /sales/lead/ available
      source_list: listName || null,
      sn_lists: listName ? [listName] : [],
      connection_status: connectionStatus,
      outreach_status: "Not started",
      // date_added / created_at / updated_at use their column defaults
    };

    // deno-lint-ignore no-explicit-any
    let inserted: any = null;
    let bizId = "";
    for (let attempt = 0; attempt < 5; attempt++) {
      bizId = await nextContactId();
      const { data, error } = await supabase.from("contacts").insert({ ...baseRow, contact_id: bizId }).select("id").single();
      if (!error) { inserted = data; break; }
      const collide = error.code === "23505" && `${error.message} ${error.details ?? ""}`.includes("contact_id");
      if (collide) { console.warn(JSON.stringify({ event: "contact_id_collision_retry", bizId, attempt })); continue; }
      throw error;
    }
    if (!inserted) throw new Error("contact_id_generation_exhausted");

    console.log(JSON.stringify({ event: "created", contact_id: inserted.id, biz_id: bizId, company_id: companyId, source: matchSource, confidence, slug }));
    return json(200, {
      status: "created",
      contact_id: inserted.id,
      company_id: companyId,
      company_match_source: matchSource,
      company_confidence: confidence,
      linkedin_slug: slug,
      action: "inserted",
    });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
