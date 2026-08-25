# Bundle B — draft categorization: SHIPPED + VERIFIED LIVE

| Task | Result |
|---|---|
| T1 migration 038 | `outreach_type` + Chaser 1/2/3 + Follow up — applied, verified |
| T2 Outreach section grouping | Lovable `e3e6f558`, verified live |
| T3 Today action-queue split | Lovable `e3e6f558`, verified live |
| T4 generate-draft trigger map | platform **v13**, verified live |
| T5 end-to-end verify | passed, test rows removed |

## Corrections the spec needed

**T1 named the wrong type.** The spec says `ALTER TYPE touch_type ADD VALUE ...`. There is no
type called `touch_type` — that is the *column* on `outreach_log`; its *type* is
`outreach_type`. The spec's statement fails with `42704`. Migration 038 targets the real type.

Also left the pre-existing `Chase` and `Event follow-up` labels untouched rather than
repurposing them, accepting some vocabulary overlap so no existing row changes meaning.

**T2's section table had no row for Connection requests — 126 of the 197 pending-review rows,
the single largest group.** Following the spec verbatim would have dumped them into "Other",
which would then hold 184 of 197 rows and defeat the point of the change. Added a dedicated
"Connection requests" section at priority 8, leaving "Other" as a genuine remainder of 58.

**T4's directive fought its own trigger.** `FORWARD_DIRECTIVE` is appended last and is
explicitly labelled as overriding everything above it on output format — and it hardcoded
"You are producing ONE LinkedIn DM ... for someone who just accepted the connection." On an
InMail chaser that contradicted the new Intent line, and the directive would have won. It is
now a function of the mapped trigger. The empty-thread text had the same hardcoded story and
was fixed the same way.

## Verified section counts (Show legacy ON)

| Section | Count |
|---|---|
| First message after acceptance | 2 |
| Cold InMail opens | 3 |
| Introduction / referral | 8 |
| Connection requests | 126 |
| Other | 58 |
| **Sum** | **197** |

Matches "Showing 197 of 197 touches" exactly — nothing was dropped. Empty sections (Reply
awaiting response, InMail chaser 1/2/3) are not rendered. Section 1 expanded by default.
Deep link `?section=connection-request` selects Pending Review, expands that section and
collapses the rest.

Today shows a single "First messages needed" card, count **2**, previewing Hermann-Wilhelm
Wantia and Marco Stiemert, with a "Review 2 drafts" button. The other three cards are hidden
at zero. "Awaiting reply over 14 days" (26), "Active conversations" (6) and "Commitments this
week" (0) are unchanged below it.

## T4 live test (synthetic contact P901, deleted afterwards)

| Trigger | Result |
|---|---|
| `chaser_1` | created — `Chaser 1` / LinkedIn inMail, lint 100 |
| `chaser_1` again | **dedup_skipped** |
| `chaser_2` | **created — not blocked by chaser_1** (the failure mode the spec called out) |
| `follow_up` | created — `Follow up` / LinkedIn DM, written as a continuation |
| `cr_accepted` | created — `Initial message` / LinkedIn DM, written as a fresh opener |

Pre-lint flagged a banned phrase ("quick one") in the chaser, score 95 — linter working.
State restored to 259 contacts / 206 outreach_log / 2 agent drafts.

## Note for later

The Pending Review tab counts 197, but 187 of those are `migrated_legacy = true` with
`send_status = 'Sent'` — already-sent historical touches whose `draft_status` is just the
column default. Only 9 rows are genuinely unsent. The "Show legacy" toggle already hides
them, so nothing was changed here, but the tab's headline number overstates real work by
roughly 20x whenever that toggle is on.
