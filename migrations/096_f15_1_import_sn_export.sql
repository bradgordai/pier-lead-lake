-- 096 F15.1 (2026-09-15): import the 14 Sep Sales Nav export (127 records, staging_sn_export_20260914).
-- Rules: never create a second row for someone who exists (11 merges by vmid / name+company); every
-- contact inside a group under ruling is imported REFUSED (Needs review + refusals.pending_ruling) and
-- never drafted; dateAdded is when the contact entered Oliver's list; outreachActivity seeds real
-- touch rows (historical, no phantom_run_id); Oliver's notes are carried; source_list = Lovable Master List.
alter table public.refusals drop constraint if exists refusals_reason_code_check;
alter table public.refusals add constraint refusals_reason_code_check check (reason_code = any (array[
  'allowance_exhausted','promise_of_quiet','dnc_or_opted_out','cr_cooldown_active','company_not_deep_researched','thread_text_missing',
  'channel_illegal_in_market','contact_parked','contact_replied','group_sibling_engaged','country_unknown','pending_ruling']));

do $$
declare
  v_team uuid := 'ef73c15e-4d6f-4159-bcfa-cc76b5ae4972';
  v_oli uuid := '6d282957-f63b-49d6-a4de-5a9a947b4284';
  v_run text := 'f15-1-sn-import-2026-09-15';
  r record; v_company uuid; v_ref text; v_new_contact uuid; v_existing uuid; v_pid text; v_n int;
  v_status public.outreach_status; v_conn text; v_level text; v_country text; v_slug text; v_public text;
  v_refuse text; v_group text; v_seq int;
  -- company mapping: export name (trimmed, lower) -> lake company_id ref
  v_map jsonb := '{
    "conrad electronic group":"C316","conrad electronic france":"C316","conrad electronic ag":"C316","getgoods.de":"C1349","getgoods.de media gmbh":"C1349",
    "swappie":"C179","otto austria group":"C1343","otto group":"C315",
    "telefónica":"C185","telefónica germany":"C185","telefónica germany retail gmbh":"C185",
    "drei österreich":"C313","hutchison drei austria gmbh":"C313","digitec galaxus ag":"C466","vodafone":"C307","vodafone group services":"C307",
    "janado gmbh":"C347","smartport":"C1090","electronic4you":"C422","electronic4you gmbh":"C422","0815 onlinehandel":"C421","0815 online handel gmbh":"C421",
    "deutsche telekom":"C045","media-saturn-holding gmbh":"C119","comet spa":"C645","hood media gmbh":"C977","talk point gmbh":"C971","talk-point gmbh":"C971","expert se":"C425"}'::jsonb;
  v_country_map jsonb := '{"Germany":"Germany","Austria":"Austria","Switzerland":"Switzerland","Italy":"Italy","Spain":"Spain","Netherlands":"Netherlands","France":"France","Poland":"Poland","Serbia":"Serbia"}'::jsonb;
