# F7: InMail dispatch wired end to end, 2026-09-08

Sanctioned send-path change. Deploy at 09:33 BST, outside every watcher window.

## What changed
- send-approved-draft v12 (commit 8631f86): the `inmail_not_wired` guard is lifted. Channel "LinkedIn inMail"
  launches the Pier Sales Navigator Message Sender phantom (8651232052097344) with `spreadsheetUrl` = the
  contact's Sales Nav URL, falling back to linkedin_url; `message` = the stripped body (frozen into sent_body at
  dispatch as before); `sendInMail=true`; `inMailSubject` = the row's subject_line, fallback "Pier Insurance";
  `numberOfProfilesPerLaunch=1`. The phantom's saved argument (session cookie, user agent) round-trips untouched.
- Guards before any launch: existing status / approval / TEST_MODE checks, plus 150 InMails per month
  (matches MONTHLY_CAP_INMAILS) and ledger balance >= 1. The F1 charge (fn_ledger_inmail_send, -1) fires after a
  successful launch; callback v12 reverses it on skip/fail, unchanged.
- Phantom notifications.webhook set (via the Phantombuster API) to the same Make hook as the DM phantom
  (Pier Send Callback, scenario 9714524). That scenario forwards any agent's payload to send-approved-callback
  with the bearer, so the InMail route closes the loop identically. This was the missing piece: the phantom had
  no webhook, so nothing would have flipped a row to Sent.

## Controlled send (the only dispatch this morning)
Test contact TEST-BRAD-INMAIL (linkedin_url = Brad's profile) + outreach row TEST-BRAD-INMAIL, channel LinkedIn
inMail, approved, body "InMail dispatch test from Pier Lead Lake, please ignore", subject "InMail dispatch test".
| step | evidence |
|---|---|
| dispatch | EF returned status sent, phantom_run_id 5044780842681493, inmail_balance 128, recipient Brad's URL |
| launch | container 5044780842681493, launched 08:34:24Z, exit 0 at 08:35:12Z, log "Sending message to Bradley Gordon", "Subject: InMail dispatch test" |
| result | resultObject one row, status "Message sent", connectionDegree "2nd", isOpenLink true, hasPendingInvitation true |
| callback | Make execution afa6353f577446889629fb145408414b at 08:35:13Z, success; row Sent / draft_status sent, sent_at_actual 08:35:14Z, sent_body intact; audit_log send_completed |
| ledger | manual_adjust 129 -> send -1 = 128 at dispatch; no reversal (send completed) |

Ledger finding: to Oliver's account Brad is a 2nd-degree contact with a pending invitation, not 1st degree, and
his profile is an Open Profile. LinkedIn does not consume a credit for an InMail to an Open Profile, so the real
LinkedIn balance did not move while the ledger charged one. The ledger has no open-profile exemption; the
phantom result carries `isOpenLink`, so a callback-side refund is possible later. Flagged, not built.

## Cleanup
Ledger row for the test deleted (balance back to 129 because the manual_adjust is again the latest event),
outreach row and test contact deleted, both logged to migration_audit run `f7-inmail-wire-2026-09-08`
(phase controlled_send_cleanup, full row snapshots in detail). audit_log keeps its trigger and callback entries
for the deleted ids. Live counts unchanged: InMails sent this month 2, ledger rows 2.

## Refusal path
Dry run generate-draft-from-context for Monica Stavarache (Withdrawn, two InMail chasers already sent),
trigger chaser_1: refused, allowance_exhausted, "LinkedIn inMail chaser allowance used: 2 of 1 sent." Gates
still run before any draft.
