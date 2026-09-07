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
