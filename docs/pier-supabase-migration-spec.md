# Supabase migration spec for pier-lead-lake-prod

Target project: `qzfrcfzeiagziqjnfarw` (Pier Insurance org, eu-west-1, Postgres 17)
Author: Brad Gordon (Nailed It AI) via Cowork
Date: 8 July 2026
For: Claude Code to translate into SQL migration files and apply via Supabase MCP

## How to use this document

Give this document to Claude Code with the instruction:

> Read this spec. Generate migration files under `migrations/` in the pier-lead-agent repo. Apply each migration to Supabase project qzfrcfzeiagziqjnfarw via the Supabase MCP `apply_migration` tool. After each migration, run `list_tables` verbose to confirm the change landed. If any step errors, halt, tell me what went wrong, propose a fix. Follow the ordering exactly.

## Ordering

Apply migrations in this order:

1. `001_enable_extensions.sql`
2. `002_enums.sql`
3. `003_teams_and_members.sql`
4. `004_reference_tables.sql` (pier_pipeline, eurefas_members)
5. `005_companies.sql`
6. `006_contacts.sql`
7. `007_outreach_log.sql`
8. `008_insurance_products_and_insurers.sql`
9. `009_supporting_tables.sql` (agent_handover, nightly_summary, blocklist, drafts_feedback, duplicate_candidates, saved_views, insights_snapshots)
10. `010_functions_and_triggers.sql`
11. `011_indexes.sql`
12. `012_rls_policies.sql`
13. `013_generated_columns.sql` (tracking cascade)
14. `014_pg_cron_schedules.sql` (V1.1, skip for now)

## 1. Enable extensions

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

Rationale: uuid-ossp for gen_random_uuid, pg_trgm for fuzzy search on company/contact names, pgvector for embedding-based similarity in the dedup pipeline, pgcrypto for random tokens.

Note: pg_cron is Supabase-managed. Enable via Supabase dashboard Extensions tab, not migration. V1.1.

## 2. Enums

Define every enum used across the schema so we get referential integrity plus dropdown values in Lovable.

