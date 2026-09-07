-- 062: InMail credit ledger wiring (F1, applied 2026-09-07). Full text. One deduction per
-- dispatched InMail row, one refund per accepted contact whose CR route used InMail, one
-- reversal per failed dispatch. Idempotency is enforced by the unique index, not the callers.
CREATE UNIQUE INDEX IF NOT EXISTS uq_inmail_ledger_event_per_row
  ON public.inmail_credit_ledger (outreach_log_id, event_type)
  WHERE outreach_log_id IS NOT NULL AND event_type IN ('send','accept_refund','send_reversal');

CREATE OR REPLACE FUNCTION public.fn_ledger_inmail_send(p_outreach_log_id uuid, p_user_id uuid DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
DECLARE r record; v_bal int; v_user uuid; v_new int;
BEGIN
  SELECT o.id, o.team_id, o.channel::text AS channel, c.owner_user_id INTO r
    FROM public.outreach_log o LEFT JOIN public.contacts c ON c.id = o.contact_id WHERE o.id = p_outreach_log_id;
  IF NOT FOUND OR r.channel <> 'LinkedIn inMail' THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM public.inmail_credit_ledger l WHERE l.outreach_log_id = p_outreach_log_id AND l.event_type = 'send') THEN RETURN NULL; END IF;
  v_user := coalesce(p_user_id, r.owner_user_id, '6d282957-f63b-49d6-a4de-5a9a947b4284'::uuid);
  SELECT balance_after INTO v_bal FROM public.inmail_credit_ledger WHERE team_id = r.team_id ORDER BY created_at DESC LIMIT 1;
  v_new := coalesce(v_bal, 0) - 1;
  INSERT INTO public.inmail_credit_ledger (team_id, user_id, event_type, delta, balance_after, outreach_log_id, note)
  VALUES (r.team_id, v_user, 'send', -1, v_new, p_outreach_log_id, 'InMail dispatched via send-approved-draft');
  RETURN v_new;
END $$;

CREATE OR REPLACE FUNCTION public.fn_ledger_inmail_reverse(p_outreach_log_id uuid, p_reason text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
DECLARE s record; v_bal int; v_new int;
BEGIN
  SELECT * INTO s FROM public.inmail_credit_ledger WHERE outreach_log_id = p_outreach_log_id AND event_type = 'send';
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM public.inmail_credit_ledger WHERE outreach_log_id = p_outreach_log_id AND event_type = 'send_reversal') THEN RETURN NULL; END IF;
  SELECT balance_after INTO v_bal FROM public.inmail_credit_ledger WHERE team_id = s.team_id ORDER BY created_at DESC LIMIT 1;
  v_new := coalesce(v_bal, 0) + 1;
  INSERT INTO public.inmail_credit_ledger (team_id, user_id, event_type, delta, balance_after, outreach_log_id, note)
  VALUES (s.team_id, s.user_id, 'send_reversal', 1, v_new, p_outreach_log_id, coalesce('Dispatch did not complete: '||p_reason, 'Dispatch did not complete'));
  RETURN v_new;
END $$;

CREATE OR REPLACE FUNCTION public.fn_ledger_inmail_accept_refund(p_contact_id uuid, p_user_id uuid DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
DECLARE o record; v_bal int; v_new int; v_user uuid;
BEGIN
  SELECT ol.id, ol.team_id, c.owner_user_id INTO o
    FROM public.outreach_log ol JOIN public.contacts c ON c.id = ol.contact_id
   WHERE ol.contact_id = p_contact_id AND ol.channel::text = 'LinkedIn inMail' AND ol.send_status::text = 'Sent'
   ORDER BY ol.touch_date DESC, ol.created_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM public.inmail_credit_ledger l JOIN public.outreach_log x ON x.id = l.outreach_log_id
             WHERE x.contact_id = p_contact_id AND l.event_type = 'accept_refund') THEN RETURN NULL; END IF;
  v_user := coalesce(p_user_id, o.owner_user_id, '6d282957-f63b-49d6-a4de-5a9a947b4284'::uuid);
  SELECT balance_after INTO v_bal FROM public.inmail_credit_ledger WHERE team_id = o.team_id ORDER BY created_at DESC LIMIT 1;
  v_new := coalesce(v_bal, 0) + 1;
  INSERT INTO public.inmail_credit_ledger (team_id, user_id, event_type, delta, balance_after, outreach_log_id, note)
  VALUES (o.team_id, v_user, 'accept_refund', 1, v_new, o.id, 'LinkedIn refunded the InMail credit on acceptance');
  RETURN v_new;
END $$;

REVOKE EXECUTE ON FUNCTION public.fn_ledger_inmail_send(uuid, uuid), public.fn_ledger_inmail_reverse(uuid, text), public.fn_ledger_inmail_accept_refund(uuid, uuid) FROM anon, authenticated;
-- 063 widens the event_type check to include 'send_reversal'.
