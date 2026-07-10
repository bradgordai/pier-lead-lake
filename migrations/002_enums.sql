-- Migration 002: Enums
-- Section 2 of pier-supabase-migration-spec.md
-- Every enum used across the schema, for referential integrity plus dropdown
-- values in Lovable.

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
