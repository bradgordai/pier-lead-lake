-- Migration 029: fix "record 'old' has no field 'contacts_count'" from the 027 guard
--
-- Migration 027 added a top-level guard to skip the contacts_count recompute cascade:
--   IF TG_OP = 'UPDATE' AND TG_TABLE_NAME = 'companies'
--      AND OLD.contacts_count IS DISTINCT FROM NEW.contacts_count AND ...
-- The contacts_count column exists ONLY on companies. PL/pgSQL resolves the record field
-- reference OLD.contacts_count against the firing row's actual composite type at execution
-- time and does NOT reliably short-circuit the flat boolean AND, so when the trigger fires
-- on contacts or outreach_log the expression throws:
--   record "old" has no field "contacts_count"
-- This broke every UPDATE on contacts / outreach_log (e.g. the Outreach "AI Edit" button).
--
-- Fix: nest the contacts_count comparison inside an outer IF that first checks
-- TG_TABLE_NAME = 'companies'. The inner expression referencing OLD/NEW.contacts_count is
-- then only ever reached (and prepared) for companies rows; contacts/outreach_log triggers
-- never evaluate it. Every 026/027 behaviour branch below is preserved verbatim
-- (delete / restore / promote / generic-update for companies + contacts; outreach_log
-- keeps the generic "Updated ... record"; the contacts_count-cascade skip still applies to
-- companies).
--
-- Supabase applies each migration file atomically in a single transaction.

CREATE OR REPLACE FUNCTION public.fn_audit_entity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id  uuid;
  v_entity   uuid;
  v_action   text;
  v_summary  text;
  v_name     text;
  v_before   jsonb;
  v_after    jsonb;
  v_actor    uuid := auth.uid();
BEGIN
  -- Skip the pure contacts_count recompute cascade on companies (a contact create/delete
  -- bumps companies.contacts_count and updated_at only). No other change -> no audit row.
  -- contacts_count exists only on companies, so the field reference MUST be nested inside a
  -- TG_TABLE_NAME = 'companies' guard; a flat condition throws on contacts / outreach_log.
  IF TG_TABLE_NAME = 'companies' AND TG_OP = 'UPDATE' THEN
    IF OLD.contacts_count IS DISTINCT FROM NEW.contacts_count
       AND (to_jsonb(OLD) - 'contacts_count' - 'updated_at')
           = (to_jsonb(NEW) - 'contacts_count' - 'updated_at')
    THEN
      RETURN NULL;
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_team_id := OLD.team_id; v_entity := OLD.id;
    v_before := to_jsonb(OLD);  v_after := NULL;
    v_action := 'deleted';      v_summary := 'Deleted ' || TG_TABLE_NAME || ' record';
  ELSIF TG_OP = 'INSERT' THEN
    v_team_id := NEW.team_id; v_entity := NEW.id;
    v_before := NULL;           v_after := to_jsonb(NEW);
    v_action := 'created';      v_summary := 'Created ' || TG_TABLE_NAME || ' record';
  ELSE  -- UPDATE
    v_team_id := NEW.team_id; v_entity := NEW.id;
    v_before := to_jsonb(OLD);  v_after := to_jsonb(NEW);
    v_action := 'updated';      v_summary := 'Updated ' || TG_TABLE_NAME || ' record';

    IF TG_TABLE_NAME IN ('companies', 'contacts') THEN
      IF TG_TABLE_NAME = 'companies' THEN
        v_name := COALESCE(NEW.company_name, 'company');
      ELSE
        v_name := COALESCE(NULLIF(BTRIM(COALESCE(NEW.first_name, '') || ' ' || COALESCE(NEW.last_name, '')), ''), 'contact');
      END IF;

      v_summary := 'Updated ' || v_name;

      IF OLD.archived_at IS NULL AND NEW.archived_at IS NOT NULL THEN
        IF NEW.archive_reason = 'promoted_to_monday' THEN
          v_action := 'archived';
          v_summary := 'Moved ' || v_name || ' to Monday';
        ELSIF NEW.archive_reason IN ('deleted', 'duplicate', 'wrong_target', 'out_of_scope', 'left_market') THEN
          v_action := 'deleted';
          v_summary := 'Deleted ' || v_name || ' (reason: ' || NEW.archive_reason || ')';
        ELSE
          v_action := 'archived';
          v_summary := 'Archived ' || v_name || ' (reason: ' || COALESCE(NEW.archive_reason, 'none') || ')';
        END IF;
      ELSIF OLD.archived_at IS NOT NULL AND NEW.archived_at IS NULL THEN
        IF OLD.archive_reason = 'promoted_to_monday' THEN
          v_action := 'restored';
          v_summary := 'Restored ' || v_name || ' from archive';
        ELSE
          v_action := 'restored';
          v_summary := 'Restored deleted ' || v_name;
        END IF;
      END IF;
    END IF;
  END IF;

  INSERT INTO public.audit_log
    (team_id, actor_user_id, entity_type, entity_id, action, before_value, after_value, summary, source)
  VALUES
    (v_team_id, v_actor, TG_TABLE_NAME, v_entity, v_action, v_before, v_after, v_summary, 'manual');

  RETURN COALESCE(NEW, OLD);
END;
$$;
