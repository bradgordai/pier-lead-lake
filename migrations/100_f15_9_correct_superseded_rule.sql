-- 100 F15.9 correction (2026-09-15): migration 099's "superseded is not sent" rule was too wide. It marked
-- 181 rows Cancelled, of which 131 are workbook-migrated rows (125 connection requests of Apr-May 2026
-- superseded by a later CR, plus 6 openers) and 6 are pre-agent manual rows: those WERE sent; "superseded"
-- on them means "replaced later", not "never went out". Restore send_status='Sent' on every row that is not
-- an agent-produced draft and not the inbox duplicate, and narrow the trigger to exactly those two cases.
-- sent_at_actual was nulled by 099 on all 181; it is restored to NULL-safe form only where it can be known
-- (agent drafts never had one; the migrated rows carried none, touch_date is their date).
update public.outreach_log o set send_status = 'Sent', updated_at = now()
  from public.migration_audit a
 where a.run_id = 'f15-9-superseded-cancelled-2026-09-15' and a.target_id = o.id
   and coalesce(o.agent_produced, false) = false
   and coalesce(o.rejection_feedback->>'reason','') <> 'duplicate_of_dispatched_row';
insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
select 'f15-9-superseded-cancelled-2026-09-15', 'revert', 'outreach_log', o.touch_id, 'update', o.id,
       jsonb_build_object('restored', 'Sent', 'why', 'not an agent draft and not the inbox duplicate: it was sent and later replaced')
  from public.outreach_log o join public.migration_audit a on a.target_id = o.id and a.run_id = 'f15-9-superseded-cancelled-2026-09-15' and a.phase = 'repair'
 where coalesce(o.agent_produced, false) = false and coalesce(o.rejection_feedback->>'reason','') <> 'duplicate_of_dispatched_row';

create or replace function public.fn_superseded_is_not_sent() returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  -- Only a draft that never went out, or an inbox copy of a message already dispatched, is cancelled by
  -- superseding. A sent row that is later "superseded" (a CR replaced by a newer CR) stays Sent.
  if new.draft_status::text = 'superseded' and new.send_status::text <> 'Cancelled'
     and (coalesce(new.agent_produced, false) or coalesce(new.rejection_feedback->>'reason','') = 'duplicate_of_dispatched_row')
     and (old.send_status is null or old.send_status::text <> 'Sent' or coalesce(new.rejection_feedback->>'reason','') = 'duplicate_of_dispatched_row') then
    new.send_status := 'Cancelled';
    new.sent_at_actual := null;
  end if;
  return new;
end $$;
