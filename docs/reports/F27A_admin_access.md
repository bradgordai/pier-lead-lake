# F27A — Admin write access for Cowork and Claude Code

Status: **DONE.** Migration 178 applied 9 Oct 2026 at 19:17:47 UTC (ledger `20261009191747 178_f27a_admin_write_access`), in one apply_migration call. The pre-flight below stopped for Brad at Step 1. He approved the predicate and asked for fn_cr_queue_populate to be left alone; the APPLIED section follows the pre-flight.
Pre-flight measured 9 Oct 2026, about 18:40 UTC, read-only.

## Re-measure vs the brief
| Figure | Brief | Measured |
|---|---|---|
| last applied migration | 20261005140447 | 20261005140447 |
| highest migration file / next | 177 / 178 | 177 / 178 |
| contacts | 1,085 | 1,085 |
| connection_status 'Request sent' | 273 | 273 (enum has both 'Request sent' and 'Withdrawn') |
| cr_queue rows / queued | 206 / 204 | 206 / 204 |
| cr_dispatch_enabled | false | false |
| audit_log rows / 'mcp_admin' rows | 21,844 / 0 | 21,844 / 0 |
| teams / members | 1 / 3 | 1 / 3 |
| security lint | 0 errors, 14 warn, 11 info; search_path_mutable 1; auth SD executable 10 | identical |
| send_queue | draining, done, failed in use | draining 1, failed 19, done 65; row 93 draining since 7 Oct 12:51, launched_at null |

**Documentation drift:** the current CLAUDE.md does not mention the security lint at all. The "lint is 0" claim must live in another document; I did not find it in CLAUDE.md. My F26 report stated "anon lint 5 → 0", which was the anon-only lint, and that is still true.

## STEP 1 — the service-role test (verbatim result)
`select auth.uid(), auth.role(), current_user, session_user, current_setting('request.jwt.claims', true);`
→ uid **null**, role **null**, current_user **postgres**, session_user **postgres**, claims **null**.
Extra: `current_setting('role') = none`, member of service_role = true, rolsuper = false.

**Finding:** the Supabase MCP does **not** connect as `service_role`. It connects directly as **`postgres`**, with no JWT at all. A predicate keyed on `auth.role() = 'service_role'` would therefore never match an MCP call, and one keyed on a null uid would also match anon, as the brief warned.

**A positive, specific test is available:** `session_user = 'postgres'`.
- Every PostgREST request (anon, authenticated, and service_role through the API) logs in as `authenticator` and only switches `current_user`. So `session_user` is `authenticator` for all of them.
- Inside a SECURITY DEFINER function `current_user` becomes the owner (postgres) for everyone, so `current_user` is useless. `session_user` is not changed by SECURITY DEFINER.
- Only a direct database login as `postgres` (the MCP, the SQL editor, migrations) has `session_user = 'postgres'`.

**Proposed predicate:** `session_user = 'postgres' OR auth.role() = 'service_role'`. The first branch covers Cowork / Claude Code through the MCP. The second covers an Edge Function calling with the service key. Both are positive tests; neither keys on a null uid.

## Guard search (all public functions, prokind = 'f')
Functions with `auth.uid() is null` guards: **exactly four**. fn_set_inmail_credits, fn_set_auto_score_new_companies, fn_set_cr_dispatch_enabled, fn_mark_cr_withdrawn. No sixth.
**Finding: fn_cr_queue_populate does not refuse from the MCP.** Its guard is `if auth.uid() is not null and p_team_id not in (…)`, so a null uid skips the check. I called it from the MCP in F26 (dry run and the real populate of 206) without error. It needs no new access path. Opening it would only add a required reason and an audit row.

## Captured attributes (BEFORE, all four plus the fifth for reference)
| function | owner | SECURITY DEFINER | proconfig | proacl |
|---|---|---|---|---|
| fn_mark_cr_withdrawn(uuid, uuid[]) | postgres | true | search_path=public, pg_temp | postgres, authenticated, service_role |
| fn_set_auto_score_new_companies(uuid, boolean) | postgres | true | search_path=public, pg_temp | postgres, authenticated, service_role |
| fn_set_inmail_credits(uuid, integer, integer) | postgres | true | search_path=public, pg_temp | postgres, authenticated, service_role |
| fn_cr_queue_populate(uuid, boolean, integer) | postgres | true | search_path=public, pg_temp | postgres, service_role |
| fn_set_cr_dispatch_enabled(uuid, boolean) — NOT TOUCHED | postgres | true | search_path=public, pg_temp | postgres, authenticated, service_role |

