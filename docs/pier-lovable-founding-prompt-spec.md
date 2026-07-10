# Founding prompt spec for the pier-lead-lake Lovable app

Target Lovable project: `pier-lead-lake` (fresh, to be created by Brad)
Target Supabase: `qzfrcfzeiagziqjnfarw` (pier-lead-lake-prod, Pier Insurance org, eu-west-1)
Author: Brad Gordon (Nailed It AI) via Cowork
Date: 8 July 2026
For: Claude Code to translate into a founding prompt and section prompts, ready for Brad to paste into Lovable

## How to use this document

Give this document to Claude Code with the instruction:

> Read this spec. Produce two outputs:
> 1. A file `docs/lovable/knowledge-base-workspace.md` with the Workspace-level Knowledge Base content Brad will paste into Lovable's Workspace KB before creating the project.
> 2. A file `docs/lovable/knowledge-base-project.md` with the Project-level Knowledge Base content Brad will paste into the project's KB after creating the project but before running Plan Mode.
> 3. A file `docs/lovable/founding-prompt.md` with the exact founding prompt text, ready to paste, sized 300 to 400 words per Lovable best practices.
> 4. A directory `docs/lovable/section-prompts/` with one file per section iteration (01-companies-list.md through 09-archive.md), each containing the exact prompt to paste after the founding prompt has been applied.
> 5. A file `docs/lovable/safety-checks.md` documenting the post-build audit steps Brad runs after each section prompt.

## The strategy

Per research findings on Lovable prompting:

1. **Two-level Knowledge Base**: Workspace-level (coding standards, libraries, patterns) plus Project-level (this specific product, schema, design decisions). Both get sent with every prompt implicitly.
2. **Founding prompt in Plan Mode**: 1 credit, no code generated. Lovable summarises what it will build. Brad reviews and confirms. Flip to Default Mode only after alignment.
3. **Section iteration after founding**: one region per prompt. Use replace/update/adjust verbs to lock unchanged parts.
4. **Manual RLS audit after every schema change**: run the audit checklist from the migration spec section 12.

## 1. Workspace-level Knowledge Base

Add to Lovable Workspace Knowledge Base BEFORE creating the project. Applies across every project Brad builds in Lovable.

```markdown
# Nailed It AI, workspace coding standards

## Frontend patterns
- React with TanStack Router and TanStack Query
- shadcn/ui component library only, no other UI kits
- Tailwind CSS for styling, use tokens not raw hex where possible
- No inline styles, no CSS modules
- All Supabase queries live in src/lib/queries/*.ts
- Every query is typed with QueryData<typeof query>
- Every list query uses .range() and returns a total count
- Every mutation uses .throwOnError() and TanStack Query invalidation

## Supabase patterns
- Server-side code hits port 6543 (Supavisor pooler), never 5432
- Every FK column has a btree index (verified in migration audits)
- Every RLS policy wraps auth.uid() as (SELECT auth.uid())
- Never use user_metadata in RLS policies
- Never expose SECURITY DEFINER views through the PostgREST API
- Every Realtime subscription cleans up on component unmount
- Never issue N+1 queries client-side, always use PostgREST nested selects

## Auth patterns
- Supabase Auth with email/password and Google OAuth
- profiles table populated by handle_new_user() trigger, with SECURITY DEFINER
- Team-scoped RLS pattern: team_id column on every row, membership check via fn_user_teams()

## Naming
- snake_case in database, camelCase in TypeScript
- Query functions named after the operation: getCompanies, updateContact, insertOutreach
- Component names match their route or feature: CompaniesList, CompanyDetail

## Testing rules
- No feature is done until: the code passes lint, the RLS policies are audited via pg_policies, and the query returns expected data at both anon and service-role scope.
```

## 2. Project-level Knowledge Base

Add to the pier-lead-lake project Knowledge Base after creating the empty Lovable project but before pasting the founding prompt.

