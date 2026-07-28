# Pier Lead Lake — State-of-CRM Audit

**Generated:** 2026-07-28 (Europe/London)
**Scope:** UI V1.1 complete, migrations through 026 applied, zero backend automations wired.
**Method:** Supabase MCP (schema + SQL, project `qzfrcfzeiagziqjnfarw`), Claude-in-Chrome MCP (live UI on `pier-lead-lake.lovable.app`), and direct reads of the Lovable codebase.
**Baseline snapshot for the "before automations" delta.** A second identical audit is planned once automations are live.

---

## Table of contents

- [0. Executive summary + CRITICAL flags](#0-executive-summary)
- [1. Technical health](#1-technical-health)
- [2. Data state](#2-data-state)
- [3. E2E round-trip tests](#3-e2e-round-trip-tests)
- [4. UX audit per tab](#4-ux-audit-per-tab)
- [5. Cross-tab consistency](#5-cross-tab-consistency)
- [6. Feature completeness matrix](#6-feature-completeness-matrix)
- [7. Strengths](#7-strengths)
- [8. Weaknesses and risks](#8-weaknesses-and-risks)
- [9. Automations master plan](#9-automations-master-plan)
- [10. Research Agent architecture proposal](#10-research-agent-architecture-proposal)
- [11. Recommended 7-day action list](#11-recommended-7-day-action-list)
- [Appendix A — audit method limitations](#appendix-a-audit-method-limitations)

---

<a name="0-executive-summary"></a>
## 0. Executive summary + CRITICAL flags

**CRITICAL flags: NONE.** No data-loss risk, RLS gap, or security issue found. All 22 public tables have RLS enabled; every server function is auth-gated; zero `service_role` usage in app code; all foreign keys intact; zero orphaned rows; test-data cleanup verified back to baseline exactly (including the append-only `audit_log`).

**One-line state:** the CRM is a well-structured, RLS-hardened, fully-manual system. Every screen renders real Supabase data or a clearly-labelled "Wired soon" placeholder. The gap to autonomy is entirely the backend automation layer (PhantomBuster / Make / Edge Functions / pg_cron), none of which exists yet. The database has already been provisioned with the target tables for that layer (`agent_errors`, `agent_handover`, `nightly_summary`, `drafts_feedback`, `duplicate_candidates`), so the schema is ahead of the wiring.

**Top 5 things to fix or decide before automations (detail in §8):**
1. **Today "drafts pending review" = 200 but Outreach → Pending Review = 0.** The widget counts all `pending_review` (200, all legacy imports); the Outreach default view hides legacy. Confusing hand-off. (P1)
2. **Audit-log cascade noise.** Creating/deleting a contact fires a `contacts_count` recompute UPDATE on its company, which the audit trigger records as "Updated {company}". Expect churn in Actions Log once contacts flow in. (P2)
3. **`% replied` and reply-based funnel stages are all zero** and stay so until `reply_received_at` / `reply_classification` are populated by a classify-reply pipeline. (P1, expected)
4. **Two legacy query-string `Link` targets remain** in `TargetsSection.tsx` and `TodayFocus.tsx` (moreHref links) — flagged, not fixed, per prior passes. (P2)
5. **`insurance_products` / `insurers` tables are empty** (0 rows) despite a Products tab reading them — dead surface until enrichment lands. (P2)

---

<a name="1-technical-health"></a>
## 1. Technical health

### 1.1 Migration inventory

`list_migrations` returned **26 migrations, sequential 001–026, no gaps, no duplicates, no orphans.**

| # | Name | | # | Name |
|---|------|-|---|------|
| 001 | enable_extensions | | 014 | pier_pipeline_product_line_to_text |
| 002 | enums | | 015 | security_fixes |
| 003 | teams_and_members | | 016 | invoker_function_search_paths |
| 004 | reference_tables | | 017 | auto_team_membership |
| 005 | companies | | 018 | expand_enums |
| 006 | contacts | | 019 | user_column_prefs |
| 007 | outreach_log | | 020 | user_column_prefs_checks |
| 008 | insurance_products_and_insurers | | 021 | add_category_tokens |
| 009 | supporting_tables | | 022 | backfill_category_tokens |
| 010 | functions_and_triggers | | 023 | reconciliation_infra |
| 011 | indexes | | 024 | data_quality_snapshots |
| 012 | rls_policies | | 025 | delete_and_documents |
| 013 | fk_covering_indexes | | 026 | audit_reason_aware |

**Migration 026 applied and correct.** `pg_get_functiondef(fn_audit_entity)` contains the `archive_reason` branch, the "Deleted …" summary, and the "Restored deleted" summary; `prosecdef = true` (SECURITY DEFINER). Verified live: a soft-delete produced `Deleted AUDIT-TEST-20260728-Company (reason: deleted)` (see §3).

### 1.2 Schema audit — RLS + tables

**Every one of the 22 public tables has `relrowsecurity = true`.** Policy counts (from `pg_policies`):

| Table | RLS | Policies | | Table | RLS | Policies |
|---|---|---|-|---|---|---|
| agent_errors | ✓ | 4 | | insights_snapshots | ✓ | 4 |
| agent_handover | ✓ | 4 | | insurance_products | ✓ | 4 |
| audit_log | ✓ | 2 (SELECT+INSERT, append-only) | | insurers | ✓ | 4 |
| blocklist | ✓ | 4 | | nightly_summary | ✓ | 4 |
| companies | ✓ | 4 | | outreach_log | ✓ | 4 |
| company_aliases | ✓ | 4 | | pier_pipeline | ✓ | 1 |
| company_documents | ✓ | 4 | | saved_views | ✓ | 4 |
| contacts | ✓ | 4 | | team_members | ✓ | 1 |
| data_quality_snapshots | ✓ | 2 (SELECT+INSERT) | | teams | ✓ | 1 |
| drafts_feedback | ✓ | 4 | | eurefas_members | ✓ | 1 |
| duplicate_candidates | ✓ | 4 | | user_column_prefs | ✓ | 4 |

- `audit_log` and `data_quality_snapshots` intentionally have only SELECT+INSERT (append-only for users) — correct.
- Tables with 1 policy (`teams`, `team_members`, `pier_pipeline`, `eurefas_members`) use a single read-scoped policy; worth a spot-check that write paths are intended to be blocked (they are, for these reference/membership tables).
- **Indexes:** covering indexes on FKs were added in 013; each new table (023–025) shipped its own indexes (`idx_company_aliases_lower_alias`, `idx_audit_log_team_created`, `idx_dq_snapshots_team_date`, `idx_company_documents_company/team`). No obvious missing hot-path index for current data volume (≤400 rows/table).

### 1.3 Server function inventory

Enumerated from `src/lib/queries/*.functions.ts` (Lovable repo). **~55 server functions across 9 files.** Every one is defined with `createServerFn(...).middleware([requireSupabaseAuth])` and uses the request-scoped `context.supabase` client (RLS-honouring). **Zero `service_role` references in application code** — verified by diff-grep on every commit that introduced or edited these files.

| File | Functions |
|---|---|
| `companies.functions.ts` | listCompaniesFn, listCompaniesPulseFn, companiesTotalCountFn, companiesArchiveStatsFn, getCompanyFn, listCountriesFn, updateCompanyFn, listCompanyContactsFn, listCompanyOutreachFn, listCompanyProductsFn, **deleteCompanyFn**, **createCompanyFn** |
| `contacts.functions.ts` | list/kanban/total-count/countries/company-names/get/update fns, **deleteContactFn**, **createContactFn** (all list/count queries filter `archived_at IS NULL`) |
| `outreach.functions.ts` | listOutreachFn, outreachTabCountsFn, updateOutreachFn, supersedeAndCreateFn, sendNowFn, bulkUpdateOutreachFn, detail/thread fns |
| `today.functions.ts` | todayTargetsFn, weeklyCapacityFn, channelFunnelsFn, extendedActivityFn, todayFocusFn, readyToMoveFn, automationHealthFn, promoteToMondayFn, unpromoteCompanyFn, promotedToMondayCountFn, agentErrors24hFn, **todayPendingDraftsFn** |
| `archive.functions.ts` | archiveListFn, archiveStatsFn, unarchiveCompanyFn, reArchiveForUndoFn, **restoreDeletedCompanyFn**, **restoreDeletedContactFn**, **listDeletedCompaniesFn**, **listDeletedContactsFn** |
| `reconciliation.functions.ts` | reconLinkedinFn, assignContactToCompanyFn, auditLogFn, dataQualityFn, reconMondayFn, addMondayLinkFn |
| `insights.functions.ts` | insightsFunnelFn, insightsSegmentsFn, insightsVolumeFn, insightsDqTrendFn, insightsCaptureSnapshotFn |
| `documents.functions.ts` | **listCompanyDocumentsFn**, **addCompanyDocumentFn**, **removeCompanyDocumentFn** |
| `prefs.functions.ts` | saveColumnPrefsFn, upsertSavedViewFn, deleteSavedViewFn |

### 1.4 Route inventory + Links

Routes registered in `routeTree.gen.ts` and reachable: `/` (→`/today`), `/auth`, `/reset-password`, `/sitemap.xml`, and under `_authenticated`: `/today`, `/companies`, `/companies/$companyId`, `/contacts`, `/contacts/$contactId`, `/outreach`, `/outreach/$touchId`, `/archive`, `/reconciliation`, `/insights`. All nav items in the sidebar are enabled (Today, Companies, Contacts, Outreach, Archive, Reconciliation, Insights); `disabledNav` is now empty. Every route loaded cleanly in Chrome during this audit.

**Interpolated `Link` scan:** the per-record navigation across the app uses the typed form `to="/x/$id" params={{...}}` (companies rows, contacts rows, archive rows, today focus contact rows, drafts widget). **Two remaining string/query-path `Link` targets** (flagged in prior passes, not fixed): the "and N more" links in `TodayFocus.tsx` and the target-tile hrefs in `TargetsSection.tsx` pass `to="/contacts?…"` / `to="/outreach?…"` string paths rather than typed `search` objects. These work but are the fragile pattern; converting needs `validateSearch` on the target routes.

### 1.5 TypeScript / build / console

- **`tsc --noEmit` was NOT run** — the application code lives in the Lovable project's own git, which this audit environment cannot check out or run a compiler against (see Appendix A). Proxy signal: every one of the ~30 commits in this build cycle passed Lovable's `bun run build:dev` gate, and each of the ~10 routes rendered without an error boundary in Chrome.
- **Console (Pier app):** across every route visited, **zero Pier-app errors**. The only console exceptions are from a browser extension (`chrome-extension://chmaghefgehniobggcaloeoibjmbhfae`, "Complexity"/`cplx-*.js`) — not app code — which the audit brief explicitly permits.

### 1.6 Dead code / unused surfaces

- **`insurance_products` (0 rows) + `insurers` (0 rows)** are read by `listCompanyProductsFn` and the Company Detail → Products tab, but hold no data. Live-but-empty surface until enrichment populates them.
- **`agent_errors`, `agent_handover`, `nightly_summary`, `drafts_feedback`, `duplicate_candidates`, `insights_snapshots`, `blocklist`** exist with RLS but are not yet read by any query function — provisioned ahead of the automation layer (intentional, not accidental dead code).
- No server function is entirely orphaned from the UI after the V1.1 pass (delete/create/restore/documents/drafts are all now wired).

---

<a name="2-data-state"></a>
## 2. Data state

### 2.1 Row counts (baseline, captured before any test mutation)

| Table | Rows | | Table | Rows |
|---|---|-|---|---|
| companies (total) | 352 | | audit_log | 21 |
| companies (active, `archived_at IS NULL`) | 350 | | company_aliases | 0 |
| companies (archived, promoted_to_monday) | 2 | | insurance_products | 0 |
| contacts (total / active) | 236 / 236 | | insurers | 0 |
| company_documents | 0 | | teams | 1 |
| outreach_log | 204 | | team_members | 1 |
| data_quality_snapshots | 1 | | saved_views | 3 |
| | | | user_column_prefs | 1 |

### 2.2 Data quality gaps (SQL, active pipeline)

| Gap | Count | Cross-check |
|---|---|---|
| Companies missing website | 267 | matches Reconciliation → Data Quality (267) |
| Companies missing country | 182 | matches (182) |
| Companies missing category | 108 | matches (108) |
| Companies missing priority | 3 | matches (3) |
| **Distinct companies with ≥1 gap** | **267** | matches "Companies with gaps 267 (560 total gap instances)" tile |
| Contacts missing linkedin_url | 130 | matches (130) — drifted from 123 baseline via edits |
| Contacts missing email | 232 | matches (232) |
| **Distinct contacts with ≥1 gap** | **234** | matches "Contacts with gaps 234 (362 total gap instances)" tile |

### 2.3 Duplicate risk

- Contacts sharing `linkedin_url`: **0 groups** (the single duplicate present at V1 has since been resolved).
- Contacts sharing `email`: **0 groups.**
- Companies sharing `website_url`: **0 groups.**

### 2.4 Foreign-key integrity

- Contacts with a `company_id` not in `companies`: **0.**
- `outreach_log` with `contact_id` not in `contacts`: **0.**
- `outreach_log` with `company_id` not in `companies`: **0.**
- Contacts with NULL `company_id`: **0** (all 236 matched).

### 2.5 Enum cleanliness

All enum-typed columns hold only valid values (DB enums enforce this; no free text can leak in):
- `companies.priority`: P0, P1, P2, P3, OoS, Competitor, null
- `companies.opportunity_status`: Active Lead, Contacted, Out of Scope, Partner, Prospect, To Review
- `contacts.outreach_status`: Active, Contacted, Cooldown, In conversation, Needs review, Not relevant, Not started
- `contacts.connection_status`: Accepted, Already connected, Not connected, Request sent
- `outreach_log.draft_status`: approved, pending_review, superseded
- `outreach_log.send_status`: Cancelled, Draft, Sent
- `outreach_log.channel`: Email, LinkedIn CR, LinkedIn DM, LinkedIn inMail
- `companies.archive_reason` (archived rows): promoted_to_monday (the only reason present — no deleted companies live)

### 2.6 Outreach composition (relevant to a cross-tab inconsistency)

`outreach_log` total **204**: **201 legacy** (`migrated_legacy=true`), **3 non-legacy**. Of the 204, **200 are `pending_review`** and **all 200 are legacy** (`pending_review AND migrated_legacy=false = 0`). This is the root of the Today-vs-Outreach mismatch in §5.

---

<a name="3-e2e-round-trip-tests"></a>
## 3. E2E round-trip tests

All test data was prefixed `AUDIT-TEST-20260728-` and hard-deleted afterward. **Baseline vs post-test counts matched exactly** (`companies_active 350→350, contacts_total 236→236, company_documents 0→0, outreach_log 204→204, dq_snapshots 1→1, audit_log 21→21`), with **0 leftover** test companies/contacts/docs/audit rows. Cleanup PASSED — no CRITICAL.

| # | Test | Result | Evidence |
|---|---|---|---|
| 1 | Company create → edit → delete(reason) → Archive → Actions Log → restore → hard-delete | **PASSED** | Audit trail: `Created companies record` → `Updated AUDIT-TEST-20260728-Company` → `Deleted AUDIT-TEST-20260728-Company (reason: deleted)` → `Restored deleted AUDIT-TEST-20260728-Company`. Chrome: row visible in Archive → Deleted companies (P3, reason "Deleted", Restore action); Actions Log rendered the delete summary (026 validated through the full stack). |
| 2 | Contact create → delete(reason: wrong_target) → restore → hard-delete | **PASSED** | `Deleted AUDIT-TEST-20260728 Contact (reason: wrong_target)` → `Restored deleted AUDIT-TEST-20260728 Contact`. Contact linked to a real company by `company_id` only (no real record modified). |
| 3 | Move-to-Monday → funnel promoted +1 → restore → −1 | **PASSED (adapted)** | Run against an AUDIT-TEST company, not a real one: promoting a real company would leave permanent audit rows even after restore, violating the "zero real-record modification" rule. The funnel `promoted_to_monday` count is a pure `WHERE archived_at IS NOT NULL AND archive_reason='promoted_to_monday'` and reads 2 from the two genuine promotes (Foxway, Vodafone Portugal), which are visible in Archive → Moved to Monday and the Insights funnel. |
| 4 | Files tab add → verify → delete | **PASSED** | `company_documents` 0 → 1 (AUDIT-TEST-20260728-DOC, source `user`) → 0 after delete. Files tab renders after Notes with "Add document" and the empty state. |
| 5 | Take snapshot now (idempotency) | **PASSED** | `fn_capture_dq_snapshot` re-run → `data_quality_snapshots` stayed **1** (ON CONFLICT overwrote today's row). |
| 6 | Today drafts widget navigation | **PASSED (with caveat)** | Widget renders **200** in red with 5 sample rows using typed `to="/outreach/$touchId"` and a "View all 200 pending drafts" link to `/outreach`. **Caveat:** the destination Outreach → Pending Review shows **0** because all 200 are legacy and the default view hides legacy — see §5. |

---

<a name="4-ux-audit-per-tab"></a>
## 4. UX audit per tab

Ratings are 1–10 for the current manual-CRM stage. Screenshots were captured live this session for every tab in default state.

### Today — 9/10 · Cognitive load: Medium
Orientation-first landing: greeting + London date, **Drafts-to-approve widget** (200 red), **Promoted to Monday**, **Ready to move (8)**, **Today's targets** (4 tiles), **Weekly/monthly capacity**, **Channel funnels**, **Activity chart**, **Today's focus** (4 groups), **Ready to move table**, **AI + Automation** box. Works well: freshness badges (Legacy / Wired soon) make live-vs-placeholder honest; London-tz throughout. Issue: dense — a first-time viewer meets ~10 widgets at once (High for a novice). Empty/loading states present (skeletons, "Nothing scheduled for this week").

### Companies — 9/10 · Low
**Pipeline Pulse** strip (Coverage 350 active / 352 total (2 archived), Opportunity gap, Deal size, Warm work, Momentum), NL "Ask" bar, filter chips, Views, Column visibility, **New company**, Table with inline pills, per-row delete, split-screen detail. Works well: the Pulse converts a list into a briefing. Issue: delete control lives in a trailing column that requires horizontal scroll to reach on a wide table.

### Contacts — 8/10 · Low
Mirrors Companies: **Contacts Pulse** (236 of 236, Warm 8, Ready to re-engage 2, 1st-degree 42, Momentum), filters, Table/Kanban toggle, **New contact**, per-row delete. Works well: Kanban view for connection stages. Issue: job-title column can be very long and pushes the table wide.

### Outreach — 7/10 · Medium
Tabs by draft_status (**Pending Review 0**, Approved 1, Sent 0, Rejected 0, All 204), Show-legacy toggle, three "Sync …" automation placeholders, **Outreach Pulse**, three-panel/Kanban, DraftEditor split (voice lint, approve/reject/send). Works well: DraftEditor's voice-lint score + reject-reason capture is genuinely differentiated. **Issue (P1):** the default Pending Review view shows 0 while Today advertises 200 pending — the legacy split is invisible here unless you toggle "Show legacy".

### Reconciliation — 8/10 · Medium
Four sub-tabs. **LinkedIn Contacts** (match stats + empty state, wires to Sales Nav export). **Actions Log** (live audit feed, filters default Today, Export CSV, AI-summary placeholder) — validated live rendering the 026 summaries and real "Moved Foxway to Monday" with actor. **Data Quality** (score 30%, Companies-with-gaps 267 / 560, Contacts-with-gaps 234 / 362, four accordions). **Monday Deals** (Lovable archives 2, Add-Monday-link + Remove-archive, placeholders). Works well: the audit feed is the connective tissue of the whole app.

### Insights — 8/10 · Medium
**Pipeline funnel** (Leads 350 → Engaged 182 → Connected 53 (29%) → Replies 0 → Positive 0 → Promoted 2), **Segment performance** (Country/Category/Priority accordions, all % ≤100 after the population-alignment fix), **Volume trend** (Daily/Weekly/Monthly line chart + "historical through May 2026" caption), **Data quality trend** (single dot + "builds after 3 snapshots"). Works well: the funnel now uses honest contact-population ratios. Issue: the DQ-trend chart is a single point until three weekly snapshots accrue.

### Archive — 8/10 · Low
Three sub-tabs: **Moved to Monday** (default; stats 2/2/83 days, week-grouped, Restore), **Deleted companies**, **Deleted contacts**. Works well: cleanly separates the promote lane from the delete lane; reason labels render. Empty states present ("No deleted companies.").

### Company Detail (split-screen) — 8/10 · Medium
Header with Priority/Stage pills, **Move to Monday** / **Already moved + Restore** control, tabs Overview | Contacts | Outreach | Notes | **Files** | Products | Timeline. Inline-editable Overview with per-field autosave + Undo. Works well: the Move/Already-moved state machine and the new Files tab. Issue: Products tab and Timeline tab are empty/placeholder.

---

<a name="5-cross-tab-consistency"></a>
## 5. Cross-tab consistency

**Design tokens:** consistent. Single indigo primary (`#1D237A` as oklch in `styles.css`), Inter font, 32px compact rows across Companies/Contacts/Outreach/Archive/Insights/Reconciliation tables, `Card` + `Badge` shadcn primitives everywhere. Chart colours use hex on marks and bare `var(--…)` for axes/grid (theme-aware), consistent after the oklch fix.

**Interaction patterns:** consistent. Delete = confirm dialog + reason Select + 10s Undo toast; archive/restore = toast + Undo; "Wired soon" and "Legacy data" badges are the same component and copy across tabs; sub-tabs (Reconciliation, Archive) share the URL-`validateSearch` pattern; typed router Links for per-record navigation.

**Notable inconsistencies:**
1. **Pending-draft count mismatch (P1):** Today = 200, Outreach → Pending Review = 0 (legacy hidden). Same underlying number, two different filters, no shared explanation.
2. **"Updated" audit summaries are mixed:** rows written before 026 read "Updated companies record" (generic); rows after read "Updated {name}". Cosmetic, self-heals as new activity accrues.
3. **Contact-linked writes emit company-level audit rows** ("Updated {company}") via the `contacts_count` recompute cascade — a consistency quirk that will add churn.

**Accessibility flags:** dialogs use shadcn (focus-trapped, ESC-closable); delete confirmations are keyboard-reachable; the disabled "Already moved to Monday" button is wrapped in a `<span tabIndex={0}>` so its tooltip still fires. Not exhaustively tested: colour-contrast ratios on muted text, full keyboard-only tab order, and ARIA-live for toasts.

**Narrow width:** the app uses responsive Tailwind grids (`grid-cols-1 md:grid-cols-N`) throughout, and the sidebar collapses via its own width toggle. A dedicated 800px-viewport sweep was **not** performed in this audit (tooling gap, see Appendix A) — flagged as an open coverage item, not a known defect.

---

<a name="6-feature-completeness-matrix"></a>
## 6. Feature completeness matrix

Live = reads real data now. Wired-soon = placeholder awaiting an automation.

| Feature | Tab | Live | Wired-soon | Needs to go live | Priority |
|---|---|---|---|---|---|
| Drafts-to-approve widget | Today | ✓ | | — | — |
| Promoted-to-Monday tile | Today | ✓ | | — | — |
| Ready-to-move tile + table | Today | ✓ | | — | — |
| Today's targets (4 tiles) | Today | ✓ | | — | — |
| Weekly/monthly capacity | Today | ✓ | | — | — |
| Channel funnels | Today | partial | Accepted/Reply rows | classify-reply pipeline | P1 |
| Activity chart | Today | ✓ (legacy) | | live outreach fills forward | — |
| Today's focus (4 groups) | Today | ✓ | | — | — |
| AI insight of the day | Today | | ✓ | daily-insight agent | P2 |
| Research Agent tiles (6) | Today | | ✓ | Research Agent + `agent_runs` | P1 |
| Replies overnight / Agent errors | Today | | ✓ | classify-reply / `agent_errors` writer | P1/P2 |
| Pipeline Pulse | Companies | ✓ | | — | — |
| Create / delete / restore company | Companies/Archive | ✓ | | — | — |
| NL "Ask" filter | Companies | ✓ | | (validate model output server-side) | P2 |
| Contacts Pulse | Contacts | ✓ | | — | — |
| Create / delete / restore contact | Contacts/Archive | ✓ | | — | — |
| LinkedIn contact matcher | Reconciliation | ✓ (0 unmatched) | | Sales Nav export feeds it | P1 |
| Actions Log feed | Reconciliation | ✓ | AI daily summary | daily-summary agent | P2 |
| Data Quality accordions | Reconciliation | ✓ | | — | — |
| Monday Deals Section A | Reconciliation | ✓ | Sections B/C | Monday API | P1 |
| Pipeline funnel | Insights | partial | Replies/Positive | classify-reply | P1 |
| Segment performance | Insights | ✓ | %-replied col | classify-reply | P1 |
| Volume trend (D/W/M) | Insights | ✓ (legacy) | | live outreach | — |
| DQ trend + snapshot button | Insights | ✓ | | weekly cron for auto-snapshots | P2 |
| Files tab (URL docs) | Company Detail | ✓ | file upload | storage bucket | P2 |
| Products tab | Company Detail | | ✓ (0 rows) | enrichment populates insurance_products | P2 |
| Timeline tab | Company Detail | | ✓ | timeline query | P2 |
| Move-to-Monday deal creation | Company Detail | partial | Monday POST | Monday API | P1 |
| Send-now (Make webhook) | DraftEditor | partial | delivery confirm | Make + receive-confirmation | P0 |
| Regenerate draft | DraftEditor | | ✓ | generate-draft Edge Fn | P0 |

---

<a name="7-strengths"></a>
## 7. Strengths (what stands out vs a generic CRM)

1. **Per-team RLS on every table, enforced end-to-end.** All 22 tables have RLS; all ~55 server functions run through `requireSupabaseAuth` + the request-scoped client; zero `service_role` in app code. A generic CRM template usually leaks a service key somewhere — this one doesn't.
2. **A real audit trail with human-readable, reason-aware summaries.** `fn_audit_entity` (023, hardened in 026) turns raw column diffs into "Moved X to Monday" / "Deleted X (reason: …)" / "Restored deleted X", surfaced live in the Actions Log with actor resolution. Most CRMs bolt this on late; here it's a DB trigger from the start.
3. **Voice-contract enforcement in the DraftEditor.** Client-side lint scoring British-English/no-em-dash/"Partner-not-client" rules on every draft, plus structured reject reasons — a domain-specific quality gate a generic tool has no concept of.
4. **Distinct-vs-instance data-quality accounting.** The Reconciliation/Insights tiles deliberately separate "267 companies with gaps" from "560 gap instances" and use bounded contact-population ratios for connect-rate — numerically honest where a naive build shows >100% "accept rates".
5. **Data-quality trend as first-class history.** `data_quality_snapshots` + `fn_capture_dq_snapshot` mean data health is tracked over time, not just at-a-glance — designed for the before/after story this audit exists to tell.
6. **Timezone discipline.** Every "today/this week/this month" resolves in Europe/London (SQL `AT TIME ZONE` and `Intl … Europe/London` in JS), so counts don't drift by a day at UTC midnight.
7. **Schema provisioned ahead of automations.** `agent_errors`, `agent_handover`, `nightly_summary`, `drafts_feedback`, `duplicate_candidates` already exist with RLS — the automation layer has landing pads.

---

<a name="8-weaknesses-and-risks"></a>
## 8. Weaknesses and risks

**Fragile patterns**
- Two query-string `Link` targets in `TodayFocus.tsx` / `TargetsSection.tsx` bypass typed routing (string `to="/contacts?…"`); they work today but are the exact pattern that silently broke navigation before (production-only). Convert to typed `search` when the target routes gain `validateSearch`.
- Auto-generated `contact_id` uses a `CT####` prefix while imported contacts use `Pnnn` — no collision, but two ID conventions in one column.
- `createCompanyFn` derives the next `Cnnn` by scanning the top 50 `C%` ids client-side; fine at 352 rows, but not concurrency-safe and not a DB sequence.

**Load-risk points**
- Several fns fetch broadly and fold in JS (`readyToMoveFn`, `insightsSegmentsFn`, `dataQualityFn` duplicate scan `limit(1000)`, `reconLinkedinFn` companies `limit(5000)`). Correct and fast at ≤400 rows; will need server-side aggregation (RPC/materialised views) at 10k+.
- `auditLogFn` returns `select("*")` (full before/after JSONB) for 50 rows; audit_log will grow unbounded (no retention job) and every company/contact/outreach write appends — including `contacts_count` recompute cascades. A pg_cron retention/rollup job will be needed.

**What Oli might reasonably question**
- "Why does Today say 200 drafts pending but Outreach shows none?" (legacy split — P1 to reconcile the copy or the filter).
- "Why is the Products tab / Research Agent panel empty?" (enrichment not wired — expected, but the placeholders should perhaps be hidden until then).
- "Insights funnel shows 0 replies" — correct but reads as broken without the "Wired soon" context.

**Code-review flags**
- No automated tests in the app repo (build-passing is the only gate).
- Full-table `select("*")` in a few list/detail paths returns unused columns over the wire.
- The `contacts_count` trigger cascade into `audit_log` will create noise once contacts are actively created/deleted.

**Migration / schema debt worth revisiting**
- `archive_reason` is free-text (no CHECK) — deliberate per spec, but a typo'd reason would slip through and mis-bucket between the Archive sub-tabs (the delete-list query is `archive_reason <> 'promoted_to_monday'`, so any non-promote string lands in "deleted").
- `insurance_products`/`insurers` empty tables + a Products tab is schema-ahead-of-data; fine, but track it.
- Soft-delete now spans two lanes on the same `archived_at`/`archive_reason` columns (promote vs delete). Distinguished only by reason string — robust as long as reasons stay disciplined.

---

<a name="9-automations-master-plan"></a>
## 9. Automations master plan

Legend — effort **S/M/L**; priority **P0** (blocker) / **P1** (core) / **P2** (nice-to-have). Owner in each subsection header.

### A. PhantomBuster phantoms — *Brad builds (Oli's LinkedIn cookies)*

| Phantom | Purpose | Trigger | Input | Output | Effort | Priority |
|---|---|---|---|---|---|---|
| **Sales Nav List Export** | Pull Oli's saved Sales Nav lead list into the CRM as contacts (feeds the LinkedIn-contacts matcher) | Schedule (daily) | Sales Nav list URL + cookies | CSV/JSON of leads (name, title, company, profile URL) → Make → `contacts` | M | **P0** |
| **Recently Connected** | Detect newly-accepted connections to flip `connection_status` and trigger first-DM drafting | Schedule (every 3h) | cookies | list of new 1st-degree connections | M | **P0** |
| **LinkedIn Inbox Sync** | Pull DM/InMail replies to populate `reply_content` / `reply_received_at` | Schedule (every 3h) | cookies | thread messages | L | **P1** |
| **Auto Connection Request Sender** | Send CRs for approved contacts within daily cap | Event (approved queue) or schedule | target profile URLs | send confirmations | M | **P1** |
| **Auto Connection Remover** | Withdraw stale pending CRs past N days to free capacity | Schedule (weekly) | pending-CR list | withdrawal confirmations | S | **P2** |
| **Profile Scraper (enrichment)** | Enrich company/contact fields the Research Agent needs | Event (triage queue) | profile/company URL | structured profile data | M | **P2** |

### B. Make.com scenarios — *Brad builds (glue)*

| Scenario | Trigger | Steps | Output | Effort | Priority |
|---|---|---|---|---|---|
| **Sales Nav → contacts upsert** | Phantom "Sales Nav Export" finishes | parse → dedupe vs `company_aliases`/existing → upsert `contacts` (unmatched land in Reconciliation) | new/updated contacts | M | **P0** |
| **Send-approved-draft → PhantomBuster** | `sendNowFn` webhook (already POSTs to Make) | receive draft → route to CR/DM/InMail phantom → write back `send_status='Ready'→'Sent'` | LinkedIn action queued | M | **P0** |
| **Delivery confirmation → outreach_log** | Phantom send confirmation | update `outreach_log.send_status='Sent'` + timestamp | confirmed send | S | **P0** |
| **Inbox reply → classify-reply** | Phantom "Inbox Sync" | write `reply_content`/`reply_received_at` → call classify-reply Edge Fn | classified reply | M | **P1** |
| **Recently-connected → draft trigger** | Phantom "Recently Connected" | flip `connection_status='Accepted'` → enqueue first-DM generate-draft | draft created | M | **P1** |
| **Monday deal create** | company archived w/ `promoted_to_monday` (DB webhook) | POST Monday API → store `monday_deal_id` | Monday deal | M | **P1** |

### C. Supabase Edge Functions — *Claude Code builds (future prompts)*

| Function | Trigger | Inputs | Outputs | Dependencies | Effort | Priority |
|---|---|---|---|---|---|---|
| **generate-draft-from-context** | DB webhook (accepted contact) / HTTP | contact + company + voice contract | `outreach_log` row `draft_status='pending_review'` | Anthropic Messages API; voice KB | L | **P0** |
| **send-approved-draft** | `sendNowFn` HTTP → (or replace the current Make webhook) | draft id | POST to Make/Phantom; set `send_status='Ready'` | Make webhook | M | **P0** |
| **receive-send-confirmation** | HTTP receiver (Phantom/Make) | send result | `send_status='Sent'` + timestamp | — | S | **P0** |
| **classify-reply** | HTTP receiver / DB webhook | `reply_content` | `reply_classification` (Positive interest / Booked / etc.) + `outcome` | Anthropic Messages API | M | **P1** |
| **inmail-auto-fallback** | cron / event | contacts stuck at "Request sent" past N days | switch channel to InMail, enqueue draft | capacity rules | M | **P2** |
| **remove-stale-crs** | cron | pending CRs past N days | mark for Phantom withdrawal | Auto-Connection-Remover | S | **P2** |
| **weekly-dq-snapshot** | pg_cron (weekly) | — | calls `fn_capture_dq_snapshot` per team | migration 024 (exists) | S | **P1** |
| **research-agent-run** | cron (nightly) | triage queue | enriched fields + `agent_runs` + `agent_insights` | see §10 | L | **P1** |
| **audit-log-retention** | pg_cron | old audit rows | prune/rollup to keep table bounded | — | S | **P2** |

### D. pg_cron jobs — *Claude Code*

| Job | Schedule | Runs |
|---|---|---|
| weekly-dq-snapshot | Mon 06:00 London | `fn_capture_dq_snapshot(team)` per team |
| nightly-research-agent | 02:00 London | research-agent-run over the triage batch |
| stale-cr-sweep | daily 07:00 | flag pending CRs > N days |
| audit-retention | weekly | prune `audit_log` older than retention window |

### E. External API integrations

| Integration | Purpose | Effort | Priority |
|---|---|---|---|
| **Monday.com** | Create a deal on Move-to-Monday; back-fill `monday_deal_id`; two-way reconciliation (Sections B/C) | M | **P1** |
| **Semrush** (or similar) | Company enrichment: `monthly_visits`, traffic, tech signals for the Research Agent | M | **P2** |
| **Anthropic Messages API** | Draft generation, reply classification, daily insight, research synthesis | L | **P0** |

### Recommended build sequence (minimise dependency waits)

1. **generate-draft-from-context** + **Sales Nav Export → contacts upsert** (unblocks the whole outbound loop and fills the matcher).
2. **send-approved-draft** + **receive-send-confirmation** (closes the send loop; makes Send-now real).
3. **Recently Connected** phantom + **recently-connected → draft trigger** (auto-drafts on accept).
4. **Inbox Sync** + **classify-reply** (lights up every reply-based stage: funnel Replies/Positive, Awaiting-reply group, Segment %-replied).
5. **Monday deal create** (Move-to-Monday becomes end-to-end).
6. **weekly-dq-snapshot** cron (DQ trend chart starts moving).
7. **research-agent-run** (see §10) + **remove-stale-crs** / **inmail-auto-fallback** (optimisation layer).

---

<a name="10-research-agent-architecture-proposal"></a>
## 10. Research Agent architecture proposal

**Purpose:** nightly, autonomously enrich under-researched companies so Oli's manual research time drops — triage the lake, deep-research the worthy, and surface signals + suggested next moves.

**Inputs (triage queue):** companies with `research_stage='Untouched'` or high data-gap score (the 267 with gaps), prioritised by `priority` (P0/P1 first). Batch size ~20–30/night to bound cost.

**Pipeline per company:**
1. **Triage** (cheap model): is this in-scope and worth deep research? → pass/fail, writes `agent_runs` (triaged/passed/failed counts already surfaced by the Today Research-Agent tiles).
2. **Enrich** (tools): WebSearch + Semrush (traffic/tech) + optional PhantomBuster company scrape → fill `website_url`, `country`, `category`, `estimated_revenue_gbp`, `employees`, `monthly_visits`, insurance signals.
3. **Synthesise** (Anthropic Messages API): produce a short "why this matters / suggested next move" → `agent_insights`, surfaced by the Today "AI insight of the day" card.

**Outputs / storage:**
- Enriched columns on `companies` (existing).
- **`agent_runs`** (new): id, team_id, run_at, companies_triaged, passed, failed, signals_found, tokens_used, status — powers the six Research-Agent tiles (currently hardcoded 0/"Never").
- **`agent_insights`** (new or reuse `insights_snapshots`): id, team_id, company_id, insight_text, created_at — powers the AI-insight card.
- Errors → **`agent_errors`** (exists; RLS'd) — powers the "Agent errors 24h" tile + modal.
- Handoffs needing a human → **`agent_handover`** (exists).

**Tools:** WebSearch, Anthropic Messages API (triage = cheap tier, synthesis = capable tier), Semrush REST, PhantomBuster (LinkedIn company data via Brad's phantoms).

**Schedule:** pg_cron `nightly-research-agent` at 02:00 London, batch 20–30, cap tokens/run.

**Human review loop:** enriched fields land as suggestions where risk is high (e.g. `opportunity_status`), reviewed via the existing inline-edit + audit trail; `agent_handover` rows appear for anything the agent won't decide. Every write is captured by the audit trigger, so Oli sees "Updated X" attributed to the agent actor.

**Cost model (rough):** triage ~1–2k tokens/company (cheap tier) + synthesis ~3–5k tokens/company (capable tier) + Semrush lookup. Order-of-magnitude **~$0.02–0.08 per company** at current pricing, so a 30-company nightly batch is roughly **$1–2.50/night** before Semrush credits. Precise figure needs the chosen model IDs and Semrush plan — a Brad/Oli decision.

---

<a name="11-recommended-7-day-action-list"></a>
## 11. Recommended 7-day action list

### Brad — can do now (no Claude Code needed)
1. Build + test the **Sales Nav List Export** phantom against Oli's saved list; confirm output shape.
2. Build the **Recently Connected** and **LinkedIn Inbox Sync** phantoms (schedule every 3h).
3. Stand up the **Make** scenarios for Sales-Nav→contacts upsert and the send-approved-draft relay (the `sendNowFn` webhook already exists).
4. Manual data cleanup on the **267 companies missing website / 182 missing country** — highest-leverage DQ wins; the trend chart will show the drop.
5. Prep Oli materials: a 2-minute Loom of the current CRM + the "before/after automations" framing this audit anchors.

### Needs a Claude Code prompt (rough scope)
1. **generate-draft-from-context** Edge Function (Anthropic Messages API + the voice KB) — the P0 unblocker.
2. **receive-send-confirmation** + **classify-reply** Edge Functions (HTTP receivers) to close the send/reply loop and light up the reply-based stages.
3. **weekly-dq-snapshot** pg_cron (one-liner around `fn_capture_dq_snapshot`) so the DQ-trend chart moves.
4. **Migration 027**: `agent_runs` + `agent_insights` tables (or wire `insights_snapshots`) to back the Research-Agent tiles.
5. **Fix the Today↔Outreach pending-draft mismatch** (P1) — either count non-legacy in the widget or land the "View all" on a legacy-inclusive view.

### Blocked on an Oli decision
1. **Deal-size formula** for Monday deal creation (what value to POST).
2. **InMail fallback delay N** (days at "Request sent" before switching channel).
3. **LinkedIn daily thresholds** (CR/DM/InMail caps to keep the account safe).
4. **Priority override for the Research Agent** (does it always follow `priority`, or can it self-reprioritise on signals?).
5. **Follow-up engine scope** (how many touches, what cadence, when to mark "Cooldown").

---

<a name="appendix-a-audit-method-limitations"></a>
## Appendix A — audit method limitations (full disclosure)

- **`tsc --noEmit` not run:** the application source lives in the Lovable project's own git, not the local `pier-lead-lake` repo (which holds only migrations, the Python loader, and docs). This audit environment cannot check out or compile the app. Type-safety is inferred from every commit passing Lovable's `bun run build:dev` gate.
- **No shell grep over the app repo:** code claims (RLS-on-fn, zero `service_role`, interpolated-Link scan) are based on reading the actual files via Lovable MCP and on per-commit diff review during the build cycle, cited inline — not a single fresh recursive grep.
- **800px narrow-width sweep not performed:** the resize tool was not loaded for this session; responsiveness is asserted from the responsive Tailwind classes in the code, not a viewport test. Flagged as an open coverage item.
- **Test 3 adapted:** run on an AUDIT-TEST company rather than a real one, to honour the "zero real-record modification" rule (a real promote would leave permanent audit rows even after restore).
- **Every numeric claim in this report is backed by a SQL query or command output produced during the audit**; UI claims are backed by a live Chrome screenshot or an explicit route. No numbers were invented.

*End of report.*
