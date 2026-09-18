-- 106 F17.2(d): a guard must be able to tell a witnessed event from a guessed one.
-- Invisible to every count: adds two columns and a log table, backfills the label. No send_status changes here.
alter table public.outreach_log add column if not exists observed_or_inferred text;
alter table public.outreach_log add column if not exists duplicate_of uuid references public.outreach_log(id);
alter table public.outreach_log drop constraint if exists outreach_log_observed_or_inferred_check;
alter table public.outreach_log add constraint outreach_log_observed_or_inferred_check
  check (observed_or_inferred in ('observed','inferred','migrated_unverified','recorded_by_hand'));
comment on column public.outreach_log.observed_or_inferred is
  'observed = the platform or this system witnessed it (run id, thread id, external key, or a system namespace). inferred = deduced, never witnessed (synthetic-, cr-backfill). migrated_unverified = Oliver''s workbook says so, no platform id. recorded_by_hand = entered manually after a manual send (F17.13).';

create table if not exists public.touch_merge_log (
  id bigint generated always as identity primary key,
  team_id uuid not null,
  outreach_log_id uuid not null,
  action text not null,
  before jsonb not null,
  after jsonb,
  reason text,
  created_at timestamptz not null default now()
);
alter table public.touch_merge_log enable row level security;

update public.outreach_log set observed_or_inferred = case
  when touch_id like 'synthetic-%' or touch_id like 'cr-backfill%' or legacy_source = 'synthetic_cr_backfill' then 'inferred'
  when phantom_run_id is not null or external_key is not null or thread_id is not null or thread_url is not null then 'observed'
  when touch_id like 'agent-%' or touch_id like 'inbox-%' or touch_id like 'reply-%' or touch_id like 'chase-%' or touch_id like 'sup-%' then 'observed'
  when migrated_legacy is true or touch_id ~ '^T[0-9]+$' then 'migrated_unverified'
  else 'migrated_unverified' end
where observed_or_inferred is null;

-- new rows written by the system are witnessed by it unless the writer says otherwise
alter table public.outreach_log alter column observed_or_inferred set default 'observed';