```markdown
# Pier Lead Lake, project knowledge

## Product
Bespoke B2B CRM for Pier Insurance Managed Services Ltd, a UK insurance broker offering embedded gadget and ticket insurance. This CRM tracks Pier Protect commercial pipeline: companies Pier could partner with to sell gadget insurance at point of sale.

## Users
3 to 6 sales/ops users. Primary: Oliver Müller (Sales, DACH), Phil Sanderson (Finance MD), Mark Gordon (CEO). Data volume: ~420 companies + 261 contacts + 222 outreach touches at v1, growing to ~2k companies over 12 months.

## Data model
Backed by Supabase Postgres 17 at qzfrcfzeiagziqjnfarw.supabase.co. Full schema in migrations/001 through 013. Key tables and their purpose:

- **companies** (39 domain columns plus 5 build columns): main entity. Priority enum P0/P1/P2/P3/OoS/Competitor. Research Stage enum Untouched/Light triage/Deep research done/Outdated. Country, Category (multi-select), plus insurance and financial fields.
- **contacts** (31 columns): people at companies. Foreign key to companies. Includes Connection to Oliver (1st/2nd degree), Formality (Sie/du), Language (EN/DE).
- **outreach_log** (18 legacy columns plus 12 new agent-managed columns): per-touch log. Foreign key to contacts and companies. Messages, replies, drafts.
- **pier_pipeline**: reference table, live partners and prospects (67 rows). Read-only, used for the tracking cascade.
- **eurefas_members**: reference table, European Refurbishment Association members (27 rows).
- **insurance_products, insurers**: catalogue tables.
- **agent_handover, nightly_summary, agent_errors, blocklist, drafts_feedback, duplicate_candidates, saved_views, insights_snapshots**: supporting tables for the 6 AI agents.

## Auth and permissions
Team-scoped RLS on every table. Every table has team_id, RLS policy checks membership via `(SELECT auth.uid())`. All tables have RLS enabled. Never use `USING (true)`.

## Voice and copy rules
- British English (colour, organisation, recognise)
- No em dashes, no en dashes, no ellipses in the UI
- "Partner" not "client" in customer facing copy
- "Programme" not "product" when referring to a partner's insurance offering

## Design language
- Dark mode first with light-mode toggle in top right
- Dense info tables like Attio and Linear, not Salesforce
- Primary colour: Pier navy #11144D
- Accent: gold #FFAE00
- Font: Inter throughout, no font mixing
- Row heights 32 to 40px for tables
- Sticky filter bar on all list views

## Pages
1. Today (landing after login)
2. Companies list (browse)
3. Company detail (unified page: overview, contacts, outreach, notes, timeline)
4. Contacts list (browse)
5. Contact detail (linked to their company page)
6. Outreach Log (all touches)
7. Reconciliation Queue (duplicate candidates review)
8. Archive (promoted-to-Monday companies)
9. Insights (auto-generated dashboards)
10. AI Query (natural language SQL, optional)

## The 20 UX decisions
Brad has locked 20 UX decisions on 2026-07-08. Reference the `docs/pier-lovable-ux-decisions.md` file in the repo for the canonical list. Highlights:
- Today tab as landing
- Split-screen list plus detail for Company and Contact pages
- Inline edit on Priority, Owner, Status, Research Stage pills
- Structured draft rejection feedback + Lovable AI edit option
- Kanban toggle for CRM subset (default table view)
- Cmd+K quick search
- Saved views
- Bulk multi-select actions
- Draft status as top-level tabs in Outreach Log (Pending Review / Approved / Sent / Rejected)
- Sticky filter bar
- Message threads read like a conversation
- Live agent status widget on Today tab
- Cost tracker on Today tab
- Dark mode toggle
- Mobile responsive without breaking desktop
- No keyboard shortcuts for V1 (Brad said skip)
- No user-facing similar-companies (backend only)

## What NOT to build
- No BD Targets as a separate tab (make it a saved view of Companies with Insurance Offered = No)
- No Actions tab (consolidate entirely into Outreach Log)
- No Insights or AI Query in main nav (move to a menu or Today tab card)
- No two-way Monday sync visibility for V1 (V2 or later)
```

## 3. The founding prompt

Add to Lovable's chat interface in Plan Mode. Sized 380 words per research findings.

