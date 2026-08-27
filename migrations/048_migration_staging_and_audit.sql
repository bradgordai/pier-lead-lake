-- B5: landing zone for the v09 migration, plus its audit trail.
-- Every column is loose `text` on purpose: a staging table must accept the source verbatim,
-- including malformed values, so classification happens in SQL where it can be inspected -
-- not silently at parse time. No constraints, no enums, no FKs.
-- RLS: enabled with NO policy = service_role only. Un-triaged import data must not be
-- readable from the app.

CREATE TABLE IF NOT EXISTS public.staging_v09_companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text, row_num int,
  company_name text, country text, website text, category text, priority text,
  research_stage text, insurance_offered text, notes text, raw jsonb,
  classification text, migration_action text, migration_note text,
  created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS public.staging_v09_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text, row_num int,
  first_name text, last_name text, full_name text, company_name text, job_title text,
  country text, linkedin_url text, sales_nav_url text, email text,
  connection_status text, outreach_status text, notes text, raw jsonb,
  classification text, migration_action text, migration_note text,
  created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS public.staging_v09_outreach (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text, row_num int,
  touch_ref text, contact_name text, company_name text, touch_date text, channel text,
  touch_type text, message_body text, reply_content text, outcome text, notes text, raw jsonb,
  classification text, migration_action text, migration_note text,
  created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS public.migration_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text NOT NULL, phase text NOT NULL,
  entity text NOT NULL, source_ref text, action text NOT NULL, target_id uuid, detail jsonb,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS idx_migration_audit_run ON public.migration_audit (run_id, created_at);

ALTER TABLE public.staging_v09_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staging_v09_contacts  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staging_v09_outreach  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.migration_audit       ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.migration_audit IS
  'One row per migration decision. RLS enabled with no policy: service_role only.';
