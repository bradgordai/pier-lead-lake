-- 113 F17 H3: three bulk writes of mine on 18 Sep 2026 went through the audit triggers and landed in
-- audit_log as source 'manual' with no actor: 1,141 outreach_log rows at 10:24 UTC (observed_or_inferred
-- backfill), 812 contacts rows at 10:44 (connection_status_source backfill), 116 outreach_log rows at 10:48+
-- (synthetic flip and empty-row merge are REAL changes and are left as they are, but re-sourced too so they
-- do not read as a human). Rows are MARKED, not deleted: audit history is never removed.
update public.audit_log set source = 'system_backfill_f17',
       summary = left('[F17 bulk migration write, not a human action] ' || coalesce(summary, ''), 500)
 where created_at >= '2026-09-18 10:20+00' and created_at < '2026-09-18 13:30+00'
   and actor_user_id is null and source = 'manual'
   and entity_type in ('outreach_log', 'contacts')
   and date_trunc('minute', created_at) in (
     select date_trunc('minute', created_at) from public.audit_log
      where created_at >= '2026-09-18 10:20+00' and created_at < '2026-09-18 13:30+00' and actor_user_id is null and source = 'manual'
      group by 1 having count(*) > 40);
