-- 066: F6.9 advisor cleanup.
-- The 065 trigger functions are SECURITY DEFINER; triggers do not need EXECUTE on the function
-- to fire, so nobody outside the trigger should be able to call them over /rest/v1/rpc.
revoke execute on function public.tg_contact_company_archived_from_company() from public, anon, authenticated;
revoke execute on function public.tg_company_archived_sync_contacts() from public, anon, authenticated;
-- The F6.4 sweep work table was reviewed and applied; migration_audit holds the full before/after.
drop table if exists public.f6_sweep_work;