```markdown
# Context
I am building a bespoke B2B CRM for Pier Insurance, a UK insurance broker offering embedded gadget insurance to retailer partners. This is called Pier Lead Lake. It replaces an Excel workbook plus a stripped-down previous Lovable prototype.

Users: 3 to 6 sales and ops people at Pier. Primary user is Oliver Müller (Sales, DACH). Data volume at v1: about 420 companies, 261 contacts, 222 outreach touches. Growing to ~2000 companies over 12 months.

Stack: Lovable frontend, Supabase Postgres 17 for the backend (project qzfrcfzeiagziqjnfarw, already provisioned in eu-west-1), Make.com for external CRM sync, PhantomBuster for LinkedIn sends and inbox tracking. Design language matches Attio and Linear: dark-mode-first, dense info tables, navy #11144D and gold #FFAE00 accents, Inter typography.

# Data model
See the Project Knowledge Base for the full schema. Highlights:
- companies (39 fields plus 5 build fields), FKs to pier_pipeline and eurefas_members reference tables for cascade lookups
- contacts (31 fields), FK to companies, unique on lower(email)
- outreach_log (18 legacy fields plus 12 agent-managed fields), FKs to contacts and companies, thread_id for grouping
- Reference tables (pier_pipeline, eurefas_members) already populated
- Supporting tables (agent_handover, nightly_summary, agent_errors, blocklist, drafts_feedback, duplicate_candidates, saved_views, insights_snapshots)
All FK columns are btree indexed. pg_trgm enabled. GIN indexes on lower(company_name) and lower(email).

# Auth and RLS
Team-scoped RLS on every table. Membership check via fn_user_teams() function. All auth.uid() wrapped in `(SELECT auth.uid())`. Never use user_metadata in policies. RLS is enabled on every table already.

# Pages
1. Today (landing)
2. Companies list (split-screen with sticky filters, saved views, Kanban toggle)
3. Company detail (unified page: overview, contacts, outreach thread-grouped, insurance products, timeline)
4. Contacts list
5. Contact detail (linked to Company)
6. Outreach Log (top-level tabs Pending Review / Approved / Sent / Rejected, AI edit option on drafts)
7. Reconciliation Queue (duplicate candidates review, HubSpot-style side-by-side)
8. Archive (companies where archived_at is not null, read-only)
9. Insights (auto-generated)

# UI style
Dark mode first with light-mode toggle. Sticky filter sidebar. Split-screen list plus detail. Dense tables (Attio/Linear). Bulk selection via row checkboxes. Cmd+K quick search. Inline edit on Priority, Owner, Status, Research Stage pills.

# Constraints
- Every list uses .range() and shows total count.
- Every child collection query is separately keyed in TanStack Query.
- No client-side N+1: use PostgREST nested selects.
- No SECURITY DEFINER views exposed via API.
- All Realtime subscriptions clean up on unmount.
- Never ship bulk-merge without an undo path.
- Server-side code hits port 6543 (Supavisor), never 5432.

# Extras
Please ask me any clarifying questions before starting. Start with the Today page and Companies list only. Do not build Contacts, Outreach, or Reconciliation yet. When you propose the schema, verify it matches what is already in the Supabase project (already migrated).
```

## 4. Post-founding iteration plan

After Plan Mode confirms the founding prompt approach and you flip to Default Mode, iterate section by section. One prompt per section. Verify each before moving on.

### Section 01: Today tab

```markdown
Update: build out the Today tab as the landing page after login.

Layout:
1. Header row: "Good morning, [user first name]. Today is [day name, date]."
2. Row of 4 metric cards:
   - Nightly Run (with green dot if today's run completed, red if failed, grey if not yet run). Show run duration in minutes.
   - Drafts Awaiting Review (count, click navigates to Outreach Log > Pending Review tab)
   - Replies Overnight (count, click navigates to Outreach Log filtered on reply_received_at >= today-1)
   - API Cost (today's total in £, this month's total, and cap remaining)
3. Left column, 60% width: Recent nightly runs table (last 7 days). Columns: date, companies triaged, companies deep researched, drafts produced, drafts lint failed, errors caught, API cost. Query via keyed TanStack Query.
4. Right column, 40% width, sections stacked:
   - Warm Leads Ready to Promote (companies with recent Positive Interest replies, click to jump)
   - Errors Last 24h (from agent_errors, click expands with context)
   - Active Agent Status (if a run is currently in progress, show progress; else "No run in progress")

Data queries:
- nightly_summary ordered by run_date DESC limit 7
- outreach_log where draft_status = 'pending_review'
- outreach_log where reply_received_at >= today minus 1 day
- agent_errors where created_at >= today minus 1 day
- outreach_log where reply_classification = 'Positive interest' AND reply_received_at >= today minus 3 days

Do not touch any other page.
```

