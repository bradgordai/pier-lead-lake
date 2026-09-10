-- 086 F13.4 (2026-09-10): chase_state must not claim a draft was sent. The engine wrote
-- chaser_N_sent when it DRAFTED a chaser. New value 'chaser_drafted' for that moment;
-- chaser_N_sent is written by fn_apply_send_effects when the chaser actually goes out.
-- Cosmetic: the engine already parks contacts with a pending draft, so no double chaser.
alter table public.contacts drop constraint if exists contacts_chase_state_check;
alter table public.contacts add constraint contacts_chase_state_check
  check (chase_state = any (array['none','awaiting_reply','chaser_drafted','chaser_1_sent','chaser_2_sent','exhausted','replied','cooldown']));
-- Repair: chaser_N_sent with zero sent chasers and a pending chaser draft.
do $$
declare r record; v_run text := 'f13-4-chaser-drafted-2026-09-10';
begin
  for r in select c.id, c.contact_id, c.first_name, c.last_name, c.chase_state
             from public.contacts c
            where c.team_id = 'ef73c15e-4d6f-4159-bcfa-cc76b5ae4972'
              and c.chase_state in ('chaser_1_sent','chaser_2_sent') and coalesce(c.chaser_count,0) = 0
              and not exists (select 1 from public.outreach_log o where o.contact_id=c.id and o.send_status::text='Sent' and o.touch_type::text like 'Chaser %') loop
    update public.contacts set chase_state = 'chaser_drafted', updated_at = now() where id = r.id;
    insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
      values (v_run, 'f13_4_chaser_drafted', 'contacts', r.contact_id, 'update', r.id,
              jsonb_build_object('name', r.first_name||' '||r.last_name, 'before', r.chase_state, 'after', 'chaser_drafted'));
  end loop;
end $$;
