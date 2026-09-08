-- 070: F9.5 (2026-09-08). The DRAFT · XX label showed the contact's language, not the draft's.
-- The drafter now records the language it targeted (and why) and the language it detected in
-- the generated body, so the label reflects the actual draft.
alter table public.outreach_log add column if not exists draft_language text;
alter table public.outreach_log add column if not exists draft_language_reason text;
comment on column public.outreach_log.draft_language is 'F9.5: language of the draft body as detected after generation (ISO-639-1 upper, e.g. EN/DE/FR). The DRAFT label must show this, not the contact language.';
comment on column public.outreach_log.draft_language_reason is 'F9.5: why the drafter chose its target language: prior_thread | contact_language | market_default, plus a note when the detected body language differed.';
