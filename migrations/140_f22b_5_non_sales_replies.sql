-- 140 F22B.5: replies that are not sales replies.
-- (a) i018: reply_classification gains 'Left company' and 'Referral' (it already had 'Wrong person').
--     outreach_log.reply_trigger_quote holds the line of the reply that triggered the classification, for the red card.
-- (b) A non-sales reply (Left company, Wrong person, Referral) gets NO sales draft. The capture function stops
--     triggering the drafter for them (capture-and-classify-reply v29), and fn_reply_candidates (the chase engine's
--     reply sweep) now excludes a contact whose LATEST reply is non-sales. Found live: Christian Deiminger (P581) was
--     back in the sweep because his stranded reply draft is Cancelled, so the 06:15 run would have drafted him a
--     second sales reply. fn_reply_candidates is not one of the six priority readers and not a consent gate; the only
--     change is the added NOT EXISTS clause, the rest is verbatim.
-- (c) contact_referrals: a named person from a referral reply, captured so they can be sourced, not lost in a thread.
-- (f) draft_feedback.signal_type: feedback on a draft for a contact whose latest reply is non-sales is a signal about
--     the CONTACT, not the draft: stamped 'contact_state' and use_for_training false by trigger, so the distillation
--     (F22B.6) never learns "this draft was badly written" from a man who has left the company.
alter type public.reply_classification add value if not exists 'Left company';
alter type public.reply_classification add value if not exists 'Referral';

alter table public.outreach_log add column if not exists reply_trigger_quote text;

create or replace function public.fn_reply_candidates(p_team_id uuid, p_limit integer default 5)
 returns table(contact_id uuid, company_id uuid, last_inbound date, inbound_channel text, days_waiting integer, connection_status text)
 language sql stable set search_path to 'public', 'pg_temp'
as $function$
  with li as (
    select o.contact_id, max(o.touch_date) as last_in
      from public.outreach_log o
     where o.team_id = p_team_id and o.touch_type::text = 'Reply'
     group by o.contact_id)
  select c.id, c.company_id, li.last_in,
         (select o.channel::text from public.outreach_log o where o.contact_id = c.id and o.touch_type::text = 'Reply' order by o.touch_date desc, o.created_at desc limit 1),
         (current_date - li.last_in)::int, c.connection_status::text
    from public.contacts c
    join li on li.contact_id = c.id
    left join public.companies co on co.id = c.company_id
   where c.team_id = p_team_id and c.chase_state = 'replied'
     and c.archived_at is null and (co.id is null or co.archived_at is null)
     and not exists (select 1 from public.outreach_log f where f.contact_id = c.id and f.touch_type::text = 'Follow up'
                      and f.draft_status::text not in ('superseded','rejected') and f.send_status::text <> 'Cancelled'
                      and (f.touch_date >= li.last_in or f.send_status::text in ('Draft','Ready','Scheduled')))
     and not exists (select 1 from public.review_queue q where q.contact_id = c.id and q.status in ('open','later')
                      and q.kind in ('reply_answered_by_hand','reply_company_in_monday','reply_order_unknown'))
     -- F22B.5(b): a non-sales latest reply never gets a sales reply draft.
     and coalesce((select o.reply_classification::text from public.outreach_log o
                     where o.contact_id = c.id and o.touch_type::text = 'Reply'
                     order by o.touch_date desc, o.created_at desc limit 1), '') not in ('Wrong person','Left company','Referral')
   order by li.last_in asc
   limit p_limit;
$function$;

create table if not exists public.contact_referrals (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  from_contact_id uuid not null references public.contacts(id) on delete cascade,
  from_touch_id uuid references public.outreach_log(id) on delete set null,
  company_id uuid references public.companies(id) on delete set null,
  named_person text not null check (length(btrim(named_person)) > 0),
  named_title text,
  note text,
  status text not null default 'to_source' check (status in ('to_source','sourced','dismissed')),
  sourced_contact_id uuid references public.contacts(id) on delete set null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists contact_referrals_team_status_idx on public.contact_referrals (team_id, status, created_at desc);
alter table public.contact_referrals enable row level security;
drop policy if exists contact_referrals_team_all on public.contact_referrals;
create policy contact_referrals_team_all on public.contact_referrals for all to authenticated
  using (team_id in (select fn_user_teams())) with check (team_id in (select fn_user_teams()));

alter table public.draft_feedback add column if not exists signal_type text not null default 'draft_quality'
  check (signal_type in ('draft_quality','contact_state'));
create or replace function public.fn_draft_feedback_signal_type() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
declare cls text;
begin
  select o.reply_classification::text into cls from public.outreach_log o
   where o.contact_id = new.contact_id and o.touch_type::text = 'Reply'
   order by o.touch_date desc, o.created_at desc limit 1;
  if cls in ('Wrong person','Left company','Referral') then
    new.signal_type := 'contact_state';
    new.use_for_training := false;
  end if;
  return new;
end $$;
drop trigger if exists trg_draft_feedback_signal_type on public.draft_feedback;
create trigger trg_draft_feedback_signal_type before insert on public.draft_feedback
  for each row execute function public.fn_draft_feedback_signal_type();
