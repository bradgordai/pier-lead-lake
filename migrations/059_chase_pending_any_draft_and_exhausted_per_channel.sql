-- 059: two chase-engine alignments the migration needs (applied 2026-09-04).
-- 1. Any UNSENT pending_review draft parks a contact (Oli's legacy drafts included, which are
--    not agent_produced). 060 later tightened "pending" to send_status Draft/Ready; the
--    fn_chase_candidates body below is the 060 (current) text so a replay lands on the final state.
-- 2. fn_chase_exhausted applies the per-channel caps (C1) instead of the deprecated chaser_cap.

CREATE OR REPLACE FUNCTION public.fn_chase_candidates(p_team_id uuid, p_limit integer DEFAULT 25)
 RETURNS TABLE(contact_id uuid, company_id uuid, chaser_number integer, route text, channel text, cap integer, is_final boolean, last_outbound date, days_since integer, priority text, connection_status text)
 LANGUAGE sql STABLE
AS $function$
  WITH settings AS (
    SELECT coalesce(chase_interval_days, 7) AS interval_days, coalesce(dm_chaser_cap, 3) AS dm_cap, coalesce(inmail_chaser_cap, 1) AS inmail_cap
    FROM public.team_settings WHERE team_id = p_team_id
    UNION ALL SELECT 7, 3, 1 LIMIT 1
  ),
  outbound AS (
    SELECT o.contact_id,
           max(o.touch_date) FILTER (WHERE o.touch_type::text <> 'Connection request') AS last_msg,
           max(o.touch_date) FILTER (WHERE o.touch_type::text =  'Connection request') AS last_cr,
           count(*) FILTER (WHERE o.touch_type::text LIKE 'Chaser %' AND o.channel::text = 'LinkedIn DM')     AS dm_chasers,
           count(*) FILTER (WHERE o.touch_type::text LIKE 'Chaser %' AND o.channel::text = 'LinkedIn inMail') AS inmail_chasers
    FROM public.outreach_log o
    WHERE o.team_id = p_team_id AND o.touch_type::text <> 'Reply' AND o.send_status::text = 'Sent'
    GROUP BY o.contact_id
  ),
  inbound AS (
    SELECT o.contact_id, max(o.touch_date) AS last_reply FROM public.outreach_log o
    WHERE o.team_id = p_team_id AND o.touch_type::text = 'Reply' GROUP BY o.contact_id
  ),
  pending AS (
    SELECT DISTINCT o.contact_id FROM public.outreach_log o
    WHERE o.team_id = p_team_id AND o.draft_status::text = 'pending_review' AND o.send_status::text IN ('Draft','Ready')
  ),
  base AS (
    SELECT c.id AS contact_id, c.company_id,
      CASE WHEN c.connection_status::text IN ('Accepted','Already connected') THEN 'accepted_chase' ELSE 'cr_not_accepted' END AS route,
      CASE WHEN c.connection_status::text IN ('Accepted','Already connected') THEN 'LinkedIn DM' ELSE 'LinkedIn inMail' END AS channel,
      CASE WHEN c.connection_status::text IN ('Accepted','Already connected') THEN s.dm_cap ELSE s.inmail_cap END AS cap,
      CASE WHEN c.connection_status::text IN ('Accepted','Already connected') THEN coalesce(ob.dm_chasers, 0) ELSE coalesce(ob.inmail_chasers, 0) END AS chasers_on_channel,
      CASE WHEN c.connection_status::text IN ('Accepted','Already connected') THEN ob.last_msg ELSE ob.last_cr END AS last_outbound,
      ib.last_reply, s.interval_days, co.priority::text AS priority, c.connection_status::text AS connection_status
    FROM public.contacts c
    JOIN settings s ON true
    LEFT JOIN public.companies co ON co.id = c.company_id
    LEFT JOIN outbound ob ON ob.contact_id = c.id
    LEFT JOIN inbound  ib ON ib.contact_id = c.id
    WHERE c.team_id = p_team_id
      AND c.archived_at IS NULL
      AND coalesce(c.do_not_contact, false) = false
      AND coalesce(c.promise_of_quiet, false) = false
      AND (co.id IS NULL OR co.archived_at IS NULL)
      AND c.outreach_status::text NOT IN ('Do not contact','Not relevant','Opted out','Left company','Meeting booked','Parked')
      AND (c.cooldown_until IS NULL OR c.cooldown_until <= CURRENT_DATE)
      AND (c.chase_scheduled_for IS NULL OR c.chase_scheduled_for <= CURRENT_DATE)
      AND c.id NOT IN (SELECT contact_id FROM pending)
  )
  SELECT b.contact_id, b.company_id, (b.chasers_on_channel + 1)::int, b.route, b.channel, b.cap, ((b.chasers_on_channel + 1) >= b.cap), b.last_outbound, (CURRENT_DATE - b.last_outbound)::int, b.priority, b.connection_status
  FROM base b
  WHERE b.chasers_on_channel < b.cap
    AND b.last_outbound IS NOT NULL
    AND b.last_outbound <= CURRENT_DATE - b.interval_days
    AND (b.last_reply IS NULL OR b.last_reply < b.last_outbound)
  ORDER BY CASE b.priority WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END, b.last_outbound ASC
  LIMIT p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.fn_chase_exhausted(p_team_id uuid, p_limit integer DEFAULT 100)
 RETURNS TABLE(contact_id uuid, company_id uuid, last_chaser date)
 LANGUAGE sql STABLE
AS $function$
  WITH settings AS (
    SELECT coalesce(chase_interval_days, 7) AS interval_days, coalesce(dm_chaser_cap, 3) AS dm_cap, coalesce(inmail_chaser_cap, 1) AS inmail_cap
    FROM public.team_settings WHERE team_id = p_team_id
    UNION ALL SELECT 7, 3, 1 LIMIT 1
  ),
  chasers AS (
    SELECT o.contact_id, o.channel::text AS channel, max(o.touch_date) AS last_chaser, count(*) AS n
    FROM public.outreach_log o
    WHERE o.team_id = p_team_id AND o.touch_type::text LIKE 'Chaser %' AND o.send_status::text = 'Sent'
    GROUP BY o.contact_id, o.channel
  ),
  inbound AS (
    SELECT o.contact_id, max(o.touch_date) AS last_reply FROM public.outreach_log o
    WHERE o.team_id = p_team_id AND o.touch_type::text = 'Reply' GROUP BY o.contact_id
  )
  SELECT c.id, c.company_id, ch.last_chaser
  FROM public.contacts c
  JOIN settings s ON true
  JOIN chasers ch ON ch.contact_id = c.id
    AND ch.channel = CASE WHEN c.connection_status::text IN ('Accepted','Already connected') THEN 'LinkedIn DM' ELSE 'LinkedIn inMail' END
  LEFT JOIN inbound ib ON ib.contact_id = c.id
  WHERE c.team_id = p_team_id
    AND c.archived_at IS NULL
    AND ch.n >= CASE WHEN c.connection_status::text IN ('Accepted','Already connected') THEN s.dm_cap ELSE s.inmail_cap END
    AND ch.last_chaser <= CURRENT_DATE - s.interval_days
    AND (ib.last_reply IS NULL OR ib.last_reply < ch.last_chaser)
    AND c.chase_state IS DISTINCT FROM 'exhausted'
  LIMIT p_limit;
$function$;
