-- 149 F23 Task 1: stop the silent draft death.
-- send-approved-callback v16 set send_status='Cancelled' when PhantomBuster exited 0 with an empty resultObject
-- (a skipped send). That Cancelled then fired trg_supersede_failed_send (migration 145), which superseded the
-- approved draft, and send-approved-draft only accepts Draft or Ready: the draft was dead for good.
-- Callback v17 (deployed with this migration) returns a skipped send to send_status='Draft',
-- draft_status='pending_review' with hold_reason='phantom_skipped_duplicate'. This column records why.
--
-- DATA, per Brad's ruling of 30 Sep (NOT the brief's original "restore all 11"): all 11 existing skipped rows were
-- already draft_status='superseded' (10 by trg_supersede_failed_send with reason send_failed, Deiminger's by the
-- F22B.5 non-sales supersede), and 8 are copies of messages delivered later (Torsten x4 sent 29 Sep, Benjamin
-- Koehler x3 sent 28 Sep, Leonard Coen's opener sent 2 Sep). So: ALL 11 are tagged with hold_reason; ONLY the newest
-- Urs Moeller Chaser 1 (created 24 Sep, e143db6f) is restored to Draft + pending_review. Deiminger (Left company) is
-- never restored. Before-values in migration_audit phase f23_1.

alter table public.outreach_log add column if not exists hold_reason text;

do $$ declare n_tag int; n_restore int; begin
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f23-2026-09-30', 'f23_1', 'outreach_log', o.id::text,
         case when o.id = 'e143db6f-54ef-492c-9b7f-9da89bfbd239' then 'tag_and_restore_to_review' else 'tag_hold_reason_only' end,
         o.id, jsonb_build_object('before', jsonb_build_object('send_status', o.send_status, 'draft_status', o.draft_status,
           'hold_reason', o.hold_reason, 'rejection_feedback', o.rejection_feedback))
    from public.outreach_log o where o.send_error = 'phantom_skipped_duplicate_or_empty';

  update public.outreach_log set hold_reason = 'phantom_skipped_duplicate'
   where send_error = 'phantom_skipped_duplicate_or_empty';
  get diagnostics n_tag = row_count;
  if n_tag <> 11 then raise exception 'expected 11 skipped rows, found %', n_tag; end if;

  update public.outreach_log set send_status = 'Draft', draft_status = 'pending_review',
         rejection_feedback = null
   where id = 'e143db6f-54ef-492c-9b7f-9da89bfbd239' and send_error = 'phantom_skipped_duplicate_or_empty'
     and draft_status::text = 'superseded' and send_status::text = 'Cancelled';
  get diagnostics n_restore = row_count;
  if n_restore <> 1 then raise exception 'expected to restore 1 Urs Moeller row, restored %', n_restore; end if;

  if exists (select 1 from public.outreach_log where send_error = 'phantom_skipped_duplicate_or_empty' and draft_status::text = 'approved') then
    raise exception 'a skipped row ended at approved';
  end if;
end $$;
