-- 076: F12 T4 + guards (2026-09-09). Inferred values are visibly distinct from stated ones; an
-- inferred country never unlocks email; the group duplicate-approach guard refuses before send.
alter table public.companies add column if not exists field_provenance jsonb not null default '{}'::jsonb;
comment on column public.companies.field_provenance is 'F12 T4: per-field {"source": stated|inferred|workbook, "basis": text, "at": iso}. A field marked inferred renders distinctly and never unlocks a legal gate.';
-- Legacy flag becomes provenance too.
update companies set field_provenance = field_provenance || jsonb_build_object('country', jsonb_build_object('source','inferred','basis','legacy country_inferred flag','at', now()))
 where country_inferred and not (field_provenance ? 'country');
-- Inference from data we hold (never overwrites a stated value). Website from a contact's corporate
-- email domain; country from the website TLD, else the contacts' recorded country.
do $$
declare v_run text := 'f12-inference-2026-09-09'; r record; v_host text; v_cc text; v_country text;
begin
  for r in
    with dom as (select c.company_id as cid, lower(split_part(c.email_normalised,'@',2)) as d, count(*) n from contacts c where c.email_normalised like '%@%' group by 1,2),
    best as (select distinct on (cid) cid, d from dom where d not in ('gmail.com','googlemail.com','outlook.com','hotmail.com','hotmail.de','yahoo.com','yahoo.de','icloud.com','web.de','gmx.de','gmx.net','gmx.at','gmx.ch','t-online.de','me.com','live.com','protonmail.com','bluewin.ch','orange.fr','free.fr','wanadoo.fr','mail.com','aol.com') order by cid, n desc)
    select co.id, co.company_id as ref, b.d from companies co join best b on b.cid=co.id where co.archived_at is null and (co.website_url is null or co.website_url='')
  loop
    update companies set website_url = 'https://' || r.d || '/',
      field_provenance = field_provenance || jsonb_build_object('website_url', jsonb_build_object('source','inferred','basis','corporate email domain of a linked contact: ' || r.d,'at', now())),
      updated_at = now() where id = r.id;
    insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail) values (v_run, 't4_website_inferred', 'companies', r.ref, 'update', r.id, jsonb_build_object('website_url', 'https://' || r.d || '/', 'basis', 'contact email domain'));
  end loop;
  for r in select co.id, co.company_id as ref, co.website_url,
             (select mode() within group (order by ct.country) from contacts ct where ct.company_id=co.id and ct.country is not null and ct.country<>'') as contact_country
           from companies co where co.archived_at is null and (co.country is null or co.country='')
  loop
    v_host := lower(regexp_replace(regexp_replace(coalesce(r.website_url,''), '^https?://(www\.)?', ''), '/.*$', ''));
    v_cc := substring(v_host from '\.([a-z]{2})$');
    v_country := case v_cc when 'de' then 'Germany' when 'at' then 'Austria' when 'ch' then 'Switzerland' when 'fr' then 'France' when 'nl' then 'Netherlands' when 'be' then 'Belgium'
                            when 'it' then 'Italy' when 'es' then 'Spain' when 'uk' then 'United Kingdom' when 'se' then 'Sweden' when 'dk' then 'Denmark' when 'no' then 'Norway'
                            when 'fi' then 'Finland' when 'pl' then 'Poland' when 'cz' then 'Czech Republic' when 'lu' then 'Luxembourg' when 'ie' then 'Ireland' when 'pt' then 'Portugal' else null end;
    if v_country is null and v_host like '%.co.uk' then v_country := 'United Kingdom'; end if;
    if v_country is not null then
      update companies set country = v_country, country_inferred = true,
        field_provenance = field_provenance || jsonb_build_object('country', jsonb_build_object('source','inferred','basis','website TLD .' || coalesce(v_cc, 'co.uk'),'at', now())), updated_at = now() where id = r.id;
      insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail) values (v_run, 't4_country_inferred', 'companies', r.ref, 'update', r.id, jsonb_build_object('country', v_country, 'basis', 'website TLD'));
    elsif r.contact_country is not null then
      update companies set country = r.contact_country, country_inferred = true,
        field_provenance = field_provenance || jsonb_build_object('country', jsonb_build_object('source','inferred','basis','country recorded on the company''s contacts','at', now())), updated_at = now() where id = r.id;
      insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail) values (v_run, 't4_country_inferred', 'companies', r.ref, 'update', r.id, jsonb_build_object('country', r.contact_country, 'basis', 'contacts'' country'));
    end if;
  end loop;
end $$;
-- Sourcing queue: every live, contactable contact without a Sales Nav URL. Never derived (F50: a
-- Sales Nav URL is never typed or inferred), so all of them are tasks.
create or replace view public.v_sourcing_queue_missing_sn_url as
  select c.id, c.team_id, c.contact_id, c.first_name, c.last_name, c.job_title, c.linkedin_url, c.connection_status, c.outreach_status, c.owner_user_id,
         co.id as company_uuid, co.company_id as company_ref, co.company_name, co.country
    from public.contacts c left join public.companies co on co.id = c.company_id
   where c.archived_at is null and coalesce(c.do_not_contact,false) = false
     and c.outreach_status::text not in ('Do not contact','Opted out','Not relevant','Left company')
     and (c.linkedin_sales_nav_url is null or c.linkedin_sales_nav_url = '');
-- Gates: group duplicate approach (acceptance test 3) and inferred country never unlocks email.
CREATE OR REPLACE FUNCTION public.fn_evaluate_gates(p_team_id uuid, p_contact_id uuid, p_channel text, p_requested text)
 RETURNS TABLE(reason_code text, reason_human text, context jsonb)
 LANGUAGE plpgsql STABLE SET search_path TO 'public', 'pg_temp' AS $function$
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
  -- F12: a company whose group sibling is already engaged (Contacted, Active Lead, Partner, in Monday,
  -- or holding an engaged contact) must not receive a NEW approach. Replies and chasers on an
  -- existing thread are not new approaches.
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
    -- F12: only a STATED country can unlock email. An inferred company country counts as unknown,
    -- and unknown fails closed.
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
      FROM public.outreach_log o WHERE o.team_id = p_team_id AND o.contact_id = p_contact_id AND o.touch_type::text <> 'Reply' AND o.send_status::text = 'Sent';
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
