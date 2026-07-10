-- Migration 017: auto-add new auth users to the Pier team
--
-- Problem this solves: every team-scoped RLS policy gates on
--   team_id IN (SELECT team_id FROM fn_user_teams())
-- and fn_user_teams() reads public.team_members. With no membership rows, a
-- freshly signed-up user sees nothing and cannot insert anything. Registration
-- is invite-only (only Brad can invite Pier staff), so any new auth.users row is
-- legitimately a Pier team member. We therefore auto-enrol every new user into
-- the Pier team on signup. No email-domain allowlist needed for V1.
--
-- Security: the trigger function is SECURITY DEFINER (it must bypass RLS to write
-- team_members and read teams during signup, before the user has any membership)
-- with a pinned search_path. EXECUTE is revoked from every client role
-- (PUBLIC, anon, authenticated, service_role), leaving only the postgres owner.
-- Unlike fn_user_teams (migration 015), this function is NOT called inside RLS
-- policies, so it never needs an authenticated grant — Postgres does not check
-- EXECUTE on a trigger function when the trigger fires. Owner-only keeps it off
-- the API surface entirely and avoids the "Signed-In Users Can Execute SECURITY
-- DEFINER Function" advisor lint (0029).

CREATE OR REPLACE FUNCTION public.fn_auto_add_to_pier_team()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  pier_team_id UUID;
BEGIN
  SELECT id INTO pier_team_id FROM public.teams WHERE slug = 'pier' LIMIT 1;
  IF pier_team_id IS NOT NULL THEN
    INSERT INTO public.team_members (team_id, user_id, role)
    VALUES (pier_team_id, NEW.id, 'member')
    ON CONFLICT (team_id, user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_auto_add_to_pier_team() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_auto_add_to_pier_team() FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_auto_add_to_pier_team() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_auto_add_to_pier_team() FROM service_role;

CREATE TRIGGER tg_auth_user_added_to_pier_team
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_auto_add_to_pier_team();
