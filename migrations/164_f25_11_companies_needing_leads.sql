-- 164 F25 Task 11: deep-researched companies with nobody to write to. Oliver's research pipeline only finishes a company
-- when leads are in the list; nothing showed which researched companies have no contacts.
-- v_companies_needing_leads: research_stage 'Deep research done', archived_at null, opportunity_status not 'Out of Scope',
-- zero contacts (archived contacts count as contacts: the person exists). Ordered by score desc (unscored last), with
-- assessed_points so the screen can say "62 of 80 assessed".
create or replace view public.v_companies_needing_leads with (security_invoker = true) as
select co.id as company_id, co.team_id, co.company_id as company_ref, co.company_name, co.country, co.priority::text as priority,
       co.opportunity_status::text as opportunity_status, co.last_refreshed,
       s.score, s.assessed_points, s.research_upside, (s.company_id is not null) as is_scored
  from public.companies co
  left join public.company_scores s on s.company_id = co.id
 where co.research_stage::text = 'Deep research done'
   and co.archived_at is null
   and co.opportunity_status::text is distinct from 'Out of Scope'
   and not exists (select 1 from public.contacts c where c.company_id = co.id)
 order by s.score desc nulls last, co.company_name;
grant select on public.v_companies_needing_leads to authenticated;
