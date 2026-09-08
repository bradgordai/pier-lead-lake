-- 071: F10.1 (2026-09-08). Drafts were stamped sent_by = the requesting operator, so a draft
-- Brad regenerated for an Oliver-owned contact read "Brad" and signed "Brad". Messages dispatch
-- from Oliver's LinkedIn whatever the operator, so the sign-off is the OWNER's name and sent_by
-- belongs to dispatch only. created_by records who asked for the draft.
alter table public.outreach_log add column if not exists created_by text;
comment on column public.outreach_log.created_by is 'F10.1: who asked for this draft (operator display name or "agent"). sent_by is reserved for dispatch: the LinkedIn identity the message actually went out from.';
