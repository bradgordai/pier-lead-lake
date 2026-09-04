-- 057_staging_wb_frozen_workbook.sql
-- Batch C Phase 2 step 1: rebuild staging for the FROZEN workbook
-- (260902_PIER_lead_lake_SHARE_COPY_v09_OM_C2.xlsx, frozen 2026-09-02 17:12).
--
-- The 048 staging_v09_* tables were shaped for an older analysis and never loaded. They
-- are dropped here (empty, verified before drop) and replaced with one table per workbook
-- sheet that holds the row VERBATIM as jsonb keyed by the sheet's real header names, plus
-- generated columns for the handful of keys the migration joins on. Generated columns
-- rather than a parse step: the source stays the single truth and every classification
-- happens in SQL where it can be inspected.
--
-- RLS enabled with NO policy = service_role only. Un-triaged import data is never
-- readable from the app.

DROP TABLE IF EXISTS public.staging_v09_companies;
DROP TABLE IF EXISTS public.staging_v09_contacts;
DROP TABLE IF EXISTS public.staging_v09_outreach;

CREATE TABLE public.staging_wb_companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text NOT NULL, row_num int,
  raw jsonb NOT NULL,
  company_ref     text GENERATED ALWAYS AS (nullif(btrim(raw->>'Company ID'),'')) STORED,
  company_name    text GENERATED ALWAYS AS (nullif(btrim(raw->>'Company Name'),'')) STORED,
  website         text GENERATED ALWAYS AS (nullif(btrim(raw->>'Website URL'),'')) STORED,
  country         text GENERATED ALWAYS AS (nullif(btrim(raw->>'Country'),'')) STORED,
  priority        text GENERATED ALWAYS AS (nullif(btrim(raw->>'Priority'),'')) STORED,
  research_stage  text GENERATED ALWAYS AS (nullif(btrim(raw->>'Research Stage'),'')) STORED,
  opportunity     text GENERATED ALWAYS AS (nullif(btrim(raw->>'Opportunity Status'),'')) STORED,
  engagement      text GENERATED ALWAYS AS (nullif(btrim(raw->>'Engagement'),'')) STORED,
  tracking        text GENERATED ALWAYS AS (nullif(btrim(raw->>'Tracking'),'')) STORED,
  classification text, migration_action text, migration_note text, target_id uuid,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX ON public.staging_wb_companies (run_id, company_ref);

CREATE TABLE public.staging_wb_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text NOT NULL, row_num int,
  raw jsonb NOT NULL,
  contact_ref        text GENERATED ALWAYS AS (nullif(btrim(raw->>'Contact ID'),'')) STORED,
  company_ref        text GENERATED ALWAYS AS (nullif(btrim(raw->>'Company ID'),'')) STORED,
  first_name         text GENERATED ALWAYS AS (nullif(btrim(raw->>'First Name'),'')) STORED,
  last_name          text GENERATED ALWAYS AS (nullif(btrim(raw->>'Last Name'),'')) STORED,
  linkedin_url       text GENERATED ALWAYS AS (nullif(btrim(raw->>'LinkedIn URL'),'')) STORED,
  sales_nav_url      text GENERATED ALWAYS AS (nullif(btrim(raw->>'LinkedIn URL (Sales Nav)'),'')) STORED,
  connection_status  text GENERATED ALWAYS AS (nullif(btrim(raw->>'Connection Status'),'')) STORED,
  outreach_status    text GENERATED ALWAYS AS (nullif(btrim(raw->>'Outreach Status'),'')) STORED,
  country            text GENERATED ALWAYS AS (nullif(btrim(raw->>'Country'),'')) STORED,
  formality          text GENERATED ALWAYS AS (nullif(btrim(raw->>'Formality'),'')) STORED,
  language           text GENERATED ALWAYS AS (nullif(btrim(raw->>'Language'),'')) STORED,
  do_not_contact     text GENERATED ALWAYS AS (nullif(btrim(raw->>'Do Not Contact'),'')) STORED,
  classification text, migration_action text, migration_note text, target_id uuid,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX ON public.staging_wb_contacts (run_id, contact_ref);

CREATE TABLE public.staging_wb_outreach (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text NOT NULL, row_num int,
  raw jsonb NOT NULL,
  touch_ref     text GENERATED ALWAYS AS (nullif(btrim(raw->>'Touch ID'),'')) STORED,
  contact_ref   text GENERATED ALWAYS AS (nullif(btrim(raw->>'Contact ID'),'')) STORED,
  touch_date    text GENERATED ALWAYS AS (nullif(btrim(raw->>'Date'),'')) STORED,
  channel       text GENERATED ALWAYS AS (nullif(btrim(raw->>'Channel'),'')) STORED,
  touch_type    text GENERATED ALWAYS AS (nullif(btrim(raw->>'Type'),'')) STORED,
  message_body  text GENERATED ALWAYS AS (nullif(btrim(raw->>'Message Body / Notes'),'')) STORED,
  send_status   text GENERATED ALWAYS AS (nullif(btrim(raw->>'Send Status'),'')) STORED,
  outcome       text GENERATED ALWAYS AS (nullif(btrim(raw->>'Outcome'),'')) STORED,
  classification text, migration_action text, migration_note text, target_id uuid,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX ON public.staging_wb_outreach (run_id, touch_ref);
CREATE INDEX ON public.staging_wb_outreach (run_id, contact_ref);

CREATE TABLE public.staging_wb_pipeline   (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text NOT NULL, row_num int, raw jsonb NOT NULL, classification text, migration_action text, migration_note text, target_id uuid, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.staging_wb_eurefas    (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text NOT NULL, row_num int, raw jsonb NOT NULL, classification text, migration_action text, migration_note text, target_id uuid, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.staging_wb_competitor (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text NOT NULL, row_num int, raw jsonb NOT NULL, classification text, migration_action text, migration_note text, target_id uuid, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.staging_wb_market     (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text NOT NULL, row_num int, raw jsonb NOT NULL, classification text, migration_action text, migration_note text, target_id uuid, created_at timestamptz NOT NULL DEFAULT now());
-- Monday export (Companies_1787752414.xlsx) for the Monday sweep.
CREATE TABLE public.staging_wb_monday     (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text NOT NULL, row_num int, raw jsonb NOT NULL, classification text, migration_action text, migration_note text, target_id uuid, created_at timestamptz NOT NULL DEFAULT now());

ALTER TABLE public.staging_wb_companies  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staging_wb_contacts   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staging_wb_outreach   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staging_wb_pipeline   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staging_wb_eurefas    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staging_wb_competitor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staging_wb_market     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staging_wb_monday     ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.staging_wb_contacts IS
  'Frozen workbook (2026-09-02 17:12) Contacts sheet, verbatim jsonb per row. Service-role only. Generated key columns for joins; classification / migration_action / target_id written by the Phase 2 run.';
