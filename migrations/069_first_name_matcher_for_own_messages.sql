-- 069: F8 follow-up (2026-09-08). The Inbox Scraper reports Oliver as the sender of his own
-- messages, so the only name we have for the counterparty is the greeting in the body
-- ("Hi Joan", "Hallo Herr Siebel"). This helper mirrors fn_match_contacts_by_name for a
-- first name, so capture-and-classify-reply can suggest (and, with a recent outbound, file)
-- the right contact for Oliver's own messages.
create or replace function public.fn_match_contacts_by_first_name(p_team_id uuid, p_first text, p_first_ascii text)
 returns table(id uuid, first_name text, last_name text, job_title text, company_name text, last_outbound date, chase_state text)
 language sql stable set search_path to 'public', 'pg_temp' as $$
  select c.id, c.first_name, c.last_name, c.job_title, co.company_name,
         (select max(o.touch_date) from public.outreach_log o where o.contact_id = c.id and o.touch_type::text <> 'Reply' and o.send_status::text = 'Sent'),
         c.chase_state
    from public.contacts c left join public.companies co on co.id = c.company_id
   where c.team_id = p_team_id and c.archived_at is null
     and (lower(split_part(c.first_name, ' ', 1)) = lower(p_first) or lower(split_part(c.first_name, ' ', 1)) = lower(p_first_ascii)
          or lower(translate(split_part(c.first_name, ' ', 1), 'äöüÄÖÜéèêáàâóòôúùûíìîñçšž', 'aouAOUeeeaaaooouuuiiincsz')) = lower(p_first_ascii))
   limit 20;
$$;
revoke execute on function public.fn_match_contacts_by_first_name(uuid, text, text) from public, anon, authenticated;
