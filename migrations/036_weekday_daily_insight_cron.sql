-- 036_weekday_daily_insight_cron.sql
-- Task 9 (UX sweep): generate "Yesterday's Work" every weekday morning.
-- Mon-Fri 08:00 UTC -> POSTs generate-daily-insight, which summarises the previous
-- day and upserts daily_insights. The /today Refresh button regenerates on demand.
--
-- NOTE: needs ANTHROPIC_API_KEY in the Edge Function env (already set for the other
-- Sonnet functions). pg_net is enabled by migration 034.
--
-- APPLY THIS YOURSELF in the Supabase SQL editor: applying it from the agent is
-- blocked by the safety classifier because it embeds the shared secret and makes an
-- outbound pg_net call from the database (same as migration 034).

SELECT cron.schedule(
  'weekday-daily-insight',
  '0 8 * * 1-5',
  $$
  SELECT net.http_post(
    url := 'https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/generate-daily-insight',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <PASTE_MAKE_SHARED_SECRET_HERE_BEFORE_RUNNING>'
    ),
    body := jsonb_build_object('force', false)
  );
  $$
);
