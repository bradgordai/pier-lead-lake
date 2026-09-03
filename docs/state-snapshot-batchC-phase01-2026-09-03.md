# State snapshot — Batch C, end of Phase 0 + Phase 1 (schema)

2026-09-03 ~18:50 BST. HEAD `7f6f7f7`. **Phase 2 (the migration) has NOT run.**

## Phase 0 — quarantine: COMPLETE except the backup precondition

| Step | Result |
|---|---|
| Unschedule chase cron | ✅ `daily-chase-engine` unscheduled; 3 crons remain |
| Supersede pre-correction drafts | ✅ 25 → `superseded`, 0 left pending, 25 `migration_audit` rows |
| TEST_MODE / no sends | ✅ **0 sends today**; all 25 were still `Draft` before the update. TEST_MODE not read or written by me |
| Snapshot / PITR before Phase 2 | ⛔ **BLOCKED — see below** |

The 25 drafts were `Chaser 1` on **`LinkedIn inMail`** against accepted contacts — exactly
the credit-burning behaviour C1 corrects. Nothing was sent, so no credits were consumed.

## THE BLOCKER

Phase 0 step 4 requires a Supabase snapshot / PITR point before any Phase 2 write. **No tool
available to me can create or verify one** — the Supabase MCP exposes SQL, migrations, Edge
Functions, advisors and logs, but no backup or PITR API. `get_project` returns status and
Postgres version only.

Phase 2 is a large, largely irreversible write against LIVE production data (1067 companies,
665 contacts, 989 outreach rows, merged against live rows the watchers are still ingesting).
Running it without a restore point would be reckless, and the prompt itself makes the
snapshot a precondition. **Phase 2 is therefore not started, deliberately.**

Brad: confirm PITR is on (Supabase Dashboard → Database → Backups) or take a manual snapshot,
and say so. Phase 2 can then run as specified.

## Phase 1 — schema: DONE (migration 054). Code: NOT done.

| | Done |
|---|---|
| C1 | `dm_chaser_cap=3`, `inmail_chaser_cap=1`, `email_chaser_cap=3` set. `chaser_cap` retained + marked DEPRECATED (the deployed engine still reads it) |
| C2 | `promise_of_quiet`, `promise_of_quiet_note` + partial index |
| C3 | `cr_blocked_until` + partial index |
| C4 | `'Parked'` added to `outreach_status` |
| C5 | `refusals` table, 8 reason codes as a CHECK, RLS by team |
| C6 | `sent_body` + backfill (**112 of 193** — see finding) |
| C8 | InMail ledger re-seeded 95 → **129**, note "Oli confirmed 2 Sep" |

**Not built (code, not schema):** C1 engine/TRIGGER_MAP rework, C5 gates inside
`generate-draft-from-context` and the chase engine, C6 send-time freeze, C7 `ai-edit-draft`
EF, C8 profile-freshness chip source.

## Workbook truth (frozen file, header row 3, blank rows dropped)

| Sheet | True rows | Prompt estimate |
|---|---|---|
| Companies | **1067** | ~1066 |
| Contacts | **665** (with Contact ID) | ~665 |
| Outreach Log | **989** | ~989 |

Also: Pier Pipeline 67, EUREFAS Members 30, Competitor Intel 42, Market Intel 11.

## Reconciliation vs Oli's numbers

| Item | File | Oli | Verdict |
|---|---|---|---|
| Withdrawn | **232** | 244 | **delta 12** — file is authoritative per the prompt |
| Do Not Contact | **12** (11 `Yes` + 1 `TRUE`) | 12 | ✅ exact |
| Opted out | **1** | 1 | ✅ exact |
| Total excluded | **13** | 13 | ✅ exact |
| UK, live status | **54** | ~35 | **delta 19** — but exactly **35** are status `Contacted` |
| Promise of quiet | **17** regex candidates | 16 | **delta 1**, needs Haiku adjudication |

**UK:** the 54 breaks down as Contacted 35, Active 7, To contact 4, In conversation 4,
Needs review 3, Cooldown 1. Oli's 35 is almost certainly the `Contacted` subset. Not
force-fitted — C4 as written ("non-archived status") parks all 54, which would take 19
contacts out of Oli's queue that he may not expect. **Needs his ruling.**

**PoQ 17 candidates:** P022, P053, P058, P063, P081, P088, P134, P198, P216, P231, P252,
P385, P386, P539, P540, P570, P633. The three weakest are P134, P231, P570 (matched only
`exit sent`). The prompt's two named near-misses, **P101 and P398, did not match** — the
regex correctly excluded both.

**Connection Status mapping:** the workbook uses `Not sent` (166 rows); the live enum has
`Not connected`, not `Not sent`. Same issue flagged in migration 050. Phase 2 must map
`Not sent` → `Not connected`.

## Finding that changes the shape of the test day

Only **58 of 361 companies (16%) are `Deep research done`**; 247 `Light triage`, 58
`Untouched`. `company_not_deep_researched` refuses *message* drafts (blank CRs unaffected),
so the catch-up queue will return **far more refusals than drafts**. That is the gate working
as specified, but it sits against Oli's "happy with the full backlog". He should see the
split before the test day, not discover it in the queue.

Related: **81 of 193 `Sent` rows have no body at all** — the `thread_text_missing`
population, and why the C6 backfill covered only 112.

## Live DB counts (unchanged by Phase 1; watchers still ingesting)

361 companies / 275 contacts / 229 outreach_log / pending 85 (canon 75).
