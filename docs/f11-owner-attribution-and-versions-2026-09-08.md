# F11 (2026-09-08, 15:25-15:45): owner-only attribution, every Save is a version, replies are terminal

Lovable commit 45674b24, published. Migration 072. ai-edit-draft v5, capture-and-classify-reply v19.

## F11.1 Admin actions render as the owner
Every sales-process surface (draft editor chip, conversation panels, the history trail, the
contact Outreach tab) attributes drafts and actions to the contact OWNER, resolved from
owner_user_id; with no owner, nothing is shown. The operator's name never renders. An unsent
draft in a conversation-style panel reads "Draft" with the pending chip, never author-styled.
created_by stays in outreach_log and draft_revisions as the internal audit trail only.

## F11.2 Every Save is a version
draft_revisions gained `source` ('original' | 'ai_edit' | 'manual_save' | 'restore'), migration
072; existing revision-0 rows were relabelled 'original'. ai-edit-draft v5 stamps its rows.
The app (src/lib/queries/revisionSnapshot.ts) snapshots the CURRENT body into draft_revisions
before any body write: revision 0 'original' when the touch has no revisions yet, else
max+1 'manual_save'. restoreDraftRevisionFn snapshots the current body as 'restore' first,
then swaps in the chosen version, so a restore is itself undoable.
Touch popout: one "Previous drafts" accordion under Conversation (collapsed, count in the
header), newest first, merging draft_revisions (Saved edit / AI edit with its instruction /
Restored / Original) with superseded and rejected rows for the same contact and touch type
(Regenerated / Rejected), each with an expandable body and "Restore this version".
The separate "AI edit revisions" and "Draft history" sections are gone.

## F11.3 Inbound replies are terminal
capture-and-classify-reply v19 files inbound replies with draft_status 'sent' (the same terminal
status every migrated Reply row carries), never 'pending_review'. Ishnav Thakooree's and Kim
Ulmer Koldby's reply rows are 'sent'; the pending-review count holds 0 Reply rows (70 pending
rows in total, none of them replies).

## Verification
Server side, by reading the shipped code: the snapshot runs before the update, the restore
snapshots first, revision numbering is max+1 under the unique (outreach_log_id, revision_number)
key. The click-through (save twice, both versions listed, restore round-trips, regenerate
appears in the same list, no operator name anywhere) is Brad's: the app is password-gated and
I do not sign in. Query to confirm after Brad's test:
  select revision_number, source, created_at, left(message_body, 60) from draft_revisions
   where outreach_log_id = '<touch id>' order by revision_number;
