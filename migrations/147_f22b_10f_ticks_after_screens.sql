-- 147 F22B.10(f): ticks for items whose screen shipped, was verified in Chrome and was published (Lovable 51f0e2c and
-- af7b7f6, F22B publishes #4 and #5). Held, not ticked: i134 (failed-send notice not seen rendered), i129 (contrast
-- change not judged by eye), i127 (the chase engine can still draft for a parked company: needs a gate).
do $$ declare r record; n int := 0; begin
  for r in select * from (values
    ('i113', 'Lovable 51f0e2c, published 23 Sep: an unsent row has a dashed border, "Draft, not sent" / "Approved, not sent yet" and "written <date>"; sent rows keep "sent <date>". Seen in Chrome on Thomas Arnoldner''s Conversation tab.'),
    ('i098', 'proofread-drafts v1 (Haiku, flags only; cron every 15 min, migration 146) stores outreach_log.proofread_flags; the draft card shows "N proofreading notes" (Lovable 51f0e2c). Seen in Chrome: 2 notes on Thomas Arnoldner''s draft (missing comma, "wieviel").'),
    ('i128', 'Migration 146/146a: manual balance via fn_set_inmail_credits with low (<=20) and stale (>7 days) warnings plus InMails sent this month; Today card in Lovable af7b7f6, seen in Chrome ("Never entered", "32 InMails sent this month"). Automation still later.')
  ) v(k, ev) loop
    update public.improvements set status = 'done', done_by = 'Brad', done_at = now() where item_key = r.k and status = 'open';
    if found then
      n := n + 1;
      insert into public.improvement_activity (team_id, improvement_id, item_key, who, at, action, before, after)
      select i.team_id, i.id, i.item_key, 'Claude (F22B batch)', now(), 'ticked off', jsonb_build_object('status', 'open'),
             jsonb_build_object('status', 'done', 'evidence', r.ev)
        from public.improvements i where i.item_key = r.k;
    end if;
  end loop;
  if n <> 3 then raise exception 'expected 3 ticks, made %', n; end if;
end $$;
