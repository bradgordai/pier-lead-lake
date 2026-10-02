-- 160 F25 Task 5: consent breaches. Fact repair for FOUR contacts only. Data only, no schema change.
-- Each was told in writing that Oliver would stop, yet promise_of_quiet was false, chase_state chaser_drafted, and the
-- chase engine kept adding drafts. The quoted sentences (from the sent thread, read 2 Oct):
--   P533 Joan Corral Ramírez  Follow up 27 Jul: "Last one from me on this so I am not filling your inbox." ...
--                                               "I will park it and leave the door open."
--   P536 Michael Taelman      Chaser 2 21 Aug:  "Last one from me."
--   P537 Marvin in 't Groen   Chaser 2 21 Aug:  "Last one from me, and with a number this time."
--   P619 Oscar Hundman        Chaser 2 27 Aug:  "One short follow-up and then I will leave it with you."
-- DO:
--   1. promise_of_quiet = true, promise_of_quiet_note = the quote.
--   2. Close the 14 open drafts (send_status Draft at 2 Oct). The 4 pending_review rows become send_status Cancelled +
--      draft_status superseded (fn_superseded_is_not_sent's own combination). The 10 rows ALREADY draft_status 'rejected'
--      keep 'rejected' and only become Cancelled: relabelling them superseded would erase Oliver's rejection reasons,
--      which the drafter's rejection block (F24.1) and the distiller read. All 14 get hold_reason 'promise_of_quiet' and
--      a send_error quoting the promise. Nothing is deleted.
--   3. cooldown_until = current_date + team_settings.cooldown_days (read, not hardcoded; 90 on 2 Oct), chase_state 'cooldown'.
-- NOT touched: chaser_count, chase_last_outbound_at, last_contacted, send_queue (asserted in the report).
-- Audit rows in migration_audit, phase f25_5.

with q(ref, note) as (values
  ('P533', 'F25.5 (2 Oct 2026): promised in the Follow up of 27 Jul 2026: "Last one from me on this so I am not filling your inbox." / "I will park it and leave the door open."'),
  ('P536', 'F25.5 (2 Oct 2026): promised in Chaser 2 of 21 Aug 2026: "Last one from me."'),
  ('P537', 'F25.5 (2 Oct 2026): promised in Chaser 2 of 21 Aug 2026: "Last one from me, and with a number this time."'),
  ('P619', 'F25.5 (2 Oct 2026): promised in Chaser 2 of 27 Aug 2026: "One short follow-up and then I will leave it with you."')),
team as (select team_id, cooldown_days from public.team_settings limit 1),
before as (select c.id, c.contact_id, c.promise_of_quiet, c.chase_state, c.cooldown_until from public.contacts c join q on q.ref = c.contact_id, team where c.team_id = team.team_id),
upd as (
  update public.contacts c set promise_of_quiet = true, promise_of_quiet_note = q.note,
         cooldown_until = current_date + team.cooldown_days, chase_state = 'cooldown'
    from q, team where c.contact_id = q.ref and c.team_id = team.team_id
  returning c.id, c.contact_id, c.cooldown_until)
insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select 'f25_5_2026-10-02', 'f25_5', 'contacts', u.contact_id, 'promise_of_quiet_set', u.id,
       jsonb_build_object('before', jsonb_build_object('promise_of_quiet', b.promise_of_quiet, 'chase_state', b.chase_state, 'cooldown_until', b.cooldown_until),
                          'after', jsonb_build_object('promise_of_quiet', true, 'chase_state', 'cooldown', 'cooldown_until', u.cooldown_until))
  from upd u join before b on b.id = u.id;

with targets as (
  select o.id, o.draft_status::text as ds, c.contact_id as ref, c.promise_of_quiet_note
    from public.outreach_log o join public.contacts c on c.id = o.contact_id
   where c.contact_id in ('P533','P536','P537','P619') and o.send_status::text in ('Draft','Ready','Scheduled')
     and o.draft_status::text in ('pending_review','rejected')),
upd as (
  update public.outreach_log o
     set send_status = 'Cancelled',
         draft_status = case when t.ds = 'pending_review' then 'superseded'::draft_status else o.draft_status end,
         hold_reason = 'promise_of_quiet',
         send_error = left('promise_of_quiet: ' || t.promise_of_quiet_note, 500)
    from targets t where o.id = t.id
  returning o.id, t.ref, t.ds)
insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select 'f25_5_2026-10-02', 'f25_5', 'outreach_log', u.ref, 'draft_cancelled_promise_of_quiet', u.id,
       jsonb_build_object('draft_status_before', u.ds, 'send_status_before', 'Draft')
  from upd u;
