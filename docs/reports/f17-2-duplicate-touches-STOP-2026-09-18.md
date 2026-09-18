# F17.2 Duplicate touch rows (i053) — STOPPED at (c), 2026-09-18

Nothing has been written to the database in F17.2. Everything below is read-only measurement.

## STOP: the `synthetic-` rows are invented, all 46 of them

| Fact | Value |
|---|---|
| Rows with touch_id `synthetic-cr-<ref>` | 46 |
| touch_type / channel / send_status | Connection request / LinkedIn CR / **Sent** |
| Created | 2026-09-04, by the workbook migration (legacy_source `synthetic_cr_backfill`). That migration was run by me (Claude). This is my defect |
| Body, platform id, external_key, phantom_run_id | none on any row |
| What the row itself says | "Synthetic connection request backfilled at migration: the contact is connected but the workbook never logged the CR. **Date is the earliest known touch minus one day.**" |
| Rows with a real CR twin for the same contact | 0 |

So for every one of the 46: the EVENT is inferred (contact is connected, therefore a CR "must" have been
sent) and the DATE is fabricated (first touch minus one day). Nobody witnessed any of them.

Why the inference is unsafe, not merely undated:
- **4 contacts' earliest real touch is an inbound Reply** (P136, P154, P532, P538). A thread that starts with
  THEM writing is at least as consistent with the prospect connecting to Oliver as with Oliver sending a CR.
- **6 contacts have no other touch at all** (P033, P167, P543, P490, P542, P491). Their synthetic date is
  therefore not even "first touch minus one"; four of them are dated 2026-09-02, two days before the
  migration. Those dates come from nothing.
- 1 (P628) had its connection status set by the 2 September "Recently Accepted" import that F17.4 shows
  wrote a false Accepted for Pfeiffer. If that accept is false, the CR premise is false with it.
- Dhananjay Choubey, Revent (P303): synthetic 2026-08-30, first real touch an Initial message 2026-08-31.

What these rows corrupt today, because they read as ordinary Sent CRs:
- the CR funnel (46 invented CRs in "CRs sent", clustered on invented dates: 24 in May);
- CR weekly capacity for any week a synthetic date falls in (5 are dated in the last three weeks);
- sequence position and "first contact" dating for 46 contacts; cooldown and duplicate-approach windows
  start a day early; cr_accepted_at backfill (F16.5) and the funnel rebuild (F16.7) would inherit them.

**Decision needed from Brad (I have not acted):**
1. RECOMMENDED: keep the rows but take them out of every count and guard: mark
   `observed_or_inferred='inferred'`, move send_status Sent -> Cancelled (trigger-safe, reversible, logged),
   and make funnel/capacity/sequence read observed rows only. The fact "connected, CR never logged" survives
   as a note on the contact, not as a Sent touch.
2. Or delete them (I will not hard-delete without an explicit instruction).
3. Or leave them and only label them. I advise against: a label no reader checks changes nothing.

## (a) The count — done

Sent-or-Reply rows sharing contact + channel + date: **102 groups, 98 contacts, 127 surplus rows.**
That overstates duplication: a live conversation legitimately has several rows a day. Broken down:

| Shape | Groups |
|---|---|
| Different touch types same day (message + reply etc.) | 26 |
| Same type, one row EMPTY and one with a body (the listing-vs-opened-thread shape) | 62 empty rows, each with exactly ONE bodied keeper: 61 Initial message, 1 Connection request |
| Same type, both bodied, IDENTICAL text (true double log, e.g. Moeller 10 Sep) | 4 |
| Same type, both bodied, different text (needs a human: could be two real messages) | 6 |

Context the brief did not have: **537 Sent non-reply rows have no body at all.** Only 62 have a bodied
twin. The other 475 are empty and alone, so the merge pass cannot help them, and every guard that needs
thread text is blind on them.

Top 20 by row count (n / empty): Brunner (re)furbed DM 7 May 4/0; Polgár-Podonyi Magyar Telekom InMail
27 May 4/0; Schottenhammer T-Mobile InMail 14 Aug 4/0; van Vuurde bol.com InMail 20 Aug 4/0 — all four are
real back-and-forth, 4 distinct bodies. Then 3 rows each: Ferguson HMD, Jensen Foxway, Catindig-Stagg James
Green (1 empty), Serres Recommerce (Email), Höijer Foxway (2 `sup-` + T014), Greiner Revendo (2 `sup-` + T011,
identical text), and the 28 July InMail cluster with 2 empties each: Mergenthaler, Scherr (Jacob Elektronik),
Peretti, Hazi, Fleck (0815), Taelman (Forza), Steneby (Reuseit), Buehler (Conrad); Verdirk ZOXS (1 empty);
Rogat notebooksbilliger (inbox- + T701, T702).

The 28 July cluster confirms the suspected mechanism: one bodied InMail plus two empty rows per contact,
from three passes over the same Sales Navigator thread list.

**ID namespaces: there are 11, not 5.** T (905), agent (140), synthetic (46), chase- (26), sup- (8),
inbox- (8), reply- (3), cr-backfill (2), and singletons cr-014…, cc-202…, sn-see….

## (b) The cheap safe pass — DESIGNED, NOT RUN

Set: the 62 empty rows with exactly one same-contact/channel/date/type bodied keeper (0 ambiguous).
Method: no delete. Add `duplicate_of uuid`; on each empty row set duplicate_of = keeper, copy onto the
keeper any field it lacks (thread_id, thread_url, sent_at_actual, external_key), move the empty row
Sent -> Cancelled, and write before/after JSON for both rows to `touch_merge_log`. Expected visible effect:
Sent 847 -> 785, LinkedIn inMail down by about 60. I held this because it shares a migration and a
reader change with the synthetic decision above, and because it moves the dashboard numbers Oliver is
watching an hour before his call. Say "run (b)" and it runs as designed.

## (d) (e) (f) — not started

(d) `observed_or_inferred` backfill rule proposed: inferred = synthetic- and cr-backfill; observed = has
phantom_run_id / external_key / thread_id, or namespace agent/inbox-/reply-/chase-/sup-; T rows =
`migrated_unverified` (a third value: Oliver's workbook says so, no platform id). Needs Brad's yes on the
third value.
(e) "chaser 3 of 2" and (f) the inMail 315->314 / DM 191->192 channel rewrite: not yet investigated.
tg_audit_outreach_log exists on the table, so (f) should be answerable from audit_log in one query.

## i-number status
- i053: measured, mechanism confirmed, fix designed, NOT applied. Blocked on the synthetic decision.
