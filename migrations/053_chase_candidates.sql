-- 053_chase_candidates.sql
-- B5 chase engine: due-detection lives in SQL so it is inspectable and testable on its
-- own, and the Edge Function stays a thin loop over the result.
--
-- Returns one row per contact that is DUE a chaser right now, with the chaser number and
-- the route. The engine reads contacts.chase_* (the 052 contract) but recomputes the
-- clock from outreach_log, so a contact whose chase_* fields were never populated (every
-- contact today, until tonight's catch-up migration runs) is still handled correctly.
-- That is deliberate: the engine must not depend on the migration having run first.
--
-- ROUTES
--   accepted_chase   connection accepted, an initial message went out, no reply since
--   cr_not_accepted  a CR was sent, never accepted, older than the interval
--
-- EXCLUSIONS applied here rather than in the function, so a suppressed contact never
-- costs a model call: archived contact, archived company, do_not_contact, and the
-- outreach_status set that means "stop" (Do not contact / Not relevant / Opted out /
-- Left company / Meeting booked). Cooldown and future scheduling are honoured too.
--
-- chaser_count is read from contacts (authoritative, counts SENT chasers) but falls back
-- to counting sent chaser touches when it is 0, so the engine behaves correctly before
-- tonight's migration backfills the column.

CREATE OR REPLACE FUNCTION public.fn_chase_candidates(
  p_team_id uuid,
  p_limit   int DEFAULT 25
)
RETURNS TABLE (
  contact_id      uuid,
  company_id      uuid,
  chaser_number   int,
  route           text,
  last_outbound   date,
  days_since      int,
  priority        text,
  connection_status text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH settings AS (
    SELECT coalesce(chase_interval_days, 7) AS interval_days,
           coalesce(chaser_cap, 2)          AS cap
    FROM public.team_settings WHERE team_id = p_team_id
    UNION ALL SELECT 7, 2
    LIMIT 1
  ),
  outbound AS (
    SELECT o.contact_id,
           max(o.touch_date) FILTER (WHERE o.touch_type <> 'Connection request') AS last_msg,
           max(o.touch_date) FILTER (WHERE o.touch_type =  'Connection request') AS last_cr,
           count(*) FILTER (WHERE o.touch_type IN ('Chaser 1','Chaser 2','Chaser 3')) AS chasers_sent
    FROM public.outreach_log o
    WHERE o.team_id = p_team_id
      AND o.touch_type <> 'Reply'
      AND o.send_status = 'Sent'
    GROUP BY o.contact_id
  ),
  inbound AS (
    SELECT o.contact_id, max(o.touch_date) AS last_reply
    FROM public.outreach_log o
    WHERE o.team_id = p_team_id AND o.touch_type = 'Reply'
    GROUP BY o.contact_id
  ),
  -- A pending agent draft already covers this contact; do not queue another.
  pending AS (
    SELECT DISTINCT o.contact_id
    FROM public.outreach_log o
    WHERE o.team_id = p_team_id
      AND o.draft_status = 'pending_review'
      AND o.agent_produced
  )
  SELECT
    c.id,
    c.company_id,
    (greatest(c.chaser_count, coalesce(ob.chasers_sent, 0)) + 1)::int AS chaser_number,
    CASE WHEN c.connection_status = 'Accepted' THEN 'accepted_chase' ELSE 'cr_not_accepted' END AS route,
    CASE WHEN c.connection_status = 'Accepted' THEN ob.last_msg ELSE ob.last_cr END AS last_outbound,
    (CURRENT_DATE - CASE WHEN c.connection_status = 'Accepted' THEN ob.last_msg ELSE ob.last_cr END)::int AS days_since,
    co.priority::text,
    c.connection_status::text
  FROM public.contacts c
  JOIN settings s ON true
  LEFT JOIN public.companies co ON co.id = c.company_id
  LEFT JOIN outbound ob ON ob.contact_id = c.id
  LEFT JOIN inbound  ib ON ib.contact_id = c.id
  WHERE c.team_id = p_team_id
    AND c.archived_at IS NULL
    AND coalesce(c.do_not_contact, false) = false
    AND (co.id IS NULL OR co.archived_at IS NULL)
    AND c.outreach_status NOT IN ('Do not contact','Not relevant','Opted out','Left company','Meeting booked')
    AND (c.cooldown_until IS NULL OR c.cooldown_until <= CURRENT_DATE)
    -- An explicit future date parks the contact until that date arrives (26 Oct re-engagement).
    AND (c.chase_scheduled_for IS NULL OR c.chase_scheduled_for <= CURRENT_DATE)
    AND c.id NOT IN (SELECT contact_id FROM pending)
    -- Cap: never queue chaser N when N already exceeds the cap.
    AND greatest(c.chaser_count, coalesce(ob.chasers_sent, 0)) < s.cap
    AND (
      (c.connection_status = 'Accepted'
        AND ob.last_msg IS NOT NULL
        AND ob.last_msg <= CURRENT_DATE - s.interval_days
        AND (ib.last_reply IS NULL OR ib.last_reply < ob.last_msg))
      OR
      (c.connection_status IS DISTINCT FROM 'Accepted'
        AND ob.last_cr IS NOT NULL
        AND ob.last_cr <= CURRENT_DATE - s.interval_days
        AND (ib.last_reply IS NULL OR ib.last_reply < ob.last_cr))
    )
  -- Capacity-aware ordering: priority first, then oldest waiting. Backlog waits for the
  -- next run rather than being dropped.
  ORDER BY
    CASE co.priority::text WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
    CASE WHEN c.connection_status = 'Accepted' THEN ob.last_msg ELSE ob.last_cr END ASC
  LIMIT p_limit;
$$;

COMMENT ON FUNCTION public.fn_chase_candidates(uuid, int) IS
  'B5: contacts due a chaser now, priority-first then oldest-first. Excludes archived/DNC/stopped contacts, cooldown, future-scheduled, cap-reached, and contacts that already have a pending agent draft.';

-- Contacts whose cadence is finished: chaser cap reached, interval elapsed since the last
-- chaser, still no reply. The engine sets cooldown and logs a register row for these.
CREATE OR REPLACE FUNCTION public.fn_chase_exhausted(p_team_id uuid, p_limit int DEFAULT 100)
RETURNS TABLE (contact_id uuid, company_id uuid, last_chaser date)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH settings AS (
    SELECT coalesce(chase_interval_days, 7) AS interval_days,
           coalesce(chaser_cap, 2)          AS cap
    FROM public.team_settings WHERE team_id = p_team_id
    UNION ALL SELECT 7, 2
    LIMIT 1
  ),
  chasers AS (
    SELECT o.contact_id, max(o.touch_date) AS last_chaser, count(*) AS n
    FROM public.outreach_log o
    WHERE o.team_id = p_team_id
      AND o.touch_type IN ('Chaser 1','Chaser 2','Chaser 3')
      AND o.send_status = 'Sent'
    GROUP BY o.contact_id
  ),
  inbound AS (
    SELECT o.contact_id, max(o.touch_date) AS last_reply
    FROM public.outreach_log o
    WHERE o.team_id = p_team_id AND o.touch_type = 'Reply'
    GROUP BY o.contact_id
  )
  SELECT c.id, c.company_id, ch.last_chaser
  FROM public.contacts c
  JOIN settings s ON true
  JOIN chasers ch ON ch.contact_id = c.id
  LEFT JOIN inbound ib ON ib.contact_id = c.id
  WHERE c.team_id = p_team_id
    AND c.archived_at IS NULL
    AND ch.n >= s.cap
    AND ch.last_chaser <= CURRENT_DATE - s.interval_days
    AND (ib.last_reply IS NULL OR ib.last_reply < ch.last_chaser)
    AND c.chase_state IS DISTINCT FROM 'exhausted'
  LIMIT p_limit;
$$;

COMMENT ON FUNCTION public.fn_chase_exhausted(uuid, int) IS
  'B5: contacts that have had the full chaser cap with no reply and are past the interval. Engine sets cooldown_until and logs a register row. There is never a third chaser.';
