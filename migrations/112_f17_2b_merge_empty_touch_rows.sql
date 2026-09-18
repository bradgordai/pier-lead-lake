-- 112 F17.2(b): the cheap safe pass. A Sent, non-reply row with NO body, where exactly one other Sent row
-- exists for the same contact, channel, date and touch type WITH a body, is merged into that keeper.
-- No deletes. The empty row gets duplicate_of = keeper and leaves Sent; the keeper inherits any id or
-- timestamp it lacks. Both rows are logged before and after in touch_merge_log.
create temporary table _merge on commit drop as
with t as (
  select o.id, o.contact_id, o.channel, o.touch_date, o.touch_type,
         nullif(btrim(coalesce(o.sent_body, o.message_body, '')), '') as body
    from public.outreach_log o
   where o.contact_id is not null and o.send_status::text = 'Sent' and o.touch_type::text <> 'Reply' and o.duplicate_of is null
)
select e.id as empty_id, (array_agg(k.id))[1] as keeper_id
  from t e join t k on k.contact_id = e.contact_id and k.channel = e.channel and k.touch_date = e.touch_date
                   and k.touch_type = e.touch_type and k.body is not null
 where e.body is null
 group by e.id having count(*) = 1;

insert into public.touch_merge_log (team_id, outreach_log_id, action, before, after, reason)
select o.team_id, o.id, 'empty_row_merged_into_keeper', to_jsonb(o),
       jsonb_build_object('send_status','Cancelled','duplicate_of', m.keeper_id), 'F17.2(b) empty listing row; keeper holds the body'
  from _merge m join public.outreach_log o on o.id = m.empty_id;
insert into public.touch_merge_log (team_id, outreach_log_id, action, before, after, reason)
select k.team_id, k.id, 'keeper_inherited_from_empty_row', to_jsonb(k),
       jsonb_build_object('thread_id', coalesce(k.thread_id, e.thread_id), 'thread_url', coalesce(k.thread_url, e.thread_url),
                          'sent_at_actual', coalesce(k.sent_at_actual, e.sent_at_actual),
                          'subject_line', coalesce(k.subject_line, e.subject_line)),
       'F17.2(b) keeper of empty row ' || e.touch_id
  from _merge m join public.outreach_log k on k.id = m.keeper_id join public.outreach_log e on e.id = m.empty_id;

-- external_key is deliberately NOT moved (it may be unique); it stays readable on the cancelled row.
update public.outreach_log k set
       thread_id = coalesce(k.thread_id, e.thread_id), thread_url = coalesce(k.thread_url, e.thread_url),
       sent_at_actual = coalesce(k.sent_at_actual, e.sent_at_actual), subject_line = coalesce(k.subject_line, e.subject_line)
  from _merge m join public.outreach_log e on e.id = m.empty_id
 where k.id = m.keeper_id;
update public.outreach_log e set send_status = 'Cancelled', duplicate_of = m.keeper_id,
       send_error = 'Not a separate send. Empty listing row merged into its keeper (F17.2b); see touch_merge_log.'
  from _merge m where e.id = m.empty_id;
