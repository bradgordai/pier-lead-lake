// Shared helper: callAnthropicWithSentinel
//
// Single choke point for every Anthropic call made from a Pier Edge Function. Wraps the
// raw fetch so that each call is (a) guarded against the known cost-blowout patterns and
// (b) logged to api_call_log with a GBP cost estimate.
//
// Deployment note: Supabase deploys each Edge Function as an independent bundle, so this
// file is shipped as a sibling inside every function that uses it and imported as
// "./_shared/anthropic-sentinel.ts". This file in supabase/functions/_shared/ is the
// canonical copy - edit here, then redeploy each consumer.
//
// ---------------------------------------------------------------------------
// PRICING - verified against platform.claude.com models overview on 2026-08-26.
//
// The cost-sentinel spec hardcoded Sonnet at $3 in / $15 out.
// That is NOT the price of the model Pier actually runs. Current published rates:
//
//   claude-fable-5              $10 / MTok in    $50 / MTok out
//   claude-opus-5               $5  / MTok in    $25 / MTok out
//   claude-sonnet-5             $2  / MTok in    $10 / MTok out   <-- every Pier function
//   claude-haiku-4-5-20251001   $1  / MTok in    $5  / MTok out
//
// Using the spec's numbers would have overstated every Sonnet call by 50% on input and
// 50% on output, so the £10/day alert would have fired roughly a third early, every day.
//
// Cache reads are 10% of the base input price (documented). The cache-WRITE multiplier is
// not given on the overview page; 1.25x input is the long-standing 5-minute-TTL rate and
// is used here as an approximation. No Pier function currently sends cache_control, so
// this path is inert today - confirm the multiplier before relying on it.
// ---------------------------------------------------------------------------

// USD per million tokens.
const PRICES: Record<string, { in: number; out: number }> = {
  "claude-fable-5": { in: 10, out: 50 },
  "claude-opus-5": { in: 5, out: 25 },
  "claude-sonnet-5": { in: 2, out: 10 },
  "claude-haiku-4-5-20251001": { in: 1, out: 5 },
  "claude-haiku-4-5": { in: 1, out: 5 },
};
// Unknown models are costed at the most expensive tier so a surprise model shows up as a
// spike rather than hiding under a cheap default.
const WORST_CASE = { in: 10, out: 50 };

const USD_TO_GBP = 0.79; // update alongside the rates above

// ---------------------------------------------------------------------------
// FAIL-CLOSED DAILY BUDGET (security audit finding F-10).
//
// The first cut of this helper logged cost but never blocked, so it failed OPEN: a runaway
// loop or a leaked shared secret could spend without limit. The budget is now checked
// BEFORE the Anthropic call and throws when today's spend is already at the ceiling.
//
// Default £10/day, overridable with ANTHROPIC_DAILY_BUDGET_GBP. Set it to 0 to disable the
// gate entirely (not recommended).
//
// One deliberate exception: if the budget QUERY itself errors, we log loudly and allow the
// call. This is a cost guard, not a security control, and a transient DB blip should not
// take the whole outreach pipeline down. A sustained failure shows up as repeated
// `sentinel_budget_check_failed` lines.
// ---------------------------------------------------------------------------
const DAILY_BUDGET_GBP = Number(Deno.env.get("ANTHROPIC_DAILY_BUDGET_GBP") ?? "10");

export class BudgetExceededError extends Error {
  constructor(public spentGbp: number, public limitGbp: number) {
    super(`anthropic_daily_budget_exceeded: spent GBP ${spentGbp.toFixed(2)} of ${limitGbp.toFixed(2)} today`);
    this.name = "BudgetExceededError";
  }
}

/** Today's total spend in GBP from api_call_log. Throws only if the caller wants it to. */
// deno-lint-ignore no-explicit-any
export async function todaySpendGbp(supabase: any): Promise<number> {
  const today = new Date().toISOString().slice(0, 10);
  const { data, error } = await supabase
    .from("api_call_log")
    .select("estimated_cost_gbp")
    .gte("created_at", `${today}T00:00:00Z`);
  if (error) throw error;
  let total = 0;
  for (const r of (data ?? []) as Array<{ estimated_cost_gbp: number | string }>) {
    total += Number(r.estimated_cost_gbp ?? 0);
  }
  return total;
}

export function estimateCostGbp(
  model: string,
  inputTokens: number,
  outputTokens: number,
  cacheReadTokens = 0,
  cacheCreationTokens = 0,
): number {
  const p = PRICES[model] ?? WORST_CASE;
  const usd =
    (inputTokens / 1_000_000) * p.in +
    (outputTokens / 1_000_000) * p.out +
    (cacheReadTokens / 1_000_000) * p.in * 0.10 +
    (cacheCreationTokens / 1_000_000) * p.in * 1.25;
  return Number((usd * USD_TO_GBP).toFixed(6));
}

export type SentinelResult = {
  content: string;
  usage: { input_tokens: number; output_tokens: number; cache_creation_tokens: number; cache_read_tokens: number };
  estimated_cost_gbp: number;
  succeeded: boolean;
  error_message?: string;
};

