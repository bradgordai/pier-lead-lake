-- 043_sync_outreach_log_company_id.sql
-- FIX 10b. Reassigning a contact's company in Reconciliation left their outreach_log rows
-- pointing at the old company (or NULL), so the Outreach tab kept grouping them under
-- "Unmatched" even after the fix. This propagates the change.
--
-- SECURITY INVOKER is deliberate: the trigger fires on a user's own UPDATE and must not
-- widen their privileges. search_path is pinned, per migration 016's convention.

CREATE OR REPLACE FUNCTION public.sync_outreach_log_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  UPDATE public.outreach_log
     SET company_id = NEW.company_id
   WHERE contact_id = NEW.id
     AND (company_id IS DISTINCT FROM NEW.company_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_outreach_company_on_contact_update ON public.contacts;
CREATE TRIGGER trg_sync_outreach_company_on_contact_update
AFTER UPDATE OF company_id ON public.contacts
FOR EACH ROW
WHEN (OLD.company_id IS DISTINCT FROM NEW.company_id)
EXECUTE FUNCTION public.sync_outreach_log_company_id();

COMMENT ON FUNCTION public.sync_outreach_log_company_id() IS
  'Propagates a contact company reassignment onto their outreach_log rows so Outreach grouping never goes stale.';