```sql
-- Companies
CREATE TYPE priority_level AS ENUM ('P0', 'P1', 'P2', 'P3', 'OoS', 'Competitor');
CREATE TYPE research_stage AS ENUM ('Untouched', 'Light triage', 'Deep research done', 'Outdated');
CREATE TYPE opportunity_status AS ENUM ('To Review', 'Prospect', 'Contacted', 'Active Lead', 'Partner', 'Out of Scope');
CREATE TYPE company_category AS ENUM (
  'Pure Online Phone Retailer',
  'Refurbished Specialist',
  'Electronics',
  'Multi-Category Retailer',
  'Operator',
  'Manufacturer',
  'Marketplace',
  'Comparison Site',
  'Industry Media',
  'Influencer',
  'Other'
);
CREATE TYPE insurance_structure AS ENUM (
  'Optional Add-On',
  'Bundled',
  'Upsold',
  'Embedded in T&Cs',
  'Redirect to Third-Party',
  'Other'
);
CREATE TYPE industry_type AS ENUM (
  'Mobile/Gadget Retail',
  'Refurb / Recommerce',
  'Telco',
  'Manufacturer',
  'Software',
  'Telco Infrastructure',
  'Industry Media',
  'Influencer',
  'Other'
);
CREATE TYPE product_line AS ENUM ('Pier Protect', 'Ticketplan', 'TIGA', 'Multiple', 'Unknown');
CREATE TYPE account_owner AS ENUM ('Oliver Müller', 'Phil', 'Mark');
CREATE TYPE tracking_flag AS ENUM (
  'Live Partner',
  'Live Prospect',
  'In Lovable',
  'EUREFAS Member',
  'EUREFAS Founding Member',
  'No longer active',
  ''
);

-- Contacts
CREATE TYPE seniority_level AS ENUM ('C-suite', 'Senior', 'Director', 'Manager', 'Other');
CREATE TYPE function_type AS ENUM (
  'Alliances / BD',
  'Marketing',
  'Product',
  'Engineering',
  'Sales',
  'Finance',
  'Operations',
  'Legal',
  'HR',
  'Executive',
  'Other'
);
CREATE TYPE connection_level AS ENUM ('1st degree', '2nd degree', '3rd degree', 'Not connected');
CREATE TYPE formality_level AS ENUM ('Formal', 'Informal');
CREATE TYPE language_code AS ENUM ('EN', 'DE', 'FR', 'ES', 'IT', 'NL', 'Other');
CREATE TYPE connection_status AS ENUM (
  'Not connected',
  'Request sent',
  'Accepted',
  'Already connected',
  'Ignored',
  'Withdrawn'
);
CREATE TYPE outreach_status AS ENUM (
  'Not started',
  'Ready',
  'Active',
  'Contacted',
  'In conversation',
  'Cooldown',
  'Needs review',
  'Do not contact',
  'Left company'
);
CREATE TYPE cooldown_status AS ENUM ('Not in cooldown', 'In cooldown', 'Ready for re-engagement');

-- Outreach Log
CREATE TYPE outreach_channel AS ENUM ('LinkedIn DM', 'LinkedIn CR', 'LinkedIn inMail', 'Email', 'Phone', 'In-person', 'Other');
CREATE TYPE outreach_type AS ENUM (
  'Initial message',
  'Connection request',
  'Chase',
  'Reply',
  'Event follow-up',
  'Introduction',
  'Meeting confirmation',
  'Other'
);
CREATE TYPE send_status AS ENUM ('Draft', 'Ready', 'Scheduled', 'Sent', 'Cancelled');
CREATE TYPE outcome_status AS ENUM ('Awaiting reply', 'Replied / Accepted', 'No reply', 'Rejected / Bounced', 'Withdrawn');
CREATE TYPE reply_classification AS ENUM (
  'Positive interest',
  'Neutral',
  'Objection',
  'Not interested',
  'Out of office',
  'Wrong person',
  'Do not contact',
  'Booked meeting',
  'Uncategorised'
);
CREATE TYPE draft_status AS ENUM ('pending_review', 'approved', 'sent', 'superseded', 'rejected');
CREATE TYPE message_path AS ENUM ('A', 'B', 'C', 'Unassigned');
CREATE TYPE psychological_frame AS ENUM ('Discovery', 'Diagnostic', 'Alternative', 'Ally', 'Peer', 'Unassigned');
CREATE TYPE story_arc AS ENUM ('A', 'B', 'C', 'D', 'E', 'Unassigned');

-- Agent Handover
CREATE TYPE agent_name AS ENUM (
  'coordinator',
  'companies',
  'contact',
  'outbound',
  'outreach',
  'reconciliation',
  'human'
);
CREATE TYPE handover_status AS ENUM ('open', 'resolved', 'blocked');
CREATE TYPE handover_request_type AS ENUM (
  'create_c_row',
  'verify_match',
  'correct_match',
  'update_insurance_state',
  'update_contact_status',
  'reclassify_priority',
  'update_research_stage',
  'other'
);

-- Duplicate candidates
CREATE TYPE duplicate_entity_type AS ENUM ('company', 'contact');
CREATE TYPE duplicate_review_status AS ENUM ('pending', 'approved', 'rejected', 'merged');
CREATE TYPE blocking_key_type AS ENUM ('domain', 'email', 'name_trigram', 'phone_prefix', 'linkedin_url', 'embedding');
```

## 3. Teams and members (auth foundation)

Team-scoped RLS is the baseline pattern per research. Every table has team_id, policies check membership.

For V1 single team (Pier), this is boilerplate. But we set it up now to avoid a painful retrofit.

```sql
CREATE TABLE public.teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.team_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member', -- 'owner', 'admin', 'member', 'read_only'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (team_id, user_id)
);

-- Seed the Pier team
INSERT INTO public.teams (name, slug) VALUES ('Pier Insurance', 'pier');
```

