-- 092 F14.4 (2026-09-14): the thread_text_missing gate counted connection requests, which are blank by
-- design, so a contact whose only prior touch is a CR refused forever. Made consistent with
-- fn_chase_candidates (touch_type <> 'Connection request'). Nothing else in the gate changes.
-- Also: a flag (default false) that lets the chase engine draft a FIRST MESSAGE AFTER CR ACCEPTED for
-- accepted contacts with no real message yet. Off = the engine behaves exactly as before.
alter table public.team_settings add column if not exists first_message_after_cr_enabled boolean not null default false;
alter table public.team_settings add column if not exists first_message_cap_per_run int not null default 5;
comment on column public.team_settings.first_message_after_cr_enabled is 'F14.4: when true the daily chase engine also drafts first messages for accepted, never-messaged contacts (trigger cr_accepted, never a chaser, never counts toward a chaser cap). Default false: Brad flips it.';
comment on column public.team_settings.first_message_cap_per_run is 'F14.4: max first-message drafts per engine run when the flag is on.';

CREATE OR REPLACE FUNCTION public.fn_evaluate_gates(p_team_id uuid, p_contact_id uuid, p_channel text, p_requested text)
 RETURNS TABLE(reason_code text, reason_human text, context jsonb)
 LANGUAGE plpgsql STABLE SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c record; co record; s record; v_cap int; v_sent int; v_email_ok boolean; v_bodies int; v_outbound int;
  v_country text; v_sibs jsonb; v_sib_names text;
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
  IF c.outreach_status::text = 'Parked' THEN
    RETURN QUERY SELECT 'contact_parked',
      'Contact is parked (UK is Jack''s territory and is not being worked in Monday yet).',
      jsonb_build_object('country', c.country);
    RETURN;
  END IF;
  IF p_requested IN ('initial_message','connection_request') AND co.id IS NOT NULL AND co.parent_group IS NOT NULL THEN
    SELECT jsonb_agg(jsonb_build_object('company_ref', g.company_ref, 'company_name', g.company_name, 'why', g.why)),
           string_agg(g.company_name || ' (' || g.why || ')', ', ')
      INTO v_sibs, v_sib_names FROM public.fn_group_siblings_engaged(p_team_id, co.id) g;
    IF v_sibs IS NOT NULL THEN
      RETURN QUERY SELECT 'group_sibling_engaged',
        format('%s belongs to the group "%s", and a sibling is already being worked: %s. One approach per group; consolidate before sending.', coalesce(co.company_name,'This company'), co.parent_group, v_sib_names),
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
  IF p_requested IN ('initial_message','chaser','reply') THEN
    IF co.id IS NULL OR co.research_stage::text IS DISTINCT FROM 'Deep research done' THEN
      RETURN QUERY SELECT 'company_not_deep_researched',
        format('%s is at "%s"; a message needs deep research first.', coalesce(co.company_name,'The company'), coalesce(co.research_stage::text,'no company linked')),
        jsonb_build_object('company_id', co.id, 'research_stage', co.research_stage::text);
      RETURN;
    END IF;
  END IF;
  IF p_requested IN ('chaser','reply') THEN
    -- F14.4: a connection request carries no text by design and is not part of the thread the
    -- no-repetition check reads. Same filter as fn_chase_candidates.
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

-- Accepted, never messaged, nothing pending, no reply on file: the contacts a first message after
-- CR accepted is for. Read by the engine only when team_settings.first_message_after_cr_enabled.
CREATE OR REPLACE FUNCTION public.fn_first_message_candidates(p_team_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(contact_id uuid, company_id uuid, accepted_on date, priority text, connection_status text)
 LANGUAGE sql STABLE SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT c.id, c.company_id, c.last_contacted, co.priority::text, c.connection_status::text
    FROM public.contacts c
    LEFT JOIN public.companies co ON co.id = c.company_id
   WHERE c.team_id = p_team_id
     AND c.archived_at IS NULL
     AND (co.id IS NULL OR co.archived_at IS NULL)
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
