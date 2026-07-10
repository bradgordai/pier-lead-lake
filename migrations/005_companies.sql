-- Migration 005: Companies
-- Section 5 of pier-supabase-migration-spec.md
-- 39 columns mirroring Excel v09 exactly, plus 5 new columns for the new build.
-- tracking and contacts_count are plain columns populated by triggers (see 010);
-- root_domain is populated by the normalise trigger. No GENERATED columns (013 deferred).

CREATE TABLE public.companies (
  -- Primary key + team
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,

  -- Excel Col A: Company ID (Cnnn sequential)
  company_id TEXT NOT NULL UNIQUE,

  -- Excel Col B: Company Name
  company_name TEXT NOT NULL,

  -- Excel Col C: Tracking (populated by trigger, see migration 010.5)
  tracking tracking_flag,

  -- Excel Col D: Priority
  priority priority_level,

  -- Excel Col E: Research Stage
  research_stage research_stage NOT NULL DEFAULT 'Untouched',

  -- Excel Col F: Contacts count (populated by trigger, see migration 010.2)
  contacts_count INTEGER NOT NULL DEFAULT 0,

  -- Excel Col G: Website URL
  website_url TEXT,

  -- Excel Col H: Country (single select)
  country TEXT,

  -- Excel Col I: Category (multi-select, array)
  category company_category[] NOT NULL DEFAULT '{}',

  -- Excel Col J: Refurbished Offered? (text with descriptor, not just Yes/No)
  refurbished_offered TEXT,

  -- Excel Col K: Sim-Free Devices? (text with descriptor)
  sim_free_devices TEXT,

  -- Excel Col L: Parent / Group Company
  parent_group TEXT,

  -- Excel Col M: Headquarter Location
  headquarter_location TEXT,

  -- Excel Col N: Countries Selling In
  countries_selling_in TEXT,

  -- Excel Col O: Estimated Revenue (£)
  estimated_revenue_gbp NUMERIC,

  -- Excel Col P: Employees
  employees INTEGER,

  -- Excel Col Q: Monthly Visits (SimilarWeb)
  monthly_visits INTEGER,

  -- Excel Col R: Creditsafe Rating (text like A1, B2)
  creditsafe_rating TEXT,

  -- Excel Col S: Insurance Offered? (Yes/No + description)
  insurance_offered TEXT,

  -- Excel Col T: Insurance Provider / Underwriter
  insurance_provider TEXT,

  -- Excel Col U: Product Type(s) (multi-select)
  insurance_product_types TEXT[] DEFAULT '{}',

  -- Excel Col V: Insurance Structure
  insurance_structure_type insurance_structure,

  -- Excel Col W: Monthly Price (£)
  insurance_monthly_price NUMERIC,

  -- Excel Col X: Annual Price (£)
  insurance_annual_price NUMERIC,

  -- Excel Col Y: Distribution Model
  distribution_model TEXT,

  -- Excel Col Z: Coverage Summary
  coverage_summary TEXT,

  -- Excel Col AA: Customer Journey
  customer_journey TEXT,

  -- Excel Col AB: Policy URL
  policy_url TEXT,

  -- Excel Col AC: Opportunity Status
  opportunity_status opportunity_status NOT NULL DEFAULT 'To Review',

  -- Excel Col AD: USP / Notes (primary narrative field with handoff tags)
  usp_notes TEXT,

  -- Excel Col AE: Additional Notes (OoS reasons live here from v08)
  additional_notes TEXT,

  -- Excel Col AF: Industry
  industry industry_type,

  -- Excel Col AG: Product Line
  product_line product_line NOT NULL DEFAULT 'Pier Protect',

  -- Excel Col AH: Account Owner
  account_owner account_owner,

  -- Excel Col AI: Account Source
  account_source TEXT,

  -- Excel Col AJ: Last Refreshed
  last_refreshed DATE,

  -- Excel Col AK: Source URLs (newline-delimited)
  source_urls TEXT,

  -- Excel Col AL: Annual Devices Sold
  annual_devices_sold TEXT,

  -- Excel Col AM: Date Added
  date_added DATE NOT NULL DEFAULT CURRENT_DATE,

  -- NEW columns for the new build
  archived_at TIMESTAMPTZ, -- promoted to Monday when set
  archive_reason TEXT,
  monday_deal_id TEXT, -- for future Monday sync
  root_domain TEXT, -- normalised domain for dedup, generated
  legacy_source TEXT, -- 'excel_v09' | 'uk_lovable_snapshot' | 'agent_created'
  migrated_at TIMESTAMPTZ,

  -- Standard timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
