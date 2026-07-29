-- Migration 028: research_agent_config (Master Prompt + source URLs)
--
-- Storage for the Research Agent's "Master Prompt" (free-text guidance for the
-- autonomous nightly runs) and a list of source URLs (trade-fair / event exhibitor
-- pages the agent should scrape for new leads). One config row per team, enforced by
-- a UNIQUE constraint on team_id. This is STORAGE + UI only — no agent is wired to it
-- yet (Phase 5). RLS is team-scoped SELECT/INSERT/UPDATE via fn_user_teams(); there is
-- deliberately NO DELETE policy (a team's config is never deleted, only edited).
--
-- source_urls and active are NOT NULL with defaults so the UI can always treat them as
-- a concrete array / boolean. updated_at is maintained by the existing
-- public.tg_update_updated_at() trigger fn (same one used by company_documents in 025).
--
-- A single empty config row is seeded for every existing team on apply, so
-- getResearchAgentConfigFn always finds a row (the UI still upserts defensively).
--
-- Supabase applies each migration file atomically in a single transaction, so any
-- failure below rolls the whole file back (no partial schema).

CREATE TABLE public.research_agent_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL UNIQUE REFERENCES public.teams(id) ON DELETE CASCADE,
  master_prompt TEXT,
  source_urls TEXT[] NOT NULL DEFAULT '{}',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER tg_research_agent_config_updated_at
  BEFORE UPDATE ON public.research_agent_config
  FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();

ALTER TABLE public.research_agent_config ENABLE ROW LEVEL SECURITY;

-- SELECT + INSERT + UPDATE only (no DELETE policy, per spec).
CREATE POLICY research_agent_config_select ON public.research_agent_config FOR SELECT
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY research_agent_config_insert ON public.research_agent_config FOR INSERT
  WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY research_agent_config_update ON public.research_agent_config FOR UPDATE
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()))
  WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));

-- Seed one empty config per existing team (idempotent via the UNIQUE team_id).
INSERT INTO public.research_agent_config (team_id)
SELECT id FROM public.teams
ON CONFLICT (team_id) DO NOTHING;
