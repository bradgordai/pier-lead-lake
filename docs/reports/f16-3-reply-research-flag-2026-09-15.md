# F16.3 report — the research gate and replies (2026-09-15)

## Change (migration 104, default OFF)
team_settings.reply_ignores_research_gate boolean not null default false (a column; the settings row is one wide row). fn_evaluate_gates exempts p_requested = 'reply' from company_not_deep_researched only when the flag is true. Nothing else changed: initial_message, chaser, connection_request and cold email keep the research gate; promise_of_quiet, dnc_or_opted_out, contact_parked, pending_ruling, the F16.1 group guard and thread_text_missing still refuse replies, flag or no flag. Drafter v36 puts a visible note on any reply written for an unresearched company (narrative and first guardrail): "Company not deep researched: written from the conversation only".

## Dry run, flag off (nothing written), the six replied contacts at unresearched companies
| Contact | Company | Flag off | Flag on (derived) |
|---|---|---|---|
| Anca Popescu | Flip (Light triage) | group_sibling_engaged | still refused: Flip is linked to Rejoy.hu (engaged) |
| Benjamin Köhler | Smarando (Light triage) | company_not_deep_researched | draftable |
| Ishnav Thakooree | Dataxis (Untouched) | company_not_deep_researched | draftable (no outbound at all; the reply is the whole thread) |
| Kim Ulmer Koldby | TELEFUNKEN / Simmtronics (Light triage) | company_not_deep_researched | thread_text_missing (1 sent touch, no text) |
| Marco Stiemert | coolblue (Untouched) | company_not_deep_researched | draftable |
| Urs Moeller | coolblue (Untouched) | company_not_deep_researched | draftable |
Four become draftable with the flag on, not six. Under ten; nothing generated. Flag is off.

## Separate defect: Today shows three, the database holds six
All six pass v_replies_needing_answer's predicates (latest reply newer than latest sent message; status not consent-excluded; Köhler's Cooldown is NOT excluded). The view returns six. The predicate that hides three is in the Lovable Today block I specified in F15: rows with source = 'migrated' (every reply row migrated from the workbook) render in a collapsed "Migrated history" group. Popescu, Köhler and Stiemert are migrated-only; Thakooree, Koldby and Moeller are live and show in the open group. Verification through the UI as Oliver: Chrome access was refused in this session (auto-mode classifier), so this is proved from the view and the F15 spec, not a screenshot. Proposed change, not made: show every unanswered reply in one list with a "migrated" badge instead of collapsing; F16 says report first.

## Refusal counts by reason code
Before F16 (all time): company_not_deep_researched 1514, thread_text_missing 190, pending_ruling 41, dnc_or_opted_out 6, promise_of_quiet 3, group_sibling_engaged 0.
After F16.1 to F16.3 (measured next turn; the only writes to refusals in this batch come from the chase-engine dry runs, which write nothing, and from Oliver's live use).
