-- 119 F16.4 (2026-09-20): an archived company is not a consent event.
--
-- Measured before writing this: 6 refusals carry reason_code 'dnc_or_opted_out'; all 6 were written by
-- the Edge Function generate-draft-from-context (its `company?.archived_at` block), all 6 say
-- "<company> is archived, so this contact is out of scope." with context.company_archived_at set, and
-- none of the 4 distinct contacts (P271 x3, P046, P010, P047) is do_not_contact, Opted out or promise_of_quiet. Genuine opt-outs: 0.
--
-- fn_evaluate_gates (the consent layer) has NO archived-company branch: it returns 'dnc_or_opted_out'
-- only for "contact not found" and for do_not_contact / outreach_status in ('Do not contact','Opted out',
-- 'Not relevant','Left company'). It is therefore NOT touched by this migration, so it behaves
-- identically by construction. The only writer for an archive is the Edge Function (edited locally,
-- deployed separately, AFTER this migration, because the CHECK below must allow the new code first).
--
-- This migration: (1) adds 'company_archived' to the closed reason-code set (the CHECK constraint is
-- the only registry; there is no lookup table of codes/labels; human label "Company archived"),
-- (2) re-codes the archive-citing refusals, logging before/after to migration_audit.

-- 1. extend the closed set (same 12 codes as live, plus company_archived)
alter table public.refusals drop constraint refusals_reason_code_check;
alter table public.refusals add constraint refusals_reason_code_check check (reason_code = any (array[
  'allowance_exhausted','promise_of_quiet','dnc_or_opted_out','cr_cooldown_active',
  'company_not_deep_researched','thread_text_missing','channel_illegal_in_market','contact_parked',
  'contact_replied','group_sibling_engaged','country_unknown','pending_ruling',
  'company_archived']));

comment on constraint refusals_reason_code_check on public.refusals is
  'Closed refusal reason-code set. company_archived (label "Company archived", F16.4 2026-09-20) = the contact''s company is archived; it is a scope refusal, NOT a consent event. dnc_or_opted_out is reserved for do_not_contact / Opted out / Not relevant / Left company.';

-- 2. re-code the archive-citing refusals. A row qualifies only if it was written by the archive block
--    (context.company_archived_at present AND the archive sentence) AND its contact is not a genuine
--    DNC / opt-out / promise of quiet. Anything else keeps dnc_or_opted_out.
with target as (
  select r.id, r.reason_code as before_code, r.reason_human, r.context, r.channel, r.requested, r.created_at,
         c.contact_id as contact_ref
    from public.refusals r
    join public.contacts c on c.id = r.contact_id
   where r.reason_code = 'dnc_or_opted_out'
     and r.context ? 'company_archived_at'
     and r.reason_human like '% is archived, so this contact is out of scope.'
     and coalesce(c.do_not_contact, false) = false
     and coalesce(c.promise_of_quiet, false) = false
     and c.outreach_status::text not in ('Do not contact','Opted out')
), upd as (
  update public.refusals r set reason_code = 'company_archived'
    from target t where r.id = t.id
  returning r.id
)
insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select 'f18-2026-09-20', 'f16_4_company_archived_reason', 'refusals', t.contact_ref, 'reason_code_recoded', t.id,
       jsonb_build_object(
         'before', jsonb_build_object('reason_code', t.before_code),
         'after',  jsonb_build_object('reason_code', 'company_archived'),
         'reason_human', t.reason_human, 'context', t.context, 'channel', t.channel,
         'requested', t.requested, 'refusal_created_at', t.created_at,
         'reason', 'archived company is not a consent event; written by generate-draft-from-context archive block')
  from target t join upd u on u.id = t.id;

-- 3. halt if an archive-block row still carries the consent code
do $$
declare n int;
begin
  select count(*) into n from public.refusals
   where reason_code = 'dnc_or_opted_out' and context ? 'company_archived_at';
  if n > 0 then
    raise exception 'F16.4: % archive-block refusal(s) still coded dnc_or_opted_out', n;
  end if;
end $$;
