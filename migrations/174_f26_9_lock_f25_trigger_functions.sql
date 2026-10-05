-- 174 F26 Task 9: five SECURITY DEFINER trigger functions were callable over /rest/v1/rpc by anon and authenticated
-- (security advisor, 5 Oct). None is meant to be called directly by anyone. Same pattern as 152: revoke from PUBLIC too,
-- because both roles inherit PUBLIC's EXECUTE. The triggers keep firing: EXECUTE is checked when a trigger is created,
-- not when it fires.
--   fn_learn_from_edit             trg_learn_from_edit on outreach_log (F25.10)
--   fn_draft_feedback_fill         trg_draft_feedback_fill on draft_feedback
--   fn_assign_revision_number      revision numbering trigger
--   fn_guidance_note_stamp         trg_guidance_note_stamp on contact_guidance_notes
--   fn_supersede_older_open_drafts trg_one_open_draft on outreach_log (F17)
-- Left callable on purpose (the app calls them, and each checks team membership itself): fn_set_auto_score_new_companies,
-- fn_set_inmail_credits, fn_release_send_queue, fn_user_teams (used inside RLS policies), fn_improvement_log_can_edit,
-- and today's fn_set_cr_dispatch_enabled (admin-only ON) and fn_mark_cr_withdrawn (Reconciliation batch action).
revoke execute on function public.fn_learn_from_edit() from public, anon, authenticated;
revoke execute on function public.fn_draft_feedback_fill() from public, anon, authenticated;
revoke execute on function public.fn_assign_revision_number() from public, anon, authenticated;
revoke execute on function public.fn_guidance_note_stamp() from public, anon, authenticated;
revoke execute on function public.fn_supersede_older_open_drafts() from public, anon, authenticated;
