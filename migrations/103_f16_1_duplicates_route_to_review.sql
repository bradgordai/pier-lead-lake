-- 103 (Claude, applied 2026-09-15 11:35 UTC as 103_f16_1_duplicates_route_to_review), three minutes after Cowork's 103.
-- Same fix applied twice, idempotent. Both version names exist in supabase_migrations.schema_migrations; both files are kept.
-- This one: fn_group_siblings_engaged excludes duplicate candidates and treats only a live approach as engaged
-- (out_of_scope never blocks); company_alerts gains alert_type duplicate_candidate + detail jsonb; one open alert per company.
CREATE OR REPLACE FUNCTION public.fn_group_siblings_engaged(p_team_id uuid, p_company_id uuid)
 RETURNS TABLE(company_id uuid, company_ref text, company_name text, why text)
 LANGUAGE sql STABLE SET search_path TO 'public', 'pg_temp' AS $function$
  select s.id, s.company_id, s.company_name,
         (case when s.monday_deal_id is not null or s.archive_reason = 'promoted_to_monday' then 'in Monday'
               when s.opportunity_status::text in ('Contacted','Active Lead','Partner') then s.opportunity_status::text
               else 'contact engaged' end) || '; linked by ' || p.rule || ' [' || p.evidence || ']'
    from public.fn_company_group_pairs(p_team_id, p_company_id) p
    join public.companies s on s.id = p.sibling_id
   where p.company_id = p_company_id
     and not exists (select 1 from public.fn_company_duplicate_candidates(p_team_id, p_company_id) d
                      where d.company_id = p.company_id and d.sibling_id = p.sibling_id)
     and ( s.monday_deal_id is not null or s.archive_reason = 'promoted_to_monday'
           or s.opportunity_status::text in ('Contacted','Active Lead','Partner')
           or exists (select 1 from public.contacts c where c.company_id = s.id and c.outreach_status::text in ('Contacted','In conversation','Meeting booked')) );
$function$;
alter table public.company_alerts drop constraint if exists company_alerts_type_check;
alter table public.company_alerts add constraint company_alerts_type_check check (alert_type in ('move_to_monday','duplicate_candidate'));
alter table public.company_alerts add column if not exists detail jsonb;
-- plus: insert one open duplicate_candidate alert per company from fn_company_duplicate_candidates (15 rows, 2026-09-15).
