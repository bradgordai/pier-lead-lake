-- F25 Task 1 regression test: a research write to companies must not raise.
-- The Python harness (tests/*.py) has no database connection, so this is an executable .sql test.
-- It EXECUTES real UPDATEs (research_stage and usp_notes) on one company and always rolls back:
-- the block ends by raising 'TEST PASS ... (rolled back)'. Any other error text is a FAIL.
-- Run: psql "$DB_URL" -f tests/company_research_write_test.sql   (or paste into the Supabase SQL runner / MCP execute_sql)
-- Expected output: ERROR:  TEST PASS: research_stage and usp_notes updates succeeded on <company> (rolled back)
do $$
declare cid uuid; nm text; st text; nxt text;
begin
  select id, company_name, research_stage::text into cid, nm, st
    from public.companies where archived_at is null order by created_at limit 1;
  nxt := case when st = 'Untouched' then 'Light triage' else 'Untouched' end;   -- both measured values of companies.research_stage
  update public.companies set research_stage = nxt::research_stage where id = cid;                    -- would raise "malformed array literal" before 157
  update public.companies set usp_notes = coalesce(usp_notes, '') || ' [regression probe]' where id = cid;
  update public.companies set research_stage = st::research_stage where id = cid;
  raise exception 'TEST PASS: research_stage and usp_notes updates succeeded on % (rolled back)', nm;
end $$;
