-- 120 F16.5 (2026-09-20): contacts.cr_accepted_at = when the connection request was accepted.
--
-- Nullable, no default. NULL means "date unknown", which is the honest value for every acceptance
-- that arrived with the workbook migration on 2026-09-04.
--
-- Measured before writing this (audit_log, entity_type 'contacts', source <> 'system_backfill_f17',
-- after connection_status = 'Accepted', before IS DISTINCT FROM 'Accepted'):
--   119 transitions in total; 77 dated 2026-09-04 (workbook migration: deliberately NOT stamped);
--   42 on other dates, of which 4 are 'created' rows for contacts that no longer exist, leaving 38
--   transitions on 37 live contacts; 36 of those contacts are still 'Accepted' today and get the
--   stamp (earliest genuine transition each): 24 from 'Already connected', 11 from 'Not connected',
--   1 from 'Request sent'. All but the 2026-07-30 rows were written by the connection watcher cron.

-- 1. the column
alter table public.contacts add column cr_accepted_at timestamptz;
comment on column public.contacts.cr_accepted_at is
  'When the connection request was accepted (F16.5). Stamped once, on a genuine transition to Accepted; never overwritten. NULL = date unknown (e.g. acceptances that arrived with the 2026-09-04 workbook migration).';

-- 2. backfill from genuine audit_log transitions only; log before/after per row
with t as (
  select a.entity_id, a.created_at, a.before_value->>'connection_status' as before_status
    from public.audit_log a
   where a.entity_type = 'contacts'
     and a.source is distinct from 'system_backfill_f17'
     and a.after_value->>'connection_status' = 'Accepted'
     and a.before_value->>'connection_status' is distinct from 'Accepted'
     and (a.created_at at time zone 'UTC')::date <> date '2026-09-04'
     and (a.created_at at time zone 'Europe/London')::date <> date '2026-09-04'
), first_t as (
  select distinct on (entity_id) entity_id, created_at as accepted_at, before_status
    from t order by entity_id, created_at asc
), upd as (
  update public.contacts c
     set cr_accepted_at = f.accepted_at
    from first_t f
   where c.id = f.entity_id
     and c.connection_status::text = 'Accepted'
     and c.cr_accepted_at is null
  returning c.id, c.contact_id as contact_ref, c.cr_accepted_at, f.before_status
)
insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select 'f18-2026-09-20', 'f16_5_cr_accepted_at_backfill', 'contacts', u.contact_ref, 'cr_accepted_at_stamped', u.id,
       jsonb_build_object(
         'before', jsonb_build_object('cr_accepted_at', null),
         'after',  jsonb_build_object('cr_accepted_at', u.cr_accepted_at),
         'transition_from', u.before_status,
         'reason', 'earliest genuine audit_log transition to Accepted; 2026-09-04 workbook-migration transitions and system_backfill_f17 rows excluded')
  from upd u;

-- 3. belt and braces: stamp on a genuine transition, whatever code path made it.
--    Separate from trg_stamp_connection_status (untouched). Ordering does not matter: no trigger on
--    contacts assigns connection_status or cr_accepted_at, and this one reads only those two.
create or replace function public.fn_stamp_cr_accepted_at()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.connection_status::text = 'Accepted'
     and old.connection_status::text is distinct from 'Accepted'
     and new.cr_accepted_at is null then
    new.cr_accepted_at := now();
  end if;
  return new;
end $function$;

create trigger trg_stamp_cr_accepted_at
  before update on public.contacts
  for each row execute function public.fn_stamp_cr_accepted_at();
