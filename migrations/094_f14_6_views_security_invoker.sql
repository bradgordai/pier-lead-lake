-- 094 F14.6 (2026-09-14): the two remaining SECURITY DEFINER views run as the caller. Same definitions.
alter view public.v_sourcing_queue_missing_sn_url set (security_invoker = true);
alter view public.v_company_size_current set (security_invoker = true);
