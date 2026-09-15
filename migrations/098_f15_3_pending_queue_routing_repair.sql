-- 098 F15.3 (2026-09-15): repair the pending queue against the routing matrix.
-- 12 pending drafts break invariant (a) or (b):
--   9 x "Chaser 1 / LinkedIn inMail" to contacts who never received any message (r1 says Initial message / InMail)
--   3 x "Initial message / LinkedIn DM" to contacts who are not connected (r13: never a DM)
-- They are SUPERSEDED here (never relabelled) and regenerated through the drafter with the right trigger, so the
-- text is written for what it actually is. The regenerate calls are made by the operator script after this file.
update public.outreach_log o
   set draft_status = 'superseded',
       rejection_feedback = jsonb_build_object('reason', 'routing_repair', 'detail',
         case when o.touch_type::text like 'Chaser %' then 'F15.3: a chaser cannot exist before a real message on this channel; regenerated as Initial message / LinkedIn inMail.'
              else 'F15.3: a LinkedIn DM cannot go to a contact who is not connected; regenerated as Initial message / LinkedIn inMail.' end),
       updated_at = now()
  from public.contacts c
 where c.id = o.contact_id and o.draft_status = 'pending_review'
   and c.connection_status::text not in ('Accepted','Already connected')
   and not exists (select 1 from public.outreach_log s where s.contact_id = c.id and s.send_status = 'Sent'
                     and s.touch_type::text not in ('Reply','Connection request') and s.channel::text = o.channel::text)
   and ( (o.touch_type::text like 'Chaser %' and o.channel::text = 'LinkedIn inMail')
      or (o.touch_type::text = 'Initial message' and o.channel::text = 'LinkedIn DM') );

-- a contact with no real message sent is not "chaser_drafted"
update public.contacts c set chase_state = 'none'
 where c.chase_state = 'chaser_drafted'
   and exists (select 1 from public.outreach_log o where o.contact_id = c.id and o.draft_status = 'superseded' and o.rejection_feedback->>'reason' = 'routing_repair')
   and not exists (select 1 from public.outreach_log s where s.contact_id = c.id and s.send_status = 'Sent' and s.touch_type::text not in ('Reply','Connection request'));

insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
select 'f15-3-routing-repair-2026-09-15', 'supersede', 'outreach_log', o.touch_id, 'update', o.id,
       jsonb_build_object('was', o.touch_type::text||' / '||o.channel::text, 'contact', c.contact_id, 'name', c.first_name||' '||c.last_name)
  from public.outreach_log o join public.contacts c on c.id = o.contact_id
 where o.rejection_feedback->>'reason' = 'routing_repair';
