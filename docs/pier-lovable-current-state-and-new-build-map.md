# Pier Lovable, current state analysis and new build map

Author: Brad Gordon (Nailed It AI)
Date: 7 July 2026
Classification: C2
Source: Walked the live UK Lovable at pierresearchproject.lovable.app on 7 July 2026

## Part 1: What the current UK Lovable actually is

### 1.1 Entity model

Four data tables surface in the UI. All others are derived.

1. **Companies** (70 rows). The main entity. Rich detail per row.
2. **Insurance Products** (15 rows). Join table between a Company and an Insurer with the product terms and customer journey narrative.
3. **Insurers / Underwriters** (15 rows). Auto generated from Product data. AIG, Argos Care, Apple Care, Assurant, etc.
4. **Actions** (3 rows). Lightweight touch log tied to a Company. Effectively a proto Outreach Log.

Notably absent:
- No **Contacts** entity at all
- No true **Outreach Log** with channel, message content, replies
- No **Archive** view for promoted to Monday
- No **agent handover** table
- No **Country coverage beyond UK** (a handful of exceptions like Refurbed Ireland, Swappie Finland, Tradeinn Spain)

### 1.2 Companies tab, the full picture

**Header actions**: Add Company, Add Insurance Product, Add Insurer, Logout

**Filters (16 total across 3 rows)**:
- Row 1: All Categories, All Countries, All Insurance, All Types, All Structures, All Distribution, All Revenue, All Traffic
- Row 2: All Parents, All HQ Locations, All Selling Countries, All Providers, All Refurbished, All Sim-Free, All Owners
- Row 3: All Statuses

**Toggle**: CRM View (swaps which column subset is visible)

**Search**: by company name

**Columns (20 visible)**:
1. Company (with external website link icon)
2. Country
3. Category
4. Monthly Visits (sortable)
5. Revenue (sortable)
6. Employees (sortable)
7. Traffic (sortable, separate from Monthly Visits, unclear why both)
8. Credit Rating (sortable)
9. Refurbished (Yes/No)
10. Sim-Free (Yes/No)
11. Insurance (Yes/No)
12. Provider (brand name, e.g. Argos Care)
13. Linked Products (link to Products table)
14. Insurer (underwriter name, e.g. Aviva)
15. Owner (Phil / Mark / Oliver)
16. Status (Not started / Contacted / In conversation / Target / Researching)
17. CRM Actions (L: date, N: date, warning icon if overdue)
18. Priority Score (NUMERIC, e.g. 14, 12, 17)
19. Research Notes (free text, often multi-line)
20. Actions (edit + delete buttons per row)

### 1.3 Company detail modal (Edit Company)

Full field set organised into sections:

**Company Information**
- Company Name (required)
- Website URL
- Country (single select dropdown)
- Category (MULTI select from Pure Online Phone Retailer / Refurbished Specialist / Electronics Multi-Category / Marketplace Comparison Site / Operator Manufacturer)

**Product Offerings**
- Refurbished Offered? (Yes/No)
- Sim-Free Devices? (Yes/No)

**Company Geography & Structure**
- Parent / Group Company
- Headquarter Location
- Countries Selling In

**Financial & Market Data**
- Estimated Revenue (£)
- Employees
- Monthly Visits (I saw 270000 for 4Gadgets)
- Creditsafe Rating (I saw 92 for 4Gadgets)

**Insurance Capture**
- Insurance Offered? (Yes/No dropdown)

**Opportunity & Notes**
- Opportunity Status (To Review / other)
- USP / Notes (multiline)
- Contact Info (single line, blank)
- Research Notes (multiline)

**Buttons**: Cancel / Update Company

### 1.4 CRM tab

**Purpose**: Pipeline subset. 11 of 70 companies (those with active engagement).

**Columns**:
- Company
- Owner
- Status (In conversation / Not started)
- Owner Notes ("Meeting Arranged for 26th March")
- Actions column showing L: date, N: date

**Filters**: All Owners, All Statuses (only 2)

### 1.5 Actions tab

**Purpose**: Lightweight touch log. Very basic.

**Columns**:
- Company
- Type (Next / Last, with warning icon for overdue)
- Date/Time
- Note (free text)
- Owner
- Status

**Filters**: All Types, All Owners, All Statuses, All (fourth filter)

**Button**: + Add Action

**Only 3 rows populated.** This is the proto Outreach Log but nowhere near full.