## 4. Reference tables

### 4.1 pier_pipeline

Live partners and prospects. Read-only reference, used by tracking cascade.

```sql
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
```

### 4.2 eurefas_members

27 members of European Refurbishment Association. Read-only reference.

```sql
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
```

## 5. Companies

39 columns mirroring Excel v09 exactly, plus 5 new columns for the new build.

```sql
CREATE TABLE public.companies (
  -- Primary key + team
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,

  -- Excel Col A: Company ID (Cnnn sequential)
  company_id TEXT NOT NULL UNIQUE,

  -- Excel Col B: Company Name
  company_name TEXT NOT NULL,

  -- Excel Col C: Tracking (GENERATED, see migration 013)
  tracking tracking_flag,

  -- Excel Col D: Priority
  priority priority_level,

  -- Excel Col E: Research Stage
  research_stage research_stage NOT NULL DEFAULT 'Untouched',

  -- Excel Col F: Contacts count (GENERATED, see migration 013)
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
```

## 6. Contacts

31 columns mirroring Excel v09 exactly, plus a few new for the new build.

```sql
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

  -- Excel Col AC: Cooldown Status (GENERATED, see migration 013)
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
```

## 7. Outreach Log

18 columns mirroring Excel v09 exactly, plus columns for the agent-managed drafts and lint results.

