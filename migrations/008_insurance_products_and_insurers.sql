-- Migration 008: Insurance Products and Insurers
-- Section 8 of pier-supabase-migration-spec.md
-- Kept from the current UK Lovable pattern. Auto-generated from Companies data.

CREATE TABLE public.insurers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  insurer_name TEXT NOT NULL UNIQUE,
  website TEXT,
  distribution_model TEXT,
  customer_journey TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.insurance_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  insurer_id UUID REFERENCES public.insurers(id) ON DELETE SET NULL,
  product_types TEXT[] NOT NULL DEFAULT '{}',
  structure insurance_structure,
  customer_journey TEXT,
  monthly_price NUMERIC,
  annual_price NUMERIC,
  distribution_model TEXT,
  coverage_summary TEXT,
  policy_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
