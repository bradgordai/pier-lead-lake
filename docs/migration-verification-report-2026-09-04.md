# Batch C Phase 2, THE MIGRATION: verification report

Run id `wb-frozen-2026-09-02`. Executed 2026-09-04 15:50 to 17:40 BST from the frozen workbook
`260902_PIER_lead_lake_SHARE_COPY_v09_OM_C2.xlsx` (frozen 2 Sep 17:12) plus the Monday export
`Companies_1787752414.xlsx`. Every decision is a row in `migration_audit` (run_id above).
Backup precondition: daily physical backups confirmed by Brad (latest 04 Sep ~06:35 UTC);
migrations 057 to 060 replayable from `migrations/`.

## 1. Staging load (step 1)

Stale `staging_v09_*` tables (never loaded, empty) dropped; `staging_wb_*` created with the
workbook's real headers as verbatim jsonb plus generated join keys (migration 057). Loaded via a
temporary, gated `migration-ingest` Edge Function (gate closed 15:54 UTC; the function is inert
without an open gate row and should be deleted from the dashboard, there is no MCP delete).

| Sheet | Workbook rows | Loaded |
|---|---|---|
| Companies | 1067 | 1067 |
| Contacts | 665 | 665 |
| Outreach Log | 989 | 989 |
| Pier Pipeline / EUREFAS / Competitor / Market | 64 / 27 / 42 / 11 | 64 / 27 / 42 / 11 |
| Monday export | 118 (112 real names) | 118 |

## 2. Identity and dedupe (step 2)

The live database had re-used ID ranges that the workbook later assigned to different people:
24 contact refs (P271 to P293) and 3 company refs (C348, C354, C355) pointed at different
entities in the two sources. Matching therefore ran on normalised LinkedIn URL first, then
Sales Nav URL (surname must agree), then name plus resolved company, and on the ref only when
the names agreed. Live wins live fields: a row edited live after the freeze (audit_log) keeps its
values and only fills gaps; otherwise the workbook value wins.

| Contacts | n |
|---|---|
| merged by LinkedIn URL | 120 |
| merged by Sales Nav URL | 64 |
| merged by name + company | 68 |
| inserted (workbook only) | 405 |
| skipped: workbook Void (duplicate) | 7 |
| skipped: workbook duplicate (P133 of P547) | 1 |
| live duplicate rows merged into the workbook survivor | 11 (P108/P300, P113/P272, P132/P296, P148/P301, P150/P302, P189/P078, P275/P235, P277/P063, P285/P198, P288/P155, P249/P082) |
| live rows re-keyed to the workbook ref | 31 |
| live rows re-keyed to a free ref (P759 to P763) | 5 |
| live rows archived as empty | 1 (P009) |
| of the 252 merges, live was newer than the freeze | 98 (live wins) |

| Companies | n |
|---|---|
| merged by ref + name | 331 |
| merged by name / domain / ref + domain | 8 |
| inserted (workbook only) | 696 |
| skipped: workbook `Duplicate -> Cxxx` | 32 (survivor gets `merged_from_refs`) |
| live rows re-keyed to the workbook ref | 7 (C320>C384, C354>C485, C355>C974, C359>C1077, C360>C646, C364>C611, C366>C401) |
| Geekmarket C348 | merged (live "entity TBC" variant) |
| notebooksbilliger C318 / C383 | both kept, C383 flagged needs_review as a possible twin |

## 3. Entities (steps 3 and 4)

| Companies | n |
|---|---|
| live before | 365 |
| live after | 1107 (1061 workbook + 9 EUREFAS + 37 Monday-only) |
| archived out_of_scope | 288 (185 inserted as OoS, 103 existing rows archived) |
| archived promoted_to_monday | 66 (28 lake companies worked in Monday + 37 Monday-only imports + 1 pre-existing) |
| Monday matched, annotated only (Monday "Prospect" with no lake signal) | 44 |
| EUREFAS dedupe-or-add | 9 added (Fenix.eco, ReWare Mobile, Tech2Com, 2Service, Buytec, EZ Furb, PanzerGlass, Simpaticotech, Twist), tracking resolved by trigger |
| country inferred, ccTLD rule | 10 |
| country inferred, Haiku | 24 |
| country still blank (live rows) | 128, 75 judged unresolvable by Haiku (no signal), the rest have no website |
| research stage, live rows | Deep 133 / Light 219 / Untouched 401 |

Country inference is marked `country_inferred=true`; email never unlocks on it (gate 6 reads
markets by country but Oli's rule that inferred countries need human verification is enforced
by the send-ready helper needing a verified country, see follow-ups).

