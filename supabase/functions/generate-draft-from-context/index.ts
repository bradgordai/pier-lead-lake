// Edge Function: generate-draft-from-context
//
// When a contact's connection_status flips to 'Accepted', auto-generate the first
// LinkedIn DM draft using the Pier EA voice contracts (pier_ea_documents) + the
// contact/company/thread context, run a pre-lint pass, and store it as a
// pending_review draft in outreach_log.
//
// Security / conventions (mirrors the other Make webhooks):
//   - service_role only at client boot; every query scoped to PIER_TEAM_ID.
//   - Shared-secret Bearer auth; deployed with verify_jwt=false.
//   - Anthropic failure -> insert a placeholder draft with lint_score=0 (never crash).
//   - EA-docs load failure -> fall back to a basic voice system prompt + log a warning.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const MAKE_SHARED_SECRET = Deno.env.get("MAKE_SHARED_SECRET") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const ANTHROPIC_MODEL = "claude-sonnet-5";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

// EA docs concatenated into the system prompt, in this exact order.
const EA_ORDER = ["PIER_Rules", "LinkedIn_Message_Architect", "Lead_and_ICP_Brief", "OUTREACH_QUICK_REFERENCE", "PIER_Response_Bank"];
const BASIC_VOICE_FALLBACK =
  "You are Oli (Oliver Mueller) at Pier Insurance, writing a first LinkedIn DM to a contact who just accepted your connection request. Voice: direct, warm, specific, peer-to-peer. No corporate jargon, no em-dashes/en-dashes, no 'circle back'/'touch base'/'unlock'/'excited to connect'/'best-in-class'/'leveraging'. Keep it short (ideally under 600 characters). Reference something concrete about their company. End with a light, low-friction question. Sign off 'Oli'. Output ONLY the message body.";

// Voice-contract banned words/phrases (case-insensitive; em/en dash by codepoint).
const BANNED = ["—", "–", "circle back", "touch base", "synergise", "synergize", "unlock", "hope this finds", "just following up", "reach out to explore", "quick one", "leveraging", "excited to connect", "we're uniquely positioned", "best-in-class"];

function countOccurrences(haystackLower: string, needleLower: string): number {
  if (!needleLower) return 0;
  let n = 0, i = 0;
  while ((i = haystackLower.indexOf(needleLower, i)) !== -1) { n++; i += needleLower.length; }
  return n;
}

