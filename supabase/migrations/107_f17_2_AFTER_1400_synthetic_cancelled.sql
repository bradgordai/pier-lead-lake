-- 107 F17.2(c): APPLY AFTER 14:00 ON 18 SEP. Moves the Sent tile 847 -> 801.
-- The 46 synthetic CR rows are inferred events with fabricated dates. Kept, never deleted; taken out of Sent.
insert into public.touch_merge_log (team_id, outreach_log_id, action, before, after, reason)
select team_id, id, 'synthetic_sent_to_cancelled', to_jsonb(o), jsonb_build_object('send_status','Cancelled'),
       'F17.2(c): inferred event, date = first touch minus one day. Approved by Brad 2026-09-18.'
from public.outreach_log o where touch_id like 'synthetic-%' and send_status::text = 'Sent';
update public.outreach_log set send_status = 'Cancelled',
  send_error = 'Not a send. Inferred at migration (synthetic CR backfill); see touch_merge_log.'
where touch_id like 'synthetic-%' and send_status::text = 'Sent';
