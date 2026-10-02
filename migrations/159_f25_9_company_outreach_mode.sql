-- 159 F25 Task 9: a company-level outreach switch (Oliver: "in conversation with the CEO at AFB and the system kept drafting
-- to other people there"). DRAFTING only in F25; CR queue behaviour is F26.
--   companies.outreach_mode text NOT NULL default 'continue', CHECK continue | pause_messages | pause_crs | pause_all
--   (text + CHECK, not an enum, so F26 can extend it without an enum migration).
--   fn_evaluate_gates: pause_messages / pause_all REFUSE with reason_code company_outreach_paused (Oliver's explicit
--   instruction, so a refusal, not a flag), placed after the absolute gates. Replies are exempt (see the comment in the
--   gate). pause_messages lets a connection_request through; pause_all does not. The rest of the function is byte for
--   byte migration 151 (live md5 bd344049 measured 2 Oct before this change).
--   refusals_reason_code_check gains company_outreach_paused (the gate would otherwise throw on its first refusal).
--   The candidate functions do NOT call fn_evaluate_gates, so the gate alone would leave paused contacts in candidacy and
--   produce a refusal row every morning. fn_chase_candidates, fn_first_message_candidates and fn_cold_inmail_candidates
--   gain one predicate excluding pause_messages / pause_all companies; their other text is unchanged.
--   fn_reply_candidates is deliberately NOT filtered: a reply to someone at a paused company is still drafted.
-- Every company stays on 'continue'. Brad sets AFB himself.

alter table public.companies add column if not exists outreach_mode text not null default 'continue';
alter table public.companies drop constraint if exists companies_outreach_mode_check;
alter table public.companies add constraint companies_outreach_mode_check
  check (outreach_mode in ('continue','pause_messages','pause_crs','pause_all'));
comment on column public.companies.outreach_mode is
  'F25.9 Oliver''s company switch: continue | pause_messages | pause_crs | pause_all. pause_messages/pause_all refuse new drafts (gate company_outreach_paused); replies exempt. pause_crs takes effect in F26.';

alter table public.refusals drop constraint if exists refusals_reason_code_check;
alter table public.refusals add constraint refusals_reason_code_check check (reason_code = any (array[
  'allowance_exhausted','promise_of_quiet','dnc_or_opted_out','cr_cooldown_active','company_not_deep_researched',
  'thread_text_missing','channel_illegal_in_market','contact_parked','contact_replied','group_sibling_engaged',
  'country_unknown','pending_ruling','company_archived','recipient_blocked','company_outreach_paused']::text[]));

CREATE OR REPLACE FUNCTION public.fn_evaluate_gates(p_team_id uuid, p_contact_id uuid, p_channel text, p_requested text)
 RETURNS TABLE(reason_code text, reason_human text, context jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c record; co record; s record; v_cap int; v_sent int; v_email_ok boolean; v_bodies int; v_outbound int;
  v_country text; v_sibs jsonb; v_sib_names text; v_ruling text; v_research_applies boolean;
BEGIN
  SELECT * INTO c FROM public.contacts WHERE id = p_contact_id AND team_id = p_team_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'dnc_or_opted_out', 'Contact not found in this team.', jsonb_build_object('contact_id', p_contact_id);
    RETURN;
  END IF;
  SELECT * INTO co FROM public.companies WHERE id = c.company_id;
  SELECT * INTO s  FROM public.team_settings WHERE team_id = p_team_id;

  IF coalesce(c.promise_of_quiet, false) THEN
    RETURN QUERY SELECT 'promise_of_quiet',
      'This contact was given a written promise that we would stop contacting them. That promise is binding on every channel.',
      jsonb_build_object('note', c.promise_of_quiet_note);
    RETURN;
  END IF;
  IF coalesce(c.do_not_contact, false) OR c.outreach_status::text IN ('Do not contact','Opted out','Not relevant','Left company') THEN
    RETURN QUERY SELECT 'dnc_or_opted_out',
      format('Contact is excluded from outreach (%s).', coalesce(nullif(c.outreach_status::text,''),'do_not_contact')),
      jsonb_build_object('outreach_status', c.outreach_status::text, 'do_not_contact', coalesce(c.do_not_contact,false));
    RETURN;
  END IF;
  -- F23.5: blocked by the recipient on LinkedIn. A fact, not a preference: every message would fail. Absolute.
  IF coalesce(c.is_blocked, false) THEN
    RETURN QUERY SELECT 'recipient_blocked',
      'This person has blocked Oliver on LinkedIn, so no message can reach them on any LinkedIn channel.',
      jsonb_build_object('blocked_at', c.blocked_at);
    RETURN;
  END IF;
  -- F25.9: Oliver's company-level switch. pause_messages and pause_all refuse every NEW approach at the company;
  -- pause_messages still lets a connection request through, pause_all does not. A reply is never refused here: the
  -- point of a pause is usually that Oliver is already in conversation with someone at the company (F16.16 rule).
  -- pause_crs and continue do not affect drafting in F25 (the CR queue is F26).
  IF co.id IS NOT NULL AND coalesce(co.outreach_mode, 'continue') IN ('pause_messages','pause_all')
     AND coalesce(p_requested, '') <> 'reply'
     AND NOT (co.outreach_mode = 'pause_messages' AND p_requested = 'connection_request') THEN
    RETURN QUERY SELECT 'company_outreach_paused',
      format('Oliver has set %s to "%s": no new %s is drafted for anyone there until he changes it on the company page.',
             coalesce(co.company_name, 'this company'),
             CASE co.outreach_mode WHEN 'pause_all' THEN 'pause all outreach' ELSE 'pause messages' END,
             CASE co.outreach_mode WHEN 'pause_all' THEN 'message or connection request' ELSE 'message' END),
      jsonb_build_object('company_id', co.id, 'outreach_mode', co.outreach_mode);
    RETURN;
  END IF;
  IF c.outreach_status::text = 'Parked' THEN
    RETURN QUERY SELECT 'contact_parked',
      'Contact is parked (UK is Jack''s territory and is not being worked in Monday yet).',
      jsonb_build_object('country', c.country);
    RETURN;
  END IF;
  IF c.outreach_status::text = 'Needs review' THEN
    SELECT r.reason_human INTO v_ruling FROM public.refusals r WHERE r.contact_id = c.id AND r.reason_code = 'pending_ruling' ORDER BY r.created_at DESC LIMIT 1;
    IF v_ruling IS NOT NULL THEN
      RETURN QUERY SELECT 'pending_ruling', 'Awaiting Oliver''s ruling: '||v_ruling, jsonb_build_object('outreach_status', c.outreach_status::text);
      RETURN;
    END IF;
  END IF;
  -- F16.1: the group guard runs for every NEW approach (initial_message, connection_request, chaser).
  -- F16.16: a reply is never a new approach; the drafter shows the collision as a note instead.
  IF co.id IS NOT NULL AND p_requested <> 'reply' THEN
    SELECT jsonb_agg(jsonb_build_object('company_ref', g.company_ref, 'company_name', g.company_name, 'why', g.why)),
           string_agg(g.company_name || ' (' || g.why || ')', ', ')
      INTO v_sibs, v_sib_names FROM public.fn_group_siblings_engaged(p_team_id, co.id) g;
    IF v_sibs IS NOT NULL THEN
      RETURN QUERY SELECT 'group_sibling_engaged',
        format('%s is linked to a company already being worked: %s. One approach per group; consolidate before sending.', coalesce(co.company_name,'This company'), v_sib_names),
        jsonb_build_object('parent_group', co.parent_group, 'siblings', v_sibs);
      RETURN;
    END IF;
  END IF;
  IF p_requested = 'chaser' AND c.chase_state = 'replied' THEN
    RETURN QUERY SELECT 'contact_replied',
      'This contact has replied; the chase is over. Answer the reply instead of sending a chaser.',
      jsonb_build_object('chase_state', c.chase_state);
    RETURN;
  END IF;
  IF p_requested = 'connection_request' AND c.cr_blocked_until IS NOT NULL AND c.cr_blocked_until > CURRENT_DATE THEN
    RETURN QUERY SELECT 'cr_cooldown_active',
      format('A new connection request is blocked until %s (six months after withdrawal).', c.cr_blocked_until),
      jsonb_build_object('cr_blocked_until', c.cr_blocked_until);
    RETURN;
  END IF;
  IF p_requested = 'chaser' THEN
    v_cap := CASE p_channel WHEN 'LinkedIn DM' THEN coalesce(s.dm_chaser_cap, 3) WHEN 'LinkedIn inMail' THEN coalesce(s.inmail_chaser_cap, 1)
                            WHEN 'Email' THEN coalesce(s.email_chaser_cap, 3) ELSE coalesce(s.dm_chaser_cap, 3) END;
    SELECT count(*) INTO v_sent FROM public.outreach_log o
     WHERE o.team_id = p_team_id AND o.contact_id = p_contact_id AND o.touch_type::text LIKE 'Chaser %'
       AND o.send_status::text = 'Sent' AND o.channel::text = p_channel;
    IF v_sent >= v_cap THEN
      RETURN QUERY SELECT 'allowance_exhausted', format('%s chaser allowance used: %s of %s sent.', p_channel, v_sent, v_cap),
        jsonb_build_object('channel', p_channel, 'sent', v_sent, 'cap', v_cap);
      RETURN;
    END IF;
  END IF;
  IF p_channel = 'Email' THEN
    v_country := nullif(btrim(coalesce(c.country, '')), '');
    IF v_country IS NULL AND co.id IS NOT NULL AND coalesce(co.country_inferred, false) = false AND coalesce(co.field_provenance->'country'->>'source','stated') <> 'inferred' THEN
      v_country := nullif(btrim(coalesce(co.country, '')), '');
    END IF;
    IF v_country IS NULL THEN
      RETURN QUERY SELECT 'country_unknown',
        'No stated country on the contact or the company (an inferred country does not count), so email legality cannot be established. Blocked.',
        jsonb_build_object('contact_country', c.country, 'company_country', co.country, 'company_country_inferred', coalesce(co.country_inferred,false));
      RETURN;
    END IF;
    SELECT m.cold_email_legal INTO v_email_ok FROM public.markets m WHERE lower(m.country) = lower(v_country);
    IF coalesce(v_email_ok, false) = false THEN
      RETURN QUERY SELECT 'channel_illegal_in_market',
        format('Cold email is not permitted in %s without prior consent.', v_country),
        jsonb_build_object('country', v_country, 'cold_email_legal', v_email_ok);
      RETURN;
    END IF;
  END IF;
  v_research_applies := p_requested IN ('initial_message','chaser','reply')
                        AND NOT (p_requested = 'reply' AND coalesce(s.reply_ignores_research_gate, false))
                        AND NOT coalesce(s.research_gate_warns_only, false);
  IF v_research_applies THEN
    IF co.id IS NULL OR co.research_stage::text IS DISTINCT FROM 'Deep research done' THEN
      RETURN QUERY SELECT 'company_not_deep_researched',
        format('%s is at "%s"; a message needs deep research first.', coalesce(co.company_name,'The company'), coalesce(co.research_stage::text,'no company linked')),
        jsonb_build_object('company_id', co.id, 'research_stage', co.research_stage::text);
      RETURN;
    END IF;
  END IF;
  IF p_requested IN ('chaser','reply') THEN
    SELECT count(*), count(*) FILTER (WHERE btrim(coalesce(o.sent_body, o.message_body, '')) <> '') INTO v_outbound, v_bodies
      FROM public.outreach_log o WHERE o.team_id = p_team_id AND o.contact_id = p_contact_id
       AND o.touch_type::text NOT IN ('Reply','Connection request') AND o.send_status::text = 'Sent';
    IF v_outbound > 0 AND v_bodies = 0 THEN
      RETURN QUERY SELECT 'thread_text_missing',
        format('%s prior sent touch(es) have no recorded text, so the no-repetition check cannot run.', v_outbound),
        jsonb_build_object('outbound_sent', v_outbound, 'with_text', v_bodies);
      RETURN;
    END IF;
  END IF;
  RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_chase_candidates(p_team_id uuid, p_limit integer DEFAULT 25)
 RETURNS TABLE(contact_id uuid, company_id uuid, chaser_number integer, route text, channel text, cap integer, is_final boolean, last_outbound date, days_since integer, priority text, connection_status text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH settings AS (
    SELECT coalesce(chase_interval_days, 7) AS interval_days, coalesce(dm_chaser_cap, 3) AS dm_cap, coalesce(inmail_chaser_cap, 1) AS inmail_cap
    FROM public.team_settings WHERE team_id = p_team_id
    UNION ALL SELECT 7, 3, 1 LIMIT 1
  ),
  outbound AS (
    SELECT o.contact_id,
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
      AND (co.id IS NULL OR co.outreach_mode NOT IN ('pause_messages','pause_all'))
      AND c.outreach_status::text NOT IN ('Do not contact','Not relevant','Opted out','Left company','Meeting booked','Parked')
      AND NOT (c.outreach_status::text = 'Needs review' AND EXISTS (SELECT 1 FROM public.refusals r WHERE r.contact_id = c.id AND r.reason_code = 'pending_ruling'))
      AND (c.cooldown_until IS NULL OR c.cooldown_until <= CURRENT_DATE)
      AND (c.chase_scheduled_for IS NULL OR c.chase_scheduled_for <= CURRENT_DATE)
      AND c.chase_state IS DISTINCT FROM 'replied'
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

CREATE OR REPLACE FUNCTION public.fn_first_message_candidates(p_team_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(contact_id uuid, company_id uuid, accepted_on date, priority text, connection_status text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT c.id, c.company_id, c.last_contacted, co.priority::text, c.connection_status::text
    FROM public.contacts c
    LEFT JOIN public.companies co ON co.id = c.company_id
   WHERE c.team_id = p_team_id
     AND c.archived_at IS NULL
     AND (co.id IS NULL OR co.archived_at IS NULL)
     AND (co.id IS NULL OR co.outreach_mode NOT IN ('pause_messages','pause_all'))
     AND c.connection_status::text IN ('Accepted','Already connected')
     AND coalesce(c.do_not_contact, false) = false
     AND coalesce(c.promise_of_quiet, false) = false
     AND c.outreach_status::text NOT IN ('Do not contact','Not relevant','Opted out','Left company','Meeting booked','Parked','In conversation')
     AND c.chase_state IS DISTINCT FROM 'replied'
     AND (c.cooldown_until IS NULL OR c.cooldown_until <= CURRENT_DATE)
     AND NOT EXISTS (SELECT 1 FROM public.outreach_log o WHERE o.contact_id = c.id AND o.send_status::text = 'Sent'
                       AND o.touch_type::text NOT IN ('Reply','Connection request') AND o.draft_status::text <> 'superseded')
     AND NOT EXISTS (SELECT 1 FROM public.outreach_log o WHERE o.contact_id = c.id AND o.draft_status::text = 'pending_review')
     AND NOT EXISTS (SELECT 1 FROM public.outreach_log o WHERE o.contact_id = c.id AND o.touch_type::text = 'Reply')
   ORDER BY CASE co.priority::text WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END, c.last_contacted ASC NULLS LAST
   LIMIT p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cold_inmail_candidates(p_team_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(contact_id uuid, company_id uuid, last_cr date, priority text, connection_status text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
     AND (co.id IS NULL OR co.outreach_mode NOT IN ('pause_messages','pause_all'))
     AND c.connection_status::text NOT IN ('Accepted','Already connected')
     AND coalesce(c.do_not_contact, false) = false
     AND coalesce(c.promise_of_quiet, false) = false
     AND c.outreach_status::text NOT IN ('Do not contact','Not relevant','Opted out','Left company','Meeting booked','Parked','In conversation','Needs review')
     AND c.chase_state IS DISTINCT FROM 'replied'
     AND (c.cooldown_until IS NULL OR c.cooldown_until <= CURRENT_DATE)
     AND (c.chase_scheduled_for IS NULL OR c.chase_scheduled_for <= CURRENT_DATE)
     AND co.research_stage::text = 'Deep research done'
     AND NOT EXISTS (SELECT 1 FROM public.outreach_log o WHERE o.contact_id = c.id AND o.send_status::text = 'Sent'
                       AND o.touch_type::text NOT IN ('Reply','Connection request'))
     AND NOT EXISTS (SELECT 1 FROM public.outreach_log o WHERE o.contact_id = c.id AND o.draft_status::text IN ('pending_review','approved'))
     AND NOT EXISTS (SELECT 1 FROM public.outreach_log o WHERE o.contact_id = c.id AND o.touch_type::text = 'Reply')
     AND coalesce((SELECT max(coalesce((o.sent_at_actual at time zone 'Europe/London')::date, o.touch_date)) FROM public.outreach_log o
                     WHERE o.contact_id = c.id AND o.send_status::text = 'Sent' AND o.touch_type::text = 'Connection request'), CURRENT_DATE - s.interval_days)
         <= CURRENT_DATE - s.interval_days
   ORDER BY CASE co.priority::text WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END, 3 ASC NULLS LAST
   LIMIT p_limit;
$function$;
