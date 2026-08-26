-- 040_create_api_call_log.sql
-- Cost sentinel, Task 1: one row per Anthropic API call made from an Edge Function.
--
-- RLS uses the existing fn_user_teams() helper rather than an inline
-- `team_id IN (SELECT team_id FROM team_members WHERE user_id = auth.uid())` subquery as
-- the spec wrote it. fn_user_teams() is the established house pattern here (it is STABLE
-- SECURITY DEFINER with a pinned search_path) and avoids re-evaluating auth.uid() per row.
--
-- No INSERT/UPDATE/DELETE policy is defined: writes come only from Edge Functions using
-- service_role, which bypasses RLS. Signed-in users get read access to their own team's
-- rows and nothing more.
--
-- estimated_cost_gbp is numeric(10,6) - sub-penny resolution, since a single Haiku call
-- can cost well under 0.01.

CREATE TABLE IF NOT EXISTS public.api_call_log (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id               uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  function_name         text NOT NULL,
  model                 text NOT NULL,
  input_tokens          integer NOT NULL DEFAULT 0,
  output_tokens         integer NOT NULL DEFAULT 0,
  cache_creation_tokens integer NOT NULL DEFAULT 0,
  cache_read_tokens     integer NOT NULL DEFAULT 0,
  thinking_tokens       integer NOT NULL DEFAULT 0,
  estimated_cost_gbp    numeric(10,6) NOT NULL DEFAULT 0,
  request_context       jsonb,
  succeeded             boolean NOT NULL DEFAULT true,
  error_message         text,
  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_call_log_created  ON public.api_call_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_call_log_function ON public.api_call_log (function_name, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_call_log_team     ON public.api_call_log (team_id);

ALTER TABLE public.api_call_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS api_call_log_team_read ON public.api_call_log;
CREATE POLICY api_call_log_team_read ON public.api_call_log
  FOR SELECT USING (team_id IN (SELECT fn_user_teams()));

COMMENT ON TABLE public.api_call_log IS
  'One row per Anthropic API call from an Edge Function. Written by service_role via the anthropic-sentinel helper.';
