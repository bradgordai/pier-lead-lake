-- 116 F18.1(b) i092: a contact may only leave chase_state 'none' when a MESSAGE has actually been sent.
-- Cause (located): an inline execute_sql in the 4 Sep 2026 migration session, 16:15:32 UTC (never a file),
-- computed last_out from Sent rows INCLUDING Connection requests, so a contact with only a sent CR became
-- 'awaiting_reply'. A connection request is not a message and nobody is awaiting a reply to it.
-- Dry run 20 Sep (rolled back): 126 targets; fn_chase_candidates, fn_cold_inmail_candidates,
-- fn_first_message_candidates, fn_chase_exhausted, fn_send_ready_contacts and fn_evaluate_gates returned
-- IDENTICAL results before and after. Zero contacts become newly eligible for anything.
insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select 'f18-2026-09-20', 'f18_1_chase_state_repair', 'contacts', c.contact_id, 'chase_state_reset_to_none', c.id,
       jsonb_build_object('before', jsonb_build_object('chase_state', c.chase_state, 'chase_next_due_at', c.chase_next_due_at),
                          'after', jsonb_build_object('chase_state', 'none', 'chase_next_due_at', null),
                          'reason', 'zero sent messages (a sent connection request is not a message)')
  from public.contacts c
 where c.chase_state in ('awaiting_reply','chaser_1_sent','chaser_2_sent','chaser_drafted')
   and not exists (select 1 from public.outreach_log o where o.contact_id = c.id and o.send_status::text = 'Sent'
                    and o.touch_type::text not in ('Reply','Connection request'));

update public.contacts c set chase_state = 'none', chase_next_due_at = null
 where c.chase_state in ('awaiting_reply','chaser_1_sent','chaser_2_sent','chaser_drafted')
   and not exists (select 1 from public.outreach_log o where o.contact_id = c.id and o.send_status::text = 'Sent'
                    and o.touch_type::text not in ('Reply','Connection request'));

-- (e) regression views: both must always return zero rows.
create or replace view public.v_regress_chase_state_without_sent_message with (security_invoker = true) as
select c.id, c.contact_id as contact_ref, c.chase_state from public.contacts c
 where c.chase_state in ('awaiting_reply','chaser_1_sent','chaser_2_sent','chaser_drafted','exhausted')
   and not exists (select 1 from public.outreach_log o where o.contact_id = c.id and o.send_status::text = 'Sent'
                    and o.touch_type::text not in ('Reply','Connection request'));
create or replace view public.v_regress_chaser_without_sent_initial with (security_invoker = true) as
select o.id, o.contact_ref, o.touch_type::text as touch_type, o.channel::text as channel, o.send_status::text as send_status, o.draft_status::text as draft_status
  from public.outreach_log o
 where o.touch_type::text in ('Chaser 1','Chaser 2','Chaser 3','Chase')
   and o.draft_status::text not in ('superseded','rejected') and o.send_status::text <> 'Cancelled'
   and not exists (select 1 from public.outreach_log s where s.contact_id = o.contact_id and s.channel = o.channel
                    and s.send_status::text = 'Sent' and s.touch_type::text not in ('Reply','Connection request')
                    and s.touch_type::text not like 'Chase%' and s.id <> o.id);
grant select on public.v_regress_chase_state_without_sent_message, public.v_regress_chaser_without_sent_initial to authenticated;
