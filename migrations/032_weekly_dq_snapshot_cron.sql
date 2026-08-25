-- Migration 032: weekly data-quality snapshot cron
--
-- Schedules fn_capture_dq_snapshot (migration 024) to run every Monday morning so the
-- Insights "Data quality trend" chart builds a weekly history without anyone clicking
-- "Take snapshot now".
--
-- Timing: pg_cron schedules in UTC. '0 7 * * 1' fires Monday 07:00 UTC, which is
-- 08:00 Europe/London during BST (summer) and 07:00 during GMT (winter) — always
-- Monday morning London. The exact hour does not matter for correctness: the function
-- stamps snapshot_date using (now() AT TIME ZONE 'Europe/London')::date and upserts
-- ON CONFLICT (team_id, snapshot_date), so it always records the right Monday and is
-- safe to run more than once.
--
-- Scope: one snapshot per team (currently just the Pier team). Looping over teams keeps
-- this correct if more teams are ever added, with no hardcoded id.

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- cron.schedule upserts by job name, so re-applying this migration is idempotent.
SELECT cron.schedule(
  'weekly-dq-snapshot',
  '0 7 * * 1',
  $$ SELECT public.fn_capture_dq_snapshot(id) FROM public.teams; $$
);
