-- 051_security_audit_findings_rls.sql
-- Formalises the hotfix applied live on 2026-09-02. The repo did not match production:
-- 041 created public.security_audit_findings with no RLS and no grant management, so the
-- table was readable via PostgREST by anon and authenticated. RLS was enabled and the
-- anon/authenticated grants revoked directly against production that morning; this file
-- captures those statements so a rebuild from migrations reproduces the fixed state.
--
-- Verified against production before writing (2026-09-02):
--   relrowsecurity = true          RLS already enabled by the hotfix
--   policy count   = 0             no policy was ever created
--   grants         = postgres, service_role only   anon/authenticated already revoked
--   rows           = 9
--
-- WHAT IS ACTUALLY PROTECTING THIS TABLE, precisely:
-- The protection comes from the two statements below that enable RLS and revoke the
-- grants, NOT from the policy. With RLS enabled and no policy, every non-superuser,
-- non-BYPASSRLS role sees zero rows regardless of grants. service_role has BYPASSRLS, so
-- it reads and writes this table whether or not a policy exists.
--
-- The policy is therefore defence in depth and documentation of intent, not the mechanism.
-- It is worth having: if someone later re-grants SELECT to authenticated (an easy mistake,
-- and exactly how 041 shipped), the explicit policy keeps the table closed instead of
-- silently depending on there being no policy at all. An empty-policy table is secure by
-- accident; a policy that names service_role is secure on purpose.
--
-- Every statement is idempotent so this replays cleanly over the already-hotfixed database.

ALTER TABLE public.security_audit_findings ENABLE ROW LEVEL SECURITY;

-- Belt and braces: the hotfix already did this, but a fresh rebuild from 041 would not.
REVOKE ALL ON public.security_audit_findings FROM anon;
REVOKE ALL ON public.security_audit_findings FROM authenticated;

DROP POLICY IF EXISTS security_audit_findings_service_role_only
  ON public.security_audit_findings;

CREATE POLICY security_audit_findings_service_role_only
  ON public.security_audit_findings
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE public.security_audit_findings IS
  'Security audit run summaries. service_role only: written by audit tooling, never exposed '
  'to anon or authenticated. RLS enabled with a single service_role policy (051).';
