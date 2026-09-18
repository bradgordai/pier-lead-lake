# F17.4 A connection marked Accepted that was never accepted (i094) — 2026-09-18

## The cause is not "absence from a list". It is a SURNAME MATCH.
Pfeiffer's own Next Action note says: "Veronika Pfeiffer is NOT P706 Florian Pfeiffer - that wrong
name-match was refused once already. This flip is on the row that actually bears her name." Veronika
Pfeiffer (P307, Nex Event) is in the Lake and is Accepted. She accepted; the flip landed on Florian anyway.
The writer was the 2 September WORKBOOK correction session (legacy_source excel_wb_20260902), carried in
by the 4 Sep migration. It is not a code path in this repo.

(a) Records written by that import: **3, not more** (searched contacts.next_action and the full audit_log
history of next_action): P706 Pfeiffer, P628 van Vuurde (bol.com), P703 Moeller (coolblue). The note
speaks of "four"; the fourth is not identifiable in the Lake. File for Oliver:
docs/reports/f17-4-oliver-connection-recheck-list-2026-09-18.md. It goes wider than the 3, because the
consistency check in (d) found the same shape elsewhere: **17 contacts are Accepted but not 1st degree**,
four of them with an APPROVED DM draft waiting (Lohmar/Tchibo, Pfaller and Karl/Drei, Petrovic/Galaxus).
(b) Pfeiffer corrected: Request sent, 2nd degree, source `manual_verified_salesnav:oliver_2026-09-17`,
evidence text on the row, misleading Next Action replaced. His only open DM draft was already rejected.
(c) The live writer, update-contact-on-cr-accepted, matches on linkedin_slug then linkedin_url, never on
name, and only fires on a positive Recently Connected event. It was already correct. The guard added is in
the data: any change of connection_status is now stamped, and a writer that does not name its source is
recorded as `unattributed:<role>`, which the conflict view reports. NOT DONE: a hard refusal of an
unattributed Accepted. It would break Lovable's manual status edit today; it needs Lovable to send a source.
(d) `v_contact_state_conflicts` (live): accepted_but_never_messaged 29, accepted_without_positive_signal 22,
connected_but_not_1st_degree 17, 1st_degree_but_not_connected 4. Not yet shown in the UI.
(e) contacts.connection_status_source / _at / _evidence added and backfilled (workbook rows attributed to the
workbook, not to a platform signal). Side effect: the backfill touched every contact row, so updated_at
and audit_log carry a bulk write at about 12:30 BST today.

## Open risk to raise with Oliver today
send-approved-draft and the routing matrix trust connection_status alone. For the four starred contacts a
"DM" would be launched at someone Sales Navigator may show as 2nd or 3rd degree. PhantomBuster would fail
or, worse, behave unpredictably. Do not bulk-send those four until section B of the list is checked.

## i-number status
- i094: Pfeiffer fixed, cause identified (surname match in the workbook session), source/date/evidence on
  connection state, conflict view live, re-check list written. Hard guard and UI surfacing outstanding.