```sql
CREATE TABLE public.outreach_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,

  -- Excel Col A: Touch ID (Tnnn)
  touch_id TEXT NOT NULL UNIQUE,

  -- Excel Col B: Contact ID FK (text + UUID)
  contact_ref TEXT, -- Pnnn for continuity
  contact_id UUID REFERENCES public.contacts(id) ON DELETE CASCADE,

  -- Denormalised FK for company (via contact.company_id, but useful for direct queries)
  company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,

  -- Excel Col H: Date
  touch_date DATE NOT NULL,

  -- Excel Col I: Channel
  channel outreach_channel NOT NULL,

  -- Excel Col J: Sent By
  sent_by TEXT,

  -- Excel Col K: Type
  touch_type outreach_type NOT NULL,

  -- Excel Col L: Message Body / Notes
  message_body TEXT,

  -- Excel Col M: Send Status
  send_status send_status NOT NULL DEFAULT 'Draft',

  -- Excel Col N: Outcome
  outcome outcome_status,

  -- Excel Col O: Next Action
  next_action TEXT,

  -- Excel Col P: Next Action Date
  next_action_date DATE,

  -- Excel Col Q: Reply Classification
  reply_classification reply_classification,

  -- Excel Col R: Subject Line
  subject_line TEXT,

  -- NEW columns for agent-managed drafts
  draft_status draft_status NOT NULL DEFAULT 'pending_review',
  pre_lint_pass BOOLEAN, -- NULL for migrated legacy, TRUE/FALSE for agent-produced
  voice_contract_violations JSONB, -- list of linter flags
  lint_score INTEGER, -- 0-100, populated by agent when internal scoring is available
  path message_path,
  recommended_frame psychological_frame,
  recommended_arc story_arc,
  thread_id UUID, -- for grouping related touches into a thread
  reply_received_at TIMESTAMPTZ,
  reply_content TEXT,
  rejection_feedback JSONB, -- structured rejection reason + free text from Oli
  migrated_legacy BOOLEAN NOT NULL DEFAULT FALSE, -- true for touches migrated from Excel
  agent_produced BOOLEAN NOT NULL DEFAULT FALSE, -- true when Outbound Agent authored
  legacy_source TEXT,
  migrated_at TIMESTAMPTZ,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

## 8. Insurance Products and Insurers

Keep from the current UK Lovable pattern. Auto-generated from Companies data.

```sql
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
```

## 9. Supporting tables

### 9.1 agent_handover

Cross-agent request channel per Oli's inter_agent_handover.md pattern.

```sql
CREATE TABLE public.agent_handover (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  from_agent agent_name NOT NULL,
  to_agent agent_name NOT NULL,
  request_type handover_request_type NOT NULL,
  entity_type TEXT, -- 'company' | 'contact' | 'outreach' | NULL
  entity_id UUID,
  payload JSONB NOT NULL DEFAULT '{}',
  status handover_status NOT NULL DEFAULT 'open',
  resolution_marker TEXT,
  resolved_by_agent agent_name,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 9.2 nightly_summary

Coordinator writes end-of-run summary. Feeds Home tab.

```sql
CREATE TABLE public.nightly_summary (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  run_date DATE NOT NULL,
  run_started_at TIMESTAMPTZ NOT NULL,
  run_completed_at TIMESTAMPTZ,
  companies_triaged INTEGER NOT NULL DEFAULT 0,
  companies_deep_researched INTEGER NOT NULL DEFAULT 0,
  companies_deep_researched_qualified INTEGER NOT NULL DEFAULT 0,
  contacts_matched INTEGER NOT NULL DEFAULT 0,
  contacts_unmatched INTEGER NOT NULL DEFAULT 0,
  drafts_produced INTEGER NOT NULL DEFAULT 0,
  drafts_lint_failed INTEGER NOT NULL DEFAULT 0,
  errors_caught INTEGER NOT NULL DEFAULT 0,
  api_tokens_used_sonnet INTEGER NOT NULL DEFAULT 0,
  api_tokens_used_haiku INTEGER NOT NULL DEFAULT 0,
  api_cost_gbp NUMERIC(10,4) NOT NULL DEFAULT 0,
  run_duration_minutes NUMERIC,
  run_notes TEXT,
  UNIQUE (team_id, run_date)
);
```

### 9.3 errors

Any agent writes on failure. Agents self-report so Brad can monitor.

```sql
CREATE TABLE public.agent_errors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  agent_name agent_name NOT NULL,
  error_type TEXT NOT NULL,
  error_message TEXT,
  entity_type TEXT,
  entity_id UUID,
  context JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 9.4 blocklist

Do Not Contact list. Any entity that should never be reached out to.

```sql
CREATE TABLE public.blocklist (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL, -- 'company' | 'contact'
  entity_id UUID NOT NULL,
  reason TEXT,
  added_by_agent agent_name,
  added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (team_id, entity_type, entity_id)
);
```

### 9.5 drafts_feedback

Structured feedback when Oli rejects a draft. Feeds Response Bank / Capture Processor.

```sql
CREATE TABLE public.drafts_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  outreach_log_id UUID NOT NULL REFERENCES public.outreach_log(id) ON DELETE CASCADE,
  reason TEXT NOT NULL, -- 'Voice off', 'Fact wrong', 'Framing wrong', 'Timing wrong', 'Register wrong', 'Other'
  detail TEXT, -- free text from Oli
  suggested_alternative TEXT, -- optional: what would be right
  feedback_from_user_id UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 9.6 duplicate_candidates

Two-stage dedup pipeline per research findings. Reviewer queue.

```sql
CREATE TABLE public.duplicate_candidates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  entity_type duplicate_entity_type NOT NULL,
  source_a_id UUID NOT NULL,
  source_b_id UUID NOT NULL,
  blocking_key blocking_key_type NOT NULL,
  match_score NUMERIC(4,3) NOT NULL, -- 0.000 to 1.000
  match_details JSONB, -- which fields matched, similarity scores per field
  status duplicate_review_status NOT NULL DEFAULT 'pending',
  reviewed_by_user_id UUID REFERENCES auth.users(id),
  reviewed_at TIMESTAMPTZ,
  rejection_reason TEXT,
  merged_into_id UUID, -- which of source_a or source_b won on merge
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 9.7 saved_views

Named views per user with filters, sort, columns.

```sql
CREATE TABLE public.saved_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  view_name TEXT NOT NULL,
  target_table TEXT NOT NULL, -- 'companies' | 'contacts' | 'outreach_log'
  filters JSONB NOT NULL DEFAULT '{}',
  sort JSONB NOT NULL DEFAULT '{}',
  columns JSONB NOT NULL DEFAULT '{}',
  is_shared BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, target_table, view_name)
);
```

### 9.8 insights_snapshots

Store Companies Agent similar-companies output (hidden from Oli per his decision, fed to research subagent).

```sql
CREATE TABLE public.insights_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  similar_companies UUID[], -- array of company IDs
  similarity_scores JSONB, -- {company_id: score}
  computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

