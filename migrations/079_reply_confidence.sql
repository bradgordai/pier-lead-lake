-- 079: F12 T7 (2026-09-09). The classifier already computes a confidence and a reasoning and
-- discarded both. Persisted on the reply row; status elevation gated on confidence.
alter table public.outreach_log add column if not exists reply_confidence smallint check (reply_confidence is null or (reply_confidence between 0 and 100));
alter table public.outreach_log add column if not exists reply_reasoning text;
comment on column public.outreach_log.reply_confidence is 'F12 T7: classifier confidence 0-100. Elevation to In conversation requires >= the threshold in capture-and-classify-reply (70).';
