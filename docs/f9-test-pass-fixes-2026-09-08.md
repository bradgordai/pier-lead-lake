# F9: fixes from Brad's test pass (2026-09-08 afternoon)

Status: shipped. Drafter generate-draft-from-context v29 -> v31, migration 070. Lovable commit
8f6c2407, published. Repo commits listed at the end.

## F9.1 Popout header overlap (Lovable)
Every popout header (touch, contact, company) is now a two-column flex row: name + company on
the left (min-w-0, truncated with a title tooltip), controls on the right (shrink-0, wrapping
onto a second line on narrow widths). No absolute positioning.

## F9.2 Search (Lovable)
(a) Global search and the Contacts page search no longer drop archived contacts or contacts at
archived companies; they appear with the archive badge. Mika Seppänen (Swappie, company
archived 4 Sep) and Adrien Serres (Recommerce Group, company archived 4 Sep) are findable again.
Search is not owner-scoped. (b) The dropdown hover state is a light fill with readable text.

## F9.3 Contact popout Outreach tab (Lovable)
Third tab "Outreach": the contact's outreach rows grouped Pending / Approved / Sent /
Refused-Rejected with the DRAFT · <language> label and the row actions, a Generate / Regenerate
button whose result renders inline (draft card, refusal card with reason, or error), and the
contact's recent refusals from public.refusals.

## F9.4 Regenerate reliability
Diagnosis (Adrien Serres). Both of Brad's clicks reached the drafter (refusals table, 11:16:10
and 11:16:31) and were refused: "Recommerce Group is archived, so this contact is out of scope"
(reason_code dnc_or_opted_out). The Lovable server function fired the edge function with
Promise.allSettled and returned { ok: true } without reading the response, so the refusal was
never shown and the UI said "will appear once the agent finishes" forever. A second silent
path: a manual regenerate for a contact with an existing pending draft hit the dedup guard and
returned dedup_skipped, also discarded. A third: trigger "manual_regenerate" was not in the
trigger map and fell through to the CR-accepted opener, so regenerating a chaser or follow-up
produced an opener.

Fix. Drafter v29-v31: manual_regenerate honours body.touch_type; without it, the next cadence
step is resolved from what has actually gone out (replied -> follow-up; nothing sent -> opener;
opener sent -> chaser 1; chaser n -> chaser n+1). A manual regenerate supersedes the existing
pending agent draft (rejection_feedback.reason = "regenerated") instead of being deduped away.
Lovable: regenerateDraftsFn awaits and parses every response and returns a result per contact
(created / refused / dedup_skipped / budget_exceeded / generation_failed / error); every caller
shows a loading toast and then always resolves visibly: new draft, inline refusal card with
the reason, or an error toast. The placeholder text is gone.

Note for Oli: Adrien's refusal is correct as the data stands. Recommerce Group was archived by
the 4 Sep migration; if that is wrong, unarchive the company and Regenerate will produce a
follow-up in English (see F9.5).

## F9.5 Draft language
(a) Label. New columns outreach_log.draft_language and draft_language_reason (migration 070).
The drafter detects the language of the generated body (stop-word detector, EN/DE/FR/NL/ES/IT/FI)
and records it; the label reads that, never the contact's Language field. Older drafts without
the column fall back to the same detector client-side (src/lib/draftLanguage.ts).
(b) Selection order, now explicit in resolveTargetLanguage and logged as language_resolved:
  1. the prior thread: the contact's own replies first, then our SENT messages, most recent
     first (an unsent draft is not evidence, fixed in v30);
  2. the contact's Language field;
  3. the market default for the company's country (EA rule), else EN.
The chosen language and reason go into the prompt ("WRITE IN German (DE). Reason: ...") and
onto the row. If the body comes back in a different language the label follows the body and
the reason records the mismatch.

## F9.6 Sign-off
ensureSignOff runs after generation: if the last two non-empty lines do not contain the
sender's first name as a whole word, "\n\n<sender>" is appended and sign_off_appended is logged.

## Verification (dry runs, no rows written)
| contact | result |
|---|---|
| Adrien Serres | refused, dnc_or_opted_out, "Recommerce Group is archived" (returned to the caller, now rendered) |
| Florian Pfeiffer | DE, reason "contact_language" (no sent messages, contact Language DE). Body German. Sign-off appended: the model again ended on the question, the check added "Oli". v29 had picked EN from his unsent English draft; v30 fixed that. |
| Lukas Steimer | DE, reason "prior_thread: our message of 2026-08-20 is DE". Body German, sign-off present natively. |

UI screenshots: not taken. The app is password-gated and I do not enter credentials; Brad's
own pass is the visual check for F9.1-F9.3.

## Commits
6ab963e drafter v29 + migration 070; 1665c6d v30; v31 + docs in the following commits.
