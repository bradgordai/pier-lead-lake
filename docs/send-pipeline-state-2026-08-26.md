# Send pipeline — state at pre-handover, 2026-08-26

## Verified working end to end

```
Lovable "Send now"
  -> send-approved-draft (EF v2, TEST_MODE=true forces recipient to Brad)
  -> PhantomBuster launch, row = Scheduled + phantom_run_id
  -> phantom notifications.webhook -> Make "Pier Send Callback" (9714524)
  -> send-approved-callback (EF v6)
  -> row reaches its true terminal state + audit_log row
```

Three outcomes, all driven by `resultObject`, **not** `exitCode`:

| Outcome | Row | audit action |
|---|---|---|
| exit 0 + non-empty results | `Sent` / `sent` / `sent_at_actual` | `send_completed` |
| exit 0 + null/empty results | `Cancelled` + `phantom_skipped_duplicate_or_empty`, **`draft_status` stays `approved`** | `send_skipped` |
| exit != 0 | `Cancelled` + `send_error` | `send_failed` |

## The thing that would have caused silent damage

PhantomBuster **exits 0 when it skips**. Container 3731377894543956 finished in 4s,
`exitCode: 0`, `endType: "finished"`, log line *"Spreadsheet is empty OR everyone is
processed"*, `resultObject: null` — it refused to re-message a profile it had already
messaged. A real send (1793456300808120) took 114s and returned a populated array.

Any callback keyed on `exitCode` marks that row **Sent** for a message that never left.
Success therefore requires a non-empty `resultObject` array.

This is not a test artefact: the phantom will skip **any** recipient it has messaged
recently, so re-engagement sends to existing contacts hit this path in normal use.

## Three defects found and fixed in the Make scenario (9714524)

It was `isActive: false` and `isinvalid: true`, so nothing ever reached Supabase.

1. **`exitCode` was absent from the request body.** The callback would have read
   `Number(undefined)` = NaN and marked **every** callback, including genuine sends, as
   failed. Now sent as `{{ifempty(2.exitCode; "-1")}}` — an absent value defaults to -1,
   which fails safe rather than falsely succeeding.
2. **`resultObject` was interpolated unquoted.** Fine for a JSON array literal, but on the
   skip path PhantomBuster sends null/empty, which rendered as nothing and produced
   malformed JSON. Now `{{ifempty(2.resultObject; "null")}}`.
3. **Scenario was never switched on.** Activated.

## Verified

`TEST-BRAD-3` (container 5615108576686287) was skipped by the phantom and correctly landed
as `send_status='Cancelled'`, `send_error='phantom_skipped_duplicate_or_empty'`,
`draft_status='approved'`, `sent_at_actual=null`, with a `send_skipped` audit row.

Two audit rows appeared 14s apart for that container: Make had **queued** the real
PhantomBuster webhook while the scenario was inactive and replayed it on activation,
alongside a manual replay. So the full PB -> Make -> Supabase chain is confirmed, not just
the Make leg.

**Minor, unfixed:** repeat callbacks for the same container write duplicate audit rows. The
row's terminal state is idempotent, so this is cosmetic. Guard on
`phantom_run_id` + existing terminal state if it becomes noisy.

## Still open

- `send-approved-callback` also accepts `?auth=<secret>` now, for a phantom pointed straight
  at Supabase (PhantomBuster's webhook field is a bare URL and cannot carry a Bearer).
- Every send runs a **Dropcontact email lookup** (`emailChooser: "phantombuster"`) — a
  per-send third-party cost and personal-data lookup on each recipient. Decide before this
  runs against real prospects.
- `TEST_MODE=true` is still set on `send-approved-draft`. **Every send goes to Brad, not the
  real contact, until that env var is set to `"false"`.**