## 10. Functions and triggers

### 10.1 Auto updated_at

Standard pattern. Every table with updated_at gets this trigger.

```sql
CREATE OR REPLACE FUNCTION public.tg_update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to every table with updated_at
CREATE TRIGGER tg_companies_updated_at BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_contacts_updated_at BEFORE UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_outreach_log_updated_at BEFORE UPDATE ON public.outreach_log FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_insurers_updated_at BEFORE UPDATE ON public.insurers FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_insurance_products_updated_at BEFORE UPDATE ON public.insurance_products FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_teams_updated_at BEFORE UPDATE ON public.teams FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_pier_pipeline_updated_at BEFORE UPDATE ON public.pier_pipeline FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_eurefas_members_updated_at BEFORE UPDATE ON public.eurefas_members FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_saved_views_updated_at BEFORE UPDATE ON public.saved_views FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
```

### 10.2 Auto contacts_count on companies

Whenever a contact is added/deleted/moved, recompute the contacts_count on the affected companies. Materialised as a column so filter queries stay fast.

```sql
CREATE OR REPLACE FUNCTION public.tg_recompute_contacts_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.companies SET contacts_count = contacts_count + 1 WHERE id = NEW.company_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.companies SET contacts_count = GREATEST(contacts_count - 1, 0) WHERE id = OLD.company_id;
  ELSIF TG_OP = 'UPDATE' AND OLD.company_id IS DISTINCT FROM NEW.company_id THEN
    IF OLD.company_id IS NOT NULL THEN
      UPDATE public.companies SET contacts_count = GREATEST(contacts_count - 1, 0) WHERE id = OLD.company_id;
    END IF;
    IF NEW.company_id IS NOT NULL THEN
      UPDATE public.companies SET contacts_count = contacts_count + 1 WHERE id = NEW.company_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_contacts_after_change AFTER INSERT OR UPDATE OR DELETE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.tg_recompute_contacts_count();
```

### 10.3 Normalise email + domain

Populate email_normalised and root_domain on write.

```sql
CREATE OR REPLACE FUNCTION public.fn_normalise_email(input TEXT)
RETURNS TEXT AS $$
BEGIN
  IF input IS NULL THEN RETURN NULL; END IF;
  RETURN lower(trim(input));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION public.fn_extract_root_domain(url TEXT)
RETURNS TEXT AS $$
DECLARE
  cleaned TEXT;
BEGIN
  IF url IS NULL THEN RETURN NULL; END IF;
  cleaned := lower(url);
  cleaned := regexp_replace(cleaned, '^https?://', '');
  cleaned := regexp_replace(cleaned, '^www\.', '');
  cleaned := split_part(cleaned, '/', 1);
  RETURN cleaned;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION public.tg_normalise_contact_fields()
RETURNS TRIGGER AS $$
BEGIN
  NEW.email_normalised := public.fn_normalise_email(NEW.email);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.tg_normalise_company_fields()
RETURNS TRIGGER AS $$
BEGIN
  NEW.root_domain := public.fn_extract_root_domain(NEW.website_url);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_contacts_normalise BEFORE INSERT OR UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.tg_normalise_contact_fields();
CREATE TRIGGER tg_companies_normalise BEFORE INSERT OR UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.tg_normalise_company_fields();
```

### 10.4 Cooldown status derivation

Mirror Excel col AC formula.

