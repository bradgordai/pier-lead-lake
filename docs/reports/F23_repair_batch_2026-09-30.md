# F23 repair batch, 30 Sep 2026 (session lovable5)

Nothing was sent. No Send now, Approve, phantom launch, drainer trigger or Make run/replay. No PhantomBuster or
Make setting was changed.

## Baseline, re-measured 30 Sep (before any change) — deviations from the brief are findings
| Measure | Brief (12:35 BST) | Measured | Note |
|---|---|---|---|
| contacts | 1035 | 1035 | |
| companies | 1159 | 1159 | |
| outreach_log Sent | 1153 | **1155** | +2 |
| Sent with sent_at_actual | 706 | **708** | +2 |
| Cancelled | 197 | 197 | |
| pending_review | 107 | **110** | +3 |
| approved and unsent | 18 | 18 | |
| rows with phantom_run_id | 56 | 56 | |
| send_error 'phantom_skipped_duplicate_or_empty' | 11 | 11 | |
| send_queue | 42 done, 12 failed, 0 live | 42 done, 12 failed | |
| last real send | 29 Sep 15:52 BST | **30 Sep 10:52 UTC** | see below |
| latest migration | 148, "file committed" | 148 applied, **file untracked** | committed dbe79de, NOT re-applied |

FINDING, last send: Torsten Schimkowiak (29 Sep 14:52 UTC, run 7026838469692543) is the last PHANTOM send. Five
later rows are Follow up / InMail marked Sent with sent_by='Oliver' and NO phantom_run_id: P1007 Leonardo Ramirez
Peña (29 Sep 12:45), P781 Daniel Freudenberger (14:33), P099 Dr. Philipp Gattner (14:35), P031 Mike Reif (30 Sep
10:03), P103 Thomas Gros (10:52). They look like hand-marked sends, not dispatcher sends.

## Task 1 — DONE (cause fixed, data repaired per Brad's ruling, regression test)
EVIDENCE: migration 149 (schema_migrations 20260930151303); send-approved-callback **v17** (ezbr 69e52833), index.ts
and _shared/authorize.ts byte-identical to the repo; test tests/send_hold_reason_test.py.
DEVIATION FROM THE BRIEF (Brad's error, confirmed by him): the 11 rows were NOT approved. All 11 were already
draft_status='superseded'. WHAT SUPERSEDES THEM (reported, not fixed): trigger **trg_supersede_failed_send**
(function fn_supersede_failed_send, migration 145, F22B.9): BEFORE UPDATE OF send_status, when send_status becomes
'Cancelled' on an 'approved' row it sets draft_status='superseded' and rejection_feedback reason 'send_failed'.
The v16 skip path set Cancelled, so every skip was superseded the moment the callback ran. 10 of 11 carry reason
send_failed; Deiminger's carries non_sales_reply (F22B.5 supersede).
Also: 8 of the 11 duplicate messages already delivered later (Torsten x4, follow-up sent 29 Sep; Benjamin Köhler x3,
sent 28 Sep; Leonard Coen's Initial message, opener sent 2 Sep).
(a) CAUSE: v17's skip path (exit 0, empty resultObject) writes send_status='Draft', draft_status='pending_review'
    (never approved), hold_reason='phantom_skipped_duplicate'. Cancelled is no longer written, so
    trg_supersede_failed_send cannot fire on a skip. A repeat callback for the same run is ignored (Draft + hold_reason);
    a real send clears hold_reason.
(b) DATA, per Brad's ruling (NOT the brief's "restore all 11"): outreach_log.hold_reason added; ALL 11 tagged; ONLY the
    newest Urs Moeller Chaser 1 (e143db6f, created 24 Sep) restored; Deiminger never restored.
    BEFORE: 11 × send_status Cancelled / draft_status superseded / hold_reason null.
    AFTER: 10 × Cancelled / superseded / phantom_skipped_duplicate; 1 × Draft / pending_review / phantom_skipped_duplicate.
    ZERO of the 11 at draft_status='approved' (asserted inside the migration).
    NOTE: Urs Moeller now has TWO open Chaser 1 drafts (e143db6f restored + 3bab700a of 26 Sep, near-identical text).
    trg_one_open_draft fires on INSERT only, so the restore by UPDATE did not supersede either. Oliver should approve at
    most one.
(c) REGRESSION TEST: **tests/send_hold_reason_test.py**. It fails if send-approved-draft's accepted send_status list
    stops including the status a hold_reason row carries, if the callback's skip branch writes Cancelled or approved,
    or if it stops writing hold_reason. PASS on v17; run against the v16 source it FAILS on 3 counts (proved).
TS types regenerated after 149 (hold_reason present in Row/Insert/Update).
FLAGGED, not fixed: (1) an InMail skipped a SECOND time after being re-sent gets no second credit refund
(fn_ledger_inmail_reverse refunds once per row). (2) Brad's finding: Torsten had chase_state='replied' (soft decline 23
Sep) yet got four Follow up drafts and a real send on 29 Sep; contact_replied only fires for p_requested='chaser', so
'Follow up' (requested='reply') bypasses it.