| Contacts | n |
|---|---|
| live before | 280 |
| live after | 685 (673 live, 12 archived duplicates/empty) |
| Parked (UK, Jack) | 71, all owner Jack; 45 by contact country, the rest by company country |
| promise_of_quiet | 17 (the locked 17-list) |
| do_not_contact | 11 (workbook Yes) + P083 Opted out (same row also DNC) + P583 void tombstone skipped |
| Withdrawn (live, unarchived) | 181, all with `cr_blocked_until` (157 derived from a dated withdrawal note or log row, 24 conservative = 2027-03-04) |
| chase_scheduled_for from a future Next Action Date | 215 (66 land in Feb 2027 check-backs, 49 in Nov 2026) plus P379 2026-10-26 |
| multi-role trio linked by person_key | 6 rows (P085/P292, P102/P156, P124/P153) |
| formality set / language set / profile snapshot dated | 359 / 448 / 110 |
| owner Oli / Jack / none | 587 / 79 / 19 (the 19 are archived duplicates or void) |

## 4. Outreach classification (step 5), Haiku, 989 rows, GBP 0.30

| Class | Rows | Action |
|---|---|---|
| message | 310 | 257 imported as Sent touches with body; 50 already live; 3 no contact |
| cr_event | 369 | 252 imported as Connection request touches; 108 already live; 8 event-only rows (CR-accept, Withdrawn) skipped, the contact status carries them; 1 no contact |
| register | 200 | 155 imported as Sent touches with EMPTY body (the thread_text_missing population, needed so the engine does not think nothing was sent); 23 skipped (thread checks, scheduled placeholders, void); 21 already live; 1 no contact |
| inbound | 44 | 33 imported as Reply rows; 11 already live |
| draft_unsent | 33 | 7 imported as LEGACY pending_review drafts (July InMail chasers, one DM); 15 bracketed placeholders skipped; 11 already live (May first-message drafts, now flagged LEGACY, 2 of them Oli had approved) |
| note | 13 | appended to contact/company notes, dated |
| task | 20 | sourcing_queue rows (11 source_contacts, 9 verify_insurance; route-to-Jack assigned) |
| ambiguous / error | 0 | |

## 5. Backfills and state (steps 5 to 6)

