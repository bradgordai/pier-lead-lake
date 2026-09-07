# F6 pre-handover punch list, 2026-09-07 (evening)

Per-task record. Repo commits reference this file; Lovable commits are recorded per task.

## F6.0 push
Repo was 10 commits ahead of origin; pushed 80c80ce..82ba911 to github.com/bradgordai/pier-lead-lake main.

## F6.4 content contamination sweep (both directions)
Workbook cells carried annotations inside message bodies. Sweep applied 2026-09-07 ~22:50 BST
against outreach_log, work table `f6_sweep_work` reviewed row by row first, then dropped.

Detection: leading `[...]` blocks (one or more), trailing `[...]` blocks (one or more, multi-line),
unterminated trailing `[...` paragraphs, a trailing `[YYYY-MM-DD] ...` line, a trailing
`--- CLASSIFICATION ---` section, and for inbound rows a trailing `CONTEXT:` section.
Five rows needed a manual split (T672 referral line, T841 and T845 quoted inbound text,
T226 and T700 have an inline placeholder bracket that is part of the sent text and were left alone).

| direction | rows corrected | notes |
|---|---|---|
| inbound (touch_type Reply) | 18 | reply_content re-pointed on 17 (was equal to the contaminated body) |
| outbound | 149 split + 5 AI-edit tags stripped + 3 annotation-only bodies nulled | 24 InMail subject lines moved from body line 1 into subject_line |

- sent_body rewritten on 153 rows so it holds only what was sent; sent_body = message_body on every row afterwards.
- 3 legacy DMs (T125, T130, T131) were annotation only ("[Soft-Welcome ... sent 12:02 today]"): body and sent_body set to NULL, so they now count as thread_text_missing like the other 557 textless legacy sends.
- Stripped text appended to 112 contacts' background_notes, each block stamped
  `[F6.4 sweep 2026-09-07: annotation moved out of touch Tnnn (date, type)]`.
- The 5 `[AI edit: ...]` tags on non-legacy drafts were stripped and logged but NOT copied to notes (edit instructions, not history).
- Every row logged to migration_audit run_id `pre-handover-2026-09-07`, phase `f6_4_contamination_sweep`,
  with old_body / new_body / annotation in detail (reversible). Actions: annotation_split_inbound 18,
  annotation_split_outbound 149, ai_edit_tag_stripped 5, annotation_only_body_nulled 3, inline_bracket_left 2.
- Examples: Marco Stiemert T944 now ends at "Beste Grüße, Marco"; Mario Opua T675 ends at "VG, Oliver",
  the BACKFILLED and Chaser #1 notes sit in his background notes.

## F6.1 pending count drift (third occurrence)
Lovable commit bb5f7048. Root cause: the Outreach Pulse "Pending review" tile counted raw draft_status rows
(71) while Today used the canon (67: contact not soft-deleted, company not archived).
- src/lib/pendingDrafts.ts now carries a boxed banner: EVERY pending count MUST come through
  fetchPendingReviewDrafts / countPendingReviewDrafts. New countPendingReviewDrafts(supabase, ownerFilter).
- Routed through the helper: Outreach tab badge, Pulse tile + collapsed summary, Pulse volume bar
  (archived rows dropped), the Pending Review tab LIST itself (total = canon), Automation Health
  "Drafts to approve" (its old exemption removed), Today action-queue cards.
- Audit of the rest of the tree: remaining pending_review mentions are enums, pills, filters and the
  thread views' "hide unsent draft" predicate, not counts.

## F6.6 drafter context + F6.7b AI-maintained conversation notes (backend)
- Migration 064 adds contacts.conversation_summary (text). Format: operator bullets, then the marker line
  `--- AI state of play (auto-maintained, edit above this line) ---`, then AI bullets. Automation only
  ever rewrites the block below the marker (supabase/functions/_shared/conversation-summary.ts).
- generate-draft-from-context v28: CONTACT NOTES block in the user prompt (next_action + due date,
  background_notes, operator conversation notes, AI state of play) with the two rules stated in the prompt
  text: gates always override notes; note dates matter (past-dated instructions are history). Also in the
  drafting directive. Model now returns state_of_play[]; after the draft row is inserted the AI section of
  conversation_summary is refreshed (non-fatal on failure).
- ai-edit-draft v3: same CONTACT NOTES block and rule in the edit directive. Read-only, does not write notes.
- capture-and-classify-reply v15: CONTACT NOTES block in the classification prompt, state_of_play[] in the
  JSON, AI section refreshed after classification (stamp "date, reply classified: <class>").
- Neither drafter previously included next_action or background_notes at all, so F6.6 was an add, not a verify.

## F6.2 Contacts archived toggle
Lovable commit 8056c204. Migration 065 adds contacts.company_archived_at, a trigger-maintained mirror of
companies.archived_at (before insert/update of company_id on contacts; after update of archived_at on
companies; backfilled: 142 live contacts sit under archived companies, 536 remain in the default view).
- Default Contacts list, pulse, total count, country / company-name / SN-list option lists all add
  `company_archived_at is null`; the "Archived only" switch (toolbar, after saved views, same as Companies)
  flips it to `is not null`. Coverage tile reads "N of M archived" when on.
- Deep link from a company page (?company=) skips the exclusion so an archived company's contacts still list.
- Archived rows: bg-primary/10 tint, sticky Name cell opaque + pseudo-element tint, outline badge with the
  reason ("Moved to Monday", "Out of scope", else the raw reason), delete hidden. Contact detail header shows
  "Company archived: <reason>".

## F6.3 Refused tab upgrades
Lovable commit 1456ffa0. refusalsListFn now passes the latest row's gate `context` through (latest-per-contact
collapse unchanged). Refused tab label carries a badge = distinct contacts refused in the default 7-day window.
Cards are clickable (button semantics, Enter/Space) and expand to: full reason + code chip, requested/channel,
first refused and last refused (d LLL yyyy HH:mm), days running, previous reason, gate context rendered as a
humanised key/value grid (dates formatted, booleans yes/no, nested JSON in a small pre), and "Open contact" /
"Open company" buttons. Name links stop propagation so they never toggle the card.
