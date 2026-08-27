-- B9: send-ready gate + supply-unlock diagnostics.
--
-- COLUMN/VALUE SUBSTITUTIONS vs the spec, verified against the live schema 2026-08-28:
--   spec `sales_nav_url` -> contacts.linkedin_sales_nav_url
--   spec `dnc`           -> contacts.do_not_contact (boolean)
--   spec `status`        -> contacts.outreach_status (enum)
--   spec `connection_status='Not sent'` -> 'Not connected'
--        FLAGGED: there is no 'Not sent' label. connection_status is (Not connected,
--        Request sent, Accepted, Already connected, Ignored, Withdrawn). 'Not connected'
--        is the only member meaning "no CR sent yet". If 'Not sent' was meant to be a NEW
--        label, this predicate needs revisiting.
--   cooldown_until is a `date`, compared to CURRENT_DATE not now().
-- SECURITY INVOKER so RLS still applies: a caller only sees their own team's rows.

CREATE OR REPLACE FUNCTION public.fn_send_ready_contacts(p_team_id uuid)
RETURNS TABLE(contact_id uuid)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO 'public','pg_temp'
AS $$
  SELECT c.id FROM public.contacts c JOIN public.companies co ON co.id = c.company_id
  WHERE c.team_id = p_team_id
    AND co.archived_at IS NULL
    AND co.priority IS DISTINCT FROM 'OoS'
    AND co.opportunity_status::text NOT ILIKE 'out of scope%'
    AND co.research_stage IN ('Light triage','Deep research done')
    AND co.country IS NOT NULL
    AND c.connection_status = 'Not connected'
    AND c.linkedin_sales_nav_url IS NOT NULL
    AND c.do_not_contact IS NOT TRUE
    AND c.outreach_status::text NOT IN ('Not relevant','Opted out')
    AND (c.cooldown_until IS NULL OR c.cooldown_until < CURRENT_DATE)
    AND c.archived_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION public.fn_supply_unlocks(p_team_id uuid)
RETURNS TABLE(missing_sn_url bigint, untriaged_company bigint, missing_country bigint)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO 'public','pg_temp'
AS $$
  WITH base AS (
    SELECT c.id,
      (co.archived_at IS NULL AND co.priority IS DISTINCT FROM 'OoS'
       AND co.opportunity_status::text NOT ILIKE 'out of scope%'
       AND c.connection_status = 'Not connected' AND c.do_not_contact IS NOT TRUE
       AND c.outreach_status::text NOT IN ('Not relevant','Opted out')
       AND (c.cooldown_until IS NULL OR c.cooldown_until < CURRENT_DATE)
       AND c.archived_at IS NULL) AS common_ok,
      (c.linkedin_sales_nav_url IS NOT NULL) AS has_sn_url,
      (co.research_stage IN ('Light triage','Deep research done')) AS triaged,
      (co.country IS NOT NULL) AS has_country
    FROM public.contacts c JOIN public.companies co ON co.id = c.company_id
    WHERE c.team_id = p_team_id)
  SELECT count(*) FILTER (WHERE common_ok AND triaged AND has_country AND NOT has_sn_url),
         count(*) FILTER (WHERE common_ok AND has_sn_url AND has_country AND NOT triaged),
         count(*) FILTER (WHERE common_ok AND has_sn_url AND triaged AND NOT has_country)
  FROM base;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_send_ready_contacts(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_supply_unlocks(uuid)      FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fn_send_ready_contacts(uuid) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.fn_supply_unlocks(uuid)      TO authenticated;
