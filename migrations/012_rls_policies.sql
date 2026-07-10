-- Migration 012: RLS policies
-- Section 12 of pier-supabase-migration-spec.md
-- Enable RLS on every table, then team-scoped policies with (SELECT auth.uid())
-- wrapping. Service role bypasses RLS by default; do NOT create policies that
-- expand access via the anon key.

-- ---------------------------------------------------------------------------
-- Enable RLS on every table
-- ---------------------------------------------------------------------------
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outreach_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pier_pipeline ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eurefas_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurance_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_handover ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nightly_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_errors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocklist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drafts_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.duplicate_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insights_snapshots ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Helper: is user a member of this team?
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_user_teams()
RETURNS TABLE (team_id UUID) AS $$
  SELECT tm.team_id FROM public.team_members tm WHERE tm.user_id = (SELECT auth.uid());
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ---------------------------------------------------------------------------
-- Team-scoped policies (SELECT / INSERT / UPDATE / DELETE) for every table
-- with a team_id column.
-- ---------------------------------------------------------------------------

-- Companies
CREATE POLICY companies_select ON public.companies FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY companies_insert ON public.companies FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY companies_update ON public.companies FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY companies_delete ON public.companies FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Contacts
CREATE POLICY contacts_select ON public.contacts FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY contacts_insert ON public.contacts FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY contacts_update ON public.contacts FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY contacts_delete ON public.contacts FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Outreach Log
CREATE POLICY outreach_log_select ON public.outreach_log FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY outreach_log_insert ON public.outreach_log FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY outreach_log_update ON public.outreach_log FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY outreach_log_delete ON public.outreach_log FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Pier Pipeline
-- DEVIATION FROM SPEC: section 4 defines pier_pipeline WITHOUT a team_id column
-- (a global "read-only reference" table), but section 12 lists it among the
-- team-scoped tables. Those two statements contradict. Per Brad's decision we
-- treat it as a global reference table: RLS on, SELECT for any authenticated
-- user, no team scoping and no write policies (writes via service role only).
CREATE POLICY pier_pipeline_select ON public.pier_pipeline FOR SELECT USING ((SELECT auth.uid()) IS NOT NULL);

-- EUREFAS Members
-- DEVIATION FROM SPEC: same contradiction as pier_pipeline. Treated as a global
-- read-only reference table.
CREATE POLICY eurefas_members_select ON public.eurefas_members FOR SELECT USING ((SELECT auth.uid()) IS NOT NULL);

-- Insurers
CREATE POLICY insurers_select ON public.insurers FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY insurers_insert ON public.insurers FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY insurers_update ON public.insurers FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY insurers_delete ON public.insurers FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Insurance Products
CREATE POLICY insurance_products_select ON public.insurance_products FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY insurance_products_insert ON public.insurance_products FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY insurance_products_update ON public.insurance_products FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY insurance_products_delete ON public.insurance_products FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Agent Handover
CREATE POLICY agent_handover_select ON public.agent_handover FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY agent_handover_insert ON public.agent_handover FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY agent_handover_update ON public.agent_handover FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY agent_handover_delete ON public.agent_handover FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Nightly Summary
CREATE POLICY nightly_summary_select ON public.nightly_summary FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY nightly_summary_insert ON public.nightly_summary FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY nightly_summary_update ON public.nightly_summary FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY nightly_summary_delete ON public.nightly_summary FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Agent Errors
CREATE POLICY agent_errors_select ON public.agent_errors FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY agent_errors_insert ON public.agent_errors FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY agent_errors_update ON public.agent_errors FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY agent_errors_delete ON public.agent_errors FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Blocklist
CREATE POLICY blocklist_select ON public.blocklist FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY blocklist_insert ON public.blocklist FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY blocklist_update ON public.blocklist FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY blocklist_delete ON public.blocklist FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Drafts Feedback
CREATE POLICY drafts_feedback_select ON public.drafts_feedback FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY drafts_feedback_insert ON public.drafts_feedback FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY drafts_feedback_update ON public.drafts_feedback FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY drafts_feedback_delete ON public.drafts_feedback FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Duplicate Candidates
CREATE POLICY duplicate_candidates_select ON public.duplicate_candidates FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY duplicate_candidates_insert ON public.duplicate_candidates FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY duplicate_candidates_update ON public.duplicate_candidates FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY duplicate_candidates_delete ON public.duplicate_candidates FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Saved Views
CREATE POLICY saved_views_select ON public.saved_views FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY saved_views_insert ON public.saved_views FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY saved_views_update ON public.saved_views FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY saved_views_delete ON public.saved_views FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Insights Snapshots
CREATE POLICY insights_snapshots_select ON public.insights_snapshots FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY insights_snapshots_insert ON public.insights_snapshots FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY insights_snapshots_update ON public.insights_snapshots FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY insights_snapshots_delete ON public.insights_snapshots FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- ---------------------------------------------------------------------------
-- teams / team_members: identity tables, membership-based SELECT
-- ---------------------------------------------------------------------------

-- teams table: user reads teams they belong to
CREATE POLICY teams_select ON public.teams FOR SELECT USING (id IN (SELECT team_id FROM public.fn_user_teams()));

-- team_members: user reads their own memberships and other members of their teams
CREATE POLICY team_members_select ON public.team_members FOR SELECT USING (
  user_id = (SELECT auth.uid())
  OR team_id IN (SELECT team_id FROM public.fn_user_teams())
);
