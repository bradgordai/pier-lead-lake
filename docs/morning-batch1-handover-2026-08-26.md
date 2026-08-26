# Morning Batch 1 — state at hard-stop, 2026-08-26

## Done and verified live

| # | Item | Result |
|---|---|---|
| 1 | Insights BLOCKER | ✅ Lovable `0b63232`, deployed. Every segment row monotonic |
| 2 | Contacts KPI HIGH | ✅ Coverage **259 of 259**, Momentum **+5** |
| 3 | authorize() rollout | ⏳ **4 of 9** functions done |
| 4 | Sentinel + fail-closed budget | ⏳ **2 of 5** functions done; helper itself done |
| 5 | Make bearer headers | ⛔ blocked — needs `INBOUND_WEBHOOK_SECRET` value |
| 6 | Lovable hardcoded secret | ⛔ blocked — needs `INTERNAL_APP_SECRET` value |

**Insights after the fix** — Leads in system now 259 (contacts, was 350 companies);
Germany 51/50/12, UK 38/38/9, Netherlands 13/13/2, France 9/7/3. No stage exceeds the one
above it in any row of any breakdown.

**Contacts after the fix** — Coverage 259 of 259, Momentum +5 ("added last 7 days", label now
matches the rolling window), Warm work 8, Ready to re-engage 2, 1st degree 42 unchanged.

## Functions carrying scoped auth (`authorize`)

✅ `send-approved-draft` (internal) · `send-approved-callback` (inbound) ·
`generate-draft-from-context` (internal) · `upsert-contact-from-sales-nav` (inbound)

⏳ Still on the raw `MAKE_SHARED_SECRET` check — mechanical, 3 lines each:
`update-contact-on-cr-accepted` (inbound) · `capture-and-classify-reply` (inbound) ·
`enrich-contact-metadata` (internal) · `enrich-company-websites` (internal) ·
`generate-daily-insight` (internal)

## Functions routed through the sentinel (cost log + fail-closed budget)

✅ `generate-draft-from-context` · `upsert-contact-from-sales-nav` (aiMatch)

⏳ `capture-and-classify-reply` · `enrich-contact-metadata` · `generate-daily-insight`

## Measured cost — this changes the budget maths

| Call | Input tokens | Cost |
|---|---|---|
| generate-draft-from-context | **58,142** | **£0.0928** |
| upsert aiMatch | 522 | £0.0027 |

Draft generation is **34× more expensive per call** than company matching, entirely because
the five EA docs are re-sent uncached every time. At the £10/day ceiling that is ~107 drafts
per day. Real usage at Oli's targets (15 DMs + 30 CRs/day) is roughly £1.40–4/day, so the
ceiling has headroom — but audit finding **F-13 (prompt-cache the EA prefix)** would remove
~87% of the dominant cost line and is now clearly the highest-ROI optimisation left.

## Blocked on Brad

`INBOUND_WEBHOOK_SECRET` and `INTERNAL_APP_SECRET` are not readable from MCP. Items 5 and 6
cannot proceed without their values. **Do not point Make at `INBOUND_WEBHOOK_SECRET` before
confirming it exists in Supabase** — the Sales Nav Watcher fires 09:00 and 13:00 London and
would 401.

Everything already deployed still accepts the legacy secret, so adding the new secrets is
non-breaking whenever they land.

## Not started

- `/code-review` at the Batch 1 checkpoint — deferred for capacity.
- Batch 2 items 7 (wire Send now button) and 8 (test send).
- `PHANTOMBUSTER_API_KEY` presence in Supabase is still **unconfirmed** — `send-approved-draft`
  returns `server_misconfigured` without it, so that needs checking before any test send.
