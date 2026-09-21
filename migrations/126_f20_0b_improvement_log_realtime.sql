-- 126 F20.0(b): the improvement log tables join the realtime publication, so Brad and Oliver editing at the
-- same time see each other. Idempotent: a table already in the publication is skipped.
do $$
declare t text;
begin
  foreach t in array array['improvements','improvement_comments','improvement_activity'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
