-- 080: F12 T9 (2026-09-09). Realtime on the two tables the Outreach and Today surfaces watch.
alter publication supabase_realtime add table public.outreach_log;
alter publication supabase_realtime add table public.contacts;
