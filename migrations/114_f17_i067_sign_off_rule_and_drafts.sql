-- 114 F17 i067: sign-off. Rule into voice layer 1 (applies to EVERY draft), and the existing drafts corrected.
-- Only the sign-off changes; no draft is regenerated. Each changed draft is logged before/after.
update public.voice_assets set
  body = body || E'\n\n## SIGN-OFF (always on, every channel and touch type, added 18 Sep 2026)\nSign as "Oliver" (or "Oliver Mueller" where a full name suits the channel). Never invent a short form.\nThe one exception: if THIS contact has already received a sent message from Oliver signed "Oli", keep "Oli" for that contact, because a relationship already exists. The drafting request states the sign-off to use; use exactly that, once, as the last line.\n',
  version = version || ' + sign-off rule 18 Sep 2026'
where id = 'pier_rules' and body not like '%## SIGN-OFF (always on%';

with d as (
  select o.id from public.outreach_log o
   where o.send_status::text in ('Draft','Ready') and o.draft_status::text in ('pending_review','rejected')
     and o.message_body ~ '\mOli\s*$'
     and not exists (select 1 from public.outreach_log s where s.contact_id = o.contact_id and s.send_status::text = 'Sent'
                      and s.touch_type::text <> 'Reply' and coalesce(s.sent_body, s.message_body) ~ '\mOli\s*$')
), logged as (
  insert into public.touch_merge_log (team_id, outreach_log_id, action, before, after, reason)
  select o.team_id, o.id, 'sign_off_oli_to_oliver', jsonb_build_object('message_body', o.message_body),
         jsonb_build_object('message_body', regexp_replace(o.message_body, '\mOli(\s*)$', 'Oliver\1')),
         'F17 i067: no prior sent message to this contact is signed Oli'
    from public.outreach_log o join d on d.id = o.id returning outreach_log_id
)
update public.outreach_log o set message_body = regexp_replace(o.message_body, '\mOli(\s*)$', 'Oliver\1')
 where o.id in (select outreach_log_id from logged);
