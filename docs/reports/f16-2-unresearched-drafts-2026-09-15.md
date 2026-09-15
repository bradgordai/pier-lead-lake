# F16.2 report — how 22 drafts reached unresearched companies (2026-09-15)

Re-measured: 19 drafts now sit at companies not at Deep research done (the 3 Save Group Chase rows were parked in F16.1).

## (a) System-made vs migrated
- 17 were made by this system's drafter (touch_id agent-..., agent_produced true), created 25 Aug to 4 Sep, created_by 'agent' (3) or 'Oli' (14, the Lovable Generate button). Every one predates migration 055_refusal_gates, applied 2026-09-03 23:04 UTC, which introduced company_not_deep_researched; the first refusal with that code is 2026-09-03 23:04. Before 055 there was no research gate to reach. The one exception by date, Catherine Meng @ Ecodair (Chaser 1, 4 Sep, already rejected), was drafted while Ecodair was Deep research done; Ecodair was moved to Outdated on 9 Sep.
- 2 are workbook rows: Florian Kasper @ notebooksbilliger.de AG (T290, pending_review) and Vladimir Amstislavski @ Firstcom Trading (T294, rejected), legacy_source excel_wb_20260902_unsent_draft.
- Conclusion: the gate is intact; the data is pre-gate. Hypothesis two (Generate/Regenerate bypass) is not it: those buttons call the drafter, which has run the gates since 055; F15.2 corrected routing, not gating.

## (b) Urs Moeller's 10 September send
Draft created 2 Sep 19:04 by the drafter (pre-gate, coolblue Untouched). Approved and sent 10 Sep 11:36 to 11:40 through send-approved-draft (phantom 2590889123414802), callback send_completed 11:40:41. coolblue's company record was edited 15 times between 11:39 and 11:40 that day (audit_log), i.e. during the send.

## (c) Does the send path call the gates today?
No. send-approved-draft, send-approved-callback and ai-edit-draft contain no call to fn_evaluate_gates (grep, 0 hits each). Gates run at DRAFT time only. A draft that predates a gate, or a company whose state changes after drafting, is sent without re-evaluation. No dry-run mode exists on send-approved-draft, so this is proved from source, not by a run. Proposed fix (not done, F16.2 says report first): re-run fn_evaluate_gates inside send-approved-draft before dispatch and refuse with the reason.

## (d) Everything through that path while it was open
46 agent drafts were created before 055 landed. 18 of them sit at companies that are not deep researched today: 16 pending_review, 1 Cancelled/superseded, 1 Sent. The one send is Moeller, 10 Sep. No other pre-gate draft to an unresearched company was sent.

## (e) Consent check
Pre-gate drafts to consent-protected contacts: 5, all Cancelled, never sent (Mayerthaler @ A1 DNC; Kaminski and Windischhofer @ (re)furbed archived; Stapelfeldt and Siebel @ MediaMarkt Saturn promise_of_quiet). Agent-produced SENT rows on parked/archived contacts: 4, but all are touch_type Other, channel Other, dated 4 Sep, phantom null: migration-day register rows, not messages (Rubinski x2 @ Janado, Kügel @ Conrad, Lau @ Swappie). Nothing sent by this system reached a contact carrying promise_of_quiet, DNC, parked or archived status. No STOP.

## Not done
The 19 drafts were not cancelled. Recommendation: cancel the 16 pending pre-gate ones with reason company_not_deep_researched (they will be refused if regenerated) and leave T290 for Oliver.
