-- 129 F20.1(b)(d): what the card reads to show the red flag, and the OTHER half of why Oliver's accepted
-- leads got no first message.
-- (b) outreach_log.research_warning: set by the drafter when the company is not deep researched. Null = none.
alter table public.outreach_log add column if not exists research_warning text;
comment on column public.outreach_log.research_warning is
  'Set by the drafter when the draft was written for a company that is not deep researched (F20.1). The card shows it in red. Null means the company was deep researched.';
-- Replies drafted before today already carry the note at the front of draft_narrative; lift it into the column.
update public.outreach_log set research_warning = substring(draft_narrative from '^(Company not deep researched[^:]*:[^.]*\.)')
 where research_warning is null and draft_narrative ~* '^Company not deep researched'
   and send_status::text in ('Draft','Ready') and draft_status::text in ('pending_review','approved');

-- (d) MEASURED 21 Sep: 14 first-message candidates passed EVERY gate and still got no draft, because
-- team_settings.first_message_after_cr_enabled was false (switched off during the 14 Sep blackout recovery).
-- The research gate was only the second lock. Brad's F20.1(d) instruction is to run this route; the per-route
-- cap stays 5 per run and the new overall ceiling is max_drafts_per_run = 20.
update public.team_settings set first_message_after_cr_enabled = true where first_message_after_cr_enabled is distinct from true;
