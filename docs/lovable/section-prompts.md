# Post-founding iteration plan — section prompts

After Plan Mode confirms the founding prompt approach and you flip to Default Mode, iterate section by section. One prompt per section. Verify each before moving on.

Each section below is a self-contained prompt to paste into Lovable after the founding prompt has been applied.

## Section 01: Today tab

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

## Section 02: Companies list

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

## Section 03: Company detail page (unified view)

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

## Section 04: Contacts list

```markdown
Update: build the Contacts list.

Same split-screen pattern as Companies. Filters: All Companies (searchable dropdown), Seniority, Connection Status, Outreach Status, Function, Country, SN Lists, Do Not Contact toggle.

Default columns: contact_id, first_name, last_name, company_name (join via company_id), job_title, seniority, connection_status, outreach_status, last_contacted, next_action_date (with warning icon if overdue).

Inline edit on connection_status, outreach_status, do_not_contact.

Row click opens split-screen Contact detail panel.

Cmd+K quick search across first_name, last_name, job_title, and company_name.
```

## Section 05: Contact detail page

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

## Section 06: Outreach Log

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

## Section 07: Reconciliation Queue

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

## Section 08: Archive

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

## Section 09: Insights (V1.1, optional for V1)

Skip for V1. This section is deferred pending V1 stability.