```sql
CREATE OR REPLACE FUNCTION public.tg_update_cooldown_status()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.outreach_status = 'Cooldown' THEN
    IF NEW.cooldown_until IS NOT NULL AND NEW.cooldown_until <= CURRENT_DATE THEN
      NEW.cooldown_status_derived := 'Ready for re-engagement';
    ELSE
      NEW.cooldown_status_derived := 'In cooldown';
    END IF;
  ELSE
    NEW.cooldown_status_derived := 'Not in cooldown';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_contacts_cooldown BEFORE INSERT OR UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.tg_update_cooldown_status();
```

### 10.5 Auto-resolve tracking flag on companies

Mirror Excel col C VLOOKUP cascade: Pier Pipeline > EUREFAS > default.

```sql
CREATE OR REPLACE FUNCTION public.tg_resolve_tracking()
RETURNS TRIGGER AS $$
DECLARE
  pipeline_stage TEXT;
  eurefas_membership TEXT;
BEGIN
  -- Check Pier Pipeline first
  SELECT stage INTO pipeline_stage FROM public.pier_pipeline WHERE lower(company_name) = lower(NEW.company_name) AND deleted = FALSE LIMIT 1;
  IF pipeline_stage IS NOT NULL THEN
    NEW.tracking := CASE
      WHEN pipeline_stage = 'Live Partner' THEN 'Live Partner'::tracking_flag
      WHEN pipeline_stage = 'Live Prospect' THEN 'Live Prospect'::tracking_flag
      WHEN pipeline_stage = 'No longer active' THEN 'No longer active'::tracking_flag
      ELSE ''::tracking_flag
    END;
    RETURN NEW;
  END IF;

  -- Check EUREFAS
  SELECT membership INTO eurefas_membership FROM public.eurefas_members WHERE lower(company_name) = lower(NEW.company_name) LIMIT 1;
  IF eurefas_membership = 'Founding member' THEN
    NEW.tracking := 'EUREFAS Founding Member'::tracking_flag;
  ELSIF eurefas_membership IS NOT NULL THEN
    NEW.tracking := 'EUREFAS Member'::tracking_flag;
  ELSE
    NEW.tracking := ''::tracking_flag;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_companies_tracking BEFORE INSERT OR UPDATE OF company_name ON public.companies FOR EACH ROW EXECUTE FUNCTION public.tg_resolve_tracking();
```

Note: cannot use GENERATED column here because we need conditional lookup across other tables. Trigger is the right pattern.

## 11. Indexes

Every FK gets a btree. Search fields get GIN (trigram). Frequent filter fields get btree.

