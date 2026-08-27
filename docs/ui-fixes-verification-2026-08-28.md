# Post-UI-test fixes — verification, 2026-08-28

Lovable `abd99b0` "Applied six outreach fixes" + `2219ee0`, deployed to
pier-lead-lake.lovable.app. Backend fixes were `52ac049` (FIX 8/10) and `a83a65b` (FIX 6a).

**Verification was strictly read-only in Outreach.** `TEST_MODE=false` — live sends are
armed — so no Send now control was touched on any row, including test rows.

## Results

| Fix | Status | Evidence |
|---|---|---|
| 1 Contacts search | ✅ | "Stiemert" (surname only, the case that failed) returns Marco in row 1, "1 contacts, page 1 of 1". Default sort now newest-first: P295, P294, P293, P292, P291 at top |
| 2 Coverage widget | ✅ | Label now reads "**355 shown** of 355 total (2 archived)" — counts what is displayed rather than a separate query |
| 3 Drawer Contacts sub-tab | ✅ | "Contact detail coming soon" gone. Real table: Name / Function / Seniority / Outreach Status, with a **View in Outreach** button per row |
| **4 Sticky Name column** | ❌ **NOT FIXED** | See below |
| 6a Insight names contacts | ✅ | Live in production. The 27 Aug cron run produced "…none tied to **named contacts**" — a phrase only the new prompt generates |
| **6b Backfill note** | ⚠️ **PARTIAL** | Contact names render in the Action queue ("Marco Stiemert, Hermann-Wilhelm Wantia, Hartmut Baumann and 1 more"). The explanatory note about backfilled CRs is **absent** |
| 7 Pending Review sections | ✅ | First message after CR accepted **4**, Cold InMail opens **3**, Other **67** = **74**, matching "Showing 74 of 74 touches". "Introduction / referral" and "Connection request" removed; empty chaser sections hidden |
| 8 Legacy CRs out of review | ✅ | Pending Review 197 → 74 (71 at the time of the change; live ingest has since added rows) |
| 9 Sent sub-tabs | ✅ | **Messages sent 0** (default landing) / **CRs sent 2**, graceful empty state |
| 10 Outreach company grouping | ✅ | COMPANIES (2): **coolblue**, **OFFICE Partner GmbH**. No "Unmatched" bucket |
| 5 Ask bar | ⛔ **NOT STARTED** | Deferred — needs a new Haiku Edge Function, its prompt spec, chips and wiring |

## FIX 4 — still broken, different symptom

Unscrolled, the Name column renders correctly with a clean divider. Scrolled right, the
**company names disappear entirely** and fragments of other columns' text occupy that space
("urer" from Manufacturer, "Category Ret" from Multi-Category Retailer).

So the sticky column is not staying pinned — it scrolls away and the scrolling content shows
through where it used to be. That is arguably worse than the original overlap: the column
you're meant to keep as your anchor is the one that vanishes.

The z-index/background change either wasn't applied to the body cells, or the sticky
positioning itself isn't taking. Needs one more pass: `position: sticky; left: 0` plus a
theme-aware opaque background and a z-index above the scrolling cells, on **both** header and
body cells.

## Other things noticed, not in scope

- **Three different pending-draft numbers on one screen.** Today's widget says **64**,
  Outreach says **74**, Automation Health says **8**. They're different predicates
  (agent-produced vs all vs approvable), but a first-time user reads them as contradictory.
  Worth reconciling the labels.
- **The 27 Aug briefing flags "11 outreach_log deletions unexplained"** and recommends
  spot-checking them. Those are **my test-row cleanups** (TEST-BRAD, TEST-BRAD-2/3, the
  sentinel and CR-log test rows). Nothing to investigate.
- **`?search=` URL param is not honoured** on /contacts — the box stays empty and the list
  unfiltered. If FIX 3's contact deep link uses `/contacts?search=<name>` rather than
  `/contacts/<id>`, it will land unfiltered.
- Live ingest is healthy after the secret rotation: contacts 259 → 261 (P294 Hartmut
  Baumann, P295 Sanmeet Singh Kochhar, both Accepted), outreach_log 208 → 217, companies
  → 355. The watchers are running on `INBOUND_WEBHOOK_SECRET`.

## Still open going into handover

- FIX 4 (sticky column), FIX 6b note, FIX 5 (Ask bar)
- Five Edge Functions still on the legacy secret — `update-contact-on-cr-accepted`,
  `capture-and-classify-reply`, `enrich-contact-metadata`, `enrich-company-websites`,
  `generate-daily-insight`. See `docs/security-critical-2-scoped-secrets-2026-08-26.md`
- `MAKE_SHARED_SECRET` cannot be deleted until those are cut over and the logs show zero
  `deprecated_secret_used`
- **`TEST_MODE=false` — live sends armed.** The Send now button sends to the real contact
- F-13 EA-doc prompt caching, ~87% off the £0.0928 per-draft cost