### 1.6 BD Targets tab

**Purpose**: The subset of companies WITHOUT insurance, sorted by priority score, top first.

**Header**: "BD Targets - No Insurance Offered", 55 companies shown, subtitle "In-scope companies without insurance, sorted by priority score (highest first)"

**Columns**:
- Priority (numeric score in dark circle, e.g. 17, 16, 16, 16)
- Company
- Category
- Region
- Monthly Visits
- Revenue (£)
- SIM-Free
- Refurbished
- Next Action (all showing "Research")

### 1.7 Products tab

**Purpose**: Insurance product catalogue.

**Header**: "Insurance Products", 15 shown, subtitle "Products synced from company forms and direct entries"

**Filter**: All Insurers

**Columns**:
- Company
- Insurer
- Product Types (tag chips: Accidental Damage, Theft, Extended Warranty, Screen Damage)
- Structure (Optional Add-On)
- Customer Journey (long narrative describing PDP > Cart > Checkout flow)
- Monthly (£)
- Annual (£)
- Distribution (narrative)

**Example**: Aznu (MTR Group LTD) x Argos Care, £5.69 monthly / £68.28 annual, Accidental Damage + Theft, Optional Add-On.

### 1.8 Insurers tab

**Purpose**: Underwriter catalogue.

**Header**: "Insurance Companies & Underwriters", 15 shown, subtitle "Insurers are automatically created from company insurance data"

**Columns**:
- Insurer Name
- Total Products (count)
- Total Companies (list, e.g. "iStore, KRCS")
- Distribution Model (narrative, e.g. "via add to basket flow")
- Customer Journey (long narrative)
- Website
- Notes
- Actions

### 1.9 Insights tab

**Purpose**: Auto generated market analysis. Read only.

**Header**: "Market Insights", subtitle "Auto-generated analysis from current data"

**Sections observed**:
- Insurance Penetration by Traffic (total monthly visits with vs without insurance)
- Theft Coverage Prevalence (Insurers covering Theft: 10 of 15 = 67%)
- AO Retail Ltd Opportunity (aggregated view of the AO group across 4 subsidiary companies)

Presumably scrolls further with more auto-generated insights.

### 1.10 AI Query tab

**Purpose**: Natural language SQL over the data.

**Header**: "AI Data Query", subtitle "Ask questions about your data in natural language. The AI will convert your question to SQL and return the results."

**Example queries as clickable chips**:
- "What is the average traffic for all companies with no insurance?"
- "Show me companies with insurance that are not in the electronics category"
- "How many companies offer theft coverage?"
- "List companies with traffic over 100000 sorted by revenue"

### 1.11 Dashboard tab

**Purpose**: Analytics landing page. Read only.

**4 metric cards**:
- Total Companies: 70 (in-scope retailers tracked)
- % Without Insurance: 78.6% (55 companies without insurance)
- Avg Monthly Traffic: 407,320
- Top Provider: Argos Care & Apple Care & Aviva (2 partnerships)

**Charts**:
- Companies by Category (pie): Electronics/Multi-Category 40%, Refurbished 37%, Pure Online 13%, Operator/Manufacturer 10%
- Insurance Penetration by Category (stacked bar)
- Top 10 Companies by Monthly Visits (Samsung, Webuy CeX, QVC UK, Giffgaff, AO, Tradeinn, Amazon, Nothing Tech, Google Store UK, Back Market)
- Revenue Distribution (stacked bar across £1M / £5M / £10M / £50M / £50M+ bands)

## Part 2: Gap analysis, current Lovable vs Oli's build spec

### 2.1 Fundamental data model gaps

