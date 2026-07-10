-- Migration 007: Outreach Log
-- Section 7 of pier-supabase-migration-spec.md
-- 18 columns mirroring Excel v09 exactly, plus columns for the agent-managed
-- drafts and lint results.

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