begin
  -- 1. cause fix: any ARCHIVED sibling in the same parent_group counts as engaged (not only promoted_to_monday)
  create or replace function public.fn_group_siblings_engaged(p_team_id uuid, p_company_id uuid)
   returns table(company_id uuid, company_ref text, company_name text, why text)
   language sql stable set search_path to 'public','pg_temp' as $f$
    select s.id, s.company_id, s.company_name,
           case when s.monday_deal_id is not null or s.archive_reason = 'promoted_to_monday' then 'in Monday'
                when s.archived_at is not null then 'archived: '||coalesce(s.archive_reason,'unspecified')
                when s.opportunity_status::text in ('Contacted','Active Lead','Partner') then s.opportunity_status::text
                else 'contact engaged' end
      from public.companies me
      join public.companies s on s.team_id = me.team_id and s.id <> me.id
                             and s.parent_group is not null and btrim(s.parent_group) = btrim(me.parent_group)
     where me.id = p_company_id and me.team_id = p_team_id and me.parent_group is not null
       and ( s.monday_deal_id is not null or s.archived_at is not null
             or s.opportunity_status::text in ('Contacted','Active Lead','Partner')
             or exists (select 1 from public.contacts c where c.company_id = s.id and c.outreach_status::text in ('Contacted','In conversation','Meeting booked')) );
  $f$;

  -- 2. companies: link known, create stubs for the rest (needs_review, added_via sales_nav_import)
  for r in select distinct btrim(coalesce(nullif(associated_account,''), company_name)) as nm, btrim(company_name) as raw_nm from staging_sn_export_20260914 loop
    v_ref := coalesce(v_map->>lower(r.nm), v_map->>lower(r.raw_nm));
    if v_ref is null then
      select company_id into v_ref from companies where team_id=v_team and lower(company_name)=lower(r.nm) limit 1;
    end if;
    if v_ref is null and r.nm <> '' then
      select 'C'||lpad((max(substring(company_id from 2)::int)+1)::text, greatest(3, length((max(substring(company_id from 2)::int)+1)::text)),'0') into v_ref from companies where team_id=v_team and company_id ~ '^C[0-9]+$';
      insert into companies(team_id, company_id, company_name, research_stage, needs_review, added_via, source_urls, country)
      select v_team, v_ref, r.nm, 'Untouched', true, 'sales_nav_import_2026-09-14',
             nullif((select max(coalesce(nullif(associated_account_url,''), regular_company_url)) from staging_sn_export_20260914 s where btrim(coalesce(nullif(s.associated_account,''), s.company_name))=r.nm),''),
             (select v_country_map->>(btrim(split_part(max(location),',',-1))) from staging_sn_export_20260914 s where btrim(coalesce(nullif(s.associated_account,''), s.company_name))=r.nm);
      insert into migration_audit(run_id, phase, entity, source_ref, action, detail) values (v_run,'f15_1_company_stub','companies',v_ref,'insert',jsonb_build_object('name',r.nm));
    end if;
  end loop;

  -- 3. contacts
  for r in select * from staging_sn_export_20260914 order by seq loop
    v_ref := coalesce(v_map->>lower(btrim(coalesce(nullif(r.associated_account,''), r.company_name))), v_map->>lower(btrim(r.company_name)));
    if v_ref is null then select company_id into v_ref from companies where team_id=v_team and lower(company_name)=lower(btrim(coalesce(nullif(r.associated_account,''), r.company_name))) limit 1; end if;
    select id into v_company from companies where team_id=v_team and company_id=v_ref;
    -- ruling groups
    v_refuse := case
      when v_ref in ('C316','C1349') then 'Conrad Electronic group: Conrad is archived promoted_to_monday (live Monday deal); getgoods/digitalo/Voelkner share the group'
      when v_ref = 'C179' then 'Swappie is archived promoted_to_monday'
      when v_ref in ('C1343','C315') then 'Otto Austria Group: handover pack rules it Oliver''s own account; three Otto rows exist (C1343, C1345, C315)'
      when v_ref = 'C185' then 'Telefónica: four export name variants map onto duplicate lake rows Telefónica C185 and Telefonica C889; merge or rule first'
      when lower(btrim(r.company_name)) = 'recommerce ag - verkaufen.ch' then 'Recommerce AG - verkaufen.ch may be the archived Recommerce Group (C149, promoted_to_monday); Oliver to decide'
      else null end;
    v_level := case when r.degree ~ '^1' then '1st degree' when r.degree ~ '^2' then '2nd degree' when r.degree ~ '^3' then '3rd degree' else null end;
    v_public := case when r.default_profile_url ~ '^https?://(www\.)?linkedin\.com/in/' then regexp_replace(r.default_profile_url, '^https?://(www\.)?linkedin\.com/in/', 'https://www.linkedin.com/in/') else null end;
    v_slug := substring(v_public from 'linkedin\.com/in/([^/?#]+)');
    v_country := v_country_map->>(btrim(split_part(r.location,',',-1)));
    -- dedupe: vmid, then public slug, then name + company
    select id into v_existing from contacts where team_id=v_team and (linkedin_sales_nav_url ilike '%'||r.vmid||'%' or linkedin_url ilike '%'||r.vmid||'%') limit 1;
    if v_existing is null and v_slug is not null then select id into v_existing from contacts where team_id=v_team and lower(linkedin_slug)=lower(v_slug) limit 1; end if;
    if v_existing is null then select id into v_existing from contacts c where c.team_id=v_team and lower(btrim(c.first_name))=lower(btrim(r.first_name)) and lower(btrim(c.last_name))=lower(btrim(r.last_name)) and c.company_id = v_company limit 1; end if;

    if v_existing is not null then
      update contacts set
        linkedin_sales_nav_url = coalesce(nullif(linkedin_sales_nav_url,''), r.sales_nav_url),
        linkedin_url = coalesce(nullif(linkedin_url,''), v_public),
        linkedin_slug = coalesce(linkedin_slug, v_slug),
        url_provenance = coalesce(url_provenance,'{}'::jsonb) || case when nullif(linkedin_sales_nav_url,'') is null then jsonb_build_object('linkedin_sales_nav_url', jsonb_build_object('source','watcher','at',r.scraped_at,'basis','Sales Nav list export 2026-09-14')) else '{}'::jsonb end,
        sn_lists = case when 'Lovable Master List' = any(coalesce(sn_lists,'{}')) then sn_lists else array_append(coalesce(sn_lists,'{}'),'Lovable Master List') end,
        job_title = coalesce(nullif(job_title,''), nullif(r.title,'')),
        connection_level = coalesce(connection_level, v_level::public.connection_level),
        background_notes = case when nullif(btrim(r.note),'') is not null and coalesce(background_notes,'') not like '%'||btrim(r.note)||'%' then concat_ws(E'\n', nullif(background_notes,''), 'Sales Nav note (Oliver, list export 2026-09-14): '||btrim(r.note)) else background_notes end,
        updated_at = now()
      where id = v_existing;
      insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail) values (v_run,'f15_1_merge','contacts',r.vmid,'update',v_existing,jsonb_build_object('name',r.full_name,'seq',r.seq));
      v_new_contact := v_existing;
    else
      select 'P'||lpad((max(substring(contact_id from 2)::int)+1)::text, greatest(3, length((max(substring(contact_id from 2)::int)+1)::text)),'0') into v_pid from contacts where team_id=v_team and contact_id ~ '^P[0-9]+$';
      v_conn := case when v_level = '1st degree' then 'Already connected' when r.outreach_activity = 'SEND_INVITATION' then 'Request sent' else 'Not connected' end;
      v_status := case when v_refuse is not null then 'Needs review' else 'Not started' end;
      insert into contacts(team_id, contact_id, company_ref, company_id, first_name, last_name, job_title, location, country,
                           linkedin_url, linkedin_sales_nav_url, linkedin_slug, url_provenance, source_list, sn_lists,
                           connection_status, connection_level, outreach_status, owner_user_id, date_added, background_notes, next_action, next_action_date)
      values (v_team, v_pid, coalesce(v_ref,''), v_company, btrim(r.first_name), btrim(r.last_name), nullif(r.title,''), nullif(r.location,''), v_country,
              v_public, r.sales_nav_url, v_slug,
              jsonb_build_object('linkedin_sales_nav_url', jsonb_build_object('source','watcher','at',r.scraped_at,'basis','Sales Nav list export 2026-09-14'),
                                 'linkedin_url', jsonb_build_object('source','watcher','at',r.scraped_at,'basis','Sales Nav list export 2026-09-14 (defaultProfileUrl)')),
              'Lovable Master List', array['Lovable Master List'],
              v_conn::public.connection_status, v_level::public.connection_level, v_status, v_oli, r.date_added::date,
              case when nullif(btrim(r.note),'') is not null then 'Sales Nav note (Oliver, list export 2026-09-14): '||btrim(r.note) else null end,
              case when v_refuse is not null then 'REFUSED pending Oliver''s ruling: '||v_refuse else null end,
              case when v_refuse is not null then current_date else null end)
      returning id into v_new_contact;
      insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail) values (v_run,'f15_1_insert','contacts',r.vmid,'insert',v_new_contact,jsonb_build_object('name',r.full_name,'seq',r.seq,'company_ref',v_ref,'refused',v_refuse is not null,'degree',r.degree));
    end if;

    -- refusal row for the ruling groups (new and merged alike); no draft is ever produced while it stands
    if v_refuse is not null then
      insert into refusals(team_id, contact_id, company_id, reason_code, reason_human, channel, requested, context)
      select v_team, v_new_contact, v_company, 'pending_ruling', v_refuse, 'LinkedIn inMail', 'initial_message',
             jsonb_build_object('source','F15.1 import 2026-09-14 export','group_ref',v_ref)
      where not exists (select 1 from refusals x where x.contact_id=v_new_contact and x.reason_code='pending_ruling');
      update contacts set outreach_status='Needs review', next_action = coalesce(next_action, 'REFUSED pending Oliver''s ruling: '||v_refuse), next_action_date = coalesce(next_action_date, current_date) where id=v_new_contact and outreach_status::text in ('Not started','To contact','Ready','Needs review');
    end if;

    -- seed real activity from LinkedIn's own record
    if r.outreach_activity = 'SEND_INVITATION' then
      if not exists (select 1 from outreach_log o where o.contact_id=v_new_contact and o.touch_type='Connection request' and o.send_status='Sent' and abs(o.touch_date - r.outreach_date::date) <= 2) then
        insert into outreach_log(team_id, touch_id, contact_id, contact_ref, company_id, channel, touch_type, touch_date, sent_at_actual, send_status, draft_status, sent_by, agent_produced, migrated_legacy, message_body)
        select v_team, 'sn-seed-'||r.vmid, v_new_contact, c.contact_id, v_company, 'LinkedIn CR', 'Connection request', (r.outreach_date at time zone 'Europe/London')::date, r.outreach_date, 'Sent', 'sent', 'Oliver Müller', false, false, null from contacts c where c.id=v_new_contact;
        update contacts set connection_status = 'Request sent' where id=v_new_contact and connection_status::text = 'Not connected';
        insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail) values (v_run,'f15_1_seed_touch','outreach_log',r.vmid,'insert',v_new_contact,jsonb_build_object('name',r.full_name,'type','Connection request','on',r.outreach_date));
      end if;
    elsif r.outreach_activity = 'SEND_MESSAGE' then
      if not exists (select 1 from outreach_log o where o.contact_id=v_new_contact and o.touch_type not in ('Reply','Connection request') and o.send_status='Sent' and abs(o.touch_date - r.outreach_date::date) <= 2) then
        insert into outreach_log(team_id, touch_id, contact_id, contact_ref, company_id, channel, touch_type, touch_date, sent_at_actual, send_status, draft_status, sent_by, agent_produced, migrated_legacy, message_body)
        select v_team, 'sn-seed-'||r.vmid, v_new_contact, c.contact_id, v_company,
               case when c.connection_status::text in ('Accepted','Already connected') then 'LinkedIn DM' else 'LinkedIn inMail' end,
               case when exists (select 1 from outreach_log p where p.contact_id=v_new_contact and p.send_status='Sent' and p.touch_type not in ('Reply','Connection request') and p.touch_date < r.outreach_date::date) then 'Follow up' else 'Initial message' end,
               (r.outreach_date at time zone 'Europe/London')::date, r.outreach_date, 'Sent', 'sent', 'Oliver Müller', false, false,
               null  -- text not captured; leaving it null keeps the thread_text_missing gate honest for any later chaser
          from contacts c where c.id=v_new_contact;
        update contacts set background_notes = concat_ws(E'\n', nullif(background_notes,''), 'LinkedIn records a message sent by Oliver on '||to_char(r.outreach_date at time zone 'Europe/London','DD Mon YYYY')||' (Sales Nav export 2026-09-14); the text was not captured.'),
                            last_contacted = greatest(coalesce(last_contacted, r.outreach_date::date), r.outreach_date::date), outreach_status = case when outreach_status::text in ('Not started','To contact','Ready') then 'Contacted'::public.outreach_status else outreach_status end where id=v_new_contact;
        insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail) values (v_run,'f15_1_seed_touch','outreach_log',r.vmid,'insert',v_new_contact,jsonb_build_object('name',r.full_name,'type','message','on',r.outreach_date));
      end if;
    end if;
  end loop;
end $$;

-- gate: a contact under ruling is never drafted, on any channel, by any caller
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

-- new companies inherit a parent_group from a same-name row, so a stub can never slip out of a group guard
create or replace function public.fn_companies_inherit_parent_group() returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if new.parent_group is null then
    select parent_group into new.parent_group from public.companies
     where team_id = new.team_id and id is distinct from new.id and parent_group is not null and lower(company_name) = lower(new.company_name) limit 1;
  end if;
  return new;
end $$;
drop trigger if exists trg_companies_inherit_parent_group on public.companies;
create trigger trg_companies_inherit_parent_group before insert or update of company_name, parent_group on public.companies for each row execute function public.fn_companies_inherit_parent_group();
