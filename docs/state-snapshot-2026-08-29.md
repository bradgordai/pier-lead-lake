# State snapshot — 2026-08-29 (session 1, outstanding fixes)

## Counts — unchanged, as required

companies **355** · contacts **261** · outreach_log **217** · pending_review **74**

All test rows created during verification were deleted.

## VERIFY

- git clean at `bd2ff17` on entry
- Jack Stevens exists: `dd9f7338-adcb-49b4-b9c3-dd43cf43f03c` — T1 unblocked
- 11:05 London at start, clear of the 12:03 watcher
- `TEST_MODE=false`, live sends armed. **Nothing in the send pipeline was touched.**

## T1 — per-user draft sign-off: ✅ EF DONE + VERIFIED, ⏳ UI in flight

`generate-draft-from-context` **platform v21**, commit `28cb1f5`.

Sender resolution: `body.requesting_user` → contact's `owner_user_id` → `"Oli"` last resort.
Every prompt path that named a person is parameterised (voice fallback, drafting directive,
TASK line, sign-off, final output instruction). TRIGGER_MAP intents moved to second person
since they are built before the sender resolves.

**Verified live in the message bodies, not just the response:**

| Call | Sender | Body signs |
|---|---|---|
| `requesting_user: "Jack Stevens"` | Jack | "Jack" |
| no `requesting_user`, Oli-owned contact | Oli | "Oli" |

**A real bug was caught and fixed mid-verification.** The owner-lookup path initially
produced sender **"oliver.muller"** — neither Oli nor Jack had a display name in
`auth.users`, so it fell through to the email local-part, and `firstNameOf` splits on
whitespace only. That path is live (the chained CR-accepted route sends no
`requesting_user`), so tonight's drafts would have been signed "oliver.muller".

Fixed by setting the missing metadata:

```
oliver.muller@pierinsurance.com  name="Oliver Müller"  first_name="Oliver"
jack.stevens@pierinsurance.com   name="Jack Stevens"   first_name="Jack"
```

**Follow-up worth doing (NOT done):** `firstNameOf` should also split on `. _ -` so an email
local-part degrades sensibly, and `resolveSender` should read `first_name` — the convention
already in use (Brad's user has `first_name`, no `name`). The data fix closes the live hole;
the code is still fragile for any future user created without metadata.

Also changed: historical touches in the thread context are attributed to their own `sent_by`
rather than the current requester, so Jack does not appear to have sent Oli's old messages.
New drafts record `sent_by` = resolved sender.

## T2 / T3 (UI) / T4 — ⏳ BUILDING, NOT VERIFIED

One Lovable batch covering: T1's UI wiring (pass logged-in display name as
`requesting_user` on every draft/regenerate/AI-edit call, plus the `owner_user_id` is canon
comment), T2 sticky Name column third attempt (with the overflow-ancestor diagnosis), T3's
card rendering, and T4 one canonical pending-drafts predicate.

**Not deployed, not verified.** Next session: check the edit landed, deploy, verify.

T4 canon given to Lovable: `outreach_log.draft_status = 'pending_review'`, currently **74**,
no `agent_produced` filter, no date window. For reference, agent-produced pending = 4 and
agent drafts in the last 24h = 1 — so Automation Health's "8" matches neither and needs
relabelling or switching to canon.

## T3 — ⚠️ HALF DONE, blocking itself

The **UI half** was sent to Lovable. The **Edge Function half was not done**:
`generate-daily-insight` does not yet emit the `note` field, so the card has nothing to
render. T3 is not complete until that prompt/output change ships. The card was instructed to
render nothing when the field is absent, so this is inert rather than broken.

## T5 — ⛔ NOT STARTED, deliberately

Ask bar / `parse-companies-query` on Haiku. Skipped on capacity grounds and flagged up front
rather than half-built: it needs a new Edge Function, its prompt spec, sentinel wiring, chip
UI and submit wiring. It remains a visible placeholder, which is honest.

## Tier 2 flags

1. **`firstNameOf` fragility** above — data patched, code not hardened.
2. **Two auth users still have no `name`** convention alignment: Brad's user has `first_name`
   only. Whatever the UI reads for display should be made consistent.
3. Yesterday's flags stand: `connection_status` has no `'Not sent'` label (B9 uses
   `'Not connected'`); `archive_reason` is text not an enum; `account_owner` still coexists
   with `owner_user_id` (now formally ruled non-canon).

## Still open from earlier

- Five Edge Functions on the legacy secret; `MAKE_SHARED_SECRET` cannot be retired until
  they are cut over and logs show zero `deprecated_secret_used`
- F-13 EA-doc prompt caching, ~87% off the £0.0928 per-draft cost
- Auth: Brad verifying Site URL / redirect allowlist and the magic link end-to-end
