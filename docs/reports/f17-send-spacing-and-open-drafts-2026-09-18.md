# F17 (added 18 Sep): send spacing, queue, one open draft — 2026-09-18

## Send spacing and queue (migration 108 applied; function deploy status at the foot)
- `fn_claim_send_slot` gives each PhantomBuster agent (DM, InMail, CR separately) one slot every 180-300 s,
  randomised, serialised by an advisory lock so two simultaneous clicks cannot both see "free".
- send-approved-draft claims a slot AFTER every gate and capacity check and immediately BEFORE launch.
  Early -> the row goes to `send_queue`, send_status `Ready`, and the response is
  `{ status: "queued", send_after, queue_position }`. It waits; it does not fail.
- `{ drain: true }` launches the oldest due row. Every gate re-runs at that moment, so a contact who opts
  out while queued is refused at launch.
- Tested in a rolled-back transaction: three claims on one agent -> now, +298 s, +491 s. Queue left empty.
- 22 approved drafts through the bulk bar now take roughly 90 minutes instead of 22 simultaneous launches.
- **Drainer cron: written, NOT applied** (supabase/migrations/109). It is a job that launches real sends
  unattended, so it is Brad's switch. Until it is applied, a queued send stays queued. It reads its bearer at
  runtime from the chase-engine job; no secret is in the file.
- Lovable: treat `status: "queued"` as success and show "Queued, sends at HH:MM". Today it will likely show
  a generic message.

## One open draft per contact per touch type (migration 108)
- Cause confirmed: the drafter's dedup looked only at `pending_review`, so an approved-but-unsent draft was
  invisible and the engine re-drafted every morning of the send outage. Drafter now treats approved+unsent
  as open.
- Backstop trigger: a newer open draft of the same touch type supersedes the older ones, logged in
  `touch_merge_log` with the full before-row.
- Cleanup, logged and reversible: Peretti P595 had THREE open Chaser 3 (approved 15 Sep, approved 17 Sep,
  pending 18 Sep), not two. Kept the 17 Sep approved one. Dupuis P036 had two Chaser 1; kept the approved
  9 Sep one. Rule: newest APPROVED wins, because it carries a human review. Open duplicates left: 0.
  Approved-unsent is now 21.

## Deploy status
send-approved-draft v16 -> **v17**, generate-draft-from-context v40 -> **v41**. Pre-deploy: live source was byte-identical to the repo. Post-deploy: every file byte-identical to local. `node --check` passed. Neither function was called. Spacing and the queue are LIVE; the drainer cron (109) is still Brad's to apply.
