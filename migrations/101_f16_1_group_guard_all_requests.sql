-- 101 F16.1 (2026-09-15): the group guard has never fired. Two defects.
--  A. fn_evaluate_gates only ran it for initial_message / connection_request; chasers and replies never reached it.
--  B. fn_group_siblings_engaged matched parent_group by exact string equality; parent_group is free text.
-- Fix B: fn_company_group_pairs derives sibling pairs deterministically from three explainable rules:
--   R1 exact: both parent_group strings are byte-equal (case/space-insensitive)           -> Conrad, Otto Austria, Telia...
--   R2 domain: A's parent_group text contains B's registrable domain (>= 6 chars)         -> asgoodasnew names save.co
--   R3 name:   A's parent_group text contains B's whole company name as a word (name >= 6 chars and
--              either multi-word or >= 8 chars, so 'Save.' or 'Otto' alone can never match)  -> asgoodasnew names "Save Group"
-- Pairs are symmetric. No transitive closure (every pair is directly explainable in the refusal text).
-- Fix A: the guard runs for EVERY p_requested. One approach per group means one.
-- Repair: the three Save Group 'Chase' drafts (asgoodasnew is in Monday) are parked (Cancelled), not deleted.

create or replace function public.fn_company_group_pairs(p_team_id uuid)
 returns table(company_id uuid, sibling_id uuid, rule text, evidence text)
 language sql stable set search_path to 'public','pg_temp' as $function$
  with co as (
    select id, company_name, parent_group,
      lower(regexp_replace(regexp_replace(coalesce(nullif(root_domain,''), website_url, ''), '^https?://(www\.)?', ''), '/.*$', '')) as dom,
      regexp_replace(lower(company_name), '[^[:alnum:] ]', '', 'g') as cname
    from public.companies where team_id = p_team_id),
  directed as (
    select a.id, b.id as sid, 'R1 exact parent_group' as rule, left(btrim(a.parent_group), 80) as evidence
      from co a join co b on a.id <> b.id
     where a.parent_group is not null and b.parent_group is not null
       and lower(btrim(a.parent_group)) = lower(btrim(b.parent_group))
    union all
    select a.id, b.id, 'R2 parent_group names the sibling''s domain', b.dom
      from co a join co b on a.id <> b.id
     where a.parent_group is not null and length(b.dom) >= 6 and b.dom not in ('linkedin.com','google.com')
       and a.parent_group ilike '%' || b.dom || '%'
    union all
    select a.id, b.id, 'R3 parent_group names the sibling company', b.company_name
      from co a join co b on a.id <> b.id
     where a.parent_group is not null and length(b.cname) >= 6 and (b.cname like '% %' or length(b.cname) >= 8)
       and a.parent_group ~* ('\m' || regexp_replace(b.company_name, '([\.\+\*\?\(\)\[\]\{\}\|\^\$\\])', '\\\1', 'g') || '\M'))
  select distinct on (x.id, x.sid) x.id, x.sid, x.rule, x.evidence
    from (select id, sid, rule, evidence from directed
          union all select sid, id, rule, evidence from directed) x
   order by x.id, x.sid, x.rule;
$function$;

create or replace function public.fn_group_siblings_engaged(p_team_id uuid, p_company_id uuid)
 returns table(company_id uuid, company_ref text, company_name text, why text)
 language sql stable set search_path to 'public','pg_temp' as $function$
  select s.id, s.company_id, s.company_name,
         (case when s.monday_deal_id is not null or s.archive_reason = 'promoted_to_monday' then 'in Monday'
               when s.archived_at is not null then 'archived: ' || coalesce(s.archive_reason, 'unspecified')
               when s.opportunity_status::text in ('Contacted','Active Lead','Partner') then s.opportunity_status::text
               else 'contact engaged' end) || '; linked by ' || p.rule || ' [' || p.evidence || ']'
    from public.fn_company_group_pairs(p_team_id) p
    join public.companies s on s.id = p.sibling_id
   where p.company_id = p_company_id
     and ( s.monday_deal_id is not null or s.archived_at is not null
           or s.opportunity_status::text in ('Contacted','Active Lead','Partner')
           or exists (select 1 from public.contacts c where c.company_id = s.id and c.outreach_status::text in ('Contacted','In conversation','Meeting booked')) );
$function$;

-- gate: group guard for every request type
CREATE OR REPLACE FUNCTION public.fn_evaluate_gates(p_team_id uuid, p_contact_id uuid, p_channel text, p_requested text)
 RETURNS TABLE(reason_code text, reason_human text, context jsonb)
 LANGUAGE plpgsql STABLE SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c record; co record; s record; v_cap int; v_sent int; v_email_ok boolean; v_bodies int; v_outbound int;
  v_country text; v_sibs jsonb; v_sib_names text; v_ruling text;
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
  -- F15.1: a contact imported under a group ruling stays refused until a human moves it out of Needs review
  IF c.outreach_status::text = 'Needs review' THEN
    SELECT r.reason_human INTO v_ruling FROM public.refusals r WHERE r.contact_id = c.id AND r.reason_code = 'pending_ruling' ORDER BY r.created_at DESC LIMIT 1;
    IF v_ruling IS NOT NULL THEN
      RETURN QUERY SELECT 'pending_ruling', 'Awaiting Oliver''s ruling: '||v_ruling, jsonb_build_object('outreach_status', c.outreach_status::text);
      RETURN;
    END IF;
  END IF;
  -- F16.1: the group guard runs for EVERY request type (chaser and reply included). One approach per group.
  IF co.id IS NOT NULL THEN
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
  IF p_requested IN ('initial_message','chaser','reply') THEN
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

-- REPAIR (a): park the three Save Group chasers. asgoodasnew (C290) is in Monday and its parent_group names save.co / Save Group.
insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
select 'f16-1-group-guard-2026-09-15', 'park', 'outreach_log', o.touch_id, 'update', o.id,
       jsonb_build_object('contact', c.first_name||' '||c.last_name, 'was', o.send_status::text||'/'||o.draft_status::text,
                          'why', 'Save Group is linked to asgoodasnew (in Monday, monday:asgoodasnew); a second approach into a live deal')
  from public.outreach_log o join public.contacts c on c.id = o.contact_id join public.companies co on co.id = c.company_id
 where co.company_id = 'C285' and o.send_status::text = 'Draft';
update public.outreach_log o set send_status = 'Cancelled', draft_status = 'rejected',
       rejection_feedback = coalesce(o.rejection_feedback, '{}'::jsonb) || jsonb_build_object('reason', 'group_sibling_engaged',
         'detail', 'F16.1: parked. Save Group is linked to asgoodasnew, which is in Monday (monday:asgoodasnew). One approach per group.'),
       updated_at = now()
  from public.contacts c join public.companies co on co.id = c.company_id
 where c.id = o.contact_id and co.company_id = 'C285' and o.send_status::text = 'Draft';
