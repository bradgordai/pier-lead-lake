-- Migration 004: Reference tables (pier_pipeline, eurefas_members)
-- Section 4 of pier-supabase-migration-spec.md

-- 4.1 pier_pipeline
-- Live partners and prospects. Read-only reference, used by tracking cascade.
CREATE TABLE public.pier_pipeline (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pipeline_id TEXT NOT NULL UNIQUE, -- Lnnn from Excel
  company_name TEXT NOT NULL,
  stage TEXT NOT NULL, -- 'Live Partner', 'Live Prospect', 'No longer active'
  product_line product_line,
  source_folder TEXT,
  deleted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4.2 eurefas_members
-- 27 members of European Refurbishment Association. Read-only reference.
CREATE TABLE public.eurefas_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id TEXT NOT NULL UNIQUE, -- EFnnn from Excel
  company_name TEXT NOT NULL,
  membership TEXT NOT NULL, -- 'Founding member', 'Member'
  country TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
