-- 042_revoke_anon_execute.sql
-- Security audit Quick Win 1: close the unauthenticated RPC surface.
--
-- Finding F-4 (HIGH): fn_capture_dq_snapshot(uuid) is SECURITY DEFINER with EXECUTE granted
-- to anon and PUBLIC, and takes a caller-supplied team_id. It was reachable unauthenticated
-- at /rest/v1/rpc/fn_capture_dq_snapshot, letting anyone write snapshot rows against any
-- team id they chose.
-- Finding F-7 (MEDIUM): fn_audit_entity() is likewise SECURITY DEFINER and granted to
-- anon/PUBLIC. It is a trigger function, so direct invocation should fail before doing
-- damage, but it should never have been callable.
--
-- SIGNATURE CORRECTION vs the fixes prompt: it specifies
-- `fn_audit_entity(text, uuid, text, jsonb)`. No such overload exists - the live function
-- takes NO arguments (verified via pg_proc 2026-08-26). That statement would have failed.
--
-- Revoking EXECUTE does not affect trigger firing: PostgreSQL does not check the caller's
-- EXECUTE privilege when a trigger function runs. It also does not affect the weekly
-- DQ-snapshot cron, which runs as postgres.
--
-- DELIBERATELY NOT REVOKED: EXECUTE on fn_capture_dq_snapshot from `authenticated`.
-- The /insights page has a "Take snapshot now" button; if it calls this RPC with the user's
-- own session rather than through service_role, revoking would break it the night before
-- handover. The unauthenticated hole - which is the actual finding - is closed either way.
-- Confirm how that button invokes the function, then revoke from authenticated too.
--
-- fn_user_teams() is intentionally left granted to `authenticated`: every RLS policy in the
-- schema calls it. Revoking it would deny all row access.

REVOKE EXECUTE ON FUNCTION public.fn_capture_dq_snapshot(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_capture_dq_snapshot(uuid) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.fn_audit_entity() FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_audit_entity() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_audit_entity() FROM authenticated;