function preLint(message: string): { score: number; pass: boolean; violations: unknown[] } {
  const lower = message.toLowerCase();
  const violations: unknown[] = [];
  let bannedHits = 0;
  for (const term of BANNED) {
    const c = countOccurrences(lower, term.toLowerCase());
    if (c > 0) {
      bannedHits += c;
      const label = term === "—" ? "em-dash" : term === "–" ? "en-dash" : term;
      violations.push({ type: "banned_word", term: label, count: c });
    }
  }
  const len = message.length;
  let score = 100 - 5 * bannedHits;
  if (len > 800) { score -= 10; violations.push({ type: "length", chars: len, note: "over LinkedIn DM soft cap (800)" }); }
  const hardFail = len > 2000;
  if (hardFail) violations.push({ type: "length_hard", chars: len, note: "over hard cap (2000)" });
  score = Math.max(0, score);
  return { score, pass: score >= 70 && !hardFail, violations };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!MAKE_SHARED_SECRET || !PIER_TEAM_ID) return json(500, { error: "server_misconfigured" });
  const authz = req.headers.get("authorization") ?? "";
  if ((authz.startsWith("Bearer ") ? authz.slice(7) : "") !== MAKE_SHARED_SECRET) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const contactId = String(body?.contact_id ?? "").trim();
  const triggerReason = String(body?.trigger_reason ?? "cr_accepted").trim();
  if (!contactId) return json(400, { error: "missing_required_fields", detail: "contact_id required" });

  try {
    // ---------- context ----------
    const { data: contact, error: cErr } = await supabase
      .from("contacts")
      .select("id, first_name, last_name, job_title, seniority, function, location, linkedin_url, company_id, connection_status")
      .eq("team_id", PIER_TEAM_ID).eq("id", contactId).maybeSingle();
    if (cErr) throw cErr;
    if (!contact) return json(404, { error: "contact_not_found" });

    // deno-lint-ignore no-explicit-any
    let company: any = null;
    if (contact.company_id) {
      const { data: co } = await supabase
        .from("companies")
        .select("company_name, country, category, priority, industry, product_line, insurance_offered, insurance_provider, coverage_summary, usp_notes, additional_notes, estimated_revenue_gbp, employees, monthly_visits")
        .eq("id", contact.company_id).maybeSingle();
      company = co ?? null;
    }

    const { data: prevRows } = await supabase
      .from("outreach_log")
      .select("touch_date, channel, touch_type, message_body, subject_line, reply_content")
      .eq("team_id", PIER_TEAM_ID).eq("contact_id", contactId)
      .order("touch_date", { ascending: true }).limit(50);
    const prev = prevRows ?? [];

    // ---------- EA voice docs -> system prompt ----------
    let systemPrompt = "";
    try {
      const { data: docs, error: dErr } = await supabase
        .from("pier_ea_documents").select("name, content")
        .eq("team_id", PIER_TEAM_ID).eq("is_active", true).in("name", EA_ORDER);
      if (dErr) throw dErr;
      const byName = new Map(((docs ?? []) as Array<{ name: string; content: string }>).map((d) => [d.name, d.content]));
      const parts: string[] = [];
      for (const n of EA_ORDER) { const c = byName.get(n); if (c) parts.push(`===== ${n} =====\n${c}`); }
      if (parts.length === 0) { console.warn(JSON.stringify({ event: "ea_docs_empty" })); systemPrompt = BASIC_VOICE_FALLBACK; }
      else systemPrompt = parts.join("\n\n");
    } catch (e) {
      console.warn(JSON.stringify({ event: "ea_docs_load_failed", message: (e as Error).message }));
      systemPrompt = BASIC_VOICE_FALLBACK;
    }

    // ---------- path / frame / arc ----------
    const path = "A"; // cr_accepted -> first post-connection message
    const arc = "A";
    const insuranceActive = !!company && ((String(company.insurance_offered ?? "").toLowerCase() === "yes") || !!(company.insurance_provider && String(company.insurance_provider).trim()));
    const isCsuite = /c-?suite|chief|founder|ceo|cfo|coo|cto/i.test(String(contact.seniority ?? ""));
    const frame = insuranceActive ? "Discovery" : (isCsuite ? "Ally" : "Peer");

    // ---------- thread history ----------
    const threadText = prev.length === 0
      ? "(none - this is the first message)"
      : prev.map((r) => {
          const lines = [`- ${r.touch_date ?? ""} [${r.channel ?? ""}/${r.touch_type ?? ""}]`];
          if (r.subject_line) lines.push(`  Subject: ${r.subject_line}`);
          if (r.message_body) lines.push(`  Oli: ${String(r.message_body).slice(0, 500)}`);
          if (r.reply_content) lines.push(`  Reply: ${String(r.reply_content).slice(0, 500)}`);
          return lines.join("\n");
        }).join("\n");

    const co = company ?? {};
    const userPrompt = `DRAFT REQUEST

Trigger: ${triggerReason}
Message type: LinkedIn DM (first message post-CR-accept)
Channel: LinkedIn DM
Path: ${path}
Frame: ${frame}
Arc: ${arc}

CONTACT
Name: ${contact.first_name ?? ""} ${contact.last_name ?? ""}
Title: ${contact.job_title ?? ""}
Seniority: ${contact.seniority ?? ""}
Function: ${contact.function ?? ""}
Location: ${contact.location ?? ""}
LinkedIn URL: ${contact.linkedin_url ?? ""}

COMPANY
Name: ${co.company_name ?? ""}
Country: ${co.country ?? ""}
Category: ${Array.isArray(co.category) ? co.category.join(", ") : (co.category ?? "")}
Priority: ${co.priority ?? ""}
Industry: ${co.industry ?? ""}
Product line: ${co.product_line ?? ""}
Insurance offered: ${co.insurance_offered ?? ""}
Insurance provider: ${co.insurance_provider ?? ""}
Coverage summary: ${co.coverage_summary ?? ""}
USP notes: ${co.usp_notes ?? ""}
Additional notes: ${co.additional_notes ?? ""}
Estimated revenue: ${co.estimated_revenue_gbp ?? ""}
Employees: ${co.employees ?? ""}
Monthly visits: ${co.monthly_visits ?? ""}

PREVIOUS OUTREACH (if any)
${threadText}

TASK
Write a first LinkedIn DM opener from Oliver Mueller (Oli) at Pier Insurance to this contact who just accepted the CR. Apply all rules in the loaded PIER_Rules, LinkedIn_Message_Architect, Lead_and_ICP_Brief, OUTREACH_QUICK_REFERENCE, and PIER_Response_Bank documents.

Sign off: Oli

Output ONLY the message body. No preamble, no meta-commentary, no subject line.`;

    // ---------- generate ----------
    let messageBody = "";
    let generationFailed = false;
    let genError = "";
    try {
      if (!ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY missing");
      const resp = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        // NOTE: claude-sonnet-5 rejects `temperature` (deprecated) and runs extended thinking by
        // default — which consumes the whole max_tokens budget before emitting a message. A short
        // DM needs no reasoning, so thinking is disabled and max_tokens kept modest.
        body: JSON.stringify({ model: ANTHROPIC_MODEL, max_tokens: 1024, thinking: { type: "disabled" }, system: systemPrompt, messages: [{ role: "user", content: userPrompt }] }),
      });
      const data = await resp.json();
      if (!resp.ok) { genError = `http_${resp.status}: ${JSON.stringify(data).slice(0, 400)}`; console.error(JSON.stringify({ event: "anthropic_http_error", status: resp.status, body: JSON.stringify(data).slice(0, 300) })); throw new Error("anthropic_http_" + resp.status); }
      const text = ((data?.content ?? []) as Array<{ type: string; text?: string }>).filter((b) => b.type === "text").map((b) => b.text ?? "").join("").trim();
      messageBody = text.replace(/^```[a-z]*\s*/i, "").replace(/```$/i, "").trim();
      if (!messageBody) throw new Error("empty_generation");
      console.log(JSON.stringify({ event: "anthropic_ok", usage: data?.usage, preview: messageBody.slice(0, 120) }));
    } catch (e) {
      generationFailed = true;
      if (!genError) genError = (e as Error).message ?? String(e);
      console.error(JSON.stringify({ event: "generation_failed", message: genError, system_len: systemPrompt.length }));
      messageBody = "[Draft generation failed, please write manually]";
    }

    // ---------- pre-lint ----------
    const lint = generationFailed
      ? { score: 0, pass: false, violations: [{ type: "generation_error", note: "Anthropic call failed; placeholder inserted" }] as unknown[] }
      : preLint(messageBody);

    // ---------- insert draft ----------
    const today = new Date().toISOString().slice(0, 10);
    const insertRow = {
      team_id: PIER_TEAM_ID,
      touch_id: `agent-${crypto.randomUUID()}`,
      contact_id: contact.id,
      company_id: contact.company_id ?? null,
      channel: "LinkedIn DM",
      touch_type: "Initial message",
      message_body: messageBody,
      subject_line: null,
      draft_status: "pending_review",
      send_status: "Draft",
      agent_produced: true,
      pre_lint_pass: lint.pass,
      voice_contract_violations: lint.violations,
      lint_score: lint.score,
      path,
      recommended_frame: frame,
      recommended_arc: arc,
      touch_date: today,
    };
    const { data: inserted, error: insErr } = await supabase.from("outreach_log").insert(insertRow).select("id").single();
    if (insErr) throw insErr;

    console.log(JSON.stringify({ event: "draft_created", touch_id: inserted.id, contact_id: contact.id, lint_score: lint.score, pass: lint.pass, generation_failed: generationFailed }));
    return json(200, {
      status: generationFailed ? "generation_failed" : "created",
      touch_id: inserted.id,
      message_preview: messageBody.slice(0, 200),
      pre_lint_pass: lint.pass,
      lint_score: lint.score,
      path,
      frame,
      gen_error: genError || undefined,
    });
  } catch (e) {
    console.error(JSON.stringify({ event: "handler_error", message: (e as Error).message ?? String(e) }));
    return json(500, { error: "internal_error", detail: (e as Error).message ?? "unknown" });
  }
});
