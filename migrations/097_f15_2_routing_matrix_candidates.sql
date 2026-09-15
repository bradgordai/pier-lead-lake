-- 097 F15.2 (2026-09-15): routing matrix in the candidate functions.
-- Invariant (a): a chaser exists only when a REAL message (not a connection request) was Sent on that same
-- channel; otherwise the next touch is an Initial message.  Invariant (b): channel follows connection state:
-- DM only to Accepted / Already connected, InMail to everyone else.
-- Before this, fn_chase_candidates clocked the InMail route off the last CONNECTION REQUEST, so 107 contacts
-- who had never received a message were queued as "InMail Chaser 1" (the 06:15 cron defect).
-- r1 (cold InMail opener) now has its own candidate function and its own per-run cap in team_settings.

alter table public.team_settings add column if not exists cold_inmail_openers_per_run integer not null default 5;

CREATE OR REPLACE FUNCTION public.fn_chase_candidates(p_team_id uuid, p_limit integer DEFAULT 25)
 RETURNS TABLE(contact_id uuid, company_id uuid, chaser_number integer, route text, channel text, cap integer, is_final boolean, last_outbound date, days_since integer, priority text, connection_status text)
 LANGUAGE sql STABLE SET search_path TO 'public', 'pg_temp' AS $function$
  WITH settings AS (
    SELECT coalesce(chase_interval_days, 7) AS interval_days, coalesce(dm_chaser_cap, 3) AS dm_cap, coalesce(inmail_chaser_cap, 1) AS inmail_cap
    FROM public.team_settings WHERE team_id = p_team_id
    UNION ALL SELECT 7, 3, 1 LIMIT 1
  ),
  outbound AS (
    SELECT o.contact_id,
           -- real messages per channel (invariant a): the chase clock and the right to chase both come from these
           max(coalesce((o.sent_at_actual at time zone 'Europe/London')::date, o.touch_date)) FILTER (WHERE o.touch_type::text <> 'Connection request' AND o.channel::text = 'LinkedIn DM')     AS last_dm_msg,
           max(coalesce((o.sent_at_actual at time zone 'Europe/London')::date, o.touch_date)) FILTER (WHERE o.touch_type::text <> 'Connection request' AND o.channel::text = 'LinkedIn inMail') AS last_inmail_msg,
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
      -- the clock is the last REAL message on the channel we would chase on; a CR never starts a chase
      CASE WHEN c.connection_status::text IN ('Accepted','Already connected') THEN ob.last_dm_msg ELSE ob.last_inmail_msg END AS last_outbound,
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
      AND NOT (c.outreach_status::text = 'Needs review' AND EXISTS (SELECT 1 FROM public.refusals r WHERE r.contact_id = c.id AND r.reason_code = 'pending_ruling'))
      AND (c.cooldown_until IS NULL OR c.cooldown_until <= CURRENT_DATE)
      AND (c.chase_scheduled_for IS NULL OR c.chase_scheduled_for <= CURRENT_DATE)
      AND c.chase_state IS DISTINCT FROM 'replied'          -- F8/068: a reply ends the chase, hard block
      AND c.id NOT IN (SELECT contact_id FROM pending)
  )
  SELECT b.contact_id, b.company_id, (b.chasers_on_channel + 1)::int, b.route, b.channel, b.cap, ((b.chasers_on_channel + 1) >= b.cap), b.last_outbound, (CURRENT_DATE - b.last_outbound)::int, b.priority, b.connection_status
  FROM base b
  WHERE b.chasers_on_channel < b.cap
    AND b.last_outbound IS NOT NULL                          -- invariant (a): no real message on this channel, no chaser
    AND b.last_outbound <= CURRENT_DATE - b.interval_days
    AND (b.last_reply IS NULL OR b.last_reply < b.last_outbound)
  ORDER BY CASE b.priority WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END, b.last_outbound ASC
  LIMIT p_limit;
$function$;

-- r1: not connected (Request sent / Withdrawn / Ignored / Not connected), never messaged on any channel -> cold InMail opener.
-- Clock: the CR (if any) must be older than the chase interval, so an outstanding request gets its chance first.
CREATE OR REPLACE FUNCTION public.fn_cold_inmail_candidates(p_team_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(contact_id uuid, company_id uuid, last_cr date, priority text, connection_status text)
 LANGUAGE sql STABLE SET search_path TO 'public', 'pg_temp' AS $function$
  WITH settings AS (
    SELECT coalesce(chase_interval_days, 7) AS interval_days FROM public.team_settings WHERE team_id = p_team_id
    UNION ALL SELECT 7 LIMIT 1
  )
  SELECT c.id, c.company_id,
         (SELECT max(coalesce((o.sent_at_actual at time zone 'Europe/London')::date, o.touch_date)) FROM public.outreach_log o
           WHERE o.contact_id = c.id AND o.send_status::text = 'Sent' AND o.touch_type::text = 'Connection request') AS last_cr,
         co.priority::text, c.connection_status::text
    FROM public.contacts c
    JOIN settings s ON true
    LEFT JOIN public.companies co ON co.id = c.company_id
   WHERE c.team_id = p_team_id
     AND c.archived_at IS NULL
     AND (co.id IS NULL OR co.archived_at IS NULL)
     AND c.connection_status::text NOT IN ('Accepted','Already connected')          -- invariant (b): never a DM here, and never DM-shaped
     AND coalesce(c.do_not_contact, false) = false
     AND coalesce(c.promise_of_quiet, false) = false
     AND c.outreach_status::text NOT IN ('Do not contact','Not relevant','Opted out','Left company','Meeting booked','Parked','In conversation','Needs review')
     AND c.chase_state IS DISTINCT FROM 'replied'
     AND (c.cooldown_until IS NULL OR c.cooldown_until <= CURRENT_DATE)
     AND (c.chase_scheduled_for IS NULL OR c.chase_scheduled_for <= CURRENT_DATE)
     AND co.research_stage::text = 'Deep research done'                              -- r12 pre-filter; the gate re-checks
     AND NOT EXISTS (SELECT 1 FROM public.outreach_log o WHERE o.contact_id = c.id AND o.send_status::text = 'Sent'
                       AND o.touch_type::text NOT IN ('Reply','Connection request'))  -- never messaged anywhere
     AND NOT EXISTS (SELECT 1 FROM public.outreach_log o WHERE o.contact_id = c.id AND o.draft_status::text IN ('pending_review','approved'))
     AND NOT EXISTS (SELECT 1 FROM public.outreach_log o WHERE o.contact_id = c.id AND o.touch_type::text = 'Reply')
     AND coalesce((SELECT max(coalesce((o.sent_at_actual at time zone 'Europe/London')::date, o.touch_date)) FROM public.outreach_log o
                     WHERE o.contact_id = c.id AND o.send_status::text = 'Sent' AND o.touch_type::text = 'Connection request'), CURRENT_DATE - s.interval_days)
         <= CURRENT_DATE - s.interval_days
   ORDER BY CASE co.priority::text WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END, 3 ASC NULLS LAST
   LIMIT p_limit;
$function$;
