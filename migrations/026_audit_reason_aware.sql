-- Migration 026: make fn_audit_entity archive_reason-aware
--
-- Migration 023 summarised EVERY companies archived_at NULL->NOT NULL transition
-- as "Moved X to Monday". Since migration 025 added a soft-delete lane (archived_at
-- + archive_reason on companies and contacts), a delete now mislabels in the Actions
-- Log. This replaces the function body only (the tg_audit_* triggers are unchanged
-- and keep pointing at it) so the summary branches on archive_reason:
--   promoted_to_monday                              -> "Moved X to Monday"
--   deleted|duplicate|wrong_target|out_of_scope|left_market -> "Deleted X (reason: R)"
--   anything else                                   -> "Archived X (reason: R)"
--   un-archive of a promote                         -> "Restored X from archive"
--   un-archive of a delete                          -> "Restored deleted X"
-- Applies to companies + contacts (both have archived_at). outreach_log has no
-- archived_at, so it never enters the archive branch and keeps "Updated ... record".
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

    -- Only companies and contacts carry archived_at / archive_reason. Referencing
    -- these fields is guarded by TG_TABLE_NAME so the outreach_log trigger (which has
    -- no such columns) never evaluates them.
    IF TG_TABLE_NAME IN ('companies', 'contacts') THEN
      IF TG_TABLE_NAME = 'companies' THEN
        v_name := COALESCE(NEW.company_name, 'company');
      ELSE
        v_name := COALESCE(NULLIF(BTRIM(COALESCE(NEW.first_name, '') || ' ' || COALESCE(NEW.last_name, '')), ''), 'contact');
      END IF;

      -- Named default for these two tables (outreach_log keeps the generic form above).
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
