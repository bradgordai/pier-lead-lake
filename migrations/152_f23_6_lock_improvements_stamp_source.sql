-- 152 F23 Task 6: fn_improvements_stamp_source is a SECURITY DEFINER trigger function (trg_improvements_stamp_source on
-- improvements) but was executable by anon and authenticated, so it could be called directly over RPC.
-- EXECUTE is revoked from anon and authenticated AND from PUBLIC: the ACL granted PUBLIC execute, which both roles
-- inherit, so revoking only the two named roles would have left them able to call it.
-- The trigger keeps firing: Postgres checks EXECUTE on a trigger function when the trigger is CREATED, not when it fires.
revoke execute on function public.fn_improvements_stamp_source() from public, anon, authenticated;
