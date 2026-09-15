-- 103 (Cowork, applied 2026-09-15 11:32 UTC via the Supabase MCP as 103_f16_1_duplicates_not_siblings_and_out_of_scope).
-- Recorded here so the repo carries every version name present in supabase_migrations.schema_migrations.
-- What it created, as it stands in pg_proc today:
CREATE OR REPLACE FUNCTION public.fn_company_duplicate_candidates(p_team_id uuid, p_company_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(company_id uuid, sibling_id uuid, rule text, evidence text)
 LANGUAGE sql STABLE SET search_path TO 'public', 'pg_temp' AS $function$
  with n as (
    select id, regexp_replace(lower(company_name), '[^[:alnum:]]', '', 'g') as key
      from public.companies where team_id = p_team_id)
  select p.company_id, p.sibling_id, p.rule, p.evidence
    from public.fn_company_group_pairs(p_team_id, p_company_id) p
    join n a on a.id = p.company_id
    join n b on b.id = p.sibling_id
   where p.rule <> 'R1 exact parent_group'
     and length(a.key) >= 5 and length(b.key) >= 5
     and (a.key like '%'||b.key||'%' or b.key like '%'||a.key||'%');
$function$;
