-- 151 F23 Task 5: blocked by recipient.
-- The Sales Nav inbox returns restriction='MEMBER_BLOCKED_BY_RECIPIENT' on four threads (Alexandra at Lenovo, both
-- mobileup contacts, Manuel at Jacob). Nothing in Supabase recorded it, so nothing stopped drafting to them.
-- contacts.is_blocked / blocked_at record it. fn_evaluate_gates gains 'recipient_blocked' as an ABSOLUTE refusal,
-- placed directly after dnc_or_opted_out and above every discretionary gate (a flag would only guarantee a failed send).
-- The refusals.reason_code check gains the new code so the drafter can record the refusal.
-- The rest of fn_evaluate_gates is byte-for-byte the live definition of 30 Sep (md5 18099d27...).
-- NO BACKFILL: nobody is flagged here; that waits for Oliver's call.

alter table public.contacts add column if not exists is_blocked boolean not null default false;
alter table public.contacts add column if not exists blocked_at timestamptz;

alter table public.refusals drop constraint if exists refusals_reason_code_check;
alter table public.refusals add constraint refusals_reason_code_check check (reason_code = any (array[
  'allowance_exhausted','promise_of_quiet','dnc_or_opted_out','cr_cooldown_active','company_not_deep_researched',
  'thread_text_missing','channel_illegal_in_market','contact_parked','contact_replied','group_sibling_engaged',
  'country_unknown','pending_ruling','company_archived','recipient_blocked']::text[]));

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