## Task 2a — BUILT AS A FLAG (Brad's amendment); NOT a gate; Task 2b CANCELLED
EVIDENCE: migration 150 (schema_migrations 20260930152444). fn_evaluate_gates md5 18099d27… unchanged and does not
mention company_already_approached.
- CONFIRMED by reading fn_group_siblings_engaged / fn_company_group_pairs: siblings are LINKED companies only (R1 exact
  parent_group, R2 parent_group names the sibling's domain, R3 parent_group names the sibling; engaged = Monday deal,
  opportunity_status Contacted/Active Lead/Partner, or a contact Contacted/In conversation/Meeting booked). Same
  company_id colleagues are not considered.
- RE-MEASURED (real first approaches, touch_type Initial message/Other, sent_at_actual NOT NULL, London day):
  **39 company-days, 96 people** (brief: 45 / 109). Worst: The Very Group 5, Rebuy 5, then mySWOOOP, Save Group, Forza
  Refurbished, bol.com 3 each. Counting real phantom CRs as well gives 79 company-days / 231 people, which may be how
  the brief's figure was reached.
- ENUM TRAP: the brief's 'Cold InMail' is NOT a touch_type value (values: Initial message | Connection request | Chase |
  Reply | Event follow-up | Introduction | Meeting confirmation | Other | Chaser 1-3 | Follow up). A cold InMail is
  'Initial message' on channel 'LinkedIn inMail'. The function uses ('Initial message','Other').
- mobileup: NEITHER mobileup contact (Beat, Elias) exists in Supabase, nor does Manuel at Jacob. Their InMails (28 and 30
  Jul) predate sent_at_actual, so the flag cannot see July-era history at all.
