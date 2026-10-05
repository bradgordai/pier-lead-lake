-- 166 F26 Task 1 follow-up: fn_linkedin_url_key lowercases BEFORE stripping the scheme.
-- 165 used the brief's literal definition, lower(regexp_replace(...)), so 'HTTP://WWW.linkedin.com/in/x/' kept its
-- scheme and slipped past the duplicate guard (found by the rolled-back guard test). Measured: 0 existing rows change.
create or replace function public.fn_linkedin_url_key(p_url text)
returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(regexp_replace(regexp_replace(lower(coalesce(p_url, '')), '^https?://(www\.)?', ''), '/+$', ''), '')
$$;

update public.contacts set linkedin_url_key = public.fn_linkedin_url_key(linkedin_url)
 where linkedin_url_key is distinct from public.fn_linkedin_url_key(linkedin_url);
