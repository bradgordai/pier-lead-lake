# State snapshot — 2026-08-28, stopped after Workstream B

Stopped deliberately **after Workstream B, before Workstream C**, per the prompt's own rule:
do not start a task that cannot be finished. Context was consumed by the overnight queue,
the morning batch, and the ten UI fixes earlier in this same session.

## Counts (unchanged, as required)

| | Before | After |
|---|---|---|
| companies | 355 | **355** |
| contacts | 261 | **261** |
| outreach_log | 217 | **217** |

No data migration was performed. All schema changes were additive.

## A — magic link: BUILT, NOT PROVEN

- ✅ Auth callback route + expired-link recovery state + login hint — Lovable `b4b766e`, deployed
- ✅ `/contacts` now reads `search` and filter params from the URL (this was C4, done here since
  it was the same Lovable pass)
- ⛔ **A1 not verifiable by me.** The Supabase MCP exposes SQL, Edge Functions, logs and
  advisors — there is no tool for Auth URL configuration. **You must check**
  Authentication → URL Configuration: Site URL `https://pier-lead-lake.lovable.app`,
  allowlist including `https://pier-lead-lake.lovable.app/**`. This is the most likely root
  cause of Oli landing on the Lovable login page.
- ⛔ **A3 not runnable.** Generating a magic link needs `SUPABASE_SERVICE_ROLE_KEY`, which is
  not in my environment. Command is in the 2026-08-26 thread.

**A is therefore built but unproven. Verify A1 first — if the Site URL is wrong, the new
callback route still will not save it.**

## B — schema prep: 7 of 9 complete

| Task | Migration | Result |
|---|---|---|
| B1 columns | 044 | `owner_user_id` on both tables, 261 + 355 backfilled to Oli |
| B2 enums | 045 | +3 `outreach_status` labels; 3 other bullets were no-ops (see below) |
| B3 ledger | 046 | `inmail_credit_ledger`, seeded +95 for Oli |
| B4 markets | 047 | 9 countries, 4 cold-email-legal (NL/BE/FR/UK) |
| B5 staging | 048 | 3 staging tables + `migration_audit`, service-role only |
| B6 sourcing | 049 | `sourcing_queue` |
| B8 settings | 049 | `team_settings` seeded, `shared_capacity` |
| B9 gates | 050 | `fn_send_ready_contacts`, `fn_supply_unlocks` |
| **B1 Jack** | — | ⛔ **blocked** — user creation needs the admin API |
| **B1 sign-off** | — | ⛔ **not started** — `generate-draft-from-context` must accept `requesting_user` and sign with that first name. Deferred rather than half-done |
| B7 notes | — | ✅ reported below, no migration needed |

### B9 first run — the most actionable output of this session

```
fn_send_ready_contacts  = 1
fn_supply_unlocks       = { missing_sn_url: 24, untriaged_company: 0, missing_country: 1 }
```

**Only one contact is currently send-ready. 24 more are blocked on nothing but a missing
Sales Nav URL.** Triage is not the bottleneck; SN URLs are.

### B7 — notes format

- `contacts.background_notes` — plain `text`
- `companies.additional_notes` and `companies.usp_notes` — plain `text`

All nullable free text with no length cap, so date-stamped appends work directly:

```sql
UPDATE contacts SET background_notes =
  COALESCE(background_notes || E'\n', '') ||
  '[2026-05-07 from Outreach Log T006] Chase if no response by 7 May'
WHERE id = ...;
```

There is no structured notes table and no append trigger. If ordering or per-author
attribution matters later, this wants a real `notes` child table — flagging, not building.

## Tier 2 flags

1. **`connection_status='Not sent'` does not exist** (B9). Enum is Not connected / Request
   sent / Accepted / Already connected / Ignored / Withdrawn. Used `'Not connected'` as the
   only member meaning "no CR sent yet". If a new label was intended, B9 needs revisiting.
2. **`archive_reason` is `text`, not an enum**, on both tables. B2's "add 'out_of_scope' and
   'not_a_fit'" has nothing to alter — the values can just be written. Converting it to an
   enum would be destructive, so it was not done.
3. **`connection_status` already had 'Withdrawn' and 'Already connected'.** B2's first
   bullet was already satisfied.
4. **`outreach_status` carries four labels the spec omitted** — Not started, Ready, Do not
   contact, Left company. All in active use. Nothing renamed, per instruction.
5. **`companies.account_owner`** (enum: Oliver Müller / Phil / Mark) still exists alongside
   the new `owner_user_id`. Two notions of ownership now coexist; decide which the UI reads.

## C — not started

C1 sticky column, C2 backfilled-CRs note, C3 reconcile the three pending-draft numbers,
C5 Ask bar. **C4 was completed** as part of the A pass.

## Also still open from before

- Five Edge Functions on the legacy secret; `MAKE_SHARED_SECRET` cannot be retired until
  they are cut over and logs show zero `deprecated_secret_used`
- F-13 EA-doc prompt caching, ~87% off the £0.0928 per-draft cost
- **`TEST_MODE=false` — live sends armed.** Nothing in the send pipeline was touched today