anon has EXECUTE on none of them today. Default ACL for functions in `public` (owners postgres and supabase_admin) grants `anon=X`, so Trap A is real for any recreate.

## STEP 4 — Lovable call sites (read via the Lovable MCP at HEAD efd865a; read only)
| function | file | call | named args |
|---|---|---|---|
| fn_set_inmail_credits | src/lib/queries/inmailCredits.functions.ts | `rpc("fn_set_inmail_credits", { p_team, p_balance })` | yes, omits p_low_at |
| fn_set_auto_score_new_companies | src/lib/queries/settings.functions.ts | `rpc("fn_set_auto_score_new_companies", { p_team, p_on })` | yes |
| fn_mark_cr_withdrawn | src/lib/queries/crReconciliation.functions.ts | `rpc("fn_mark_cr_withdrawn", { p_team, p_contact_ids })` | yes |
| fn_cr_queue_populate | not called by the app (revoked from authenticated in 169) | — | — |
| fn_set_cr_dispatch_enabled (reference) | src/lib/queries/crQueue.functions.ts | `rpc(…, { p_team, p_on })` | yes |
No positional call sites. Adding `p_reason text default null` keeps every existing call valid.

## STEP 7 — flags (not fixed)
- **fn_release_send_queue** updates only `status in ('launched','stuck')`. Measured statuses in use: draining 1, done 65, failed 19 (none launched or stuck). **Confirmed: the release tool cannot fire on any real row**, including send_queue **id 93**: status draining, created 7 Oct 12:51, not_before 13:13, launched_at null, agent 5691059901018698 (DM sender), outreach_log 45e68317…. Not touched.
- **fn_improvement_log_can_edit(p_team_id)** is a SQL function returning `exists(… tm.user_id = auth.uid() …)`. From the MCP it returns **false** quietly instead of raising. Confirmed, not changed.
- **audit_log on screen: YES.** `src/lib/queries/reconciliation.functions.ts` → `auditLogFn` reads `audit_log` (50 per page, cursor paging, no total count) for the **Reconciliation › Actions Log** tab. A row with `actor_user_id` null is labelled **"System"**, so an `mcp_admin` row would also show as "System" unless the screen learns to read `source`.

## Decisions (answered by Brad, 9 Oct)
1. Approve the predicate `session_user = 'postgres' OR auth.role() = 'service_role'` instead of a pure service_role test, since the MCP is not service_role.
2. fn_cr_queue_populate already works from the MCP. Either (a) leave it untouched (my recommendation: no DROP needed, less risk), or (b) still recreate it to require a reason and write an audit row.
3. Then 178 is three functions (or four) via DROP + CREATE + REVOKE + GRANT + `NOTIFY pgrst` in one apply, with every Step 2–6 proof as specified.

1. → **Approved:** `session_user = 'postgres' OR auth.role() = 'service_role'`. Record which half matched in the audit row.
2. → **fn_cr_queue_populate left exactly as it is.** The batch is three functions.
3. → The "System" label on Actions Log is a defect for the closing table, not fixed here.
4. → The "lint is 0" line was Brad's error; ignored.

---

# APPLIED — migration 178

## Pre-checks
- **pg_cron (session_user = postgres) callers:** for all 11 jobs, matched with `command ilike` booleans only (command text never selected). **No job calls fn_mark_cr_withdrawn, fn_set_auto_score_new_companies or fn_set_inmail_credits.** No other public function calls them either.
- **Dependents:** none in pg_depend, so a plain DROP is safe (no CASCADE used). audit_log has no CHECK on source or action; actor_user_id is an FK to auth.users (null allowed).

