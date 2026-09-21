-- 123 F19.10 + F19 addendum 3: improvement log housekeeping. Data only. The activity trigger records every
-- change below by itself (who = 'system', because this runs as a migration, not as a signed-in person).
-- Keys are allocated as the next free number below i900 (i900 and i999 are reserved specials).

-- (a) i096: resolved, tick WITH a note. i001 was already ticked by Brad, so it is left alone.
update public.improvements set status = 'done', done_by = 'Claude (F19.10, on Brad''s instruction)', done_at = now(),
       notes = notes || E'\n\n[21 Sep 2026, F19.10] RESOLVED. Cause: the app computed revision_number itself and landed on a number already taken whenever a draft had been revised before. All approvals were intact throughout; only the revision snapshot failed. Fixed in the database on 18 Sep (the database now assigns the number). The UI half shipped to Lovable on 21 Sep (commit 639e4f4a): one write per click, all action buttons disabled while busy, exactly one toast per action. Not yet exercised by a real Approve.'
 where item_key = 'i096' and status <> 'done';

with base as (
  select (select id from public.teams limit 1) as team_id,
         coalesce((select max(substring(item_key from 2)::int) from public.improvements where item_key ~ '^i[0-9]+$' and substring(item_key from 2)::int < 900), 0) as n
), new_items(ord, title, category, owner, priority, detail, notes, contact_ref) as (values
  (1, 'The "Awaiting Oliver''s ruling:" prefix stacks on repeated pending_ruling refusals',
      'Outreach & drafting', 'Brad', 'must',
      'Each time a contact held for a ruling is refused again, the refusal''s human-readable reason gains another "Awaiting Oliver''s ruling:" in front of it, so the sentence grows with every run ("Awaiting Oliver''s ruling: Awaiting Oliver''s ruling: …"). Seen in the refusals table on 20 Sep 2026 while re-coding archive refusals (F16.4): 45 pending_ruling refusals, the repeated ones carry the stacked prefix.',
      'Not fixed on purpose (F19.10b). The text is built where the pending_ruling reason is composed; it should be written once, not prepended to the previous refusal''s text.', null),
  (2, 'A send between 23:00 and 24:00 UTC in summer lands on two different days',
      'Data & schema', 'Brad', 'nice',
      'When a send completes, the touch is dated with the LONDON date. The reply sync that recognises Oliver''s own messages compares the UTC date. Between 23:00 and 24:00 UTC in British Summer Time those are different days, so the same-day duplicate match misses and the message can be logged twice.',
      'Found in F17.5 while checking the hand-written Frank Pelzer row. Not fixed here (F19.10c). Either side can move; both should use one date.', null),
  (3, 'Today shows replies as one large block; each person should be a collapsible row',
      'Lovable UI', 'Brad', 'must',
      'On Today, "Replies needing an answer" renders every reply in full, one after another. Each person should be a collapsible row showing their draft answer, with a click through to their touchpoint in Outreach.',
      'Raised by Brad on 21 Sep 2026 after the list went from 2 visible to all 22. Flagged, not fixed (F19 addendum 3a).', null),
  (4, 'Contacts who replied carry none of the earlier conversation',
      'Integrations', 'Both', 'must',
      'Ishnav Thakooree (Dataxis) has asked for a testimonial and the system holds one row for him: his inbound message. Nothing Oliver said before it is recorded. Replies matched by the inbox sync arrive without the thread that led to them, so any draft answer is written blind.',
      'Likely needs a full PhantomBuster inbox scrape of legacy contacts. SCOPE IT, DO NOT RUN IT: the inbox scraper keeps only the 20 newest threads, InMails are not in the LinkedIn data export at all, and nobody has confirmed PhantomBuster can read message history without account risk (i048).', 'P761'),
  (5, 'A received LinkedIn DM is recorded against a contact who is "Not connected"',
      'Data & schema', 'Brad', 'nice',
      'Six contacts have a received message while connection_status is not Accepted. Five are legitimate: their replies came by InMail or email, which need no connection (P016, P083, P277, P444, P611, all Withdrawn). ONE is a data fault: Ishnav Thakooree (P761) replied by LinkedIn DM while recorded as Not connected. A DM cannot arrive from someone who is not a connection, so his connection status is wrong.',
      'Reported, not repaired (F19 addendum 3c). He is 1st degree in reality; correcting it needs a positive signal, not an inference (see i094).', 'P761')
)
insert into public.improvements (team_id, item_key, title, category, owner, priority, status, raised_by, created_at, blocks, blocked_by, pinned, hidden, seen_by, detail, notes, linked_contact_id)
select b.team_id, 'i' || lpad((b.n + i.ord)::text, 3, '0'), i.title, i.category, i.owner, i.priority, 'open', 'Brad', now(),
       '{}'::text[], '{}'::text[], false, false, '{}'::jsonb, i.detail, i.notes,
       (select c.id from public.contacts c where c.contact_id = i.contact_ref)
  from new_items i cross join base b
 where not exists (select 1 from public.improvements x where x.title = i.title);
