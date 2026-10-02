-- 157 F25 Task 1: fn_company_score_mark_dirty (migration 137, applied 22 Sep 2026 23:20 UTC) has refused every UPDATE to
-- companies that touches research_stage, a size field, an insurance field, usp_notes, country or last_refreshed.
-- `changed` is text[] and each append was `changed || 'word'` with an untyped literal; Postgres resolves
-- text[] || unknown as text[] || text[] and parses the bare word as an array literal: ERROR malformed array literal.
-- The exception fires before the UPDATE on company_scores, so the row count there is irrelevant.
-- REPAIR SCOPE: no bad data exists. The writes were refused, not mangled. Exposure: 22 Sep 23:20 UTC to this
-- migration (about nine and a half days) of research writes that could not land.
-- FIX: the six appends become array_append(changed, '<word>'::text). Nothing else changes.

create or replace function public.fn_company_score_mark_dirty() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $function$
declare changed text[] := '{}';
begin
  if new.research_stage is distinct from old.research_stage then changed := array_append(changed, 'research_stage'::text); end if;
  if new.annual_devices_sold is distinct from old.annual_devices_sold
     or new.annual_devices_sold_evidence is distinct from old.annual_devices_sold_evidence
     or new.employees is distinct from old.employees or new.monthly_visits is distinct from old.monthly_visits
     or new.estimated_revenue_gbp is distinct from old.estimated_revenue_gbp then changed := array_append(changed, 'company_size'::text); end if;
  if new.insurance_offered is distinct from old.insurance_offered or new.insurance_provider is distinct from old.insurance_provider
     or new.insurance_structure_type is distinct from old.insurance_structure_type
     or new.insurance_monthly_price is distinct from old.insurance_monthly_price
     or new.insurance_annual_price is distinct from old.insurance_annual_price
     or new.coverage_summary is distinct from old.coverage_summary or new.policy_url is distinct from old.policy_url
     or new.distribution_model is distinct from old.distribution_model or new.customer_journey is distinct from old.customer_journey
     then changed := array_append(changed, 'insurance'::text); end if;
  if new.usp_notes is distinct from old.usp_notes then changed := array_append(changed, 'wedge'::text); end if;
  if new.country is distinct from old.country then changed := array_append(changed, 'country'::text); end if;
  if new.last_refreshed is distinct from old.last_refreshed then changed := array_append(changed, 'last_refreshed'::text); end if;
  if array_length(changed, 1) > 0 then
    update public.company_scores set needs_rescore = true,
      rescore_reason = left(coalesce(rescore_reason || '; ', '') || array_to_string(changed, ',') || ' changed ' || to_char(now(), 'YYYY-MM-DD'), 500)
     where company_id = new.id;
  end if;
  return new;
end $function$;
