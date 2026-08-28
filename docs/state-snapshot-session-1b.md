# State snapshot — session 1b (finish what session 1 parked)

Entry HEAD `a01bfbe`, clean. 17:43 London, clear of the 12:03 and 13:00 watchers.
`TEST_MODE=false`, live sends armed — **nothing in the send pipeline was touched.**

## Counts — unchanged

companies **355** · contacts **261** · outreach_log **217** · pending_review **74**

One test contact (P961) and its three drafts were created for the T1b sign-off tests and
deleted immediately after. Oli's auth metadata was temporarily stripped as part of that test
and restored in the same sequence.

## What shipped

| Task | State | Evidence |
|---|---|---|
| T0 Lovable batch | ✅ landed + deployed | commit `7b6c39aa` is `latest_commit_sha` in production |
| T3b insight `note` | ✅ done + verified | EF v12; stored jsonb read back |
| T1b sender hardening | ✅ done + verified | EF v22; 3 live drafts inc. a regression case |
| T5 Ask bar — Edge Function | ✅ done + verified | new EF v1; 6 queries + auth negative |
| T5 Ask bar — UI | ⏳ building | Lovable `umsg_01m14n8ffwfc5vh2w2nhfvhq53` |
| T6 magic link | ✅ verified | login page renders unauthenticated |
| T2 / T3-UI / T4 | ⚠️ code-verified, **not** visually verified | see below |

## The sticky column: actual root cause, third attempt

Not z-index, not an overflow ancestor. **tailwind-merge was silently dropping `sticky`**
because the same className carried `relative`, and it treats them as one position group -
last one wins. The column had no sticky positioning at all, which is exactly what the
symptom said (names vanishing entirely, other columns' text showing through).

Verified in source at the deployed commit: body cell is `sticky left-0 z-[3] border-r
bg-background` with no `relative`; header `z-[4]`, corner cell `z-[5]`; `bg-background` is a
theme token so it holds in both themes; and the `overflow-auto` scroll container wraps the
`<table>` directly. The `before:`/`after:` tint layers still work because a sticky element is
already a containing block - which is why removing `relative` was safe rather than a
regression.

## Verification that is NOT done, and why

Brad's browser session expired mid-session and the app is magic-link only. I did not request
a link or enter credentials - Brad is testing that flow himself. So **T2, T3-UI and T4 have no
screenshots.** What exists instead is source-level verification against the exact deployed
commit, plus Lovable's own build + typecheck. The remaining risk is visual only (does the
column actually stay put, does the note actually render) - the logic is confirmed.

**Brad: log in once and check three things.** /companies scrolled fully right; Today's
pending-drafts number equals Outreach Pending Review; the note under Yesterday's Work.

## Tier 2 flags

**1. The two "wrong" numbers were both meaningful.** They are now gone, per the canon ruling,
but they were not nonsense:

- Today's **64** was 74 minus the 10 pending drafts whose contact or company is archived.
- Automation Health's **8** was 74 minus the 66 rows flagged `migrated_legacy`.

**2. Canon 74 is 89% backfilled.** 66 of the 74 are `migrated_legacy`. "74 drafts awaiting
review" therefore overstates genuinely new work by roughly nine times. The canon is what was
asked for and the three surfaces now agree, but the headline number is not what a reader will
assume it means. Worth either a legacy-excluding secondary figure or a label.

**3. Today's pending list now shows 10 stale tasks.** Removing the archived filter to hit
canon also removed it from the *list*, so Today now surfaces drafts for soft-deleted contacts
and archived companies. Counts matching was the requirement; this is the side effect.

**4. `account_owner` vs `owner_user_id` is unresolved and now blocks a feature.** The ruling
is that `owner_user_id` is canon. But all 355 companies have the same `owner_user_id` (Oli),
while `account_owner` still carries the real variety (Oliver Müller 342, Phil 8, Mark 2) and
is what the Companies table's Owner column actually renders. The Ask bar's owner filter
therefore targets `account_owner`, because filtering must match what the user can see. This
should switch to `owner_user_id` once a backfill migration copies the distinction across -
no data migration was in scope this session.

**5. `insurance_offered` is free text, not Yes/No.** It holds paragraphs of research prose,
so equality filtering can never match. It is in `PRIMARY_FILTER_KEYS` as a filter chip
regardless, which means that chip is close to useless in the UI too. The Ask bar routes
insurance intent to the derived `__insurance_state__` facet instead.

**6. Numeric ranges are not expressible.** `chipsToServerFilters` only emits `op:"in"`; there
is no gte/lte. Revenue and headcount questions are returned as `unmatched` rather than
silently dropped. Supporting them needs a `FilterClause` op extension.

**7. AI-edit does not re-sign.** Lovable correctly established that the AI-edit path
(`supersedeAndCreateFn`) never calls an Edge Function - it is local text editing - so
`requesting_user` does not apply. Consequence: an edited draft keeps whatever sign-off the
original had. Fine today, worth knowing.

**8. Five Edge Functions still on the legacy secret.** `generate-daily-insight` is one of
them and is also still calling Anthropic directly rather than through the sentinel, so its
Sonnet spend is invisible to the budget gate. `MAKE_SHARED_SECRET` cannot be retired until
all five are cut over and the logs show zero `deprecated_secret_used`.

**9. Carried forward:** F-13 EA-doc prompt caching (~87% off the £0.0928 per-draft cost);
`connection_status` has no `'Not sent'` label (B9 uses `'Not connected'`); `archive_reason`
is text not an enum.
