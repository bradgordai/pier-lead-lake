-- 052_chase_engine_and_card.sql
-- Batch B schema: chase engine state (B5), touch-card fields (B7), move-to-Monday
-- alerts (B8).
--
-- THE CHASE-STATE CONTRACT. Tonight's catch-up migration and the chase engine must read
-- and write THE SAME per-contact fields; two sources of truth here would produce either
-- duplicate chasers or silent gaps. These columns are that single source of truth:
--
--   contacts.chase_state           where this contact is in the cadence
--   contacts.chaser_count          how many chasers have actually been SENT (not drafted)
--   contacts.chase_last_outbound_at   date of the outbound touch the clock runs from
--   contacts.chase_next_due_at     when the next chaser becomes due (nullable = not due)
--   contacts.chase_scheduled_for   explicit future date; overrides the interval when set
--   contacts.cooldown_until        already existed (date). Reused, not duplicated.
--
-- DELIBERATE CHOICES, flagged rather than assumed:
--
-- 1. chase_state is TEXT + CHECK, not a Postgres enum. The catch-up migration may need to
--    introduce a state we have not thought of tonight; widening a CHECK is a one-line
--    ALTER, widening an enum needs ALTER TYPE ... ADD VALUE which cannot run inside a
--    transaction block on older PG and cannot be reverted. If the state set settles, this
--    can become an enum later.
--
-- 2. chaser_count counts SENT chasers, not drafted ones. A draft sitting in Pending Review
--    has not been chased - counting drafts would let the cap be consumed by drafts Oli
--    never approves, and the cadence would stall silently.
--
-- 3. chase_next_due_at is STORED, not computed on read. The engine runs daily over the
--    whole contact table; a stored, indexed date turns that into a range scan. It is
--    derived (chase_last_outbound_at + team_settings.chase_interval_days) and the engine
--    is responsible for keeping it correct.
--
-- 4. chase_scheduled_for OVERRIDES the interval when set. This is what carries the 26 Oct
--    re-engagement: a contact can be parked with a future date and the engine will ignore
--    the normal interval until that date arrives.
--
-- 5. 'exhausted' is terminal for the cadence, NOT for the contact. Chaser cap reached and
--    cooldown set; the contact can re-enter via a reply or an explicit reschedule.

-- ---------------------------------------------------------------- B5 chase state
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS chase_state            text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS chaser_count           smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS chase_last_outbound_at date,
  ADD COLUMN IF NOT EXISTS chase_next_due_at      date,
  ADD COLUMN IF NOT EXISTS chase_scheduled_for    date;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contacts_chase_state_check') THEN
    ALTER TABLE public.contacts ADD CONSTRAINT contacts_chase_state_check
      CHECK (chase_state IN ('none','awaiting_reply','chaser_1_sent','chaser_2_sent','exhausted','replied','cooldown'));
  END IF;
END $$;

COMMENT ON COLUMN public.contacts.chase_state IS
  'Chase cadence position. Single source of truth shared by the chase engine and the catch-up migration (052).';
COMMENT ON COLUMN public.contacts.chaser_count IS
  'Chasers actually SENT (not drafted). Capped by team_settings.chaser_cap.';
COMMENT ON COLUMN public.contacts.chase_scheduled_for IS
  'Explicit future chase date. When set, overrides the chase_interval_days schedule.';

-- The engine's hot path: due contacts, priority-first. Partial index keeps it small.
CREATE INDEX IF NOT EXISTS idx_contacts_chase_due
  ON public.contacts (chase_next_due_at)
  WHERE chase_state IN ('awaiting_reply','chaser_1_sent','chaser_2_sent');
CREATE INDEX IF NOT EXISTS idx_contacts_chase_scheduled
  ON public.contacts (chase_scheduled_for)
  WHERE chase_scheduled_for IS NOT NULL;

-- ---------------------------------------------------------------- B7 touch card
-- generate-draft-from-context now returns {draft, narrative, guardrails[]}; the card
-- renders narrative as prose and each guardrail as an amber "do not" box.
ALTER TABLE public.outreach_log
  ADD COLUMN IF NOT EXISTS draft_narrative  text,
  ADD COLUMN IF NOT EXISTS draft_guardrails jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.outreach_log.draft_guardrails IS
  'Array of strings: things NOT to do on this touch (e.g. do not restate an ignored number). Rendered amber on the card.';

-- AI edit must REWRITE the body and stack a revision, never append a note to the draft.
-- Revision 0 is the original generation, written at draft creation.
CREATE TABLE IF NOT EXISTS public.draft_revisions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id          uuid NOT NULL,
  outreach_log_id  uuid NOT NULL REFERENCES public.outreach_log(id) ON DELETE CASCADE,
  revision_number  int  NOT NULL,
  message_body     text NOT NULL,
  edit_instruction text,
  created_by       uuid,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (outreach_log_id, revision_number)
);
CREATE INDEX IF NOT EXISTS idx_draft_revisions_touch
  ON public.draft_revisions (outreach_log_id, revision_number DESC);

ALTER TABLE public.draft_revisions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS draft_revisions_team ON public.draft_revisions;
CREATE POLICY draft_revisions_team ON public.draft_revisions
  FOR ALL TO authenticated
  USING (team_id IN (SELECT public.fn_user_teams()))
  WITH CHECK (team_id IN (SELECT public.fn_user_teams()));

-- ---------------------------------------------------------------- B8 move-to-Monday
-- One OPEN alert per company at a time. A rejected alert is dismissed, and the next
-- inbound reply from that company re-fires it: that is why the uniqueness is partial on
-- status='open' rather than a plain unique on (team_id, company_id).
CREATE TABLE IF NOT EXISTS public.company_alerts (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id               uuid NOT NULL,
  company_id            uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  alert_type            text NOT NULL DEFAULT 'move_to_monday',
  status                text NOT NULL DEFAULT 'open',
  triggered_by_touch_id uuid REFERENCES public.outreach_log(id) ON DELETE SET NULL,
  trigger_count         int  NOT NULL DEFAULT 1,
  first_seen_at         timestamptz NOT NULL DEFAULT now(),
  last_seen_at          timestamptz NOT NULL DEFAULT now(),
  resolved_at           timestamptz,
  resolved_by           uuid,
  CONSTRAINT company_alerts_status_check CHECK (status IN ('open','approved','dismissed')),
  CONSTRAINT company_alerts_type_check   CHECK (alert_type IN ('move_to_monday'))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_company_alerts_open
  ON public.company_alerts (team_id, company_id, alert_type)
  WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_company_alerts_open
  ON public.company_alerts (team_id, status, last_seen_at DESC);

ALTER TABLE public.company_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS company_alerts_team ON public.company_alerts;
CREATE POLICY company_alerts_team ON public.company_alerts
  FOR ALL TO authenticated
  USING (team_id IN (SELECT public.fn_user_teams()))
  WITH CHECK (team_id IN (SELECT public.fn_user_teams()));

COMMENT ON TABLE public.company_alerts IS
  'Today-surface alerts about a company. move_to_monday fires on any inbound reply; approving archives the company with archive_reason promoted_to_monday. No snooze by design (052/B8).';
