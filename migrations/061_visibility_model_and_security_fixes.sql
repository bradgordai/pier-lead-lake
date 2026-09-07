-- 061: A2 visibility model + A3 security fixes (applied 2026-09-04). Full text.
ALTER TABLE public.team_settings ADD COLUMN IF NOT EXISTS members_see_all_leads boolean NOT NULL DEFAULT true;
UPDATE public.team_settings SET members_see_all_leads = true;
COMMENT ON COLUMN public.team_settings.members_see_all_leads IS
  'Oli 2026-09-04: data tabs (Companies, Contacts, Insights, Reconciliation, Archive) show ALL leads to every member. Work surfaces (Today queues/alerts, Outreach draft and task queues) filter to owner_user_id = self for members; admins see all with an owner toggle.';

UPDATE public.team_members tm SET role = 'admin'
FROM auth.users u WHERE u.id = tm.user_id AND u.email = 'bradleyg@naileditai.com';
UPDATE public.team_members tm SET role = 'member'
FROM auth.users u WHERE u.id = tm.user_id AND u.email IN ('oliver.muller@pierinsurance.com','jack.stevens@pierinsurance.com');

CREATE OR REPLACE FUNCTION public.fn_task_scope()
RETURNS TABLE (user_id uuid, team_id uuid, role text, is_admin boolean, members_see_all_leads boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT tm.user_id, tm.team_id, tm.role, (tm.role = 'admin') AS is_admin,
         coalesce(ts.members_see_all_leads, true)
  FROM public.team_members tm
  LEFT JOIN public.team_settings ts ON ts.team_id = tm.team_id
  WHERE tm.user_id = (SELECT auth.uid());
$$;
GRANT EXECUTE ON FUNCTION public.fn_task_scope() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_task_scope() FROM anon;

-- A3.1 / A3.2 CRITICAL: reference tables were readable by ANY signed-in user of any project.
DROP POLICY IF EXISTS eurefas_members_select ON public.eurefas_members;
CREATE POLICY eurefas_members_select ON public.eurefas_members
  FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.fn_user_teams()));
DROP POLICY IF EXISTS pier_pipeline_select ON public.pier_pipeline;
CREATE POLICY pier_pipeline_select ON public.pier_pipeline
  FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.fn_user_teams()));

-- A3.3 SECURITY DEFINER functions: fn_capture_dq_snapshot cron-only; fn_user_teams stays (RLS depends on it).
REVOKE EXECUTE ON FUNCTION public.fn_capture_dq_snapshot(uuid) FROM authenticated, anon;
COMMENT ON FUNCTION public.fn_user_teams() IS
  'SECURITY DEFINER by design: RLS policies call it in the caller''s context and it returns only the caller''s own team ids (auth.uid()). Must stay executable by authenticated. Reviewed 2026-09-04.';
COMMENT ON FUNCTION public.fn_capture_dq_snapshot(uuid) IS
  'SECURITY DEFINER, cron-only since 061 (EXECUTE revoked from authenticated/anon). Re-grant deliberately if a user-facing refresh button is ever added.';

-- A3.4 mutable search_path on our own functions
ALTER FUNCTION public.fn_evaluate_gates(uuid, uuid, text, text) SET search_path = public, pg_temp;
ALTER FUNCTION public.fn_chase_candidates(uuid, integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.fn_chase_exhausted(uuid, integer) SET search_path = public, pg_temp;

-- Migration helpers are done; drop them.
DROP FUNCTION IF EXISTS public.mig_clean(text), public.mig_date(text), public.mig_num(text), public.mig_int(text),
  public.mig_seniority(text), public.mig_function(text), public.mig_connlevel(text), public.mig_formality(text),
  public.mig_language(text), public.mig_connstatus(text), public.mig_outreachstatus(text), public.mig_priority(text),
  public.mig_research(text), public.mig_opportunity(text), public.mig_industry(text), public.mig_productline(text),
  public.mig_owner(text), public.mig_insstructure(text), public.mig_category(text), public.mig_channel(text),
  public.mig_bool(text), public.mig_touchtype(text, text), public.mig_outcome(text);