## The change (all in one transaction)
- `DROP` the three old signatures, then `CREATE` with `p_reason text default null` appended. Bodies are based on the pg_get_functiondef capture.
- **Trap C, diff:** every original line is preserved. The original guard survives verbatim as the `elsif` of the new admin branch. The only additions are the parameter, the admin branch (predicate, a non-blank reason or RAISE, team-exists check), the before-value capture and the audit insert. The diff was run against the captured text with `diff -i -w`.
- **Trap B:** `ALTER FUNCTION … OWNER TO postgres`, `SECURITY DEFINER` and `SET search_path TO 'public','pg_temp'` restated.
- **Trap A:** `REVOKE ALL … FROM PUBLIC, anon`, then `GRANT EXECUTE … TO postgres, authenticated, service_role`.
- **Trap E:** the migration ends with `NOTIFY pgrst, 'reload schema';`. Confirmed effective: PostgREST resolved the new 3- and 4-argument signatures on the anon probe below.
- **Trap D:** a single apply. There was no failure, so there was no partial state.

## Behaviour
- **Signed-in caller (PostgREST, session_user = authenticator):** the original guard runs; p_reason is ignored. The Lovable call sites (named arguments, no p_reason) stay valid.
- **Admin caller:** `session_user = 'postgres'` (MCP / SQL editor), recorded as matched `session_user`; or `auth.role() = 'service_role'` (Edge Function with the service key), recorded as `service_role`. p_reason must be non-blank and p_team must exist. One `audit_log` row is written: source `mcp_admin`, actor_user_id null, `summary` = the reason, real `before_value` / `after_value`, and `after_value.caller = {matched, session_user, auth_role}`.
- fn_mark_cr_withdrawn keeps the 50-contact cap.

## Verification (proof)
1. **Rolled-back admin withdraw on P756 Oscar Visser** (Request sent):
   - Return value: **1**.
   - Before: Request sent; blocked null; min age 30; label_at 6 Oct 16:46; source sent_request_extractor.
   - After: Withdrawn; blocked **2027-04-07**; pending fields cleared; source reconciliation_manual. connection_status_changes 0 → 1.
   - Audit row: `action admin_mark_cr_withdrawn`, `source mcp_admin`, `actor_user_id null`, `summary "F27A verification on P756 (rolled back)"`, `before_value.contacts[0].connection_status "Request sent"`, `after_value.withdrawn 1`, `after_value.caller {"matched":"session_user","session_user":"postgres","auth_role":null}`.
   - **After rollback:** P756 still Request sent, blocked null, source sent_request_extractor; 0 status-change rows; 0 mcp_admin rows.
   - Side note: P960 Ralf Lenz (my first pick) was already Withdrawn. Someone marked him on the Reconciliation tab on 6 Oct, which closes the F26 open item.
2. **Signed-in member call: NOT EXECUTED.** It cannot be done from a build session. There is no user JWT, and in a direct database session `session_user` stays `postgres` even after `SET ROLE authenticated`, so any simulation takes the admin branch. What is proven instead: the member guard is byte-identical (diff, plus a regex check in the test), and the call sites still match the signatures (named arguments, optional p_reason).
3. **Admin call with no reason RAISES:** `admin call (session_user) needs a non-blank p_reason`. A reason of three spaces raises the same.
4. **anon has no EXECUTE:** `has_function_privilege('anon', …)` is false for all three, the old signatures are gone, and a **live PostgREST call with the anon key** returned **401 `42501 permission denied`** for all three (net.http_post requests 352–354).
5. **Security linter after:** 0 errors; **function_search_path_mutable 1** (unchanged); **authenticated_security_definer_function_executable 10** (unchanged; fn_cr_queue_populate still not granted to authenticated); extension_in_public 3; info 11; no anon lint. **Not worsened.**
6. **tests/f27a_admin_path_test.sql:** run and returned `TEST PASS: F27A admin path (ACL, owner, search_path, guard, anon, reason, audit; rolled back)`.
   - It asserts the exact ACL, no anon, owner, SECURITY DEFINER and search_path for all three; the member guard is present; no old signature remains; fn_cr_queue_populate is not widened; no-reason and blank-reason raise; a SET ROLE authenticated call with a non-member JWT and no reason raises; and a reasoned call writes exactly one mcp_admin row with the caller recorded.
   - It can fail: its first run did fail, on my own test bug. The fake JWT leaked into a later audit trigger and is now cleared.
   - The header documents the session_user limitation.
