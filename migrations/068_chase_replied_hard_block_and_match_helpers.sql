-- 068: F8 chase safety + matching helpers (applied 2026-09-08 via MCP; body identical to the applied migration).
-- (a) 'contact_replied' joins the closed refusal set; fn_evaluate_gates refuses chasers on a replied contact.
-- (b) fn_chase_candidates excludes replied contacts outright (same body as before plus one predicate).
-- (c) alias / name lookup helpers used by capture-and-classify-reply's matching ladder.
-- See the applied migration text in the Supabase migration history (068_chase_replied_hard_block_and_match_helpers);
-- the fn_evaluate_gates and fn_chase_candidates bodies are the live ones with these additions:
--   fn_evaluate_gates: IF p_requested = 'chaser' AND c.chase_state = 'replied' THEN RETURN 'contact_replied' ...
--   fn_chase_candidates base CTE: AND c.chase_state IS DISTINCT FROM 'replied'
alter table public.refusals drop constraint if exists refusals_reason_code_check;
alter table public.refusals add constraint refusals_reason_code_check check (reason_code in (
  'allowance_exhausted','promise_of_quiet','dnc_or_opted_out','cr_cooldown_active',
  'company_not_deep_researched','thread_text_missing','channel_illegal_in_market','contact_parked','contact_replied'));

create or replace function public.fn_match_contact_by_alias(p_team_id uuid, p_ids text[])
 returns uuid language sql stable set search_path to 'public', 'pg_temp' as $$
  select c.id from public.contacts c
   where c.team_id = p_team_id and c.archived_at is null and c.linkedin_aliases ?| p_ids
   order by c.updated_at desc limit 1;
$$;
create or replace function public.fn_match_contacts_by_name(p_team_id uuid, p_last text, p_last_ascii text)
 returns table(id uuid, first_name text, last_name text, job_title text, company_name text, last_outbound date, chase_state text)
 language sql stable set search_path to 'public', 'pg_temp' as $$
  select c.id, c.first_name, c.last_name, c.job_title, co.company_name,
         (select max(o.touch_date) from public.outreach_log o where o.contact_id = c.id and o.touch_type::text <> 'Reply' and o.send_status::text = 'Sent'),
         c.chase_state
    from public.contacts c left join public.companies co on co.id = c.company_id
   where c.team_id = p_team_id and c.archived_at is null
     and (lower(c.last_name) = lower(p_last) or lower(c.last_name) = lower(p_last_ascii)
          or lower(translate(c.last_name, 'äöüÄÖÜéèêáàâóòôúùûíìîñçšž', 'aouAOUeeeaaaooouuuiiincsz')) = lower(p_last_ascii))
   limit 20;
$$;
revoke execute on function public.fn_match_contact_by_alias(uuid, text[]), public.fn_match_contacts_by_name(uuid, text, text) from public, anon, authenticated;
