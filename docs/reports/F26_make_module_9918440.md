# Make module spec — scenario 9918440 "pier sent request extractor" (F26 Task 2)

For Brad to wire. I did not edit or run the scenario. Today it has one module, the webhook (hook 4415136, gateway-webhook,
`https://hook.eu2.make.com/akyk4eb9kyc3xy7qtjxo4f4q9ti5dhxi`), zero executions, scenario inactive.

## What arrives
PhantomBuster 7326870632604661 (Sent Request Extractor) posts its standard webhook body ONCE per run:
`{ agentId, agentName, containerId, script, launchDuration, runDuration, exitCode, exitMessage, resultObject }`,
where `resultObject` is the whole pending list as a JSON **string** (184 rows + 1 junk row on 2 Oct).

## Module 2 — HTTP › Make a request (the only module to add)
| Field | Value |
|---|---|
| URL | `https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/ingest-sent-requests` |
| Method | `POST` |
| Header | `Authorization` = `Bearer <INBOUND_WEBHOOK_SECRET>` ← type the inbound secret here yourself; it is the same one the InMail watcher (9850348) uses |
| Header | `Content-Type` = `application/json` |
| Body type | Raw, content type JSON (application/json) |
| Request content | the output of the JSON module below (`{{2.json}}`) |
| Parse response | Yes |
| Timeout | 60 s |

Put **JSON › Create JSON** between the webhook and the HTTP module: one field `resultObject` (type Text), mapped from
`{{1.resultObject}}`. It produces `{"resultObject":"[...]"}` with the escaping done for you. Do not hand-build the body
with string concatenation; the titles contain quotes and emoji. This is still ONE operation per run.

## One call per run. Do NOT iterate.
**If at any point you add an Iterator or a "Parse JSON" that splits the rows into bundles, you MUST put an
Array Aggregator before the HTTP module** (source = the iterator, aggregated field = the whole bundle), and send
`{"rows": {{2.array}}}`. The function also accepts a bare array `[...]`.
Per-record looping is what put the inbox watchers at 15,071 operations. Aggregated (or passed straight through as above)
this scenario costs about 3 operations a run (webhook + Create JSON + HTTP) instead of about 190.
The org is at 19,911 / 20,000 with auto-purchase ON, so a loop here would bill, not pause.

## What the function does with it
`fn_ingest_sent_requests` (migration 167), all in one transaction:
- every row → `cr_extractor_rows` under one `cr_extractor_runs` row; junk `invitation-manager` row dropped;
- matched contact (normalised URL key) → `connection_status = 'Request sent'`, source `sent_request_extractor`,
  evidence = the raw `sentDate` label, `cr_pending_min_age_days`, `cr_pending_label_at`;
  Accepted / Already connected are never downgraded (counted as conflicts);
- live contact still `Request sent` but absent from the list → `Not connected`, source `sent_request_extractor_absent`,
  unless its status or a Sent connection request postdates the extraction;
- **safety:** an empty payload clears nothing; a run that would demote more than 60% of Request sent is refused
  (`absent_sweep = skipped_guard`) — a truncated extractor run cannot wipe the field;
- unknown profile → `unmatched_sent_requests` (Reconciliation tab, Create contact).

## Test before you switch it on
1. Run the scenario once with "Run once", then trigger the phantom by hand (your call — it only reads LinkedIn).
2. Or append `?dry_run=1` to the URL for the first run: the response carries the full summary and nothing persists.
3. Response `200 {"ok":true,"summary":{...}}`. Check `absent_sweep` is `applied` and `rows` ≈ LinkedIn's pending count.

## Schedule
The Task 5 counter returns NULL (dispatch paused) when the newest extractor data is older than 6 hours, so the phantom
must run at least every 6 hours while the CR dispatcher is on — every 4 hours on weekdays is a safe default.
