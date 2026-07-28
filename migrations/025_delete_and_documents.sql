-- Migration 025: soft-delete for contacts + company_documents
--
-- Adds a soft-delete lane for contacts (mirroring companies.archived_at) and a
-- company_documents table for the Files tab (URLs this pass; file upload later).
--
-- The existing archive lane on companies is reused for "deleted companies" too:
-- archive_reason distinguishes 'promoted_to_monday' (Move to Monday) from the new
-- delete reasons ('deleted' | 'duplicate' | 'wrong_target' | 'out_of_scope' |
-- 'left_market'). No CHECK constraint on archive_reason (kept free-text, per brief).
--
-- Supabase applies each migration file atomically in a single transaction, so any
-- failure below rolls the whole file back (no partial schema).

-- contacts soft-delete columns
ALTER TABLE public.contacts
  ADD COLUMN archived_at TIMESTAMPTZ,
  ADD COLUMN archive_reason TEXT;

-- company_documents
CREATE TABLE public.company_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  doc_type TEXT NOT NULL CHECK (doc_type IN ('url','file')),
  url TEXT NOT NULL,
  title TEXT,
  description TEXT,
  source TEXT NOT NULL CHECK (source IN ('agent','user')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_company_documents_company ON public.company_documents (company_id);
CREATE INDEX idx_company_documents_team ON public.company_documents (team_id);

CREATE TRIGGER tg_company_documents_updated_at
  BEFORE UPDATE ON public.company_documents
  FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();

ALTER TABLE public.company_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_documents_select ON public.company_documents FOR SELECT
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY company_documents_insert ON public.company_documents FOR INSERT
  WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY company_documents_update ON public.company_documents FOR UPDATE
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()))
  WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY company_documents_delete ON public.company_documents FOR DELETE
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
