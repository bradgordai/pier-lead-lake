-- Migration 019: user_column_prefs (per-user column visibility for list views)
--
-- NOTE: saved_views was NOT re-created here. It already exists from migration 009
-- with exactly the shape the Companies list upgrade needs:
--   saved_views(team_id, user_id, view_name, target_table, filters JSONB,
--               sort JSONB, columns JSONB, is_shared, UNIQUE(user_id,target_table,view_name))
-- That already persists filter set + sort + column visibility per saved view.
--
-- user_column_prefs is the separate, always-on default: the user's current column
-- visibility for a view, independent of whether they have loaded a saved view.
-- Keyed by user_id + view_name per the spec.

CREATE TABLE public.user_column_prefs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  view_name TEXT NOT NULL,               -- e.g. 'companies_list'
  visible_columns JSONB NOT NULL DEFAULT '[]',  -- ordered array of column keys
  column_widths JSONB NOT NULL DEFAULT '{}',    -- optional {column_key: px}
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, view_name)
);

CREATE INDEX idx_user_column_prefs_user_view ON public.user_column_prefs(user_id, view_name);
CREATE INDEX idx_user_column_prefs_team_id ON public.user_column_prefs(team_id);

CREATE TRIGGER tg_user_column_prefs_updated_at
  BEFORE UPDATE ON public.user_column_prefs
  FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();

ALTER TABLE public.user_column_prefs ENABLE ROW LEVEL SECURITY;

-- Team-scoped AND owner-scoped: a user only ever sees/edits their own prefs.
CREATE POLICY user_column_prefs_select ON public.user_column_prefs FOR SELECT
  USING (user_id = (SELECT auth.uid()) AND team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY user_column_prefs_insert ON public.user_column_prefs FOR INSERT
  WITH CHECK (user_id = (SELECT auth.uid()) AND team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY user_column_prefs_update ON public.user_column_prefs FOR UPDATE
  USING (user_id = (SELECT auth.uid()) AND team_id IN (SELECT team_id FROM public.fn_user_teams()))
  WITH CHECK (user_id = (SELECT auth.uid()) AND team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY user_column_prefs_delete ON public.user_column_prefs FOR DELETE
  USING (user_id = (SELECT auth.uid()) AND team_id IN (SELECT team_id FROM public.fn_user_teams()));
