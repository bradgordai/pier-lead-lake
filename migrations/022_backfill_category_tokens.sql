-- Migration 022: backfill the category tokens that 021 made legal
--
-- Three companies carried ONLY tokens from the dropped set, so Phase B landed
-- them with category = '{}' — no classification at all, not a partial one:
--   C096 Ingram Micro Lifecycle  Refurb, Recommerce
--   C071 Fixfirst                Software Provider
--   C002 mobileparts.shop        Wholesaler, Distributor
--
-- Token set taken from the workbook via load_full_data.read_companies, so the
-- tokenisation matches exactly what the loader would now produce.
--
-- Idempotent: appends only tokens not already present, and the EXISTS guard
-- means a re-run matches zero rows. Order-preserving: existing entries keep
-- their position and missing ones are appended.

WITH backfill(company_id, tokens) AS (
  VALUES
    ('C096', ARRAY['Refurb', 'Recommerce']::company_category[]),
    ('C071', ARRAY['Software Provider']::company_category[]),
    ('C002', ARRAY['Wholesaler', 'Distributor']::company_category[])
)
UPDATE public.companies c
SET category = c.category || ARRAY(
      SELECT t FROM unnest(b.tokens) AS t
      WHERE NOT (t = ANY(c.category))
    )
FROM backfill b
WHERE c.company_id = b.company_id
  AND EXISTS (
    SELECT 1 FROM unnest(b.tokens) AS t
    WHERE NOT (t = ANY(c.category))
  );
