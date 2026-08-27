-- B3: InMail credit ledger.
-- WIRING RULES (store only; not yet implemented):
--   monthly_grant +50/user on the 1st, balance hard-capped at 150
--   send          -1 on confirmed send (not on launch)
--   accept_refund +1 on CR accepted (LinkedIn refund rule)
--   manual_adjust corrections / reconciliation against the real LinkedIn balance
-- balance_after is stored not derived, so the ledger is auditable against LinkedIn's own
-- number at a point in time; nullable because a correction may precede a known running total.

CREATE TABLE IF NOT EXISTS public.inmail_credit_ledger (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id         uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type      text NOT NULL CHECK (event_type IN ('monthly_grant','send','accept_refund','manual_adjust')),
  delta           int  NOT NULL,
  balance_after   int,
  outreach_log_id uuid REFERENCES public.outreach_log(id) ON DELETE SET NULL,
  note            text,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inmail_ledger_team_created ON public.inmail_credit_ledger (team_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inmail_ledger_user_created ON public.inmail_credit_ledger (user_id, created_at DESC);

ALTER TABLE public.inmail_credit_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS inmail_credit_ledger_team_read ON public.inmail_credit_ledger;
CREATE POLICY inmail_credit_ledger_team_read ON public.inmail_credit_ledger
  FOR SELECT USING (team_id IN (SELECT fn_user_teams()));

INSERT INTO public.inmail_credit_ledger (team_id, user_id, event_type, delta, balance_after, note)
SELECT 'ef73c15e-4d6f-4159-bcfa-cc76b5ae4972', '6d282957-f63b-49d6-a4de-5a9a947b4284',
       'manual_adjust', 95, 95, 'Opening balance reconciled against LinkedIn 2026-08-28'
WHERE NOT EXISTS (SELECT 1 FROM public.inmail_credit_ledger
  WHERE user_id = '6d282957-f63b-49d6-a4de-5a9a947b4284' AND event_type = 'manual_adjust');

COMMENT ON TABLE public.inmail_credit_ledger IS
  'Append-only InMail credit ledger. send -1, accept_refund +1, monthly_grant +50 on the 1st, balance capped at 150.';
