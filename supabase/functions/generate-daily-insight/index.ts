// generate-daily-insight
// Task 9 (UX sweep): "Yesterday's Work" — gather the previous day's CRM activity
// and have claude-sonnet-5 write a 250-350 word narrative as structured JSON,
// upserted into daily_insights (one row per team per day).
//
// Auth: shared-secret Bearer (MAKE_SHARED_SECRET), verify_jwt=false.
// Body (all optional): { "date": "YYYY-MM-DD", "force": true }
//   - date: override the day to summarise (default = yesterday, Europe/London)
//   - force: regenerate even if a row already exists for that date

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SHARED_SECRET = Deno.env.get("MAKE_SHARED_SECRET")!;
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const PIER_TEAM_ID = "ef73c15e-4d6f-4159-bcfa-cc76b5ae4972";
const MODEL = "claude-sonnet-5";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

function londonDateMinus(days: number): string {
  const todayLondon = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/London" }).format(new Date());
  const d = new Date(`${todayLondon}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}
const tally = (rows: any[], key: (r: any) => string) => {
  const m: Record<string, number> = {};
  for (const r of rows) { const k = key(r); if (!k) continue; m[k] = (m[k] ?? 0) + 1; }
  return m;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (req.headers.get("authorization") !== `Bearer ${SHARED_SECRET}`) return json(401, { error: "unauthorized" });
  if (!ANTHROPIC_KEY) return json(500, { error: "ANTHROPIC_API_KEY not configured" });

  let body: any = {};
  try { body = await req.json(); } catch { /* empty ok */ }
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

  const dateStr: string = /^\d{4}-\d{2}-\d{2}$/.test(body.date ?? "") ? body.date : londonDateMinus(1);
  const nextStr = (() => { const d = new Date(`${dateStr}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + 1); return d.toISOString().slice(0, 10); })();

  // idempotency: skip if a row exists for this date and not forced
  if (!body.force) {
    const { data: existing } = await supabase.from("daily_insights")
      .select("id, generated_at, content").eq("team_id", PIER_TEAM_ID).eq("insight_date", dateStr).maybeSingle();
    if (existing) return json(200, { status: "exists", insight_date: dateStr, generated_at: existing.generated_at });
  }

  // ---- gather yesterday's activity ----
  const [{ data: outreach }, { data: audit }, { data: pending }, { data: convos }] = await Promise.all([
    supabase.from("outreach_log")
      .select("touch_type, send_status, draft_status, channel, agent_produced, reply_classification, outcome, contact_id")
      .eq("team_id", PIER_TEAM_ID).gte("touch_date", dateStr).lt("touch_date", nextStr),
    supabase.from("audit_log")
      .select("entity_type, action").eq("team_id", PIER_TEAM_ID).gte("created_at", dateStr).lt("created_at", nextStr),
    supabase.from("outreach_log")
      .select("id, contact_id", { count: "exact" })
      .eq("team_id", PIER_TEAM_ID).eq("draft_status", "pending_review").eq("agent_produced", true),
    supabase.from("contacts")
      .select("first_name, last_name, outreach_status, priority")
      .eq("team_id", PIER_TEAM_ID).eq("outreach_status", "In conversation").limit(25),
  ]);

  const orows = outreach ?? [];
  const replies = orows.filter((r) => r.touch_type === "Reply");

  // FIX 6a: the briefing used to report bare counts ("2 messages sent"), which reads as
  // unexplained activity - Oli cannot tell WHO was touched or jump to them. Resolve the
  // contacts behind yesterday's touches so the model can name them and the UI can link.
  const touchedIds = Array.from(new Set(orows.map((r) => r.contact_id).filter(Boolean))) as string[];
  // deno-lint-ignore no-explicit-any
  let peopleById = new Map<string, any>();
  if (touchedIds.length) {
    const { data: people } = await supabase.from("contacts")
      .select("id, contact_id, first_name, last_name")
      .eq("team_id", PIER_TEAM_ID).in("id", touchedIds);
    peopleById = new Map(((people ?? []) as Array<{ id: string }>).map((p) => [p.id, p]));
  }
  const activity_by_person = touchedIds.map((id) => {
    const p = peopleById.get(id);
    const mine = orows.filter((r) => r.contact_id === id);
    return {
      contact_id: id,
      contact_ref: p?.contact_id ?? null,
      name: p ? `${p.first_name ?? ""} ${p.last_name ?? ""}`.trim() : "(unknown contact)",
      touches: mine.map((r) => ({ touch_type: r.touch_type, channel: r.channel, send_status: r.send_status })),
    };
  });
  const facts = {
    date: dateStr,
    outreach_activity: {
      total_touches_logged: orows.length,
      sent: orows.filter((r) => r.send_status === "Sent").length,
      by_touch_type: tally(orows, (r) => r.touch_type),
      by_channel: tally(orows, (r) => r.channel),
      agent_drafts_created: orows.filter((r) => r.agent_produced && r.draft_status === "pending_review").length,
    },
    replies_and_conversations: {
      replies_received: replies.length,
      by_sentiment: tally(replies, (r) => r.reply_classification),
      by_outcome: tally(replies, (r) => r.outcome),
      active_conversations_now: (convos ?? []).length,
    },
    contact_changes: {
      audit_events: (audit ?? []).length,
      by_entity: tally(audit ?? [], (r) => r.entity_type),
      by_action: tally(audit ?? [], (r) => r.action),
    },
    drafts_waiting: { pending_review_now: (pending as any) ? (pending as any).length : 0 },
    // Who was actually touched. Every name the briefing mentions must come from here.
    activity_by_person,
  };
  // count is on the response object, not the data array — re-read via count query result
  const { count: pendingCount } = await supabase.from("outreach_log")
    .select("id", { count: "exact", head: true })
    .eq("team_id", PIER_TEAM_ID).eq("draft_status", "pending_review").eq("agent_produced", true);
  facts.drafts_waiting.pending_review_now = pendingCount ?? 0;

  // ---- Sonnet ----
  const system = `You are the assistant for Oli, who runs B2B outreach for Pier (embedded gadget insurance) in a bespoke CRM. Write a crisp "Yesterday's Work" briefing from the activity facts. British English, plain and specific, no hype, no emoji. If a metric is zero, say so briefly rather than inventing activity.

NAME PEOPLE. Never write a bare count like "2 messages sent" - Oli cannot act on a number.
Whenever activity involves specific contacts, name them from activity_by_person, e.g.
"2 connection requests recorded, Marco Stiemert and Hermann-Wilhelm Wantia". If more than
four people are involved, name the first three and add "and N others". Use only names that
appear in activity_by_person; never invent one.

IMPORTANT CONTEXT ABOUT CONNECTION REQUESTS: touches with touch_type "Connection request"
include historical CRs being backfilled into the funnel, not only new sends made yesterday.
Do not describe them as if Oli sent them yesterday. Say they were "recorded" or "logged"
rather than "sent", and if CRs are the bulk of the activity, note plainly that these are
backfilled historical records.

Return ONLY valid minified JSON (no markdown), exactly this shape:
{"date":"YYYY-MM-DD","headline":"<=90 chars, the single most important thing about yesterday","sections":{"outreach_activity":"1-2 sentences","replies_and_conversations":"1-2 sentences","contact_changes":"1-2 sentences","drafts_waiting":"1-2 sentences","priority_signals":"2-3 sentences on what deserves Oli's attention today"},"priority_flags":["short actionable flag", "..."],"queue_recommendations":["short next-step recommendation", "..."],"people":[{"id":"<contact_id uuid from activity_by_person>","name":"<their name>"}]}
"people" must list every contact you named anywhere in the briefing, with the exact uuid from
activity_by_person, so the UI can turn each mention into a link. Empty array if you named none.
Total prose across all sections 250-350 words. priority_flags and queue_recommendations: 0-4 items each, terse and specific. Base everything strictly on the facts provided.`;

  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: MODEL, max_tokens: 1200, thinking: { type: "disabled" },
      system, messages: [{ role: "user", content: `Activity facts for ${dateStr}:\n${JSON.stringify(facts, null, 2)}` }],
    }),
  });
  if (!resp.ok) return json(502, { error: "anthropic_failed", status: resp.status, detail: (await resp.text()).slice(0, 400) });
  const ai = await resp.json();
  let raw = (ai.content?.find((b: any) => b.type === "text")?.text ?? "").trim();
  raw = raw.replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/```\s*$/i, "").trim();
  let content: any;
  try { content = JSON.parse(raw); } catch { return json(502, { error: "parse_failed", raw: raw.slice(0, 500) }); }
  content.date = dateStr;

  const { error: upErr } = await supabase.from("daily_insights").upsert({
    team_id: PIER_TEAM_ID, insight_date: dateStr, headline: content.headline ?? null,
    content, model: MODEL, generated_at: new Date().toISOString(),
  }, { onConflict: "team_id,insight_date" });
  if (upErr) return json(500, { error: "upsert_failed", detail: upErr.message });

  console.log(JSON.stringify({ event: "daily_insight_generated", insight_date: dateStr, headline: content.headline }));
  return json(200, { status: "generated", insight_date: dateStr, headline: content.headline, facts });
});
