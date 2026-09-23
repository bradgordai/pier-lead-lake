-- 146 F22B.10: housekeeping that needs the database.
-- (d) i128 INMAIL CREDITS, MANUAL FIELD. Oliver types the balance he sees in Sales Navigator; the app stamps who and
--     when. v_inmail_credits adds the two warnings (low: balance at or under the threshold, default 20; stale: not
--     updated for 7 days or never) and the count of InMails SENT THIS CALENDAR MONTH from v_sent_touches (the true
--     send date), so the typed number can be read against what the system sent. Automation comes later (i128).
-- F22B.9(e) cron 'proofread-drafts' every 15 minutes: calls the function ONLY when a pending draft has not been
--     proofread (or was edited since). Flags only; the function never changes text. Bearer read from Vault, as every job.
-- (f) TICKS WITH EVIDENCE for items this batch finished and verified (UI-dependent items are ticked only after their
--     screen is published): i138, i125, i110. Each gets an improvement_activity 'ticked off' row carrying the evidence.

alter table public.team_settings add column if not exists inmail_credits_balance int check (inmail_credits_balance >= 0);
alter table public.team_settings add column if not exists inmail_credits_updated_at timestamptz;
alter table public.team_settings add column if not exists inmail_credits_updated_by uuid;
alter table public.team_settings add column if not exists inmail_credits_low_at int not null default 20 check (inmail_credits_low_at >= 0);

create or replace function public.fn_inmail_credits_stamp() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if new.inmail_credits_balance is distinct from old.inmail_credits_balance then
    new.inmail_credits_updated_at := now();
    new.inmail_credits_updated_by := auth.uid();
  end if;
  return new;
end $$;
drop trigger if exists trg_inmail_credits_stamp on public.team_settings;
create trigger trg_inmail_credits_stamp before update of inmail_credits_balance on public.team_settings
  for each row execute function public.fn_inmail_credits_stamp();

create or replace view public.v_inmail_credits with (security_invoker = true) as
select ts.team_id, ts.inmail_credits_balance as balance, ts.inmail_credits_updated_at as updated_at,
       ts.inmail_credits_updated_by as updated_by, ts.inmail_credits_low_at as low_at, ts.monthly_inmail_grant,
       (ts.inmail_credits_balance is not null and ts.inmail_credits_balance <= ts.inmail_credits_low_at) as is_low,
       (ts.inmail_credits_updated_at is null or ts.inmail_credits_updated_at < now() - interval '7 days') as is_stale,
       (select count(*) from public.v_sent_touches s
         where s.team_id = ts.team_id and s.channel::text = 'LinkedIn inMail' and s.touch_type::text <> 'Reply'
           and s.sent_on >= date_trunc('month', current_date)::date) as sent_this_month
  from public.team_settings ts;
grant select on public.v_inmail_credits to authenticated;

do $$ begin
  if exists (select 1 from cron.job where jobname = 'proofread-drafts') then perform cron.unschedule('proofread-drafts'); end if;
  perform cron.schedule('proofread-drafts', '*/15 * * * *', $job$
  select net.http_post(
    url := 'https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/proofread-drafts',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'internal_app_secret')),
    body := jsonb_build_object('limit', 20),
    timeout_milliseconds := 120000)
  where exists (select 1 from public.outreach_log o where o.draft_status::text = 'pending_review' and o.message_body is not null
                  and (o.proofread_at is null or o.updated_at > o.proofread_at + interval '1 second'));
  $job$);
end $$;

-- (f)
do $$ declare r record; n int := 0; begin
  for r in select * from (values
    ('i138', 'InMail replies ARE collected: the Sales Navigator inbox scraper captured Christian Deiminger''s (P581) InMail reply on 22 Sep 20:18 UTC, thread_url linkedin.com/sales/inbox/…; filed by capture-and-classify-reply (F22B batch report, F22B.9(h)).'),
    ('i125', 'Migration 144: trigger trg_company_state_flip moves a company forward on a Sent outbound message (-> Contacted) or a sales reply (-> Active Lead), never backwards; 72 mislabelled companies fixed in the same migration with before/after in migration_audit phase f22b_8a_flip.'),
    ('i110', 'Today rebuilt (Lovable commit 8671790, published 23 Sep): every reply is one collapsible row per person; verified in Chrome, 75 items, Deiminger''s non-sales card expands with its trigger quote and actions.')
  ) v(k, ev) loop
    update public.improvements set status = 'done', done_by = 'Brad', done_at = now() where item_key = r.k and status = 'open';
    if found then
      n := n + 1;
      insert into public.improvement_activity (team_id, improvement_id, item_key, who, at, action, before, after)
      select i.team_id, i.id, i.item_key, 'Claude (F22B batch)', now(), 'ticked off', jsonb_build_object('status', 'open'),
             jsonb_build_object('status', 'done', 'evidence', r.ev)
        from public.improvements i where i.item_key = r.k;
    end if;
  end loop;
  if n <> 3 then raise exception 'expected 3 ticks, made %', n; end if;
end $$;
