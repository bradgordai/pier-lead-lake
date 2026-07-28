-- Migration 027: skip audit noise from the contacts_count recompute cascade
--
-- companies.contacts_count is maintained by a recompute trigger that fires whenever a
-- contact is created/deleted. That UPDATE cascades into fn_audit_entity (026) and writes a
-- spurious "Updated <company>" audit row every time a contact moves. This adds a guard at
-- the very top of the function: if a companies UPDATE changed ONLY contacts_count (and the
-- auto-touched updated_at), return early and write nothing. All 026 behaviour is otherwise
-- preserved verbatim (delete / restore / promote / generic-update branches for companies
-- and contacts; outreach_log untouched).
--
-- The guard compares to_jsonb(OLD) and to_jsonb(NEW) with contacts_count and updated_at
-- removed; if the remainder is identical AND contacts_count actually changed, it is a pure
-- recompute cascade. A real edit (e.g. country) leaves other keys differing, so it is still
-- audited even if contacts_count also changed incidentally.
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
  IF TG_OP = 'UPDATE' AND TG_TABLE_NAME = 'companies'
     AND OLD.contacts_count IS DISTINCT FROM NEW.contacts_count
     AND (to_jsonb(OLD) - 'contacts_count' - 'updated_at')
         = (to_jsonb(NEW) - 'contacts_count' - 'updated_at')
  THEN
    RETURN NULL;
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
