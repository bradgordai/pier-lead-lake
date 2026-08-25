-- 039_add_send_tracking_columns.sql
-- Send-Approved Flow, Task 1: tracking for the push of an approved draft out to
-- LinkedIn via PhantomBuster.
--
-- Verified 2026-08-26 that none of these three exist yet (sent_by and thread_id do),
-- so Task 1 is required rather than skippable.
--
--   phantom_run_id  the PhantomBuster container id for the launch, so a send can be
--                   traced back to its run and its output fetched later.
--   sent_at_actual  when the send actually completed, as distinct from touch_date
--                   (the logical date) and from send_status flipping to 'Sent'.
--   send_error      last failure reason; NULL on success. Kept as free text because
--                   it holds whatever PhantomBuster reports.
--
-- The partial index covers the only hot read: "what is approved and still waiting to
-- go out". send_status 'Ready' and 'Draft' are both included because approved drafts
-- currently sit at 'Draft' (3 rows today) and the send flow will move them to 'Ready'.

ALTER TABLE public.outreach_log
  ADD COLUMN IF NOT EXISTS phantom_run_id text,
  ADD COLUMN IF NOT EXISTS sent_at_actual timestamptz,
  ADD COLUMN IF NOT EXISTS send_error     text;

CREATE INDEX IF NOT EXISTS idx_outreach_log_pending_send
  ON public.outreach_log (draft_status, send_status)
  WHERE draft_status = 'approved' AND send_status IN ('Ready', 'Draft');

COMMENT ON COLUMN public.outreach_log.phantom_run_id IS
  'PhantomBuster container id for the launch that sent this touch.';
COMMENT ON COLUMN public.outreach_log.sent_at_actual IS
  'Timestamp the send actually completed (distinct from touch_date).';
COMMENT ON COLUMN public.outreach_log.send_error IS
  'Last send failure reason; NULL when the send succeeded.';
