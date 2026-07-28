-- Migration 023: reconciliation infrastructure
--
-- Adds the two tables and the audit trigger the Reconciliation tab needs:
--   company_aliases  - workbook/LinkedIn company_ref -> canonical company, so future
--                      auto-matching can resolve a ref without re-asking the user.
--   audit_log        - append-only activity trail powering the Actions Log sub-tab.
-- Plus fn_audit_entity(), attached to companies/contacts/outreach_log, which writes
-- an audit_log row on every INSERT/UPDATE/DELETE and gives archive/restore their own
-- human-readable summary.

-- ---------------------------------------------------------------------------
-- A. company_aliases
-- ---------------------------------------------------------------------------
CREATE TABLE public.company_aliases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  alias TEXT NOT NULL,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (team_id, alias)
);
CREATE INDEX idx_company_aliases_lower_alias ON public.company_aliases (lower(alias));
CREATE INDEX idx_company_aliases_company ON public.company_aliases (company_id);

ALTER TABLE public.company_aliases ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_aliases_select ON public.company_aliases FOR SELECT
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY company_aliases_insert ON public.company_aliases FOR INSERT
  WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY company_aliases_update ON public.company_aliases FOR UPDATE
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()))
  WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY company_aliases_delete ON public.company_aliases FOR DELETE
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- ---------------------------------------------------------------------------
-- B. audit_log (append-only: SELECT + INSERT policies only)
-- ---------------------------------------------------------------------------
CREATE TABLE public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  action TEXT NOT NULL,
  before_value JSONB,
  after_value JSONB,
  summary TEXT,
  source TEXT NOT NULL DEFAULT 'manual',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audit_log_team_created ON public.audit_log (team_id, created_at DESC);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
-- No UPDATE/DELETE policy: the trail is append-only for users. (The migration role
-- and any future retention job can still prune via the service connection.)
CREATE POLICY audit_log_select ON public.audit_log FOR SELECT
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY audit_log_insert ON public.audit_log FOR INSERT
  WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- ---------------------------------------------------------------------------
-- C. audit trigger function
-- ---------------------------------------------------------------------------
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
    IF TG_TABLE_NAME = 'companies' THEN
      IF OLD.archived_at IS NULL AND NEW.archived_at IS NOT NULL THEN
        v_action := 'archived';
        v_summary := 'Moved ' || COALESCE(NEW.company_name, 'company') || ' to Monday';
      ELSIF OLD.archived_at IS NOT NULL AND NEW.archived_at IS NULL THEN
        v_action := 'restored';
        v_summary := 'Restored ' || COALESCE(NEW.company_name, 'company') || ' from archive';
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

-- ---------------------------------------------------------------------------
-- D. attach the trigger
-- ---------------------------------------------------------------------------
CREATE TRIGGER tg_audit_companies AFTER INSERT OR UPDATE OR DELETE ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_entity();
CREATE TRIGGER tg_audit_contacts AFTER INSERT OR UPDATE OR DELETE ON public.contacts
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_entity();
CREATE TRIGGER tg_audit_outreach_log AFTER INSERT OR UPDATE OR DELETE ON public.outreach_log
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_entity();
