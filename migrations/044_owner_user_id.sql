-- B1: per-record ownership for multi-user (Oli + Jack).
-- Additive and nullable. RLS stays TEAM-scoped for SELECT by design - the UI filters by
-- owner, ownership is not a security boundary here. No RLS policy is changed.
--
-- Note: companies already has an `account_owner` column of enum type account_owner
-- ('Oliver Müller','Phil','Mark'). That is a display/CRM label, not an auth identity, and is
-- left untouched. owner_user_id is the auth.users FK.

ALTER TABLE public.contacts  ADD COLUMN IF NOT EXISTS owner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS owner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_contacts_owner_user  ON public.contacts  (owner_user_id) WHERE owner_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_companies_owner_user ON public.companies (owner_user_id) WHERE owner_user_id IS NOT NULL;

UPDATE public.contacts  SET owner_user_id = '6d282957-f63b-49d6-a4de-5a9a947b4284' WHERE owner_user_id IS NULL;
UPDATE public.companies SET owner_user_id = '6d282957-f63b-49d6-a4de-5a9a947b4284' WHERE owner_user_id IS NULL;

COMMENT ON COLUMN public.contacts.owner_user_id  IS 'auth.users owner. UI filters by this; RLS remains team-scoped.';
COMMENT ON COLUMN public.companies.owner_user_id IS 'auth.users owner. UI filters by this; RLS remains team-scoped.';