| What Oli's build needs | Current UK Lovable | Gap |
|---|---|---|
| Priority = P0/P1/P2/P3/OoS/Competitor enum | Priority Score = numeric (17, 16, 14) | Add enum column, keep numeric as computed sort |
| Research Stage = Untouched/Light triage/Deep research done/Outdated | Opportunity Status conflates research + engagement | Add explicit Research Stage column |
| CoID = Cnnn sequential | Row ID exists but not visible in UI | Surface CoID column |
| Category = single enum per Companies Agent rules | Category = multi-select | Small deviation, keep multi-select (more forgiving in Lovable) |
| Insurance State = Greenfield/Annual recurring/Monthly recurring | Not captured at all | Add column |
| Size Tier = T1/T2/T3 | Not captured at all | Add column (with derived proxy method note) |
| Full Contacts entity | Does not exist | Build entirely new |
| Full Outreach Log (channel/message/replies/status) | Actions tab is 3 rows and lightweight | Rebuild as proper Outreach Log |
| Archive view (promoted to Monday) | Does not exist | Add archived_at + archive_reason columns plus Archive tab |
| agent_handover table | Does not exist | Add table plus minimal UI for open items |
| Ticketplan / Product Line dimension | Does not exist (Pier Protect implicit) | Add Product Line column (Pier Protect / Ticketplan / Multiple) |
| Country coverage beyond UK | Ireland/Finland/Spain as exceptions, dominantly UK | Expand to full DACH + EU |
| Reconciliation with Monday CRM | Does not exist | Add Reconciliation summary tab |

### 2.2 Features to KEEP from current Lovable

Do not reinvent these. They work well.

- Rich Companies table with 20+ columns
- 16 filters
- CRM View toggle (column set switcher)
- Products as separate related table
- Insurers as auto-generated related table
- Customer Journey narrative field in Products
- Auto-generated Insights tab
- AI Query natural language SQL
- BD Targets cohort view (companies without insurance)
- CRM tab pipeline subset
- Dashboard analytics cards + charts
- L: / N: date columns for Last/Next contact
- Owner notes as a distinct short field
- Priority Score (numeric) as a supplementary metric alongside the P0/P1 enum

### 2.3 Features to ADD

New to build in the pan European Lovable.

- **Contacts tab** with columns: Contact ID (Pnnn), First Name, Last Name, LinkedIn URL, Job Title, Seniority, Company (foreign key), Email, Phone, Connection Status, Outreach Status, Path (A/B/C), Do Not Contact toggle, Source Phantom, Last Contact At, Created At
- **Full Outreach Log tab** with columns: Draft ID, Contact, Company, Channel (LinkedIn/Email), Message Type (CR/DM/inMail/reply/event follow-up), Draft Content, Draft Status (pending_review/approved/sent/rejected/superseded), Pre-lint Pass (bool), Voice Contract Violations (JSON), Path (A/B/C), Frame, Arc, Draft Created At, Sent At, Reply Received At, Reply Content, Reply Classification, Rejection Feedback
- **Archive tab** showing archived companies (archived_at IS NOT NULL) with archive reason, read only, toggle to include in Companies search
- **Priority column** with P0/P1/P2/P3/OoS/Competitor enum (colour coded)
- **Research Stage column** with Untouched/Light triage/Deep research done/Outdated
- **Insurance State column** with Greenfield/Annual recurring/Monthly recurring (inline text notes in USP/Notes acceptable for V1 walking skeleton)
- **Size Tier column** with T1/T2/T3 plus estimation proxy method note
- **Product Line column** with Pier Protect / Ticketplan / Multiple / Unknown
- **agent_handover** minimal UI showing open items across agents
- **Reconciliation tab** showing daily Lovable vs Monday overlap summary
- **Promote to Monday button** on each company detail
- **Nightly run summary card** on Home/Dashboard showing latest agent run stats
- **CCE qualifying test result** visible on Company detail (Yes/No/Uncertain, with reason)

### 2.4 Features to CHANGE

