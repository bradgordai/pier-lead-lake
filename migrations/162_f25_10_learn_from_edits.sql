-- 162 F25 Task 10: learn from Oliver's edits, not just his rejections. FORWARD-LOOKING ONLY: before this, Lovable edited
-- message_body in place and the generated text was kept nowhere (sent_body differs from message_body on 6 of 445 rows),
-- so there is no history to mine and no backfill.
--   outreach_log.generated_body text: exactly what the model produced, written by generate-draft-from-context v47 at
--   insert and never updated (trg_generated_body_immutable keeps it so).
--   On APPROVAL (draft_status -> 'approved'), when message_body differs from generated_body, trg_learn_from_edit writes ONE
--   draft_feedback row: action 'edited_before_send', reason_code NULL, signal_type 'draft_quality', use_for_training true,
--   rejected_body = generated_body (set EXPLICITLY: fn_draft_feedback_fill would otherwise fill it from message_body, the
--   EDITED text, and the pair would be identical), replacement_body = message_body, note = a short description of the
--   change. fn_draft_feedback_signal_type may still flip it to contact_state / use_for_training false when the contact's
--   latest reply is Wrong person / Left company / Referral; that is correct and is left alone.
--   The insert runs in its own exception block: a failure is logged as a WARNING and NEVER blocks or delays the approval.
-- The table is draft_feedback (44 rows, written by the app, read by the distiller). drafts_feedback (0 rows, nothing reads
-- it) is NOT used and is reported as a dead table for Brad to drop.
-- Constraints measured 2 Oct and extended:
--   draft_feedback_action_check     reject | regenerate | ai_edit            -> + edited_before_send
--   draft_feedback_reason_required  action = 'ai_edit' or reason_code set     -> + action = 'edited_before_send'

alter table public.outreach_log add column if not exists generated_body text;
comment on column public.outreach_log.generated_body is
  'F25.10: the body exactly as the model generated it (drafter v47+). Never updated. Null on older and hand-written rows.';

create or replace function public.fn_generated_body_immutable() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if old.generated_body is not null and new.generated_body is distinct from old.generated_body then
    new.generated_body := old.generated_body;
  end if;
  return new;
end $$;
drop trigger if exists trg_generated_body_immutable on public.outreach_log;
create trigger trg_generated_body_immutable before update of generated_body on public.outreach_log
  for each row execute function public.fn_generated_body_immutable();

alter table public.draft_feedback drop constraint if exists draft_feedback_action_check;
alter table public.draft_feedback add constraint draft_feedback_action_check
  check (action in ('reject','regenerate','ai_edit','edited_before_send'));
alter table public.draft_feedback drop constraint if exists draft_feedback_reason_required;
alter table public.draft_feedback add constraint draft_feedback_reason_required
  check (action in ('ai_edit','edited_before_send') or reason_code is not null);

create or replace function public.fn_learn_from_edit() returns trigger
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare g text; m text; gl int; ml int; note text; i int := 1;
begin
  if new.draft_status::text = 'approved' and old.draft_status::text is distinct from 'approved'
     and new.generated_body is not null
     and btrim(regexp_replace(coalesce(new.message_body, ''), '\s+', ' ', 'g')) <> btrim(regexp_replace(new.generated_body, '\s+', ' ', 'g')) then
    begin
      g := new.generated_body; m := coalesce(new.message_body, '');
      gl := length(g); ml := length(m);
      while i <= least(gl, ml) and substr(g, i, 1) = substr(m, i, 1) loop i := i + 1; end loop;
      note := format('Edited before approval: %s -> %s characters (%s%s). First change at character %s: "%s" became "%s".',
                     gl, ml, case when ml > gl then '+' else '' end, ml - gl, i,
                     regexp_replace(substr(g, i, 80), '\s+', ' ', 'g'), regexp_replace(substr(m, i, 80), '\s+', ' ', 'g'));
      insert into public.draft_feedback (team_id, outreach_log_id, contact_id, action, reason_code, note,
                                         rejected_body, replacement_body, use_for_training, signal_type)
      values (new.team_id, new.id, new.contact_id, 'edited_before_send', null, note, g, m, true, 'draft_quality');
    exception when others then
      raise warning 'fn_learn_from_edit: draft_feedback insert failed for outreach_log %: %', new.id, sqlerrm;
    end;
  end if;
  return new;
end $$;
drop trigger if exists trg_learn_from_edit on public.outreach_log;
create trigger trg_learn_from_edit after update of draft_status on public.outreach_log
  for each row execute function public.fn_learn_from_edit();