```sql
-- Companies
CREATE INDEX idx_companies_team_id ON public.companies(team_id);
CREATE INDEX idx_companies_priority ON public.companies(priority);
CREATE INDEX idx_companies_research_stage ON public.companies(research_stage);
CREATE INDEX idx_companies_country ON public.companies(country);
CREATE INDEX idx_companies_product_line ON public.companies(product_line);
CREATE INDEX idx_companies_account_owner ON public.companies(account_owner);
CREATE INDEX idx_companies_opportunity_status ON public.companies(opportunity_status);
CREATE INDEX idx_companies_archived_at ON public.companies(archived_at) WHERE archived_at IS NULL;
CREATE INDEX idx_companies_root_domain ON public.companies(root_domain);
CREATE INDEX idx_companies_company_id ON public.companies(company_id);
CREATE INDEX idx_companies_name_trgm ON public.companies USING GIN (lower(company_name) gin_trgm_ops);
CREATE INDEX idx_companies_notes_trgm ON public.companies USING GIN (lower(usp_notes) gin_trgm_ops);

-- Contacts
CREATE INDEX idx_contacts_team_id ON public.contacts(team_id);
CREATE INDEX idx_contacts_company_id ON public.contacts(company_id);
CREATE INDEX idx_contacts_company_ref ON public.contacts(company_ref);
CREATE INDEX idx_contacts_email_normalised ON public.contacts(email_normalised);
CREATE INDEX idx_contacts_outreach_status ON public.contacts(outreach_status);
CREATE INDEX idx_contacts_connection_status ON public.contacts(connection_status);
CREATE INDEX idx_contacts_seniority ON public.contacts(seniority);
CREATE INDEX idx_contacts_country ON public.contacts(country);
CREATE INDEX idx_contacts_do_not_contact ON public.contacts(do_not_contact) WHERE do_not_contact = FALSE;
CREATE INDEX idx_contacts_name_trgm ON public.contacts USING GIN (lower(first_name || ' ' || last_name) gin_trgm_ops);
CREATE INDEX idx_contacts_last_contacted ON public.contacts(last_contacted);
CREATE INDEX idx_contacts_next_action_date ON public.contacts(next_action_date);

-- Outreach Log
CREATE INDEX idx_outreach_team_id ON public.outreach_log(team_id);
CREATE INDEX idx_outreach_contact_id ON public.outreach_log(contact_id);
CREATE INDEX idx_outreach_company_id ON public.outreach_log(company_id);
CREATE INDEX idx_outreach_touch_date ON public.outreach_log(touch_date);
CREATE INDEX idx_outreach_send_status ON public.outreach_log(send_status);
CREATE INDEX idx_outreach_draft_status ON public.outreach_log(draft_status);
CREATE INDEX idx_outreach_channel ON public.outreach_log(channel);
CREATE INDEX idx_outreach_touch_type ON public.outreach_log(touch_type);
CREATE INDEX idx_outreach_thread_id ON public.outreach_log(thread_id);
CREATE INDEX idx_outreach_pre_lint_pass ON public.outreach_log(pre_lint_pass);
CREATE INDEX idx_outreach_reply_classification ON public.outreach_log(reply_classification);
CREATE INDEX idx_outreach_body_trgm ON public.outreach_log USING GIN (lower(message_body) gin_trgm_ops);

-- Reference tables
CREATE INDEX idx_pier_pipeline_name_lower ON public.pier_pipeline(lower(company_name)) WHERE deleted = FALSE;
CREATE INDEX idx_eurefas_name_lower ON public.eurefas_members(lower(company_name));

-- Supporting
CREATE INDEX idx_agent_handover_status ON public.agent_handover(status);
CREATE INDEX idx_agent_handover_to_agent ON public.agent_handover(to_agent) WHERE status = 'open';
CREATE INDEX idx_agent_handover_entity ON public.agent_handover(entity_type, entity_id);
CREATE INDEX idx_nightly_summary_date ON public.nightly_summary(run_date DESC);
CREATE INDEX idx_agent_errors_created ON public.agent_errors(created_at DESC);
CREATE INDEX idx_blocklist_entity ON public.blocklist(entity_type, entity_id);
CREATE INDEX idx_drafts_feedback_outreach ON public.drafts_feedback(outreach_log_id);
CREATE INDEX idx_duplicate_candidates_status ON public.duplicate_candidates(status) WHERE status = 'pending';
CREATE INDEX idx_duplicate_candidates_entity ON public.duplicate_candidates(entity_type, source_a_id, source_b_id);
CREATE INDEX idx_saved_views_user_table ON public.saved_views(user_id, target_table);
```

## 12. RLS policies

**HARD RULE**: after this migration lands, Claude Code MUST run:

```sql
SELECT tablename, policyname, cmd, qual, with_check FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename, policyname;
```

And return the output to Brad for a hand-audit. Per research findings, 89% of Lovable RLS is misconfigured. We do not ship without a manual review.

Pattern: enable RLS on every table, then team-scoped policies with `(SELECT auth.uid())` wrapping.

