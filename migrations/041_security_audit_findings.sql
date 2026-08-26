-- 041_security_audit_findings.sql
-- Summary rows for each read-only security audit run. Created during the 2026-08-26 audit,
-- which is otherwise read-only: this table was the single write that audit authorised.
-- One row per category (secrets/auth/rls/input/cost) per run_date.

CREATE TABLE IF NOT EXISTS public.security_audit_findings (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_date   date NOT NULL DEFAULT CURRENT_DATE,
  category   text NOT NULL,
  severity   text NOT NULL,
  count      int  NOT NULL,
  summary    text,
  created_at timestamptz NOT NULL DEFAULT now()
);
