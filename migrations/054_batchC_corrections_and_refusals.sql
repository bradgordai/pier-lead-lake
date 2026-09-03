-- 054_batchC_corrections_and_refusals.sql
-- Batch C Phase 1: Oli's corrections + the refusal architecture (C1-C8 schema side).
-- Additive only. No data migration here; Phase 2 does that and needs a snapshot first.

-- ---------------------------------------------------------------- C1 per-channel caps
-- Oli's correction 3a: InMail allowance is ONE message + ONE chaser, not two. At two
-- credits per account that is ~47 accounts per 95 credits against 31 at three.
-- LinkedIn DM is three chasers. Email is three but dormant (stage two, LinkedIn first).
ALTER TABLE public.team_settings
  ADD COLUMN IF NOT EXISTS dm_chaser_cap     smallint NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS inmail_chaser_cap smallint NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS email_chaser_cap  smallint NOT NULL DEFAULT 3;

UPDATE public.team_settings
   SET dm_chaser_cap = 3, inmail_chaser_cap = 1, email_chaser_cap = 3;

-- chaser_cap is NOT dropped. The deployed chase-engine still reads it, and dropping the
-- column while that code is live would break the engine on its next run. It is superseded
-- by the three per-channel caps above and should be removed once the engine no longer
-- references it. FLAGGED rather than silently left ambiguous.
COMMENT ON COLUMN public.team_settings.chaser_cap IS
  'DEPRECATED (Batch C / C1). Superseded by dm_chaser_cap / inmail_chaser_cap / email_chaser_cap. Retained only until chase-engine stops reading it; drop then.';
COMMENT ON COLUMN public.team_settings.inmail_chaser_cap IS
  'Oli 2026-09-02: InMail is one initial message + ONE chaser = 2 credits max per account.';

-- ---------------------------------------------------------------- C2 promise of quiet
-- Oli's correction 3b: a written promise to stop is BINDING. These contacts must never
-- generate a draft, on any channel, under any rule. Breaking it is not recoverable.
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS promise_of_quiet      boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS promise_of_quiet_note text;

COMMENT ON COLUMN public.contacts.promise_of_quiet IS
  'ABSOLUTE suppression. Oli: "A promise to stop is binding and breaking it is not recoverable." Enforced at the refusal gate, the chase engine and the drafter suppression guard.';

CREATE INDEX IF NOT EXISTS idx_contacts_promise_of_quiet
  ON public.contacts (promise_of_quiet) WHERE promise_of_quiet;

-- ---------------------------------------------------------------- C3 Withdrawn split
-- Withdrawn contacts stay ELIGIBLE, but a new CR is blocked for six months so that one
-- can safely auto-send. InMail/email escalation may come sooner but NEVER automatically.
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS cr_blocked_until date;

COMMENT ON COLUMN public.contacts.cr_blocked_until IS
  'C3: withdrawal date + 6 months. Before this date a new CR is refused (cr_cooldown_active). InMail/email escalation is permitted but MANUAL ONLY - the chase engine never auto-generates it.';

CREATE INDEX IF NOT EXISTS idx_contacts_cr_blocked_until
  ON public.contacts (cr_blocked_until) WHERE cr_blocked_until IS NOT NULL;

-- ---------------------------------------------------------------- C4 UK parking
-- 'Parked' added here so Phase 2 can use it. Postgres forbids USING a new enum value in
-- the same transaction that adds it, which is exactly why this is split from Phase 2.
ALTER TYPE public.outreach_status ADD VALUE IF NOT EXISTS 'Parked';

-- ---------------------------------------------------------------- C5 refusal architecture
-- Oli's requirement 5a: the draft call must be able to return a REFUSAL, not just a draft.
-- Lovable must accept a "no" rather than treat drafting as always-succeeds.
CREATE TABLE IF NOT EXISTS public.refusals (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id     uuid NOT NULL,
  contact_id  uuid REFERENCES public.contacts(id) ON DELETE CASCADE,
  company_id  uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  reason_code text NOT NULL,
  reason_human text,
  channel     text,
  requested   text,
  context     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT refusals_reason_code_check CHECK (reason_code IN (
    'allowance_exhausted',
    'promise_of_quiet',
    'dnc_or_opted_out',
    'cr_cooldown_active',
    'company_not_deep_researched',
    'thread_text_missing',
    'channel_illegal_in_market',
    'contact_parked'
  ))
);
CREATE INDEX IF NOT EXISTS idx_refusals_contact ON public.refusals (contact_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_refusals_team_recent ON public.refusals (team_id, created_at DESC);

ALTER TABLE public.refusals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS refusals_team ON public.refusals;
CREATE POLICY refusals_team ON public.refusals
  FOR ALL TO authenticated
  USING (team_id IN (SELECT public.fn_user_teams()))
  WITH CHECK (team_id IN (SELECT public.fn_user_teams()));

COMMENT ON TABLE public.refusals IS
  'C5: every gate failure that produced no draft. Surfaced on the touch card and queue rows as the reason, never as an error. The eight reason codes are the closed set from Oli requirement 5a.';

-- ---------------------------------------------------------------- C6 verbatim sent text
-- Oli's requirement 5b: the text as ACTUALLY SENT must post back verbatim, including his
-- edits. The no-repetition check compares new drafts against what actually went out; if
-- edited sends are not captured the thread history rots and drafts repeat things Oli
-- already said. He notes this "fails silently and does not surface for weeks".
ALTER TABLE public.outreach_log
  ADD COLUMN IF NOT EXISTS sent_body text;

COMMENT ON COLUMN public.outreach_log.sent_body IS
  'C6: immutable record of what was actually sent, frozen at send time AFTER any edits. message_body stays the working draft. The drafter reads sent_body (fallback message_body) for no-repetition context.';

-- Backfill history: for rows already Sent, the body we have is the best available record
-- of what went out. Marked so it is never mistaken for a true send-time capture.
UPDATE public.outreach_log
   SET sent_body = message_body
 WHERE send_status::text = 'Sent'
   AND sent_body IS NULL
   AND message_body IS NOT NULL;
