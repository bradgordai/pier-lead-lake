-- Migration 009: Supporting tables
-- Section 9 of pier-supabase-migration-spec.md
-- agent_handover, nightly_summary, agent_errors, blocklist, drafts_feedback,
-- duplicate_candidates, saved_views, insights_snapshots

-- 9.1 agent_handover
-- Cross-agent request channel per Oli's inter_agent_handover.md pattern.
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

-- 9.2 nightly_summary
-- Coordinator writes end-of-run summary. Feeds Home tab.
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

-- 9.3 errors
-- Any agent writes on failure. Agents self-report so Brad can monitor.
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

-- 9.4 blocklist
-- Do Not Contact list. Any entity that should never be reached out to.
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

-- 9.5 drafts_feedback
-- Structured feedback when Oli rejects a draft. Feeds Response Bank / Capture Processor.
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

-- 9.6 duplicate_candidates
-- Two-stage dedup pipeline per research findings. Reviewer queue.
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

-- 9.7 saved_views
-- Named views per user with filters, sort, columns.
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

-- 9.8 insights_snapshots
-- Store Companies Agent similar-companies output (hidden from Oli, fed to
-- research subagent).
CREATE TABLE public.insights_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  similar_companies UUID[], -- array of company IDs
  similarity_scores JSONB, -- {company_id: score}
  computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
