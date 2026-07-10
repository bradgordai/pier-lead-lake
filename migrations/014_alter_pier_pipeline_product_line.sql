-- Migration 014: alter pier_pipeline.product_line (enum -> TEXT)
--
-- TAXONOMY CONFLICT
-- -----------------
-- Two incompatible meanings of "product line" collide on this column:
--
--   * The schema's `product_line` enum encodes PIER's own product lines:
--       'Pier Protect', 'Ticketplan', 'TIGA', 'Multiple', 'Unknown'
--     (see migration 002). companies.product_line uses this and is unaffected.
--
--   * The source workbook's "Product Line" column on the Pier Pipeline sheet
--     actually holds a MARKET-SEGMENT taxonomy — the observed values are
--     'Mobile/Gadget' (63 rows) and 'Travel' (1 row) — which are not members of
--     the enum. Inserting them into an enum-typed column fails outright
--     (invalid input value for enum product_line).
--
-- Resolution (per Brad's decision): preserve the segment labels verbatim rather
-- than coercing them to 'Unknown'/NULL or forcing them into the enum. This
-- column is therefore converted from the enum to plain TEXT. Nothing in V1 reads
-- pier_pipeline.product_line (the tracking-cascade trigger uses only `stage` and
-- `company_name`), so widening the type is safe. The `product_line` enum type
-- itself is left intact and still governs companies.product_line.
--
-- Note: the spec's ordering reserved "014" for pg_cron (V1.1, deferred and never
-- generated). This 014 is the real next migration in the applied sequence.

ALTER TABLE public.pier_pipeline
  ALTER COLUMN product_line TYPE TEXT USING product_line::text;
