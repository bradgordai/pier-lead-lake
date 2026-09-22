-- 133 F22A.4: draft_feedback. STAGE ONE: CAPTURE ONLY. Nothing reads this table yet; the distillation and any
-- drafter wiring are Prompt B and need Brad. Every Reject, Regenerate and AI edit writes one row.
--   reason_code is MANDATORY on reject and regenerate (check constraint), optional on ai_edit.
--   use_for_training defaults ON.
--   rejected_body = the draft text before; replacement_body = the text after (AI edit output / regenerated draft).
-- Context columns (contact, company, touch_type, channel, language) are filled from the draft by trigger when the
-- client leaves them null, so a thin client payload still yields a complete row.

create table if not exists public.draft_feedback (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  outreach_log_id uuid references public.outreach_log(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,
  company_id uuid references public.companies(id) on delete set null,
  touch_type text,
  channel text,
  language text,
  action text not null check (action in ('reject','regenerate','ai_edit')),
  reason_code text check (reason_code in ('wrong_angle','wrong_channel','wrong_timing','tone_off','factually_wrong','already_covered','too_long','other')),
  note text,
  rejected_body text,
  replacement_body text,
  use_for_training boolean not null default true,
  created_by uuid default auth.uid(),
  created_by_name text,
  created_at timestamptz not null default now(),
  constraint draft_feedback_reason_required check (action = 'ai_edit' or reason_code is not null)
);
create index if not exists draft_feedback_team_created_idx on public.draft_feedback (team_id, created_at desc);
create index if not exists draft_feedback_draft_idx on public.draft_feedback (outreach_log_id);

create or replace function public.fn_draft_feedback_fill() returns trigger
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare o record;
begin
  if new.outreach_log_id is not null then
    select contact_id, company_id, touch_type::text tt, channel::text ch, draft_language, message_body into o
      from public.outreach_log where id = new.outreach_log_id;
    if found then
      new.contact_id := coalesce(new.contact_id, o.contact_id);
      new.company_id := coalesce(new.company_id, o.company_id);
      new.touch_type := coalesce(new.touch_type, o.tt);
      new.channel := coalesce(new.channel, o.ch);
      new.language := coalesce(new.language, o.draft_language);
      new.rejected_body := coalesce(new.rejected_body, o.message_body);
    end if;
  end if;
  if new.created_by_name is null and new.created_by is not null then
    select coalesce(raw_user_meta_data->>'first_name', raw_user_meta_data->>'name', split_part(email,'@',1))
      into new.created_by_name from auth.users where id = new.created_by;
  end if;
  return new;
end $$;
drop trigger if exists trg_draft_feedback_fill on public.draft_feedback;
create trigger trg_draft_feedback_fill before insert on public.draft_feedback for each row execute function public.fn_draft_feedback_fill();

alter table public.draft_feedback enable row level security;
drop policy if exists draft_feedback_team_read on public.draft_feedback;
create policy draft_feedback_team_read on public.draft_feedback for select to authenticated
  using (team_id in (select fn_user_teams()));
drop policy if exists draft_feedback_team_insert on public.draft_feedback;
create policy draft_feedback_team_insert on public.draft_feedback for insert to authenticated
  with check (team_id in (select fn_user_teams()));
-- No update/delete policy: feedback is a record of what happened. The toggle is set at capture time.
