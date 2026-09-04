-- 058: columns the Phase 2 migration writes. Applied 2026-09-04.
ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS person_key uuid;
CREATE INDEX IF NOT EXISTS idx_contacts_person_key ON public.contacts (person_key) WHERE person_key IS NOT NULL;
COMMENT ON COLUMN public.contacts.person_key IS 'Shared by contact rows that are the same human in different roles/companies (Blaumann, Smith, Green). Both rows stay live; the UI shows them as linked.';
ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS profile_snapshot_at date;
COMMENT ON COLUMN public.contacts.profile_snapshot_at IS 'Date of the last profile scrape/snapshot (workbook "Profile Snapshot (dated)"). The freshness chip reads this, never updated_at.';
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS country_inferred boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.companies.country_inferred IS 'TRUE when country was inferred from the website domain during migration. Must be human-verified before it can unlock email; LinkedIn unaffected.';
ALTER TABLE public.contacts  ADD COLUMN IF NOT EXISTS merged_from_refs text[];
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS merged_from_refs text[];
