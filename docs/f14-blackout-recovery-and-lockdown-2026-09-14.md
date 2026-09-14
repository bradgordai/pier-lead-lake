# F14 (2026-09-14, 22:00-23:40): post-blackout verification, send-effects lockdown, research unblock

Migrations 089-094, one per task, one commit each. Edge functions: capture-and-classify-reply v21,
update-contact-on-cr-accepted v16, upsert-contact-from-sales-nav v22, chase-engine v7. Lovable
commit 7b77a477, published. Nothing sent, no phantom launched, no button clicked; Chrome read-only.
Cron job 5 untouched and active.

## READ FIRST: what the 06:15 cron does tomorrow
The F14.4 gate fix (connection requests no longer count as "prior sent touches without text")
unblocked far more than expected. Dry run after all of F14, flag OFF, engine limit 25 (the cron's
body): 25 considered, 23 WOULD DRAFT (all InMail chaser 1 on the cr_not_accepted route), 2 refused
(company_not_deep_researched). Before F14 the same run drafted 0 and refused 25. Whole backlog
(117 due): 92 would draft (89 InMail chaser 1, 3 DM chaser 3), 25 refused (23 deep research,
2 thread_text_missing). Oliver has 59 pending already. The 23 for tomorrow, by name:
Marc Adelberg, Christian Allinger, Sami Amarir, Sabrina Arndt, Jean-Francois Baril, Alisha
Baesmann, Olivier Blanchard, Nathalie D, Christian Deiminger, Lucas Dosso, Marcel Erian, Florian
Gibfried, Jean-Christophe Haimb, Anja Hille, Julia Kaltenecker, Eden Ktorza, Ilias Moutani, Gabor
Ponicsan, Mathilde Saint-Pol Cousteix, Konstantinos Stamatopoulos, Michael Stolle, Florian
Teuteberg, Sandra Wursthorn. All are contacts whose only prior touch is a connection request
(Request sent or Withdrawn); the "chaser" the engine drafts is in practice a first InMail after a
CR that went nowhere. Drafts only, review-only, roughly GBP 3 of model spend. If that is not wanted
tomorrow, lower the cron body's limit (SELECT ... body := jsonb_build_object('limit', 25)) or pause
job 5 before 06:15 UTC; I did not change it because the brief said leave it active.

## F14.0 blackout recovery, measured (not trusted)
Counts: 1,121 companies, 694 contacts (682 live), 1,089 touches, 59 pending raw (54 actionable),
156 Accepted, 27 updated to Accepted at 19:22 London, one reply today (Urs Moeller, Objection 80,
19:22). F13 regression tests 1-4: 0, 0, 0, 0. Baseline deviations: refusals today were 696
initial_message + 2 chaser for deep research (pack: 698 initial only); Accepted never messaged 61
(pack: 60).
Duplicates: external_key 0. (contact, date, type) 94 groups, all from the 23 Jul / 26 Aug / 4 Sep
migrations or superseded regenerates (Dupuis 5 Chaser 1 drafts, Pfeiffer 2), except ONE from the
replay: Urs Moeller's opener filed a second time by the inbox watcher (inbox-7ca5ddd1, created
19:22) because the dispatched copy has a trailing space before the line break inside the first 40
characters the dedupe compared. Thread-id dedupe was vacuous: thread_id is null on all 1,089 rows
(LinkedIn thread URLs are not UUIDs).
Acceptances: none of the 27 was written off (no cooldown, no exhausted, no blocking status).
Raymond van Eck is Accepted at 2nd degree. Nine have neither a pending draft nor a message.
Urs Moeller: reply on contact P703, company coolblue, same company id on all four rows,
classification Objection 80 with reasoning, chase_state replied, next due cleared, no pending
draft, not in the due list, chaser gate refuses with contact_replied.
Nothing missed: the newest inbox snapshot (20 threads) has every inbound message either filed
(Urs) or already dismissed/assigned in the reconciliation queue on 8 Sep; all of Oliver's own
messages assigned or dismissed.
Fixed (089, run f14-0-urs-twin-2026-09-14): the twin row marked superseded with the dispatched row
as its twin, not deleted; v_sent_touches excludes superseded rows. Forward: classifier v21 compares
bodies on collapsed whitespace and additionally on thread URL + full text; outreach_log.thread_url
(text) is written on every inbox row from now (no backfill).

## F14.1 lock down fn_apply_send_effects (090)
EXECUTE revoked from anon, authenticated, public; service_role only (postgres owns it). Grants now:
service_role, postgres. Advisors 0028/0029: the function no longer appears; the only 0029 finding
is fn_user_teams, which is intentional.

## F14.2 automation heartbeat (091 + Lovable)
Table automation_heartbeat (source, label, interval 240 min, grace 480 min, last_seen_at,
last_payload_rows, consecutive_failures, last_error, last_failure_at). fn_heartbeat (service_role
only) stamps a success or a failure. v_automation_health computes silent_minutes, threshold
(12 h) and is_silent. Three sources: inbox_watcher (capture-and-classify-reply v21),
connection_watcher (update-contact-on-cr-accepted v16), sales_nav_watcher
(upsert-contact-from-sales-nav v22). Each stamps on every authorised, well-formed call and on a
handler error. Backfilled last_seen_at from the newest real row: inbox 18:22 UTC, connection
19:04 UTC, sales nav 19:04 UTC (all today). Today shows one strip above AI and Automation: alive
line when nothing is silent, red line per silent watcher with hours silent, threshold and last error.
Verified on the published build: "Watchers alive: Connection watcher 3h 10m ago, Inbox watcher ...".

