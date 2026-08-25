-- 033_company_enrichment_queue.sql
-- Task 8 (UX sweep): review queue for AI-suggested company field enrichments
-- (website_url first). Populated by the enrich-company-websites Edge Function
-- for MEDIUM/LOW-confidence guesses, and by the Reconciliation bulk-select
-- "Send to enrichment queue" action. Oli approves/rejects from /reconciliation.
-- company_id is nullable to support future new-company suggestions.

CREATE TABLE IF NOT EXISTS public.company_enrichment_queue (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id         uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  company_id      uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  suggested_field text NOT NULL,
  suggested_value text NOT NULL,
  source_urls     jsonb NOT NULL DEFAULT '[]'::jsonb,
  confidence      integer NOT NULL DEFAULT 0 CHECK (confidence BETWEEN 0 AND 100),
  status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  actor           text,
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  reviewed_at     timestamptz,
  reviewed_by     text
);

CREATE INDEX IF NOT EXISTS idx_ceq_team_status ON public.company_enrichment_queue(team_id, status);
CREATE INDEX IF NOT EXISTS idx_ceq_company     ON public.company_enrichment_queue(company_id);

-- One open (pending) suggestion per company+field, so re-running the enricher or
-- the bulk-select does not pile up duplicates. (NULL company_id rows are exempt,
-- as Postgres treats NULLs as distinct — intended for future new-company suggestions.)
CREATE UNIQUE INDEX IF NOT EXISTS uq_ceq_pending_company_field
  ON public.company_enrichment_queue(team_id, company_id, suggested_field)
  WHERE status = 'pending';

ALTER TABLE public.company_enrichment_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY ceq_select ON public.company_enrichment_queue
  FOR SELECT USING (team_id IN (SELECT team_id FROM fn_user_teams()));
CREATE POLICY ceq_insert ON public.company_enrichment_queue
  FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM fn_user_teams()));
CREATE POLICY ceq_update ON public.company_enrichment_queue
  FOR UPDATE USING (team_id IN (SELECT team_id FROM fn_user_teams()))
  WITH CHECK (team_id IN (SELECT team_id FROM fn_user_teams()));