```sql
-- Enable RLS on every table
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outreach_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pier_pipeline ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eurefas_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurance_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_handover ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nightly_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_errors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocklist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drafts_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.duplicate_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insights_snapshots ENABLE ROW LEVEL SECURITY;

-- Helper: is user a member of this team?
CREATE OR REPLACE FUNCTION public.fn_user_teams()
RETURNS TABLE (team_id UUID) AS $$
  SELECT tm.team_id FROM public.team_members tm WHERE tm.user_id = (SELECT auth.uid());
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Policies for each table
-- Pattern: SELECT / INSERT / UPDATE / DELETE all check membership via team_id

-- Companies
CREATE POLICY companies_select ON public.companies FOR SELECT USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY companies_insert ON public.companies FOR INSERT WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY companies_update ON public.companies FOR UPDATE USING (team_id IN (SELECT team_id FROM public.fn_user_teams())) WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY companies_delete ON public.companies FOR DELETE USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Repeat exact same 4 policies for every table with team_id
-- (contacts, outreach_log, pier_pipeline, eurefas_members, insurers, insurance_products,
--  agent_handover, nightly_summary, agent_errors, blocklist, drafts_feedback,
--  duplicate_candidates, saved_views, insights_snapshots)

-- teams table: user reads teams they belong to
CREATE POLICY teams_select ON public.teams FOR SELECT USING (id IN (SELECT team_id FROM public.fn_user_teams()));
-- team_members: user reads their own memberships and other members of their teams
CREATE POLICY team_members_select ON public.team_members FOR SELECT USING (
  user_id = (SELECT auth.uid())
  OR team_id IN (SELECT team_id FROM public.fn_user_teams())
);

-- Service role bypasses RLS by default (it does anyway). Do NOT create policies that expand access via anon key.
```

Claude Code MUST paste the full policy set for all tables in the actual migration, this spec shows the pattern for companies as a template.

## 13. Generated columns (V1.1, defer)

The tracking cascade is handled by trigger (10.5), not a generated column, because it requires reading other tables. GENERATED STORED cannot do cross-table lookups.

If you want a materialised view for tracking stats (count of P0 companies, etc), add in V1.1.

## 14. pg_cron schedules (V1.1)

Not for V1. In V1.1 add:

- Refresh materialised views nightly
- Compute similar_companies daily (feeds hidden research agent insights)
- Recompute duplicate_candidates weekly

## Post-migration audit checklist

Claude Code runs this after all 12 migrations apply:

```sql
-- 1. Confirm every table has RLS enabled
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND NOT rowsecurity;
-- Expected: empty result. If any row returns, that table has no RLS. Halt and fix.

-- 2. Confirm no policies use USING (true)
SELECT tablename, policyname, qual FROM pg_policies WHERE schemaname = 'public' AND qual LIKE '%true%';
-- Expected: empty. If any row, that policy is wide open. Halt and fix.

-- 3. Confirm indexes exist on every FK
SELECT c.conname, c.conrelid::regclass AS table_name, a.attname AS column_name,
       EXISTS (SELECT 1 FROM pg_indexes i WHERE i.tablename = c.conrelid::regclass::text AND i.indexdef LIKE '%' || a.attname || '%') AS has_index
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace
ORDER BY table_name;
-- Expected: has_index = TRUE for every row. If FALSE anywhere, add the index.

-- 4. Confirm extensions enabled
SELECT extname FROM pg_extension WHERE extname IN ('uuid-ossp', 'pg_trgm', 'vector', 'pgcrypto');
-- Expected: 4 rows.

-- 5. Confirm enums created
SELECT typname FROM pg_type WHERE typtype = 'e' ORDER BY typname;
-- Expected: ~25 enum types.

-- 6. Count tables (sanity)
SELECT count(*) FROM pg_tables WHERE schemaname = 'public';
-- Expected: 17 (teams, team_members, companies, contacts, outreach_log, pier_pipeline, eurefas_members, insurers, insurance_products, agent_handover, nightly_summary, agent_errors, blocklist, drafts_feedback, duplicate_candidates, saved_views, insights_snapshots).
```

Return the audit output to Brad. If any check fails, halt.

## Next migrations (out of scope for this spec)

- 015: PhantomBuster webhook receiver Edge Function (V1)
- 016: Klaviyo Edge Function (V2)
- 017: MS365 email sync (V2)
- 018: Monday sync Edge Function (V1.1)
- 019: pg_cron nightly refresh jobs (V1.1)
- 020: materialised view for insights aggregates (V1.1)
