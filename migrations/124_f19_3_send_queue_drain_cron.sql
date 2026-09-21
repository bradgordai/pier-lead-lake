-- 124 F19.3(g): the send queue drainer. This is the file held as 109_DO_NOT_APPLY since 18 Sep. Brad released
-- it in F19 (21 Sep 2026): the queue now releases only on a confirmed terminal state, and every gate re-runs
-- at drain time, so an unattended launch can only be a draft a human already pressed Send now on.
-- APPLY ONLY AFTER send-approved-draft (drain mode + slot claim) and send-approved-callback are deployed.
--
-- Two jobs, both every minute:
--  1. housekeeping, unconditionally: reconcile the queue with outreach_log and apply the 10 minute dead-man's
--     switch, so a stuck send is marked even when nobody is pressing anything. Pure SQL, sends nothing.
--  2. the drainer: ONLY when something is queued and due, ask send-approved-draft to launch the oldest one.
--     With an empty queue it makes no HTTP call at all.
-- The bearer is read AT RUNTIME from the existing chase-engine job, so no secret is written here and a
-- rotation of that job carries over. Replace with a Vault read when the cron jobs move to Vault (F17.1).
select cron.unschedule('send-queue-housekeeping') where exists (select 1 from cron.job where jobname = 'send-queue-housekeeping');
select cron.schedule('send-queue-housekeeping', '* * * * *', $job$
  select public.fn_send_queue_housekeeping(t.id) from public.teams t
   where exists (select 1 from public.send_queue q where q.team_id = t.id and q.status in ('launched','stuck'));
$job$);

select cron.unschedule('send-queue-drain') where exists (select 1 from cron.job where jobname = 'send-queue-drain');
select cron.schedule('send-queue-drain', '* * * * *', $job$
  select net.http_post(
    url := 'https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/send-approved-draft',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
      'Bearer ' || (select substring(command from 'Bearer ([A-Za-z0-9._-]+)') from cron.job where jobname = 'daily-chase-engine')),
    body := jsonb_build_object('drain', true),
    timeout_milliseconds := 20000)
  where exists (select 1 from public.send_queue where status = 'queued' and not_before <= now());
$job$);
