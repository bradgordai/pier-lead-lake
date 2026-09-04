# Pier Lead Lake, security posture summary (for Paul's pack)

Prepared 2026-09-04 by Claude Code for Brad. Classification C2, commercial in confidence.

## Auth model
- Supabase Auth, email provider. Three users: bradleyg@naileditai.com (admin),
  oliver.muller@pierinsurance.com (member), jack.stevens@pierinsurance.com (member). All three
  have a password on file; email verified. Invite-only: `fn_auto_add_to_pier_team` adds a new
  auth user to the single Pier team, and there is no self-signup page.
- Primary sign-in is now email + password (Lovable A1 rework, 2026-09-04). Magic link stays as a
  fallback. Password recovery doubles as first login. Minimum length 12 is enforced client-side;
  the server-side minimum and leaked-password protection are Supabase dashboard settings
  (Auth > Providers > Email) that need to be set there, the API cannot toggle them.
- App server functions run under the signed-in user's JWT (`requireSupabaseAuth` middleware), so
  RLS is the enforcement layer, not the UI.

## Row Level Security
- Every application table has RLS enabled and a team-scoped policy (`team_id IN (SELECT
  fn_user_teams())`). `fn_user_teams()` is SECURITY DEFINER by design: it returns only the
  caller's own team ids and must remain executable by `authenticated` because every policy calls
  it. Reviewed and documented in migration 061.
- Reference tables without a team column (`eurefas_members`, `pier_pipeline`) were readable by any
  signed-in user of any project (`auth.uid() IS NOT NULL`). Fixed in 061: readers must belong to a
  team.
- Staging and audit tables (`staging_wb_*`, `migration_audit`) have RLS enabled with no policy:
  service-role only, deliberately. The advisor reports them as INFO.
- Visibility model (Oli's ruling): data tabs show all leads to every user; work queues filter to
  the owner for members, admins get an owner toggle. Enforced in the app's shared scope helper;
  the database exposes `fn_task_scope()` and `team_settings.members_see_all_leads`.

## Secrets and callers
- Edge Functions authenticate callers with two scoped secrets: `INBOUND_WEBHOOK_SECRET` (Make
  and PhantomBuster webhooks) and `INTERNAL_APP_SECRET` (Lovable server functions, pg_cron,
  function-to-function). The legacy `MAKE_SHARED_SECRET` is still accepted during the
  transition; the Edge Function logs show ZERO `deprecated_secret_used` events in the last 24
  hours (query 2026-09-04 16:30 UTC), so every caller is on the scoped secrets and the legacy
  secret can be deleted (Supabase dashboard > Edge Functions > Secrets; not possible via the
  API used here). After deleting, re-run one Make scenario and one Send now to confirm.
- Known weakness: the internal secret is hard-coded in the Lovable server functions
  (`outreach.functions.ts`, `drafts.functions.ts`) and appears in the two pg_cron job bodies.
  It is server-side only (never shipped to the browser) but should move to an env var / Vault
  once Lovable exposes secrets to server functions. Tracked.
- LinkedIn session cookie lives only inside the PhantomBuster phantom arguments; the send
  function reads and round-trips it without logging. Cookie and PhantomBuster API key rotation
  is scheduled with Oli after the test days.
- Anthropic, PhantomBuster and service-role keys are Supabase secrets, never in the repo.

## Cost controls
- Every model call goes through `callAnthropicWithSentinel`: per-call cost logged to
  `api_call_log`, fail-closed daily budget (`ANTHROPIC_DAILY_BUDGET_GBP`, default GBP 10),
  Sonnet only, thinking disabled. Prompt caching on the EA document block (57k tokens) keeps a
  warm draft at about GBP 0.015. Migration day spend: GBP 1.83.
- Send path caps: 15 DMs a day, 120 CRs a week, InMail ledger (129 credits). TEST_MODE defaults
  to on; live sends require the explicit `TEST_MODE=false`.

## Backups
- Supabase daily physical backups (latest 2026-09-04 ~06:35 UTC, confirmed by Brad). Every
  schema change is a numbered migration in `migrations/` (001 to 061) and replayable. Migration
  decisions for the workbook import are in `migration_audit` (run `wb-frozen-2026-09-02`).

## Advisor status (Supabase security linter, 2026-09-04 21:00 BST)
| Finding | 2 Sep | Now |
|---|---|---|
| eurefas_members / pier_pipeline readable by any signed-in user (CRITICAL) | open | fixed (061) |
| SECURITY DEFINER callable by authenticated | fn_capture_dq_snapshot, fn_user_teams | fn_capture_dq_snapshot revoked; fn_user_teams kept by design and documented |
| Function search_path mutable | fn_evaluate_gates, fn_chase_candidates, fn_chase_exhausted (+ migration helpers) | all set; helpers dropped |
| RLS enabled, no policy | migration_audit, staging tables | unchanged, intentional (service-role only) |
| Extensions in public schema | pg_trgm, vector, pg_net | unchanged; moving pg_net would break the cron callers, accepted |
| npm dependency advisories (11) | open | audit requested from the Lovable build (see A3 section of the run report) |

## Outstanding
1. Delete `MAKE_SHARED_SECRET` in the dashboard (logs clean for 24h+).
2. Set password minimum 12 and leaked-password protection in Auth settings.
3. Rotate the LinkedIn cookie and the PhantomBuster key after Oli's test days.
4. Move the internal secret out of the Lovable source once server-side env vars are available.
5. Delete the temporary `migration-ingest` and `migration-classify` functions.
