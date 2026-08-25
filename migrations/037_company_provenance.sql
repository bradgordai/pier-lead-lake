-- 037_company_provenance.sql
-- Bundle A, Task 4: provenance + review flag for companies created automatically
-- by the Sales Nav ingest path (upsert-contact-from-sales-nav auto-create, T3b).
--
-- needs_review: true on any row a machine created without human confirmation, so
--   the Reconciliation UI can surface it for Oli to confirm/merge/rename.
-- added_via:    free text provenance tag. Known values today:
--   'manual' | 'sales_nav_auto' | 'apify_enrichment' | 'reconciliation_confirm'
--   Left as text (not an enum) so new ingest paths can tag themselves without a
--   migration; the set is small and only read for display/filtering.
--
-- Both columns are additive and nullable-or-defaulted, so this migration is safe
-- to keep in place even if the Edge Function that writes them is rolled back.

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS needs_review boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS added_via    text;

-- Partial index: the review queue only ever reads needs_review = true, newest first.
CREATE INDEX IF NOT EXISTS idx_companies_needs_review
  ON public.companies (needs_review, updated_at DESC)
  WHERE needs_review = true;

COMMENT ON COLUMN public.companies.needs_review IS
  'True when the row was created automatically (e.g. sales_nav_auto) and still needs human confirmation in Reconciliation.';
COMMENT ON COLUMN public.companies.added_via IS
  'Provenance of the row: manual | sales_nav_auto | apify_enrichment | reconciliation_confirm.';
