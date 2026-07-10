-- Migration 006: Contacts
-- Section 6 of pier-supabase-migration-spec.md
-- 31 columns mirroring Excel v09 exactly, plus a few new for the new build.
-- email_normalised populated by trigger (010.3); cooldown_status_derived by
-- trigger (010.4). No GENERATED columns (013 deferred).

CREATE TABLE public.contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,

  -- Excel Col A: Contact ID (Pnnn)
  contact_id TEXT NOT NULL UNIQUE,

  -- Excel Col B: Company ID FK, plus modern UUID FK for joins
  company_ref TEXT NOT NULL, -- the Cnnn text ref for continuity
  company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,

  -- Excel Cols C, D: VLOOKUP fields, resolved via joins in the app instead
  -- company_name = via join
  -- lead_priority = via join

  -- Excel Cols E, F: Name
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,

  -- Excel Col G: Job Title
  job_title TEXT,

  -- Excel Col H: Seniority
  seniority seniority_level,

  -- Excel Col I: Function
  function function_type,

  -- Excel Col J: Location (city, country combined)
  location TEXT,

  -- Excel Col K: LinkedIn URL
  linkedin_url TEXT,

  -- Excel Col L: LinkedIn URL (Sales Nav)
  linkedin_sales_nav_url TEXT,

  -- Excel Col M: Email
  email TEXT,
  email_normalised TEXT, -- for dedup, generated

  -- Excel Col N: Phone
  phone TEXT,

  -- Excel Col O: Connection to Oliver
  connection_level connection_level,

  -- Excel Col P: Formality
  formality formality_level,

  -- Excel Col Q: Language
  language_code language_code,

  -- Excel Col R: Source List (SN list name)
  source_list TEXT,

  -- Excel Col S: Connection Status
  connection_status connection_status NOT NULL DEFAULT 'Not connected',

  -- Excel Col T: Outreach Status
  outreach_status outreach_status NOT NULL DEFAULT 'Not started',

  -- Excel Col U: Last Contacted
  last_contacted DATE,

  -- Excel Col V: Next Action
  next_action TEXT,

  -- Excel Col W: Next Action Date
  next_action_date DATE,

  -- Excel Col X: Background / Notes
  background_notes TEXT,

  -- Excel Col Y: Country
  country TEXT,

  -- Excel Col Z: City
  city TEXT,

  -- Excel Col AA: Cooldown Until
  cooldown_until DATE,

  -- Excel Col AB: Do Not Contact
  do_not_contact BOOLEAN NOT NULL DEFAULT FALSE,

  -- Excel Col AC: Cooldown Status (populated by trigger, see migration 010.4)
  cooldown_status_derived cooldown_status,

  -- Excel Col AD: Date Added
  date_added DATE NOT NULL DEFAULT CURRENT_DATE,

  -- Excel Col AE: SN Lists (which Sales Nav lists this contact appears in)
  sn_lists TEXT[],

  -- NEW columns
  legacy_source TEXT,
  migrated_at TIMESTAMPTZ,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
