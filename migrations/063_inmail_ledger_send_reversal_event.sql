-- 063: 046's check list lacked the reversal event 062 writes when a dispatched InMail never went out.
ALTER TABLE public.inmail_credit_ledger DROP CONSTRAINT IF EXISTS inmail_credit_ledger_event_type_check;
ALTER TABLE public.inmail_credit_ledger ADD CONSTRAINT inmail_credit_ledger_event_type_check
  CHECK (event_type IN ('monthly_grant','send','accept_refund','send_reversal','manual_adjust'));