7. **Types regenerated** (generate_typescript_types): `fn_mark_cr_withdrawn {p_contact_ids, p_reason?, p_team}`, `fn_set_auto_score_new_companies {p_on, p_reason?, p_team}`, `fn_set_inmail_credits {p_balance, p_low_at?, p_reason?, p_team}`. The generated file was not hand-edited. Lovable syncs its own copy (observed in F26); no Lovable message was sent (read-only, per the brief).

**Consent check, exact shape** (`fn_evaluate_gates(team, c.id, 'linkedin_dm', 'Initial message')`, LEFT JOIN LATERAL, all 1,085 contacts), before → after:
| reason_code | before | after |
|---|---|---|
| (none) | 811 | 811 |
| group_sibling_engaged | 74 | 74 |
| contact_parked | 70 | 70 |
| dnc_or_opted_out | 68 | 68 |
| pending_ruling | 41 | 41 |
| promise_of_quiet | 21 | 21 |

**Identical.** Finding: `'linkedin_dm'` and `'Initial message'` are not the gate's literals (the gate compares `p_channel = 'Email'` and `p_requested IN ('initial_message','chaser','reply','connection_request')`). With this shape the research gate never runs, so `company_not_deep_researched` cannot appear. The comparison is still valid as a before/after control, because the migration touches neither contacts nor gates.

**Cron, 19:18–19:22 UTC (5 min after apply):** 15 runs (cr-dispatch, send-queue-drain, send-queue-housekeeping), **0 failures**. cr_dispatch_enabled is still **false**. Settings unchanged (auto_score false, InMail balance 138).

## Closing table
| function | new signature | ACL before → after | owner before → after | search_path before → after | service-role / admin call writes to audit_log | screen |
|---|---|---|---|---|---|---|
| fn_mark_cr_withdrawn | (p_team uuid, p_contact_ids uuid[], p_reason text default null) | postgres, authenticated, service_role → same; anon none → none | postgres → postgres | public, pg_temp → same | 1 row: admin_mark_cr_withdrawn, source mcp_admin, summary = reason, before/after contact states, requested_ids, caller | Reconciliation › Withdrawals due (member path, unchanged); admin rows on Reconciliation › Actions Log as **"System"** (defect) |
| fn_set_auto_score_new_companies | (p_team uuid, p_on boolean, p_reason text default null) | same → same; anon none | postgres → postgres | same | 1 row: admin_set_auto_score_new_companies, before/after auto_score_new_companies, caller | Settings (member path, unchanged); admin rows on Actions Log as **"System"** (defect) |
| fn_set_inmail_credits | (p_team uuid, p_balance integer, p_low_at integer default null, p_reason text default null) | same → same; anon none | postgres → postgres | same | 1 row: admin_set_inmail_credits, before/after balance, low_at, updated_at, updated_by, caller | Today › InMail credits card (member path, unchanged); admin rows on Actions Log as **"System"** (defect) |
| fn_cr_queue_populate | **unchanged** (p_team_id uuid, p_dry_run boolean, p_max integer) | postgres, service_role → same | postgres → postgres | same | **none: writes cr_queue with no reason and no audit row** (gap for F27) | **none** (server-side only; the dispatcher calls it) — defect |
| fn_set_cr_dispatch_enabled | **not touched** | unchanged | unchanged | unchanged | n/a | Connection queue switch |

**Defects:**
1. Admin writes appear on Reconciliation › Actions Log as **"System"**. They must show who and why: the screen should read `source` and `summary`.
2. fn_cr_queue_populate writes cr_queue with no reason and no audit, and has no screen (F27).
3. The Actions Log list has no total count (cursor paging only), against the CLAUDE.md §6 pagination rule.

## STEP 7 flags (unchanged, not fixed)
- fn_release_send_queue cannot release any real row (statuses in use: draining 1, done 65, failed 19); send_queue row 93 remains draining. Not touched.
- fn_improvement_log_can_edit quietly returns false from the MCP. Not changed.
- New: P756 and the other due contacts show `cr_pending_label_at` 6 Oct 16:46, so the extractor has run since F26. Request sent has risen 206 → 273, consistent with the extractor now feeding.
