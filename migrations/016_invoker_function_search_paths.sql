-- Migration 016: pin search_path on the SECURITY INVOKER functions
--
-- Migration 015 hardened the one SECURITY DEFINER function (fn_user_teams). The
-- remaining 8 functions in public are SECURITY INVOKER (triggers + two helpers)
-- and still tripped the "Function Search Path Mutable" lint (0011). Pinning
-- search_path = public, pg_temp removes the search-path-injection surface for
-- each. All object references in these bodies are either unqualified public
-- objects or already schema-qualified, so pinning to public (plus pg_temp) is
-- behaviour-preserving.
--
-- ALTER FUNCTION (rather than CREATE OR REPLACE) is used so the function bodies,
-- ownership, and existing grants are left untouched — only the config is added.

ALTER FUNCTION public.tg_update_updated_at()          SET search_path = public, pg_temp;
ALTER FUNCTION public.tg_recompute_contacts_count()   SET search_path = public, pg_temp;
ALTER FUNCTION public.fn_normalise_email(text)        SET search_path = public, pg_temp;
ALTER FUNCTION public.fn_extract_root_domain(text)    SET search_path = public, pg_temp;
ALTER FUNCTION public.tg_normalise_contact_fields()   SET search_path = public, pg_temp;
ALTER FUNCTION public.tg_normalise_company_fields()   SET search_path = public, pg_temp;
ALTER FUNCTION public.tg_update_cooldown_status()     SET search_path = public, pg_temp;
ALTER FUNCTION public.tg_resolve_tracking()           SET search_path = public, pg_temp;
