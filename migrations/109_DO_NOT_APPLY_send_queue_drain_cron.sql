-- *** DO NOT APPLY. Brad's decision, 18 Sep 2026. ***
-- This job launches real LinkedIn sends unattended, which breaks the standing rule that nothing sends
-- without Oliver. It stays unapplied until a human has watched the queue work. It is NOT in
-- supabase_migrations.schema_migrations and must not be added by a bulk 'apply pending' run.
-- Until it is applied, a send that is queued by the spacing rule stays queued (send_status Ready) and
-- goes only when someone presses Send now again after its send_after time.

-- 109 F17: the drainer. Every minute, ask send-approved-draft to launch the oldest queued send that is due.
-- With an empty queue the function answers nothing_due and does nothing. It only ever launches a draft a
-- human already pressed Send on; every gate re-runs at launch.
-- The bearer is read AT RUNTIME from the existing chase-engine job, so no secret is written here and a
-- rotation of that job carries over. Replace with a Vault read when the three cron jobs move to Vault (F17.1).
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