- BUILT: fn_company_already_approached(p_team_id, p_contact_id, p_requested) -> (flagged, colleague, approached_at,
  colleague_contact_id); the brief's 'blocked' column is named 'flagged' because nothing is refused. Chasers and replies
  never flag. v_draft_company_flags gives the flag + flag_text ("A colleague at this company, X, was approached on
  <date> and has not replied.") for every open draft. The card display is Lovable work (Task 4 message).
- REFUSAL COUNTS (before; unchanged because nothing is wired), 1,023 live contacts, channel LinkedIn DM:
  chaser: PASS 727, group_sibling_engaged 70, contact_parked 67, dnc_or_opted_out 67, pending_ruling 41,
  thread_text_missing 23, promise_of_quiet 17, contact_replied 9, allowance_exhausted 2.
  initial_message: PASS 761, group_sibling_engaged 70, contact_parked 67, dnc_or_opted_out 67, pending_ruling 41,
  promise_of_quiet 17.
- DRY RUN: open drafts 108 pending_review + 18 approved (brief: 107 + 18). FLAGGED: **24 pending + 5 approved = 29 drafts
  at 13 companies.**
  Approved (5): Luca Sansone and Daniele Voltolina (Comet; colleague Massimo Cillerai 25 Aug); Anthony O'Dea (GreenIT
  Ireland; Greg Kielek 28 Jul); Sanmeet Singh Kochhar (HMD; Anssi Rönnemaa 22 Sep); **Philipp Lohmar (Tchibo; Davit
  Gniech 28 Jul)**.
  Pending (24): Marcel Masek (0815); Nathalie D (AfB; Mike Reif); Caroline Prick, Luuc Mannaerts, Fiona Vanderbroeck
  (bol.com; Maite Zubiaurre); Sami Amarir, Ilias Moutani (DBC ELECTRONICS; Selim Salah); Rowan Westerduin (Fixje);
  Jean-Francois Baril, Csilla Bors, Duc Anh Nguyen P654 AND P921 (HMD, a duplicate contact); Konstantinos Stamatopoulos,
  Marta Gutiérrez Ràfales, Alexander Klinger, Janette Keller, Sebastian Koch, Henry Braun, Alexander T. Rauchut
  (MediaMarkt Saturn; Chris Stapelfeldt 10 Aug); Jean-Christophe Haimb (Pearl; Sandra Wursthorn); Frank Schuster, Monika
  Maciejewska (T-Mobile; Ronit Avzardel); Markus Lawrenz, Johannes Häner (topi; Leonard Coen 2 Sep).
- DEVIATION: Bianca Pfaller and Robert Karl (Drei) are NOT flagged. Nobody at Drei has a real send yet: all 6 Drei
  drafts are open (2 approved: Bianca, Robert; 4 pending). The flag looks at sends, not at open drafts queued together,
  so it fires for the rest as soon as the first Drei message goes out. A "sibling drafts also open" warning would need
  a second rule; not built.
- Oliver's two rulings (expiry, company vs group) are no longer needed; the flag is shown and he decides.

