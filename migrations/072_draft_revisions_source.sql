-- 072: F11.2 (2026-09-08). Every Save is a version. draft_revisions already held AI-edit
-- revisions; manual saves and restores now snapshot into the same table, so a source column
-- says how each revision came to be. Attribution never renders (F11.1): created_by stays as
-- the internal audit trail only.
alter table public.draft_revisions add column if not exists source text not null default 'ai_edit';
alter table public.draft_revisions drop constraint if exists draft_revisions_source_check;
alter table public.draft_revisions add constraint draft_revisions_source_check check (source in ('original','ai_edit','manual_save','restore'));
comment on column public.draft_revisions.source is 'F11.2: how this revision came to be. original = the body before the first edit; ai_edit = ai-edit-draft; manual_save = operator saved the editor; restore = operator restored an earlier version (the displaced body is snapshotted first).';
update public.draft_revisions set source = 'original' where revision_number = 0 and edit_instruction is null;
create index if not exists draft_revisions_log_created_idx on public.draft_revisions (outreach_log_id, created_at desc);