- Rename "Insurance" column to "Insurance Offered?" (matches Oli's schema)
- Rename "CRM Actions" to "Last / Next Touch" (clearer)
- Change Priority Score to be COMPUTED from traffic + revenue + fit, keep as secondary sort; primary Priority is the enum
- Change Statuses to match Oli's spec exactly: To Review / Prospect / Contacted / Active Lead / Partner / Out of Scope
- Extend Country dropdown from mostly UK to full EU + DACH + UK plus a "Rest of World" bucket for OoS
- Add colour coding to Priority column: P0 red, P1 orange, P2 yellow, P3 grey, OoS light grey, Competitor purple

## Part 3: The connected data model for the new Lovable

Every table below is a Supabase table. Relationships shown by foreign keys.

### 3.1 companies

Existing 39 column schema per Oli's Companies Agent bootstrap (A through AM). Plus 4 new columns for the new build:
- `archived_at` (timestamp, nullable)
- `archive_reason` (text, nullable)
- `created_at` (timestamp, default now)
- `updated_at` (timestamp, default now)

### 3.2 contacts (NEW)

Foreign key: `company_id` references `companies.id`

Columns:
- id (uuid PK)
- contact_id (Pnnn sequential)
- company_id (FK to companies)
- first_name
- last_name
- linkedin_url
- job_title
- seniority (enum: C-level / Head of / MD / Director / Manager / Other)
- email (nullable)
- phone (nullable)
- connection_status (enum: Not connected / CR sent / Connected / Ignored / Withdrawn)
- outreach_status (enum: Not started / DM sent / Replied / Booked / Bounced / Do not contact)
- path (enum: A / B / C, owned by Outbound Agent)
- do_not_contact (bool)
- source_phantom (enum: Sales Nav / Recently Connected / LinkedIn Inbox / Manual)
- source_run_id
- last_contact_at (timestamp, nullable)
- created_at
- updated_at

### 3.3 outreach_log (NEW)

Foreign keys: `contact_id` references `contacts.id`, `company_id` references `companies.id`

Columns:
- id (uuid PK)
- contact_id (FK)
- company_id (FK)
- channel (enum: LinkedIn / Email)
- message_type (enum: connection_request / first_dm / cold_inmail / reply / event_follow_up)
- draft_content (text)
- draft_status (enum: pending_review / approved / sent / superseded / rejected)
- pre_lint_pass (bool, must be true before draft_status can be pending_review)
- voice_contract_violations (jsonb, list of linter flags)
- path (enum: A / B / C, set by Outbound Agent)
- recommended_frame (enum: Discovery / Diagnostic / Alternative / Ally / Peer)
- recommended_arc (enum: A / B / C / D / E)
- draft_created_at
- sent_at (nullable)
- reply_received_at (nullable)
- reply_content (nullable)
- reply_classification (nullable, enum: Positive interest / Neutral / Objection / Not interested / OOO / Wrong person / DNC)
- rejection_feedback (nullable, text, Oli's feedback when rejecting a draft, feeds Capture Processor)

### 3.4 insurance_products (KEEP existing, minor changes)

Existing table from current Lovable. Rename to match Supabase snake_case convention if needed.

### 3.5 insurers (KEEP existing)

Existing table, auto generated from Products.

### 3.6 actions (SUPERSEDED by outreach_log)

Migrate existing 3 rows into outreach_log as message_type = 'event_follow_up' or similar, then deprecate the actions table.

### 3.7 agent_handover (NEW)

Columns:
- id (uuid PK)
- from_agent (enum: companies / contact / outbound / outreach / reconciliation / coordinator)
- to_agent (same enum)
- request_type (enum: create_c_row / verify_match / correct_match / update_insurance_state / update_contact_status / other)
- payload (jsonb)
- status (enum: open / resolved / blocked)
- created_at
- resolved_at (nullable)
- resolution_marker (text, "[CompA verified 2026-07-15] ...")
- resolved_by_agent (nullable)

### 3.8 nightly_summary (NEW)

Written by the Coordinator at end of each nightly run. Feeds the Home tab summary card.

Columns per the build doc section 6.3.

### 3.9 blocklist (NEW)

Do Not Contact list. Companies/Contacts flagged never to reach out.

Columns:
- id, entity_type (company/contact), entity_id, reason, added_at, added_by_agent

## Part 4: Lovable prompts for the new build

Draft these in order. Paste one at a time into a FRESH Lovable project (create `pier-lead-lake` pointing at pier-lead-lake-prod Supabase). Verify each before moving to the next.

### Prompt 0, initial project setup

```
Create a pan European CRM for Pier Insurance Managed Services Ltd, replacing our current UK-only Lovable. This is the Pier Lead Lake, a Supabase-backed system.

Style: clean, dense, B2B SaaS aesthetic similar to Attio or Linear. Not Salesforce. Use Inter font. Support dark mode toggle in the top right. Primary brand colour: Pier navy #11144D. Accent: gold #FFAE00.

Set up top navigation with these tabs in this order:
- Dashboard (summary and charts, similar to current Lovable dashboard)
- Companies (main working tab)
- Contacts (NEW)
- Outreach Log (NEW, replaces the Actions tab from current Lovable)
- BD Targets (kept from current Lovable, no-insurance cohort)
- Products (kept from current Lovable, insurance products catalogue)
- Insurers (kept from current Lovable, underwriter catalogue)
- Archive (NEW, promoted-to-Monday companies)
- Insights (kept from current Lovable, auto-generated)
- AI Query (kept from current Lovable, natural language SQL)

Top action bar (right side):
- Add Company
- Add Contact (NEW)
- Add Outreach Draft (NEW)
- Add Insurance Product
- Add Insurer
- Logout

Do not create Supabase tables yet. Assume migrations are applied separately. Just build the navigation shell and empty tab placeholders.
```

### Prompt 1, Companies tab

```
Build the Companies tab.

Source table: Supabase table `companies` (39 columns per attached schema, plus archived_at, archive_reason, created_at, updated_at). Default filter: WHERE archived_at IS NULL.

Table columns visible by default:
1. Company ID (Cnnn)
2. Company Name (with external link icon to Website URL)
3. Country
4. Category
5. Priority (colour-coded enum: P0 red bg, P1 orange, P2 yellow, P3 grey, OoS light grey, Competitor purple)
6. Research Stage
7. Insurance Offered? (Yes/No/Unknown)
8. Insurance State (Greenfield / Annual recurring / Monthly recurring)
9. Size Tier (T1 / T2 / T3)
10. Owner
11. Opportunity Status (colour coded)
12. Last / Next Touch (L: date, N: date with warning icon if overdue)
13. Priority Score (numeric, computed from traffic + revenue + fit)
14. Actions (edit + promote-to-Monday buttons)

Column picker in top right lets user toggle ANY of the 39 columns on/off. Persist choice to localStorage.

Filters (grouped in a collapsible bar at top, matches current Lovable pattern):
- Row 1: All Categories, All Countries, All Insurance, All Types, All Structures, All Distribution, All Revenue, All Traffic
- Row 2: All Parents, All HQ Locations, All Selling Countries, All Providers, All Refurbished, All Sim-Free, All Owners, All Priorities
- Row 3: All Statuses, All Research Stages, All Insurance States, All Size Tiers, All Product Lines

Search: by Company Name, Website URL, and USP/Notes.

Sort: by any column. Default sort: Priority (P0 first), then Priority Score descending.

Row click opens Company Detail drawer (build in next prompt).

Pagination: 50 rows per page. Row count shown at bottom.

Toggle in top right: "CRM View" swaps between full research columns and pipeline columns (matches current Lovable pattern).

Show "Companies shown: N" count next to search bar.
```

### Prompt 2, Company Detail drawer

```
Build the Company Detail drawer that opens when a company row is clicked.

Layout: right-side slide-in drawer, 60% width of viewport, scrollable.

Sections (collapsible):

1. Company Information
   - Company ID (Cnnn, read-only)
   - Company Name (required)
   - Website URL
   - Country
   - Category (multi-select)

2. Priority & Research
   - Priority (P0/P1/P2/P3/OoS/Competitor enum)
   - Priority Score (numeric, computed, read-only)
   - Research Stage (Untouched / Light triage / Deep research done / Outdated)
   - Owner (Oliver Müller / Phil / Mark)
   - Opportunity Status
   - Account Source

3. Product Offerings
   - Refurbished Offered? (Yes/No)
   - Sim-Free Devices? (Yes/No)
   - Product Line (Pier Protect / Ticketplan / TIGA / Multiple / Unknown)

4. Company Geography & Structure
   - Parent / Group Company
   - Headquarter Location
   - Countries Selling In

5. Financial & Market Data
   - Estimated Revenue (£)
   - Employees
   - Monthly Visits
   - Creditsafe Rating
   - Annual Devices Sold

6. CCE Qualifying Test
   - Sells Hardware? (Yes/No/Uncertain)
   - Test Result (CCE applies / Does not apply / Uncertain)
   - Test Reason (free text)

7. Insurance Capture
   - Insurance Offered? (Yes/No)
   - Insurance Provider / Underwriter
   - Product Type(s) (multi-select)
   - Insurance Structure
   - Monthly Price (£)
   - Annual Price (£)
   - Distribution Model
   - Coverage Summary
   - Customer Journey (long text, narrative)
   - Policy URL

8. Sales Qualifying
   - Size Tier (T1 / T2 / T3, with proxy method text below)
   - Insurance State (Greenfield / Annual recurring / Monthly recurring)

9. Notes
   - USP / Notes (multi-line)
   - Additional Notes (multi-line)
   - Contact Info
   - Source URLs (multi-line)
   - Last Refreshed (date)
   - Date Added (read-only)

Right-side action buttons pinned at top of drawer:
- Save
- Promote to Monday (opens confirmation modal, sets archived_at + generates Monday create URL)
- Delete (danger, confirmation modal)

Bottom section: RELATED
- Linked Contacts (mini table showing contacts where company_id matches, click to open Contact detail)
- Linked Insurance Products (mini table)
- Linked Outreach Drafts (mini table showing outreach_log rows where company_id matches)
- Agent Handover Items (open items in agent_handover table addressed to or from this company)
```

### Prompt 3, Contacts tab

```
Build the Contacts tab.

Source table: Supabase table `contacts` with foreign key to companies. Default filter: WHERE do_not_contact = false.

Table columns visible by default:
1. Contact ID (Pnnn)
2. First Name
3. Last Name
4. Company Name (via join to companies, click to open Company detail)
5. Job Title
6. Seniority
7. LinkedIn URL (icon link)
8. Connection Status
9. Outreach Status
10. Path (A / B / C)
11. Last Contact At
12. Source Phantom
13. Actions (edit)

Filters:
- All Companies (searchable dropdown)
- All Seniorities
- All Connection Statuses
- All Outreach Statuses
- All Paths
- All Source Phantoms

Search: by First Name, Last Name, Job Title, Company Name.

Row click opens Contact Detail drawer.

Contact Detail drawer sections:
1. Contact Info: Contact ID, First Name, Last Name, LinkedIn URL, Job Title, Seniority, Email, Phone
2. Company: linked Company Name with click-through to Company detail
3. CRM State: Connection Status, Outreach Status, Path, Do Not Contact toggle, Last Contact At
4. Source: Source Phantom, Source Run ID
5. Related: Outreach Log drafts for this contact (mini table)

No delete button (contacts should never be hard-deleted, only marked Do Not Contact).

Add "View Company" link that navigates to the linked Company detail.
```

### Prompt 4, Outreach Log tab

```
Build the Outreach Log tab. This REPLACES the current Actions tab entirely.

Source table: Supabase table `outreach_log` with foreign keys to contacts and companies.

Default sort: draft_status = pending_review first (at top), then sent, then superseded, then rejected. Within each group sort by draft_created_at descending.

Table columns visible by default:
1. Draft ID
2. Contact Name (via join, click to open Contact detail)
3. Company Name (via join, click to open Company detail)
4. Channel (LinkedIn / Email, colour coded)
5. Message Type
6. Draft Content (truncated to 100 chars, click to expand)
7. Draft Status (colour coded: pending_review yellow, approved green, sent blue, superseded grey, rejected red)
8. Pre-lint Pass (green tick or red flag)
9. Voice Contract Violations (count, click to expand)
10. Path (A / B / C)
11. Draft Created At
12. Sent At
13. Reply Received At
14. Reply Classification

Filters:
- All Statuses
- All Channels
- All Message Types
- All Paths
- All Reply Classifications
- Pre-lint Pass = true/false

Search: across Draft Content and Reply Content.

Row click opens Draft Detail drawer:
- Full draft_content in monospace, respecting line breaks
- Pre-lint pass status prominently at top (green tick or red flag with violations listed)
- Voice contract violations expanded if any
- Recommended Frame and Arc shown
- Path classification shown
- Reply Content and Reply Classification if received

Action buttons on drawer:
- Approve and Copy (copies draft to clipboard, marks approved)
- Reject with Feedback (opens feedback textarea, saves to rejection_feedback)
- Mark as Sent (records sent_at, moves to sent state)
- Mark as Superseded (if a newer draft supersedes this one)

Do not allow inline editing of draft_content (drafts are agent generated, human should approve or reject, not edit).
```

### Prompt 5, Archive tab

```
Build the Archive tab.

Source: Supabase table `companies` WHERE archived_at IS NOT NULL. Read only.

Same columns as Companies tab plus:
- Archived At date
- Archive Reason
- Monday Deal ID (if linked)

No edit actions. No delete actions. Toggle at top right: "Show archived in main Companies view" persists to localStorage.

Search across Company Name, Website URL, USP/Notes.

Filters: All Priorities, All Countries, All Archive Reasons.

Row click opens read-only Company Detail drawer (fields disabled).
```

### Prompt 6, Home / Dashboard tab

```
Build the Home / Dashboard tab.

Top section: Nightly Run Summary Card
- Reads latest row from `nightly_summary` table
- Shows: date of last run, companies triaged, companies deep researched, contacts matched, drafts produced, drafts lint failed, errors caught, API cost GBP
- If last run > 24 hours ago, show red banner "Last successful run: [X hours ago]. Check the agent."
- Show mini trend table of last 7 nights below the card

Middle section: 4 metric cards (matches current Lovable pattern)
- Total Companies (in-scope, excluding archived)
- % Without Insurance
- Avg Monthly Traffic
- Top Provider

Bottom section: Charts (match current Lovable pattern)
- Companies by Category (pie)
- Insurance Penetration by Category (stacked bar)
- Top 10 Companies by Monthly Visits (horizontal bar)
- Revenue Distribution (stacked bar)
- NEW: Priority Distribution (bar showing count per P0/P1/P2/P3/OoS/Competitor)
- NEW: Insurance State Distribution (bar showing count per Greenfield/Annual recurring/Monthly recurring)
```

### Prompt 7, BD Targets, Products, Insurers, Insights, AI Query

```
Keep the current UK Lovable implementation of these five tabs. Migrate the layout and logic verbatim, adapting only:
- BD Targets: sort by Priority enum first (P0 top), then Priority Score descending
- Products: no logic change
- Insurers: no logic change
- Insights: extend auto-generated analysis to include DACH-specific insights when data available
- AI Query: no logic change

All five source their data from the same Supabase tables. No new tables needed.
```

### Prompt 8, Reconciliation Agent summary card

```
Add a Reconciliation summary panel to the Home tab (V1.1, deferred from walking skeleton V1).

Source: Supabase table `daily_reconciliation` (written by Reconciliation Agent).

Shows:
- Companies flagged warm in Monday but still active in Lovable (Companies Agent guardrail check)
- Contacts duplicated across Lovable + Monday (dedupe review)
- Companies in Monday but missing from Lovable (backfill candidates)

Each item is clickable, opens the relevant detail drawer.
```

### Prompt 9, agent_handover mini panel

```
Add an "Agent Handover Queue" panel to the Home tab.

Source: Supabase `agent_handover` table WHERE status = 'open' ORDER BY created_at DESC LIMIT 20.

Show as compact list:
- From agent > To agent
- Request type
- Created at
- Payload preview (truncated)
- "Mark resolved" button

Also add badge to Companies, Contacts, Outreach Log tabs showing open handover item count addressed to that entity.
```

## Part 5: Order of operations for this afternoon

Given you have ~4 hours and the Excel workbook is still en route:

1. **Now**: Create a fresh Lovable project called `pier-lead-lake`, point it at pier-lead-lake-prod Supabase. Paste Prompt 0. Verify shell navigation works.
2. **When Excel arrives**: extract schema, apply Supabase migration for the 39 companies columns (plus new columns per section 3.1). Also apply migrations for contacts, outreach_log, agent_handover, nightly_summary, blocklist.
3. **Then**: paste Prompt 1 into Lovable. Wait for Companies tab build. Verify with test data.
4. **Then**: Prompt 2 (Company Detail drawer). Verify.
5. **Then**: Prompt 3 (Contacts). Verify.
6. **Then**: Prompt 4 (Outreach Log). Verify.
7. **Then**: Prompt 5 (Archive). Verify.
8. **Then**: Prompt 6 (Home/Dashboard). Verify.
9. **Then**: Prompt 7 (BD Targets etc from current Lovable). Verify.
10. **V1.1**: Prompts 8 and 9 (Reconciliation, Agent Handover).

## Part 6: Notes for Oli's review

Three things to flag with Oli when you show him the new Lovable:

1. **Priority Score numeric is being kept ALONGSIDE the P0/P1/P2/P3 enum, not replaced.** His Companies Agent bootstrap defines Priority as the enum. The current Lovable's numeric score becomes a secondary supplementary sort. Best of both worlds.

2. **Category becomes multi-select** (matches current Lovable behaviour). Oli's rules technically say single enum but multi-select is more forgiving in real cases (e.g. 4Gadgets is both Refurbished Specialist AND Electronics/Multi-Category Retailer).

3. **Insurance State and Size Tier become explicit columns** rather than being buried in USP/Notes. Better filtering in Lovable. His rules said keep in USP/Notes but I'd argue promoting them to columns is worth the small deviation.

Ask Oli which of these he wants to overrule. Adjust prompts if he pushes back.
