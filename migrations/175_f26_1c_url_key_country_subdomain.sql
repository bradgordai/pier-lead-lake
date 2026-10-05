-- 175 F26 Task 1 follow-up, found while verifying the L1 screen: two people appeared twice in the CR queue.
-- (a) Meik Neuhaus P655 'https://de.linkedin.com/in/meikneuhaus' vs P908 'https://linkedin.com/in/meikneuhaus':
--     the key kept LinkedIn's country subdomain (de., pt.). 2 rows carry one; 1 live duplicate pair results.
--     The key now folds xx.linkedin.com to linkedin.com and the pair is merged by fn_merge_contact_duplicates (167 rules;
--     no consent flag differs: measured).
-- (b) P591 "David Resa Polo" has linkedin_url .../in/daniel-ramos-1297348a, another person's profile (P891 holds the
--     real david-resa-polo URL). A connection request from the queue would go to the wrong person. Its queue row is
--     skipped with the reason; the URL itself is left for Oliver to correct (not guessed here).
-- Francesco Briguglio P679 / P680 carry two DIFFERENT profile URLs and are left alone (may be two profiles).

create or replace function public.fn_linkedin_url_key(p_url text)
returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           lower(public.fn_url_percent_decode(btrim(coalesce(p_url, '')))),
           '^https?://', ''),
           '^(www\.|[a-z]{2,3}\.)(linkedin\.com/)', '\2'),
           '[?#].*$', ''),
           '^(linkedin\.com/in/[^/?#]+)/[a-z]{2}(/|$)', '\1'),
           '[/?#]+$', ''), '')
$$;

update public.contacts set linkedin_url_key = public.fn_linkedin_url_key(linkedin_url)
 where linkedin_url_key is distinct from public.fn_linkedin_url_key(linkedin_url);

select public.fn_merge_contact_duplicates('2026-10-05 (175 country subdomain)', 'f26_1c_merge') as merged;

-- a merge loser never stays queued
update public.cr_queue q set status = 'cancelled', skip_reason = 'contact merged into ' || s.contact_id
  from public.contacts l join public.contacts s on s.id = l.merged_into_contact_id
 where q.contact_id = l.id and q.status = 'queued';

update public.cr_queue q set status = 'skipped',
       skip_reason = 'LinkedIn URL points at another person (daniel-ramos-1297348a); correct the contact before any request'
  from public.contacts c
 where q.contact_id = c.id and c.contact_id = 'P591' and q.status = 'queued';