- 46 synthetic Connection request touches for Accepted contacts with no CR in the log, legacy-dated to the earliest known touch minus one day, `legacy_source=synthetic_cr_backfill`.
- 102 legacy `Chase` rows renumbered Chaser 1/2/3 per contact and channel in date order, so the per-channel caps count history.
- `sent_body` = body on every Sent legacy row with text: 347 Sent rows have text, 557 do not (the register population).
- 61 legacy Sent rows carried `draft_status=pending_review` from the v09 load and were parking their contacts; set to `sent` (migration 060 also tightens the engine's pending test to unsent drafts).
- Chase-state contract written for every contact: none 347 / awaiting_reply 153 / cooldown 97 / chaser_1_sent 28 / exhausted 26 / replied 11 / chaser_2_sent 11 (pre-engine figures).
- T306 (P379) became `chase_scheduled_for 2026-10-26`, not a touch.

## 6. Catch-up scan through fn_evaluate_gates (step 6) and draft generation (step 7)

Two passes (the second after the pending fix above). Combined day-one picture:

| Due type | PROCEED (drafted) | Refused | Reason |
|---|---|---|---|
| due_first_message | 6 | 8 | company_not_deep_researched |
| due_chaser_1 (DM) | 9 | 1 | thread_text_missing |
| due_chaser_2 (DM) | 5 | 2 | company_not_deep_researched |
| due_inmail_chaser | 14 | 76 | thread_text_missing 64, company_not_deep_researched 12 |
| **total** | **34 drafts** | **87 refusals** | |

Every draft is `pending_review`, nothing sent. Drafts came from the real chase engine (v3, two live
runs, 24 + 4 drafts) and six direct first-message calls; 25 exhausted cadences were closed into
cooldown by the engine. Refusals are logged once per contact and reason per day (engine v3 dedupes;
the scan's duplicates were removed).

Day-one queue (pending review, unsent): 25 agent first messages (LinkedIn DM), 14 InMail chasers,
9 DM chaser 1, 5 DM chaser 2, 7 LEGACY July chasers, 6 LEGACY May first messages, 4 other = 70
(canon). Send-ready (blank CR pool) 31. Supply unlocks: missing SN URL 4, missing country 6.

## 7. Reconciliation vs Oli and vs the file

| Item | File | Oli | Live after migration | Note |
|---|---|---|---|---|
| Companies | 1067 | | 1061 from workbook (+9 EUREFAS, +37 Monday) | 32 workbook duplicates collapsed, 6 net new from live watchers kept |
| Contacts | 665 | | 673 live | 7 void + 1 dup skipped, 21 live-only kept |
| Outreach | 989 | | 951 legacy rows live (+108 live rows) | 23 register skips, 15 placeholders, 8 events, 5 no contact |
| Withdrawn | 232 | 244 | 181 live | delta 12 file vs Oli logged; 51 workbook Withdrawn rows are now Not relevant/void/archived or had a newer live status (live wins) |
| Promise of quiet | 17 regex | 16 | 17 | locked 17-list; P022 (6-month check-back) and the exit-sent trio P134/P231/P570 are the borderliners for Oli |
| DNC + opted out | 12 + 1 | 12 + 1 | 11 + 1 (same person) | P583 is a void tombstone, P083 is both |
| UK live | 54 | ~35 | 71 parked | 55 parked before this run + 18 new (workbook UK rows) minus merges |
| InMail credits | | 129 | 129 | ledger unchanged |

## 8. Spend

Today GBP 1.83 at 17:30 BST against the GBP 10 fail-closed budget: classification GBP 0.36
(42 Haiku calls incl. country), drafter GBP 1.33 (40 calls, one cold cache write, the rest
warm at ~GBP 0.015), ai-edit-draft GBP 0.11 (one cold test). Budget was not raised.

## 9. Test shapes, actual Edge Function responses (drafter v26, dry runs, nothing written)

| # | Contact | Trigger | Response |
|---|---|---|---|
| 1 | P269 Anthony (GreenIT Ireland, EN, accepted, deep) | cr_accepted | DRAFT, LinkedIn DM, cache read 57,080 tokens, GBP 0.0146 |
| 2 | P037 Elena Panova (A1 Telekom, accepted, 0 chasers) | chaser_1 | DRAFT on LinkedIn DM (free route), Chaser 1 |
| 3 | P227 Bram Weijschede (Fixje, accepted, 3 DM chasers) | chaser_1 | REFUSED `allowance_exhausted` "LinkedIn DM chaser allowance used: 3 of 3 sent." |
| 3 | P050 Vittorio Buonfiglio (MediaMarkt, request sent, 1 InMail chaser) | chaser_1 | REFUSED `allowance_exhausted` "LinkedIn inMail chaser allowance used: 1 of 1 sent." |
| 4 | P198 Dennis Backofen | cr_accepted and chaser_1 | REFUSED `promise_of_quiet` on both |
| 5 du | P001 Peter Stolzlederer (A1, Informal) | chaser_1 | DRAFT in du: "Peter, kurzer Gedanke zu A1: ihr nutzt beim Tarif..." |
| 5 Sie | P045 Alejandro Plater (A1, Formal) | chaser_1 | DRAFT in Sie: "Herr Plater, eine kurze Ergänzung zu meiner letzten Nachricht ... Ihre aktuelle Attachment Rate" |
| 6 | P706 Florian Pfeiffer (Sparhandy, accepted, deep, empty sent touch) | chaser_1 | REFUSED `thread_text_missing` |
| 6 | P297 Alessandro P. (TrenDevice, accepted, deep) | chaser_1 | REFUSED `thread_text_missing` |

Shape 5 note: the du draft wrote "Gerateversicherung" without the umlaut; the EA rule covers ss/ß,
not umlauts. Worth a line in the drafting directive if Oli objects.

## 10. Chase cron

Re-enabled as `daily-chase-engine` (jobid 5, 06:15 UTC daily, limit 25). Conditions met: T2
per-channel rules verified on two live runs (free DM route for accepted contacts, InMail cap 1,
exit shape on the final chaser) and T5 complete with historical thread context in place.

## 11. Follow-ups surfaced by the run

1. 557 Sent legacy touches have no text (the workbook never captured them). The engine will refuse
   `thread_text_missing` for those contacts until Oli pastes the real thread or logs a manual
   send; 64 of the 90 due InMail chasers are in this state.
2. 22 due contacts sit at companies below Deep research done; the gate refuses messages there by
   design (Oli's board rule). Research unlocks them.
3. Companies archived promoted_to_monday (66) refuse drafts for their contacts. 44 Monday
   "Prospect" rows were only annotated; Oli should confirm which of those he wants archived.
4. 75 companies with a website but no inferable country stay blank; 53 more have no website.
5. The temporary functions `migration-ingest` and `migration-classify` should be deleted in the
   dashboard (no MCP delete); both are inert (gate closed / classification finished).
6. The migration helper functions `mig_*` are dropped in migration 061 (they were flagged by the
   advisor as mutable search_path).
7. `fn_chase_candidates`, `fn_chase_exhausted`, `fn_evaluate_gates` get `SET search_path` in 061.
