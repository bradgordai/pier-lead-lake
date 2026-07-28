-- Migration 024: data_quality_snapshots + capture function
--
-- Powers the Insights tab's data-quality trend chart. A snapshot records the
-- distinct-gap and gap-instance counts for a team on a given day. The Insights
-- tab has a "Take snapshot now" button; weekly automation (pg_cron) is a future
-- backlog item and is deliberately NOT added here.
--
-- fn_capture_dq_snapshot mirrors the gap logic in dataQualityFn EXACTLY:
--   company gaps (active pipeline, archived_at IS NULL): website_url null,
--     country null/'' , category null/empty array, priority null.
--   contact gaps: linkedin_url null/'' , email null/''.
--   *_with_gaps  = DISTINCT rows missing ANY of those fields.
--   *_instances  = SUM of the individual gap counts (double-counts multi-gap rows).
-- Because it is SECURITY DEFINER (bypasses RLS) it scopes explicitly on team_id.
--
-- Supabase applies each migration file atomically in a single transaction, so any
-- failure below rolls the whole file back (no partial schema).

CREATE TABLE public.data_quality_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  snapshot_date DATE NOT NULL,
  companies_with_gaps INT NOT NULL,
  gap_instances INT NOT NULL,
  contacts_with_gaps INT NOT NULL,
  contact_gap_instances INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (team_id, snapshot_date)
);
CREATE INDEX idx_dq_snapshots_team_date ON public.data_quality_snapshots (team_id, snapshot_date);

ALTER TABLE public.data_quality_snapshots ENABLE ROW LEVEL SECURITY;
-- SELECT + INSERT only (append-only history, no update/delete policies for users).
CREATE POLICY dq_snapshots_select ON public.data_quality_snapshots FOR SELECT
  USING (team_id IN (SELECT team_id FROM public.fn_user_teams()));
CREATE POLICY dq_snapshots_insert ON public.data_quality_snapshots FOR INSERT
  WITH CHECK (team_id IN (SELECT team_id FROM public.fn_user_teams()));

CREATE OR REPLACE FUNCTION public.fn_capture_dq_snapshot(p_team_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today   date := (current_timestamp AT TIME ZONE 'Europe/London')::date;
  v_web int; v_country int; v_cat int; v_prio int; v_cwg int; v_gi int;
  v_li int; v_email int; v_ctwg int; v_ctgi int;
BEGIN
  SELECT
    count(*) FILTER (WHERE website_url IS NULL),
    count(*) FILTER (WHERE country IS NULL OR country = ''),
    count(*) FILTER (WHERE category IS NULL OR cardinality(category) = 0),
    count(*) FILTER (WHERE priority IS NULL),
    count(*) FILTER (WHERE website_url IS NULL
                        OR country IS NULL OR country = ''
                        OR category IS NULL OR cardinality(category) = 0
                        OR priority IS NULL)
  INTO v_web, v_country, v_cat, v_prio, v_cwg
  FROM public.companies
  WHERE team_id = p_team_id AND archived_at IS NULL;

  v_gi := v_web + v_country + v_cat + v_prio;

  SELECT
    count(*) FILTER (WHERE linkedin_url IS NULL OR linkedin_url = ''),
    count(*) FILTER (WHERE email IS NULL OR email = ''),
    count(*) FILTER (WHERE (linkedin_url IS NULL OR linkedin_url = '')
                        OR (email IS NULL OR email = ''))
  INTO v_li, v_email, v_ctwg
  FROM public.contacts
  WHERE team_id = p_team_id;

  v_ctgi := v_li + v_email;

  INSERT INTO public.data_quality_snapshots
    (team_id, snapshot_date, companies_with_gaps, gap_instances, contacts_with_gaps, contact_gap_instances)
  VALUES (p_team_id, v_today, v_cwg, v_gi, v_ctwg, v_ctgi)
  ON CONFLICT (team_id, snapshot_date) DO UPDATE
    SET companies_with_gaps   = EXCLUDED.companies_with_gaps,
        gap_instances         = EXCLUDED.gap_instances,
        contacts_with_gaps    = EXCLUDED.contacts_with_gaps,
        contact_gap_instances = EXCLUDED.contact_gap_instances;
END;
$$;

-- Initial snapshot per team so the trend chart has a starting dot.
DO $$
DECLARE t record;
BEGIN
  FOR t IN SELECT id FROM public.teams LOOP
    PERFORM public.fn_capture_dq_snapshot(t.id);
  END LOOP;
END $$;
