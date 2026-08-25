-- 035_daily_insights.sql
-- Task 9 (UX sweep): "Yesterday's Work" — a Sonnet-generated daily narrative of
-- what happened in the CRM the previous working day. One row per team per day;
-- regenerated (upserted) by the generate-daily-insight Edge Function on a weekday
-- cron and on-demand via the /today Refresh button (1-hour cooldown enforced in UI
-- off generated_at).

CREATE TABLE IF NOT EXISTS public.daily_insights (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id       uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  insight_date  date NOT NULL,                 -- the day being summarised (yesterday)
  headline      text,
  content       jsonb NOT NULL DEFAULT '{}'::jsonb,  -- { date, headline, sections{...}, priority_flags[], queue_recommendations[] }
  model         text,
  generated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (team_id, insight_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_insights_team_date
  ON public.daily_insights(team_id, insight_date DESC);

ALTER TABLE public.daily_insights ENABLE ROW LEVEL SECURITY;

CREATE POLICY di_select ON public.daily_insights
  FOR SELECT USING (team_id IN (SELECT team_id FROM fn_user_teams()));
