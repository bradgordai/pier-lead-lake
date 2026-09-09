-- 081: F12 T4 helper used by enrich-company-websites to mark a found website as inferred.
create or replace function public.fn_set_field_provenance(p_company_id uuid, p_field text, p_source text, p_basis text)
returns void language sql set search_path to 'public','pg_temp' as $$
  update public.companies
     set field_provenance = coalesce(field_provenance,'{}'::jsonb) || jsonb_build_object(p_field, jsonb_build_object('source', p_source, 'basis', p_basis, 'at', now())),
         country_inferred = case when p_field = 'country' and p_source = 'inferred' then true else country_inferred end
   where id = p_company_id;
$$;
revoke execute on function public.fn_set_field_provenance(uuid, text, text, text) from public, anon, authenticated;