### Section 02: Companies list

```markdown
Update: build out the Companies list tab.

Data source: companies table where archived_at is null.

Layout: split-screen. Left panel: filter sidebar (240px wide, sticky, collapsible). Middle: companies table (fills available width). Right: detail panel (hidden until a company is selected, then 40% width).

Sticky filter sidebar sections (all collapsible, saved state to localStorage):
- Search box (searches company_name, website_url, usp_notes via pg_trgm)
- Priority (multi-select checkboxes: P0, P1, P2, P3, OoS, Competitor)
- Research Stage (multi-select)
- Country (multi-select, populated from distinct(country))
- Category (multi-select from company_category enum)
- Insurance Offered (Yes/No/Unknown radio)
- Owner (Oliver/Phil/Mark checkboxes)
- Opportunity Status (multi-select)
- Product Line (Pier Protect/Ticketplan/TIGA/Multiple/Unknown)
- "Reset filters" button at bottom

Table columns visible by default:
company_id, company_name (with website link icon), country, category, priority (colour coded pill: P0 grey, P1 red, P2 amber, P3 green, OoS light grey, Competitor purple), research_stage, insurance_offered, owner, opportunity_status, last_refreshed, contacts_count

Column picker in the table header lets user toggle any of the 39 columns. Persist to localStorage.

Row actions:
- Click row: opens split-screen detail panel on right (do not navigate)
- Cmd+click row: opens full-page company detail in new tab
- Checkbox column left of company_name: enables bulk select
- Bulk action bar appears at top when >0 rows selected: "Change Priority", "Change Owner", "Change Research Stage", "Export", "Archive"

Inline edit: click the Priority pill in any row, dropdown appears in place, saves on select. Same pattern for Owner, Research Stage, Opportunity Status.

Sorting: click any column header to sort. Default sort: priority ASC then priority_score DESC.

Pagination: .range() with 50 rows per page. Show "N of TOTAL companies" at bottom.

Query pattern:
supabase.from('companies').select('*', { count: 'exact' }).is('archived_at', null).range(from, to).order(...)
```

### Section 03: Company detail page (unified view)

```markdown
Update: build the Company detail page.

Entry points: click a company row from Companies list (opens in split-screen right panel) OR direct URL /companies/:id (opens full page).

Data: single PostgREST embed query:
supabase.from('companies')
  .select(`
    *,
    contacts(*),
    outreach:outreach_log(*, contact:contacts(first_name, last_name, linkedin_url)),
    products:insurance_products(*, insurer:insurers(insurer_name))
  `)
  .eq('id', :id)
  .single()

Header: company_name (h1), tracking flag badges inline (Live Partner green, Live Prospect amber, In Lovable blue, EUREFAS purple), Priority pill (colour coded), Research Stage pill, Country. Right side: pinned actions (Edit, Promote to Monday, Delete with confirm).

Tabbed sections inside the page (shadcn/ui Tabs, URL synced):
1. Overview (default): all 39 fields grouped into 8 sections matching Excel form (Company Info, Priority & Research, Product Offerings, Geography & Structure, Financial & Market Data, Insurance Capture, Opportunity & Notes, Industry Meta). Fields editable inline. Save on blur or Cmd+S.
2. Contacts (badge shows count from contacts_count): mini table of related contacts with columns first_name, last_name, job_title, connection_status, outreach_status. Click a contact opens the Contact detail page. "Add Contact" button.
3. Outreach (badge shows count of outreach rows): grouped by contact then by thread, chronological, most recent first. Each thread shows contact name at top, then messages chronologically with visual reply-indent. Reply detection: message_body content plus outcome plus reply_classification. AI Edit button on any Draft-status message.
4. Notes: read-only chronological view of usp_notes + additional_notes + background_notes, parsed by [YYYY-MM-DD] prefixes.
5. Insurance Products: mini table with insurer name, product types, monthly price, annual price, customer journey.
6. Timeline (V1.1, defer): auto-generated story of the company from company_created_at through most recent touch.

For V1, tabs 1 through 5. Timeline skipped.

Actions:
- Promote to Monday button: opens modal, on confirm sets archived_at = now(), archive_reason = "Promoted to warm CRM (Monday)", generates a Monday create URL with pre-filled data, opens in new tab. Company disappears from Companies list, appears in Archive.
- Delete: confirmation modal, then DELETE. RLS will scope.

Do not touch other pages.
```

