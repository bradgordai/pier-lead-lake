# F8: reply matching, orphan queue and backfill (2026-09-08, before the 14:00 handover)

Status: shipped. Repo commits bb5a8ba (v16, migrations 067/068), e140883 (v17, migration 069),
5f65ef7 (v18). Lovable commit 4d8f65d2, published. capture-and-classify-reply live at v18.

## The fault

The Inbox Scraper phantom (2840951049581867, 6x a day) hands Make an anonymised sender URL
(`/in/ACoAA...`), a participant entity URN and a thread URL. It never sends the public slug.
capture-and-classify-reply v15 matched on the slug only, returned `orphan` for everyone else
and stored nothing, so every live reply since the 4 Sep migration was dropped on the floor.

Two more things the payload told us once we looked:

- For Oliver's own messages the phantom names **Oliver** as the sender. The only name for the
  counterparty is the greeting line in the body ("Hi Joan", "Hallo Herr Siebel").
  `linkedInUrls` does carry the counterparty's anonymised id, which is what alias learning binds.
- A message with no text (an image, a document, a reaction) arrives with `message: ""`.

## What v16-v18 do

Matching ladder, in order, for every message:

1. **alias**: any identifier in the payload (sender URL, entity URN, participant URLs, thread
   URL) already learned onto `contacts.linkedin_aliases`. Exact match.
2. **slug**: a public `/in/<slug>` in the payload against `linkedin_slug`, `linkedin_url`,
   `linkedin_sales_nav_url`.
3. **name**: prospect messages use `firstnameFrom` + `lastnameFrom` (diacritics folded),
   scored 50, +30 if we sent them something within 60 days of the message, +20 if
   `occupationFrom` overlaps their title or company. Auto-filed only when exactly one candidate
   scores 70 or more. Oliver's own messages use the greeting name instead (first name via
   `fn_match_contacts_by_first_name`, surname when a title such as Herr/Frau/Mr precedes it)
   and need exactly one candidate at 80 or more, so a recent outbound is mandatory.
4. otherwise the message goes to `unmatched_replies` with the scored candidates. Nothing is
   dropped; text-less messages get a placeholder body.

On every match the payload identifiers are merged into `contacts.linkedin_aliases`, so that
sender exact-matches from then on. A human assignment from the queue does the same, and also
files any other queued message from the same sender.

Idempotency: `outreach_log.external_key = sha256(threadUrl | lastMessageDate | body)`, unique
per team, plus a same-day, same-opening-text check against legacy rows without a key. The
watcher can resend the whole inbox snapshot every four hours and replays are no-ops. A message
that was queued and later matches (after alias learning) closes its queue row automatically.

Filing a **prospect's** reply: verbatim `Reply` touch, classification with the contact notes
block, AI state of play refreshed under the marker in `conversation_summary`,
`chase_state = replied` with `chase_next_due_at` cleared, elevation to In conversation on
Positive interest or Booked meeting, pending Chaser 1/2/3 drafts superseded with an audit_log
entry, Move-to-Monday alert. Filing **Oliver's own** message: an outbound touch (`inbox-<uuid>`,
sent_by Oliver, sent_body set), `last_contacted` updated, chase_state replied -> awaiting_reply.
No classification, no draft, no alert.

Actions on the function: `assign`, `dismiss`, `sync_inbox` (launches the phantom),
`sync_status` (processes the result object when finished), `replay_containers` (backfill).

Database: migration 067 (`contacts.linkedin_aliases`, `outreach_log.external_key`,
`unmatched_replies`), 068 (`contact_replied` refusal in `fn_evaluate_gates`, `fn_chase_candidates`
excludes `chase_state = replied`, alias and surname matchers), 069 (first-name matcher).

Lovable (commit 4d8f65d2): Reconciliation tab "Unmatched replies" with open-count badge, three
tiles, one card per message (sender, message, suggested contacts with Confirm, Assign-to-contact
search, Dismiss); Outreach "Sync LinkedIn replies" button launches the phantom, polls every 8 s
for up to five minutes and reports processed / filed / threaded / queued;
`REFUSAL_LABELS.contact_replied`.

## Backfill

Source: the 26 Inbox Scraper containers finalised since 4 Sep 03:29 UTC (Make execution history
carries no module payloads, so the phantom's result objects were replayed instead). 520 rows in
total, 20 per container: the phantom retains the 20 most recent threads, so every container is a
near-identical snapshot and the real coverage window is "the 20 newest threads in Oliver's
inbox", whose message dates run from 24 Jul to 6 Sep. Anything that fell out of that window
before 4 Sep was never captured by the phantom and cannot be recovered from this source.

| | unique messages | filed / threaded | queued for a human |
|---|---|---|---|
| prospect messages | 8 | 2 | 6 |
| Oliver's own messages | 13 | 7 (4 new touches, 3 already on record as T767 / T792 / T833) | 6 |
| total | 21 | 9 | 12 |

Matched rate: 9 of 21 messages (43%) filed without a human. Of the 8 inbound messages, the 2
from contacts we had actually messaged (Ishnav Thakooree, Kim Ulmer Koldby) both filed
automatically; the 6 queued are cold pitches to Oliver (Maria Clark, LinkedIn Talent Solutions,
Alireza Mansouri), a recruiter (Kevin Jones), a text-less message (Lee F) and Patrick Brückner.
The 6 queued own messages either have no greeting ("Same to you", the 26 Aug send test) or a
first name shared by several recent contacts (Christian: 5 suggestions, Matthias: 4).

Dropped: 0. Nothing in the queue costs more than one click.

Fresh pass after the backfill: see the sync counts at the end of this file.

## Verification

- Spot-check, prospect replies: Ishnav Thakooree "would actually love to have a testimonial"
  (31 Aug) filed as Positive interest, chase_state replied, state of play written; Kim Ulmer
  Koldby's emoji reply (24 Jul) sits on the thread with her CR and initial message of the same
  day, aliases learned. Note: the classifier read the emoji as Positive interest and elevated
  her to In conversation, which is generous for a relationship-only contact; Oli can downgrade.
- Spot-check, own messages: "Hallo Herr Rogat" filed under Matthias Rogat (notebooksbilliger)
  next to three earlier sends; "Hi Stefano" under Stefano Petrillo; "Guten Tag Herr Lenane" and
  "Hallo Herr Siebel" were recognised as the migrated chasers T767 and T792 and simply keyed.
- Patrick Brückner's "Vielen Dank": queued. He is not a contact (the message is dated 26 Jul;
  8 Sep was only the scrape time). Assign or dismiss from the queue.
- Chase hard block: `fn_evaluate_gates(..., 'chaser')` returns `contact_replied` for both filed
  contacts; `fn_chase_candidates` returns 0 replied contacts out of 88 candidates.
- Idempotency: a second replay of the newest container returned 20 duplicates, 0 new rows.

## Constraints honoured

No outbound sends. Phantom launches limited to the Inbox Scraper (a read). Edge Function deploys
at 10:15, 10:27 and 10:32 London, clear of the 12:53-13:13 watcher window. Per-task commits.

Fresh pass (sync_inbox -> container 8976768161069044, 10:41 London): 20 processed, 0 new,
20 duplicates. Nothing new had arrived in Oliver's inbox since the backfill.
