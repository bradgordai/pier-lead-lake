-- 034_weekly_enrich_websites_cron.sql
-- Task 8 (UX sweep): weekly sweep that fills in missing company websites.
-- Sunday 06:00 UTC -> POSTs the enrich-company-websites Edge Function, which
-- processes up to MAX_PER_RUN (60) null-website companies per run: HIGH-confidence
-- hits are written to companies.website_url (insert-only), the rest queued for review.
--
-- NOTE: the function needs APIFY_TOKEN set in Supabase -> Edge Functions -> Secrets;
-- until then each run returns a graceful 500 and writes nothing.

CREATE EXTENSION IF NOT EXISTS pg_net;

SELECT cron.schedule(
  'weekly-enrich-company-websites',
  '0 6 * * 0',
  $$
  SELECT net.http_post(
    url := 'https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/enrich-company-websites',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <PASTE_MAKE_SHARED_SECRET_HERE_BEFORE_RUNNING>'
    ),
    body := jsonb_build_object('mode', 'missing', 'limit', 60)
  );
  $$
);