## F14.3 a Sent row renders as sent (Lovable)
Touch popout on Fischer: Sent chip, Touch history 24 Jul Initial message + 9 Sep Chaser 1, frozen
body, "Sent Wed, 9 Sept 2026, 13:57 via LinkedIn inMail by Oliver", Previous drafts 2, notes. No
editor, no Approve, no Send now, no LINT, no "message 2 of 3", no legacy "never sent" note.
Moeller: history CR 28 Aug, opener 10 Sep, reply 14 Sep; "Sent Thu, 10 Sept 2026, 12:40 via
LinkedIn DM by Oliver". Contact popout Outreach tab: both sent rows read "Sent ... by Oliver" with
Open, not Edit. Flagged below: the superseded twin still lists under Follow up (marked SUPERSEDED),
and the Reply row carries a "Sent ... by Oliver" line it should not.

## F14.4 thread_text_missing gate + first message after CR (092, engine v7)
Gate: the prior-touch count now excludes Connection request, matching fn_chase_candidates. Nothing
else relaxed. Effect on the chaser backlog: thread_text_missing 85 -> 2; see the cron note above.
Flag: team_settings.first_message_after_cr_enabled (default FALSE) and first_message_cap_per_run
(default 5). fn_first_message_candidates = Accepted / Already connected, never messaged, no pending
draft, no reply on file, no live cooldown, not In conversation. Engine v7 runs it ONLY when the
flag is true (or in a dry run that asks for it), requests initial_message through the gates, and
drafts with trigger cr_accepted, the same trigger the Connection Watcher uses, so the type is a
first message after CR accepted, never a chaser, never counted toward a chaser cap.
Dry run, flag OFF: first-message section considered 0. Dry run, flag ON, cap 5: 5 considered,
1 would draft (Gerald Bourdin, YesYes, deep research done), 4 refused company_not_deep_researched
(Alexander Stork / ALDI DX, Jean-Marie Guian / Save Group, Pieter Waasdorp, Marek Grabowski).
Whole pool: 17 candidates, 1 at Deep research done. So flipping the flag produces one draft
tomorrow and then nothing until research catches up. Proposed cap: leave 5 per run.
Caveat: the drafter still reads pier_ea_documents; the layer 4 voice for this type arrives with the
F12 draft-stack cutover, which is not done.

## F14.5 chase accounting (093)
Fischer's dispatched row retyped Chase -> Chaser 1; his contact now chaser_1_sent, chaser_count 1;
the InMail chaser gate refuses him with allowance_exhausted. Forward: fn_apply_send_effects retypes
a sent 'Chase' to the next 'Chaser N' on its channel. 'Chase' rows remaining: 1 Cancelled, 6 Draft,
all migrated.
Report only: the cr_not_accepted route clocks from the last SENT connection request. 53 live,
chase-eligible contacts have a real message but no Sent CR row and are invisible to the engine:
Fischer (now capped anyway), 17 exhausted with a legitimate rest to 3 Dec, 8 with a migration
cooldown stamp (Honhon, Meiners, B. Ewenstein, Bonfils, Fleck, Hazi, Kuecuek, Cakiroglu), and 27
with chase_state none, among them the four Withdrawn contacts InMailed on 27 Aug (Jonkman,
Schuurmans, Hundman, Zubiaurre), Petrillo and v. Banhans (Not connected, messaged 25 and 17 Aug)
and 21 Withdrawn contacts messaged 27-31 Jul. Full list in the report SQL.

## F14.6 views (094)
v_sourcing_queue_missing_sn_url and v_company_size_current set security_invoker = true. Advisor
0010 gone; both views still return rows (218 and 0).

## F14.7 trigger WHEN clause: already in place
The live trigger is trg_sync_outreach_company_on_contact_update, AFTER UPDATE OF company_id ...
WHEN (old.company_id IS DISTINCT FROM new.company_id), from migration 043. No migration needed.
The other per-row contacts triggers (audit, contacts_count, cooldown status, normalise,
updated_at, degree guard) are all cheap. The 40-second timeout on that path was not this trigger.

## F14.8 regression tests
Five added to docs/oli-test-shapes-2026-09.md beside the F13 five. Baseline: 0, 0, visual, consent
codes promise_of_quiet 2 / dnc_or_opted_out 1 / contact_parked 0 / cr_cooldown_active 0, 0.

## Flagged, not fixed
- Contact popout Outreach tab shows the superseded Urs twin under "Follow up" with a Sent chip, and
  labels the inbound Reply row "Sent on 14 Sep, time not recorded, via DM by Oliver". Replies are
  not sends; the label should read Received. The touch popout's Touch history also lists the twin.
- Dupuis holds 5 Chaser 1 rows from 9 Sep (4 superseded regenerates in 4 minutes) and Pfeiffer 2:
  regenerate does not guard against rapid repeats.
- 10 duplicate Reply rows and ~80 duplicate Initial message rows from the migrations remain; the
  F14.8 duplicate test therefore only covers rows created from 14 Sep.
- thread_id (uuid) is dead weight; thread_url replaces it forward.
- fn_user_teams is SECURITY DEFINER and callable by authenticated (advisor 0029); intentional, left.
- The two remaining thread_text_missing refusals are contacts whose only prior message row has an
  empty body (workbook rows with no text).
