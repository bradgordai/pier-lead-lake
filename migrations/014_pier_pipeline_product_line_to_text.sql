-- Migration 014: pier_pipeline.product_line enum -> TEXT
-- The source workbook's "Product Line" column on the Pier Pipeline sheet holds a
-- market-segment taxonomy (Mobile/Gadget, Travel) that does not match the
-- product_line enum (Pier Protect / Ticketplan / TIGA / Multiple / Unknown).
-- Per Brad's decision we store those segment values verbatim, so this column is
-- converted to TEXT. The product_line enum type itself is left intact — companies
-- .product_line still uses it.
--
-- Note: the spec's ordering reserved "014" for pg_cron (V1.1, deferred and never
-- generated). This 014 is the real next migration in the applied sequence.

ALTER TABLE public.pier_pipeline
  ALTER COLUMN product_line TYPE TEXT USING product_line::text;