## Task 3 — STOPPED AND REPORTED: THE DATABASE IS AT FAULT (not Lovable). Nothing changed.
The brief's premise (fault in Lovable; fn_company_score_mark_dirty harmless) is wrong. Rolled-back probes on Smarando
(C962), 30 Sep:
- update usp_notes (changed value)        -> ERROR malformed array literal: "wedge"
- update research_stage (valid enum cast) -> ERROR malformed array literal: "research_stage"
- update last_refreshed = current_date     -> ERROR malformed array literal: "last_refreshed"
- no-op update (industry = industry)       -> ok
CAUSE: fn_company_score_mark_dirty (migration 137, F22B.1, written by me on 22 Sep), fired by trg_company_score_mark_dirty
AFTER UPDATE ON companies FOR EACH ROW (no column list). It declares `changed text[]` and appends with
`changed := changed || 'research_stage'`: the untyped literal makes Postgres pick array || array and parse the word as an
array literal. All six branches (research_stage, company_size, insurance, wedge=usp_notes, country, last_refreshed) fail
whenever that field actually changes. The error is raised BEFORE the company_scores UPDATE, so "company_scores has 3
rows" does not make it harmless. The 28 Sep usp_notes probe almost certainly wrote an unchanged value, so no branch ran.
i145 and i156 already describe exactly this.
IMPACT: since 22 Sep 23:20 UTC NO research field on ANY company can be changed, from Lovable or through the MCP.
PROPOSED FIX (not applied, needs Brad's word; it is a database change): cast every literal, e.g.
`changed := changed || 'wedge'::text` (or array_append(changed, 'wedge')) in all six branches, one migration, then
re-run the four probes above expecting ok. No data change is needed.
The array columns category / insurance_product_types / merged_from_refs are not involved in this error.

## Task 5 — DATABASE DONE (UI: Lovable message after Task 4)
EVIDENCE: migration 151 (schema_migrations 20260930152834).
- contacts.is_blocked boolean NOT NULL DEFAULT false, contacts.blocked_at timestamptz.
- fn_evaluate_gates: 'recipient_blocked' is an ABSOLUTE refusal placed directly after dnc_or_opted_out, above
  contact_parked and every discretionary gate. PROOF the rest is unchanged: new md5 bd344049…; the same definition with
  the new 7-line block removed hashes to 18099d27…, identical to the pre-batch function.
- refusals.reason_code check extended with 'recipient_blocked' (otherwise the drafter's refusal insert would fail).
  FINDING: the check also lists 'company_archived' (emitted by the drafter, not the gate function), so there are 13
  codes in use, not the brief's 12; 14 with the new one.
- NO BACKFILL. is_blocked = true on 0 contacts.
- VERIFY, refusal counts per reason_code, 1,023 live contacts × {chaser, initial_message}, before vs after: EVERY
  contact's code identical (0 rows changed). recipient_blocked = 0. Totals unchanged: chaser PASS 727,
  group_sibling_engaged 70, contact_parked 67, dnc 67, pending_ruling 41, thread_text_missing 23, promise_of_quiet 17,
  contact_replied 9, allowance_exhausted 2; initial_message PASS 761, group 70, parked 67, dnc 67, pending 41, quiet 17.
- SOURCE for the later backfill (NOT done): 260928_salesnav_inbox_run1/2.json, 4 threads with
  restriction=MEMBER_BLOCKED_BY_RECIPIENT, participants[] EMPTY in all 4 (identified only by the annotated 'who'
  field). In Supabase: Alexandra Asanache (P093, Lenovo) EXISTS; Beat and Elias (mobileup) and Manuel (Jacob) do NOT
  exist as contacts, so they cannot be flagged until they are created.
- TS types regenerated after 151 (is_blocked, blocked_at, v_draft_company_flags, fn_company_already_approached present).

## Task 6 — DONE
EVIDENCE: migration 152 (schema_migrations 20260930153418). fn_improvements_stamp_source ACL was
{=X (PUBLIC), postgres, anon, authenticated, service_role}; now {postgres, service_role}. has_function_privilege:
anon false, authenticated false.
DEVIATION (necessary): EXECUTE was also granted to PUBLIC, which anon and authenticated inherit, so revoking only from
the two named roles would have left the function callable. Revoked from PUBLIC, anon and authenticated.
PROOF the trigger still works: rolled-back insert into improvements AS authenticated (Brad's user) succeeded and
trg_improvements_stamp_source stamped source_channel='lovable_app' and source_actor.

## Task 7 — STOPPED AND REPORTED: no invitation date reaches Supabase. This is a PhantomBuster question. Nothing built.
- WHO WRITES THE SYNTHETIC CR ROWS: all of them since 20 Sep carry touch_id 'cr-<uuid>' and come from
  upsert-contact-from-sales-nav (on a NEW Request-sent contact it inserts a Connection request row with touch_date =
  the ingest day, send_status Sent, no sent_at_actual). Per ingest day: 22 Sep 71 (+1 legacy 'cc-20260902' row),
  24 Sep 52, 25 Sep 9, 28 Sep 62, 29 Sep 7.
- THE PAYLOAD: Make 9589633 "Pier Sales Nav List Watcher" (read only) forwards ONLY profileUrl, linkedInProfileUrl,
  firstName, lastName, headline, companyName, companyUrl, location, connectionDegree, listName. No date at all.
- WHAT THE PHANTOM EMITS (Sales Navigator List Export, agent 2343586699386601, sample bundle in the Make blueprint):
  dateAdded (when the lead was added to the Sales Nav LIST, not the invitation date), timestamp (the scrape time),
  and outreachDate / outreachActivity, which are EMPTY ("") in the sample. The latest run (container 3228157281688873,
  30 Sep 12:09) returned "No new results found", and PhantomBuster no longer holds the 22 Sep containers, so I could
  not confirm whether outreachDate is ever populated.
- CONCLUSION: the true invitation date is not available to Supabase today. Whether outreachDate / outreachActivity
  carry it (and could be mapped through Make) is a PhantomBuster question. Using dateAdded or the ingest day would be
  inference, which the brief forbids. cr_observed_at, the per-day view and daily_cr_cap are NOT built.
- Related findings: team_settings has weekly_cr_target and no daily cap; allowance_exhausted is only computed for
  chasers inside fn_evaluate_gates, never for CRs. The same scoped inbound bearer is typed in plaintext in 9589633's
  two HTTP modules (as in 9850348). Not changed.

## Task 8 — GUARD DONE (existing 12 untouched)
EVIDENCE: migration 153. Rolled-back tests: insert "BACK-market" -> 23505 duplicate_company: matches existing C1382
Back Market by name; insert "Totally Different Name" with website https://www.easycash.fr/shop -> 23505 matches C345
Easy Cash by domain; a genuinely new name -> inserted.
ROOT CAUSE (finding): upsert-contact-from-sales-nav's company matcher loads only companies with archived_at IS NULL, so
an ARCHIVED company is invisible to it and its auto-create (added_via 'sales_nav_auto') makes a second. 11 of the 12
collisions are an archived original plus a newer copy.
GUARD: trg_company_duplicate_guard (BEFORE INSERT on companies) refuses a normalised-name (lower, non-alphanumerics
stripped) or root_domain match against ANY company of the team, archived or not, with SQLSTATE 23505 and a message
naming the existing company. NOTE root_domain is always derived from website_url by tg_companies_normalise, which fires
first, so domain matching uses the website.
DEVIATION (honest): a trigger cannot RETURN the existing company to the caller. The ingest treats the refusal as
"auto-create failed" and inserts the contact UNMATCHED, which sends it to Reconciliation for a human to attach. Attaching
it to the existing company automatically needs a change in upsert-contact-from-sales-nav, plus a ruling on whether a
contact may be attached to an ARCHIVED company (its drafts would then be refused as company_archived). Not done.
THE 12 EXISTING COLLISIONS, for Brad's ruling (NOT merged):
| key | older | newer |
|---|---|---|
| backmarket | C019 Back Market (archived, 23 Jul) | C1382 Back Market (24 Sep) |
| easycash | C052 EasyCash [easycash.fr] (archived) | C345 Easy Cash [easycash.fr] (both 23 Jul) |
| ebuyer | C230 Ebuyer [ebuyer.com] | C337 Ebuyer [ebuyer.com] (both live, both 23 Jul) |
| efones | C282 eFones [efones.com] (archived) | C231 eFones (both 23 Jul) |
| geekmarket | C348 Geekmarket (archived, 23 Jul) | C1385 GeekMarket (24 Sep) |
| grover | C089 Grover [grover.com] (archived, 23 Jul) | C1380 Grover (24 Sep) |
| mediamonster | C497 Media-Monster [media-monster.be] (archived, 4 Sep) | C1373 MediaMonster (22 Sep) |
| mediongmbh | C1322 medion GmbH (archived, 4 Sep) | C1393 medion GmbH (28 Sep) |
| recommercegroup | C149 Recommerce Group (archived) | C150 re/commerce Group (both 23 Jul, same domain) |
| spusu | C456 spusu [spusu.at] (archived, 4 Sep) | C1388 spusu (24 Sep) |
| swappie | C179 Swappie [swappie.com] (archived, 23 Jul) | C1384 Swappie (24 Sep) |
| utopya | C202 Utopya [utopya.fr] (archived, 23 Jul) | C1339 Utopya [utopya.com] (9 Sep) |

## Amendment: converting five gates to flags — ANALYSIS ONLY, nothing converted (Brad scopes it separately)
WHO CALLS fn_evaluate_gates: five edge functions (generate-draft-from-context, chase-engine, send-approved-draft,
capture-and-classify-reply, update-contact-on-cr-accepted); no SQL function calls it. Every caller treats ANY returned
row as a refusal. So the shared change for all five is: fn_evaluate_gates returns a severity ('refuse' | 'flag'); the
five callers proceed on 'flag' and persist it on the draft (e.g. outreach_log.gate_flags jsonb, with code, text and
evaluated_at); send-approved-draft re-evaluates at launch and still stops on 'refuse' only. The refusals table would
then record only refusals, and flags would live on the draft. The screens that show a flag reuse the F23 amber line
(DraftWarnings) on: the Outreach list and thread panel, the contact Conversation tab, Today to-do, and the refusal-reason
list in "What the system did".
PER GATE:
| gate | what it guards today | conversion work beyond the shared change | where the flag shows |
|---|---|---|---|
| group_sibling_engaged | new approach at a company whose LINKED company is already worked (replies exempt) | none extra: fn_group_siblings_engaged already returns names + why, the drafter already writes a GROUP COLLISION note for replies; reuse it for every touch | draft card: "Linked to X (in Monday / Contacted); one approach per group" |
| cr_cooldown_active | a new connection request within 6 months of a withdrawal (cr_blocked_until) | nothing drafts CRs today (sent by hand or by phantom), so the flag has no draft to sit on: it belongs on the CONTACT card ("new CR blocked until <date>"). The 125 withdrawn CRs carry cr_blocked_until | contact card header |
| allowance_exhausted | chaser N+1 on a channel once cap (DM 3 / InMail 1 / Email 3) is sent | ALSO enforced by fn_chase_candidates (protected; mentions caps), so converting the gate alone changes nothing: the engine never proposes the contact. Needs a change to a protected function | draft card: "4th chaser; allowance is 3" |
| contact_replied | a chaser after the contact replied (chase_state='replied'), only for p_requested='chaser' | ALSO filtered by fn_chase_candidates / first-message / cold-InMail / reply candidates (all mention 'replied'). And, per Brad's Torsten finding, 'Follow up' (requested 'reply') bypasses it today, so as a flag it should cover follow-ups too | draft card: "They replied on <date>: answer the reply, not a chaser" |
| country_unknown | EMAIL only: no stated country, so cold-email legality unknown | fn_send_ready_contacts mentions country. CAUTION: channel_illegal_in_market stays absolute, but with no country it cannot be evaluated, so a flag here means an email can go out with legality unestablished. Brad to confirm that is intended | email draft card: "Country unknown: cold-email legality not established" |

## Task 4 — DONE (Lovable 45ca060 + fixes 57085ee, 4242e27; PUBLISHED)
Expected figures MEASURED AT RUNTIME (queries):
- Sent: `select count(*) from outreach_log where send_status='Sent'` = 1,155 (draft_status='sent' gives 1,259; 109 of those
  are Cancelled). Chrome, Outreach "Sent" tab: **1155** ✔.
- Pending Review canon: `select count(*) from outreach_log o left join contacts c on c.id=o.contact_id left join companies co
  on co.id=c.company_id where o.send_status='Draft' and o.draft_status='pending_review' and co.archived_at is null` = 106.
  Chrome: Outreach Pending Review **106** ✔, Today "Drafts to approve" **106** ✔. (Dropping Lovable's old "contact not
  soft-deleted" rule changes nothing today: 0 such drafts.)
- Approved and unsent: `draft_status='approved' and send_status in ('Draft','Ready')` = 18. Chrome, Today strip:
  "**18 approved, waiting for you to press Send**" ✔ (previously "Send queue empty").
- Promotion rate: was 558% (67 promoted ÷ 12 DM replies). Now "Promotion rate (of companies that replied)": companies with a
  Reply row that are promoted ÷ companies with a Reply row. Lovable counts promoted as archive_reason='promoted_to_monday'
  only: 11 ÷ 32 = 34%; Chrome all-time **34%** ✔. (Counting monday_deal_id as well would give 15/32 = 47%; flagged.)
  Any rate over 100% is clamped by safeRate() with console.warn('rate_clamped', …).
- Empty windows render "—" (Chrome: Accepted this wk "—", Positive-sentiment "—") ✔.
- hold_reason line: Chrome, Today to-do under Urs Moeller: "The LinkedIn tool skipped this last time. It was returned to
  review; check it before sending again." ✔. (Urs's contact Conversation tab lists no open drafts at all, so the line is
  not there; existing behaviour.)
- Colleague flag (Task 2a): Chrome, Philipp Lohmar's contact Conversation tab: "A colleague at this company, **Davit
  Gniech** (link), was approached on 28 Jul 2026 and has not replied." ✔. Two Lovable fixes were needed: the warnings
  were not mounted on the contact tab's unsent-draft card, and the loader coupled the two lookups.
- Restored drafts do not increment chaser counters: chaser counts read send_status='Sent' only (confirmed by Lovable; the
  gate counts Sent chasers only).

## Task 5 UI — DONE (Lovable 9a01adb + label fix f667a46; PUBLISHED)
Chrome: Alexandra Asanache (P093) contact header shows "Mark as blocked by recipient" (NOT clicked; is_blocked = 0 rows).
Today > What the system did > Refusals now reads "Linked company already being worked", "Earlier message text missing"
(was raw codes; one shared label map with all 14 codes, fallback "Refused (<code>)"). Red "Blocked" pill, "Blocked by
recipient on LinkedIn · since <date>" badge and the Contacts filter are built but cannot render until someone is blocked
(0 today): NOT seen rendered.

## Close-out
Scratch table _f23_gate_snap DROPPED. Migrations 149-153 in schema_migrations. Lovable publishes this batch: Task 4
(45ca060 + 57085ee + 4242e27) and Task 5 (9a01adb + f667a46), pier-lead-lake.lovable.app. Nothing sent.

## FINAL TABLE — every column, function, view, gate and trigger added, and the screen it appears on
| Object | Type | Task | Screen |
|---|---|---|---|
| outreach_log.hold_reason | column | 1 | Draft card amber line "The LinkedIn tool skipped this last time…" (Today to-do seen; Outreach list/thread, contact Conversation) |
| send-approved-callback v17 (skip → Draft + pending_review) | function (EF) | 1 | the returned draft reappears in Pending Review (Outreach, Today) |
| tests/send_hold_reason_test.py | regression test | 1 | **none** (repo test; no screen by nature) — DEFECT per brief's rule, listed |
| fn_company_already_approached | function | 2a | via v_draft_company_flags (below) |
| v_draft_company_flags | view | 2a | Draft card amber line "A colleague at this company, X (link), was approached on <date>…" (contact Conversation seen for Lohmar; Today to-do, Outreach) |
| contacts.is_blocked | column | 5 | Contact header badge + "Mark as blocked by recipient" (seen), Contacts list pill + filter (not yet seen: 0 blocked) |
| contacts.blocked_at | column | 5 | Contact header "since <date>" (not yet seen: 0 blocked) |
| gate 'recipient_blocked' in fn_evaluate_gates | gate | 5 | Refusal lists "Blocked by recipient" (label map; not yet seen: 0 refusals) |
| refusals_reason_code_check (+recipient_blocked) | constraint | 5 | **none** directly (enables the refusal row) — DEFECT per rule, listed |
| fn_improvements_stamp_source EXECUTE revoked | privilege | 6 | **none** (security hardening; no screen by nature) — DEFECT per rule, listed |
| fn_company_name_key | function | 8 | **none** (used by the guard) — DEFECT per rule, listed |
| companies_team_name_key_idx, companies_team_root_domain_idx | indexes | 8 | **none** — DEFECT per rule, listed |
| fn_company_duplicate_guard / trg_company_duplicate_guard | function + trigger | 8 | Error toast on the Lovable "new company" form when a duplicate is typed (NOT tested in Chrome: it would create a company). Contacts from Sales Nav land in Reconciliation > LinkedIn Contacts when refused |
| cr_observed_at / per-day CR view / daily_cr_cap | NOT BUILT | 7 | STOPPED: no invitation date in the payload |
| fn_company_score_mark_dirty fix | NOT BUILT | 3 | STOPPED: DB at fault, fix proposed |
