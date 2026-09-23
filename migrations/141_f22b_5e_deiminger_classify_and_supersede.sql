-- 141 F22B.5(e): Deiminger is the test. SUPERSEDE AND CLASSIFY, never resend.
-- A second migration for F22B.5 only because Postgres cannot use an enum value in the transaction that adds it
-- ('Left company' was added by 140).
-- 1. His 22 Sep reply ("ich bin nicht mehr für die GSD tätig ...") was classified 'Wrong person'; it is 'Left company',
--    with the triggering line stored for the red card.
-- 2. His stranded reply draft (approved, then Cancelled by PhantomBuster's skip) is superseded with the reason.
--    Nothing else about him changes: the card's actions (Mark Left company, Park company, Snooze, Find another
--    contact) are one click each, for Oliver, and nothing is automatic.
do $$ declare r_id uuid; d_id uuid; n int; begin
  select o.id into r_id from public.outreach_log o join public.contacts c on c.id = o.contact_id
   where c.contact_id = 'P581' and o.touch_type::text = 'Reply' and o.reply_content like '%nicht mehr für die GSD tätig%';
  select o.id into d_id from public.outreach_log o join public.contacts c on c.id = o.contact_id
   where c.contact_id = 'P581' and o.touch_type::text = 'Follow up' and o.draft_status::text = 'approved' and o.send_status::text = 'Cancelled';
  if r_id is null or d_id is null then raise exception 'Deiminger rows not found (reply %, draft %)', r_id, d_id; end if;

  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22b-2026-09-23', 'f22b_5e_deiminger', 'outreach_log', o.id::text,
         case when o.id = r_id then 'reclassify_left_company' else 'supersede_stranded_draft' end, o.id,
         jsonb_build_object('before', jsonb_build_object('reply_classification', o.reply_classification, 'draft_status', o.draft_status, 'send_status', o.send_status))
    from public.outreach_log o where o.id in (r_id, d_id);

  update public.outreach_log set reply_classification = 'Left company',
         reply_trigger_quote = 'ich bin nicht mehr für die GSD tätig. Die Profildaten wurden noch nicht aktualisiert.',
         reply_reasoning = coalesce(reply_reasoning || ' | ', '') || 'F22B.5: reclassified Left company (he says he no longer works for GSD).'
   where id = r_id;
  update public.outreach_log set draft_status = 'superseded',
         rejection_feedback = jsonb_build_object('reason', 'non_sales_reply', 'detail',
           'Superseded 23 Sep (F22B.5): the contact replied that he has left GSD. Not resent. Cancelled by PhantomBuster on 22 Sep.')
   where id = d_id and send_status::text = 'Cancelled';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'supersede touched % rows', n; end if;
end $$;
