-- Migration 030: pier_ea_documents (Pier Executive Assistant voice/context library)
--
-- Stores the Pier EA source documents (rules, message/email/journey templates,
-- targeting briefs, capability + living context, response bank, and skills) that the
-- generate-draft-from-context Edge Function loads at runtime to produce on-voice
-- outreach drafts. One row per document per team (UNIQUE team_id, name).
--
-- RLS is team-scoped SELECT/INSERT/UPDATE via fn_user_teams(); no DELETE policy
-- (documents are versioned/deactivated, not deleted). updated_at is maintained by the
-- existing public.tg_update_updated_at() trigger. version + is_active carry NOT NULL
-- defaults so callers can always treat them concretely.
--
-- Supabase applies each migration file atomically in a single transaction, so any
-- failure below rolls the whole file back (no partial schema).

CREATE TABLE public.pier_ea_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  content TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('rules', 'template', 'targeting', 'context', 'response', 'skill')),
  version INT NOT NULL DEFAULT 1,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (team_id, name)
);
CREATE INDEX idx_pier_ea_documents_team_active ON public.pier_ea_documents (team_id, is_active);

CREATE TRIGGER tg_pier_ea_documents_updated_at
  BEFORE UPDATE ON public.pier_ea_documents
  FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();

ALTER TABLE public.pier_ea_documents ENABLE ROW LEVEL SECURITY;

-- SELECT + INSERT + UPDATE only (no DELETE policy, per spec).
CREATE POLICY pier_ea_documents_select ON public.pier_ea_documents FOR SELECT
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY pier_ea_documents_insert ON public.pier_ea_documents FOR INSERT
  WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY pier_ea_documents_update ON public.pier_ea_documents FOR UPDATE
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()))
  WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