### Section 04: Contacts list

```markdown
Update: build the Contacts list.

Same split-screen pattern as Companies. Filters: All Companies (searchable dropdown), Seniority, Connection Status, Outreach Status, Function, Country, SN Lists, Do Not Contact toggle.

Default columns: contact_id, first_name, last_name, company_name (join via company_id), job_title, seniority, connection_status, outreach_status, last_contacted, next_action_date (with warning icon if overdue).

Inline edit on connection_status, outreach_status, do_not_contact.

Row click opens split-screen Contact detail panel.

Cmd+K quick search across first_name, last_name, job_title, and company_name.
```

### Section 05: Contact detail page

```markdown
Update: build the Contact detail page.

Layout similar to Company detail but focused on the person.

Header: full name, job title, company name (link to Company page), seniority pill, country flag, language pill (EN/DE), formality pill (Sie/du).

Tabs:
1. Overview: all 31 fields grouped into sections (Personal, Role, LinkedIn, Company Relationship, Outreach State, Notes).
2. Company: embedded mini-view of the parent Company with link to full Company page.
3. Outreach Touches: all messages sent to and from this contact chronologically, grouped as a thread. Reply-indent for their replies.
4. Timeline (V1.1, defer)

Do not touch other pages.
```

### Section 06: Outreach Log

```markdown
Update: build the Outreach Log tab.

Top-level tabs (not a dropdown filter): Pending Review (badge count) | Approved | Sent | Rejected | All. Draft status determines which tab a row appears in.

For each tab, list of touches with columns: touch_id, contact name (join), company name (join), channel, touch_type, date, message_body (truncated 100 chars), send_status, pre_lint_pass (green tick or red flag).

Row click opens Draft Detail drawer (or split-screen):
- Full message_body in monospace preserving line breaks
- Pre-lint pass status prominently: green tick with score, or red flag with voice_contract_violations expanded
- Recommended frame and arc shown as pills
- Path A/B/C shown
- Reply content and reply_classification if received
- Rejection feedback shown if rejected

Actions on the Draft Detail:
- Approve and Copy: copies message_body to clipboard, sets draft_status = approved, records timestamp
- Reject with Feedback: opens structured form (reason dropdown: Voice off/Fact wrong/Framing wrong/Timing wrong/Register wrong/Other, plus detail text, plus optional suggested_alternative). Writes to drafts_feedback table. Sets draft_status = rejected.
- Edit with AI: opens Lovable's AI edit interface with the current message_body plus context (contact/company details), lets user prompt "shorter", "more formal", "translate to German", saves new version
- Manual Edit: plain text editor, save creates new version, links via supersedes_touch_id
- Mark as Sent: sets sent_at = now, moves to Sent tab
- Mark as Superseded

Message threads: in the All tab, group by thread_id. Show as email-thread-style with indentation for replies.

Do not touch other pages.
```

### Section 07: Reconciliation Queue

