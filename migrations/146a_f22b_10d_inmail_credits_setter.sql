-- 146a F22B.10(d) correction to 146: team_settings has only a SELECT policy for authenticated users, so the app could
-- not save the balance. Rather than open UPDATE on the whole settings row, one SECURITY DEFINER setter writes ONLY the
-- two credit fields, for a caller who is a member of that team. The 146 trigger stamps who and when.
create or replace function public.fn_set_inmail_credits(p_team uuid, p_balance int, p_low_at int default null)
returns public.v_inmail_credits
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare r public.v_inmail_credits;
begin
  if auth.uid() is null or p_team not in (select fn_user_teams()) then raise exception 'not a member of this team'; end if;
  if p_balance is null or p_balance < 0 or p_balance > 100000 then raise exception 'balance must be a whole number from 0'; end if;
  update public.team_settings set inmail_credits_balance = p_balance,
         inmail_credits_low_at = coalesce(p_low_at, inmail_credits_low_at)
   where team_id = p_team;
  if not found then raise exception 'no settings row for team %', p_team; end if;
  select * into r from public.v_inmail_credits where team_id = p_team;
  return r;
end $$;
revoke all on function public.fn_set_inmail_credits(uuid, int, int) from public, anon;
grant execute on function public.fn_set_inmail_credits(uuid, int, int) to authenticated;