export async function callAnthropicWithSentinel(params: {
  model: string;
  system?: string;
  messages: Array<{ role: string; content: string }>;
  max_tokens: number;
  thinking?: { type: "disabled" | "enabled" };
  temperature?: number;
  function_name: string;
  team_id: string;
  request_context?: Record<string, unknown>;
  // deno-lint-ignore no-explicit-any
  supabase: any;
  anthropic_api_key: string;
}): Promise<SentinelResult> {
  const {
    model, system, messages, max_tokens, function_name, team_id,
    request_context, supabase, anthropic_api_key,
  } = params;
  let { thinking, temperature } = params;

  // --- Guards against the known blow-out patterns, applied BEFORE the call ---

  // claude-sonnet-5 runs extended thinking by default, which silently eats the whole
  // max_tokens budget before a short message is ever emitted. Every Pier caller wants
  // short output, so thinking is forced off unless a caller explicitly enabled it.
  if (model === "claude-sonnet-5" && (!thinking || thinking.type !== "disabled")) {
    console.warn(JSON.stringify({ event: "sentinel_forced_thinking_disabled", function_name, model }));
    thinking = { type: "disabled" };
  }
  // claude-sonnet-5 rejects `temperature` outright (400), so strip rather than fail.
  if (temperature !== undefined && model === "claude-sonnet-5") {
    console.warn(JSON.stringify({ event: "sentinel_stripped_temperature", function_name, model }));
    temperature = undefined;
  }
  if (max_tokens > 2000) {
    console.warn(JSON.stringify({ event: "sentinel_high_max_tokens", function_name, max_tokens }));
  }

  // --- Fail-closed budget gate, BEFORE any spend ---
  if (DAILY_BUDGET_GBP > 0) {
    try {
      const spent = await todaySpendGbp(supabase);
      if (spent >= DAILY_BUDGET_GBP) {
        console.error(JSON.stringify({
          event: "sentinel_budget_exceeded", function_name, model,
          spent_gbp: Number(spent.toFixed(4)), limit_gbp: DAILY_BUDGET_GBP,
        }));
        // Record the refusal so the digest shows blocked attempts, not silence.
        try {
          await supabase.from("api_call_log").insert({
            team_id, function_name, model,
            input_tokens: 0, output_tokens: 0, cache_creation_tokens: 0, cache_read_tokens: 0,
            thinking_tokens: 0, estimated_cost_gbp: 0,
            request_context: { ...(request_context ?? {}), blocked_by: "daily_budget" },
            succeeded: false,
            error_message: `blocked: daily budget GBP ${DAILY_BUDGET_GBP} reached (spent ${spent.toFixed(4)})`,
          });
        } catch { /* logging must never mask the block */ }
        throw new BudgetExceededError(spent, DAILY_BUDGET_GBP);
      }
    } catch (e) {
      if (e instanceof BudgetExceededError) throw e;
      // Budget check itself failed - allow the call, but make it loud.
      console.error(JSON.stringify({
        event: "sentinel_budget_check_failed", function_name,
        message: (e as Error).message ?? String(e),
      }));
    }
  }

  // deno-lint-ignore no-explicit-any
  const payload: Record<string, any> = { model, max_tokens, messages };
  if (system) payload.system = system;
  if (thinking) payload.thinking = thinking;
  if (temperature !== undefined) payload.temperature = temperature;

  let content = "";
  let inTok = 0, outTok = 0, cacheCreate = 0, cacheRead = 0;
  let succeeded = true;
  let errorMessage: string | undefined;

  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": anthropic_api_key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await resp.json();
    if (!resp.ok) throw new Error(`anthropic_http_${resp.status}: ${JSON.stringify(data).slice(0, 300)}`);

    content = ((data?.content ?? []) as Array<{ type: string; text?: string }>)
      .filter((b) => b.type === "text").map((b) => b.text ?? "").join("").trim();

    const u = data?.usage ?? {};
    inTok = Number(u.input_tokens ?? 0);
    outTok = Number(u.output_tokens ?? 0);
    cacheCreate = Number(u.cache_creation_input_tokens ?? 0);
    cacheRead = Number(u.cache_read_input_tokens ?? 0);
  } catch (e) {
    succeeded = false;
    errorMessage = (e as Error).message ?? String(e);
  }

  const cost = estimateCostGbp(model, inTok, outTok, cacheRead, cacheCreate);

  // Log the call whether or not it worked - a failing function that retries hard is
  // exactly the thing this table exists to make visible. Never let logging break the
  // caller, and never log the API key or the message bodies.
  try {
    await supabase.from("api_call_log").insert({
      team_id,
      function_name,
      model,
      input_tokens: inTok,
      output_tokens: outTok,
      cache_creation_tokens: cacheCreate,
      cache_read_tokens: cacheRead,
      thinking_tokens: 0, // not itemised separately by the API; counted inside output_tokens
      estimated_cost_gbp: cost,
      request_context: request_context ?? null,
      succeeded,
      error_message: errorMessage ?? null,
    });
  } catch (logErr) {
    console.error(JSON.stringify({ event: "sentinel_log_failed", function_name, message: (logErr as Error).message }));
  }

  console.log(JSON.stringify({
    event: "sentinel_call", function_name, model, succeeded,
    input_tokens: inTok, output_tokens: outTok, estimated_cost_gbp: cost,
  }));

  if (!succeeded) throw new Error(errorMessage ?? "anthropic_call_failed");

  return {
    content,
    usage: { input_tokens: inTok, output_tokens: outTok, cache_creation_tokens: cacheCreate, cache_read_tokens: cacheRead },
    estimated_cost_gbp: cost,
    succeeded,
    error_message: errorMessage,
  };
}
