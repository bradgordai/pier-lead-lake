-- 134 F22A.5: per-contact guidance notes ("chaser 1: focus on the free first month").
-- (a) each note is its own row with its own author and timestamp; editable and deletable ONLY by whoever wrote it.
-- (b) all notes render newest first (index); (e) per contact, persist across touches.
-- (c)(d) generate-draft-from-context v43 already reads this table into its own labelled block and states that a note
-- never overrides a consent gate; before this migration the read failed quietly (table absent) and changed nothing.

create table if not exists public.contact_guidance_notes (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  contact_id uuid not null references public.contacts(id) on delete cascade,
  body text not null check (length(btrim(body)) > 0),
  author_user_id uuid not null default auth.uid(),
  author_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists contact_guidance_notes_contact_idx on public.contact_guidance_notes (contact_id, created_at desc);

create or replace function public.fn_guidance_note_stamp() returns trigger
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  if tg_op = 'INSERT' and new.author_name is null then
    select coalesce(raw_user_meta_data->>'first_name', raw_user_meta_data->>'name', split_part(email,'@',1))
      into new.author_name from auth.users where id = new.author_user_id;
  end if;
  if tg_op = 'UPDATE' then
    new.author_user_id := old.author_user_id;  -- authorship never changes
    new.created_at := old.created_at;
    new.updated_at := now();
  end if;
  return new;
end $$;
drop trigger if exists trg_guidance_note_stamp on public.contact_guidance_notes;
create trigger trg_guidance_note_stamp before insert or update on public.contact_guidance_notes
  for each row execute function public.fn_guidance_note_stamp();

alter table public.contact_guidance_notes enable row level security;
drop policy if exists guidance_notes_team_read on public.contact_guidance_notes;
create policy guidance_notes_team_read on public.contact_guidance_notes for select to authenticated
  using (team_id in (select fn_user_teams()));
drop policy if exists guidance_notes_team_insert on public.contact_guidance_notes;
create policy guidance_notes_team_insert on public.contact_guidance_notes for insert to authenticated
  with check (team_id in (select fn_user_teams()) and author_user_id = auth.uid());
drop policy if exists guidance_notes_author_update on public.contact_guidance_notes;
create policy guidance_notes_author_update on public.contact_guidance_notes for update to authenticated
  using (author_user_id = auth.uid()) with check (author_user_id = auth.uid());
drop policy if exists guidance_notes_author_delete on public.contact_guidance_notes;
create policy guidance_notes_author_delete on public.contact_guidance_notes for delete to authenticated
  using (author_user_id = auth.uid());
