-- Migration 021: five first-class company_category tokens
--
-- These five appear in the Companies sheet (col I, semicolon-delimited) but were
-- not enum members, so the Phase B loader dropped them with a warning and the
-- affected companies landed with short category arrays. They describe how a
-- company trades rather than what it sells, which the existing members do not
-- express: 'Refurbished Specialist' is not the same claim as 'Refurb' applied
-- alongside a retail category, and Wholesaler/Distributor are channel positions.
--
-- Appended, not reordered: existing values keep their sort order, so anything
-- relying on enum ordinality is unaffected.
--
-- Companion changes:
--   scripts/load_full_data.py  - these move from the known-drop list to identity
--   022 backfill               - re-adds the dropped tokens to affected companies

ALTER TYPE company_category ADD VALUE IF NOT EXISTS 'Refurb';
ALTER TYPE company_category ADD VALUE IF NOT EXISTS 'Recommerce';
ALTER TYPE company_category ADD VALUE IF NOT EXISTS 'Software Provider';
ALTER TYPE company_category ADD VALUE IF NOT EXISTS 'Wholesaler';
ALTER TYPE company_category ADD VALUE IF NOT EXISTS 'Distributor';