```markdown
Update: build the Reconciliation Queue tab. This is Lovable's biggest weakness per research; keep it minimal for V1.

Data: duplicate_candidates table WHERE status = 'pending', ordered by match_score DESC.

Layout: side-by-side comparison per HubSpot pattern.

Top: filter tabs (Companies | Contacts) plus match score threshold slider.

For each candidate, two-column view:
- Left column: Record A (primary label, editable)
- Right column: Record B
- Swap Primary button between them (Attio pattern)
- Per-field radio buttons: pick winner or "keep both" or "keep null"
- Show match score prominently at top: e.g. "0.87 similarity (name + domain match)"
- Actions: Merge (with confirmation), Reject (marks status = rejected with reason dropdown), Skip

Bulk actions bar: Bulk Reject only. NO bulk merge (per research and Oli's rules).

Confirmation modal on Merge: "This action is permanent and cannot be undone. Are you sure?" plus explicit undo warning.

Do not touch other pages.
```

### Section 08: Archive

```markdown
Update: build the Archive tab.

Data: companies WHERE archived_at IS NOT NULL, ordered by archived_at DESC.

Same columns as Companies tab plus archived_at date and archive_reason.

Read-only: no edit inline, no delete, no bulk actions.

Toggle at top-right: "Show archived in main Companies view" (persists to localStorage, affects Companies list filter default).

Filters: All Countries, All Archive Reasons, search across company_name.

Row click opens read-only Company detail (all fields disabled).

Do not touch other pages.
```

### Section 09: Insights (V1.1, optional for V1)

Skip for V1. Note in the section-prompts/09-insights.md that this is deferred pending V1 stability.

## 5. Safety checks after every section

After each section prompt is applied and Lovable finishes generating, run these before moving to the next section:

1. **Visual check in Lovable preview**: does the section render? Any obvious layout breaks?
2. **RLS audit via Supabase MCP (Claude Code)**:
   ```sql
   SELECT tablename, policyname, cmd, qual, with_check
   FROM pg_policies
   WHERE schemaname = 'public'
   ORDER BY tablename;
   ```
   Any policy with `qual` containing "true" without a scoping condition is a leak. Halt and fix.
3. **N+1 audit**: open browser dev tools Network tab in Lovable preview, click a row, count Supabase requests. If more than 2 (one for the list, one for the detail), the query is N+1. Prompt again to consolidate into a nested select.
4. **Pagination audit**: verify each list query has `.range()` and shows a total count. If it says "Loading" or "Showing all" without a count, prompt again to add pagination.
5. **Anon key leak test**: attempt a curl against the Supabase REST endpoint using the anon key. Should return only rows the RLS policy allows.

## 6. Handoff back to Claude Code for reconciliation

After every 2 to 3 sections, run:
- `list_tables` verbose against the Supabase project
- Verify Lovable has not added any tables you did not spec
- If Lovable added a table, decide: keep or drop. If keep, add to migration spec so it is documented.
- If dropped, DROP TABLE via Claude Code migration.

Never let Lovable's schema drift silently. Every schema state should be reproducible from migrations in the repo.

## Common Lovable prompting gotchas to avoid

Per research:
1. Do not use lorem ipsum or "Feature 1" placeholders. Use real Pier content.
2. Do not batch 5 unrelated tasks into one prompt.
3. Do not hit "Try to Fix" more than 3 times. If it fails, switch to Chat Mode with "use chain-of-thought reasoning to identify the root cause".
4. Do not paste the full spec into one prompt. Section by section.
5. Do not skip Plan Mode for anything non-trivial.
6. Do not let Lovable set RLS policies unaudited.
7. Do not connect OAuth via Lovable Cloud; connect directly via Supabase.
8. Do not use TanStack Query defaults for stale time. Set explicit staleTime per query.
9. Do not use Realtime subscriptions without an unmount cleanup.
10. Do not ship any bulk-merge without an undo path.

## Timeline

If Brad works at focused pace:
- Founding prompt in Plan Mode plus review: 30 min
- Section 01 (Today): 90 min including safety checks
- Section 02 (Companies list): 2 hours
- Section 03 (Company detail): 2 hours
- Section 04 (Contacts list): 90 min
- Section 05 (Contact detail): 90 min
- Section 06 (Outreach Log): 2.5 hours
- Section 07 (Reconciliation): 2 hours (largest risk area)
- Section 08 (Archive): 45 min

Total: about 14 focused hours across 2 to 3 working days.

Add another 2 to 3 hours per section for iteration and safety fixes. Realistic total: 20 to 25 hours to a shipped V1 Lovable UI.
