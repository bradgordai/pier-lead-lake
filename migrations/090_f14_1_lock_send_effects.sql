-- 090 F14.1 (2026-09-14): fn_apply_send_effects is callable by the service key only.
revoke execute on function public.fn_apply_send_effects(uuid, text) from anon, authenticated, public;
grant execute on function public.fn_apply_send_effects(uuid, text) to service_role;
