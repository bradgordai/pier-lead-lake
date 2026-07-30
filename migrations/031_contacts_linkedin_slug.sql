-- Migration 031: canonical linkedin_slug on contacts
--
-- The Sales Nav "List Export" phantom stores profileUrl in Sales Navigator internal
-- format (https://www.linkedin.com/sales/lead/ACwAAB...), while the "Recently Connected"
-- phantom emits the public form (https://www.linkedin.com/in/{slug}). Because
-- update-contact-on-cr-accepted matched on the full linkedin_url, the two never matched
-- and every accept returned ignored:not_in_pier_pipeline.
--
-- Fix: add a canonical linkedin_slug (the /in/{slug} identifier). Edge functions extract
-- and store it on ingest, and match by slug on accept. This column is ADDITIVE — existing
-- linkedin_url values are never modified. Rows whose linkedin_url is already /in/ format
-- get their slug backfilled here; /sales/lead/ rows have no reliable public slug and stay
-- NULL (they remain unmatchable on accept until re-ingested with a public URL).
--
-- Supabase applies each migration file atomically in a single transaction (the explicit
-- BEGIN/COMMIT below documents the intended boundary for direct psql runs).

BEGIN;

ALTER TABLE public.contacts ADD COLUMN linkedin_slug text;

CREATE INDEX idx_contacts_linkedin_slug ON public.contacts (linkedin_slug)
  WHERE linkedin_slug IS NOT NULL;

-- Backfill: extract the slug from existing /in/ URLs.
UPDATE public.contacts
SET linkedin_slug = substring(linkedin_url from 'linkedin\.com/in/([^/?#]+)')
WHERE linkedin_url ~ 'linkedin\.com/in/'
  AND linkedin_slug IS NULL;

COMMIT;
