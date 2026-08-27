-- B6 sourcing queue + B8 team settings and shared capacity. See DB for full applied text.
CREATE TABLE IF NOT EXISTS public.sourcing_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  task_type text NOT NULL CHECK (task_type IN ('source_contacts','verify_insurance','missing_country','missing_sn_url')),
  detail text, assigned_to uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','done','dismissed')),
  source text, created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS idx_sourcing_queue_open ON public.sourcing_queue (team_id, status, created_at DESC) WHERE status = 'open';
ALTER TABLE public.sourcing_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sourcing_queue_team_read ON public.sourcing_queue;
CREATE POLICY sourcing_queue_team_read ON public.sourcing_queue FOR SELECT USING (team_id IN (SELECT fn_user_teams()));
DROP POLICY IF EXISTS sourcing_queue_team_write ON public.sourcing_queue;
CREATE POLICY sourcing_queue_team_write ON public.sourcing_queue FOR INSERT WITH CHECK (team_id IN (SELECT fn_user_teams()));
DROP POLICY IF EXISTS sourcing_queue_team_update ON public.sourcing_queue;
CREATE POLICY sourcing_queue_team_update ON public.sourcing_queue FOR UPDATE
  USING (team_id IN (SELECT fn_user_teams())) WITH CHECK (team_id IN (SELECT fn_user_teams()));

CREATE TABLE IF NOT EXISTS public.team_settings (
  team_id uuid PRIMARY KEY REFERENCES public.teams(id) ON DELETE CASCADE,
  weekly_cr_target int DEFAULT 80, weekly_dm_cap int DEFAULT 15,
  monthly_inmail_grant int DEFAULT 50, inmail_balance_cap int DEFAULT 150,
  chaser_cap int DEFAULT 2, chase_interval_days int DEFAULT 7, cooldown_days int DEFAULT 90,
  updated_at timestamptz NOT NULL DEFAULT now());
INSERT INTO public.team_settings (team_id) VALUES ('ef73c15e-4d6f-4159-bcfa-cc76b5ae4972') ON CONFLICT (team_id) DO NOTHING;
ALTER TABLE public.team_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS team_settings_team_read ON public.team_settings;
CREATE POLICY team_settings_team_read ON public.team_settings FOR SELECT USING (team_id IN (SELECT fn_user_teams()));

-- Lead Lake and Monday drive the SAME LinkedIn account, so neither alone knows true spend.
CREATE TABLE IF NOT EXISTS public.shared_capacity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  as_of date NOT NULL, source text NOT NULL,
  crs_sent_week int, inmails_sent_week int, dms_sent_week int, inmail_credits_remaining int,
  detail jsonb, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (team_id, as_of, source));
ALTER TABLE public.shared_capacity ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS shared_capacity_team_read ON public.shared_capacity;
CREATE POLICY shared_capacity_team_read ON public.shared_capacity FOR SELECT USING (team_id IN (SELECT fn_user_teams()));

COMMENT ON TABLE public.shared_capacity IS
  'Combined LinkedIn spend across Lead Lake and Monday (same account). Today widgets read source=combined when present, else live queries.';
