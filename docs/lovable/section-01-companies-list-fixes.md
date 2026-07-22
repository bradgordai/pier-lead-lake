# Lovable fix prompt: Companies list, six bugs

Paste into Lovable after the Section 01 upgrade. Scope is the Companies list and
Company Detail panel only.

Verified against Supabase before writing (see corrections inside the prompt):
- saved_views RLS is correct and permissive enough. Three rows already persisted.
- public.companies has 49 physical columns, of which 39 are the domain columns.
- priority_score, research_notes and "CRM Actions" do not exist in the schema.

---

```lovable-prompt
Fix six bugs in the Companies list and Company Detail panel. Do not touch other pages, auth, or the database schema. Do not create, drop or alter any table, column, enum or policy.

Voice rules apply to every piece of UI copy you write or touch: British English (colour, organisation, recognise), no em dashes, no en dashes, no ellipses.

# FIX 1: Encoding, currency and empty cells

Escape sequences are being rendered as literal text instead of characters. Revenue currently displays as £3,620,000,000 instead of £3,620,000,000.

1. Search the whole codebase for the literal strings £, —, –, … and any occurrence of \\u. Check the number formatter, the currency formatter, and every column renderer.
2. Replace each with the actual character: £ becomes £. Do not keep the escape sequence in a string literal where it will not be interpreted.
3. Currency columns (estimated_revenue_gbp, insurance_monthly_price, insurance_annual_price) render with a real £ prefix and thousand separators, right aligned.
4. Empty or null cells render as an EMPTY STRING. Do not render an em dash, an en dash, an ellipsis, "null", "N/A" or a placeholder glyph. A blank cell is correct.

Acceptance: revenue reads £3,620,000,000. A global search for £ and — returns zero results in rendered output.

# FIX 2: Saved Views

Important, verified in the database before you start: saving IS working. Three rows already exist in saved_views ("test", "default", "test2"), each with a valid user_id and team_id. The insert and the RLS policy are both fine. Do not rewrite them looking for a permissions bug that does not exist.

There are two real bugs.

Bug 2a, the dropdown does not refresh. After a successful save, rename or delete, the Saved Views dropdown still shows stale data until a hard reload. Invalidate and refetch the saved_views query immediately after every successful mutation. Use the TanStack Query cache key for saved_views and call invalidateQueries in the mutation onSuccess handler. Apply this to save, update, rename and delete.

Bug 2b, the saved view captures no state. All three existing rows have filters = [], sort = [] and columns = []. The view is being created but the current filter set, sort order and column visibility are never written into it. Fix the save handler so it serialises the CURRENT UI state into those three JSONB columns, and so that selecting a saved view restores all three.

Schema corrections, use these exact names:
- The table column is view_name, NOT name.
- The unique constraint is (user_id, target_table, view_name), NOT (user_id, team_id, name). Use that as the upsert conflict target.
- target_table must be set to 'companies'.
- Always set team_id from the user's team membership and user_id from auth.uid() on insert.

Acceptance: create a view with filters and hidden columns applied, reload the page, select the view, and both the filters and the column visibility are restored.

# FIX 3: Close button on Company Detail

The detail panel has no way to close it.

1. Add an X icon button to the top right of the Company Detail panel header. Clicking it clears the selection and returns the table to full width.
2. Bind the Esc key globally while a detail panel is open. Esc closes it. Remove the listener on unmount so it does not leak.
3. Clicking outside the detail panel (backdrop click) also closes it. A click inside the panel must not close it.
4. All three paths clear the selection from the URL so back and forward behave correctly.

# FIX 4: Row click behaviour

Currently a click anywhere on a row opens Company Detail. Change it.

1. Only a click on the Company Name cell opens the Company Detail panel. Make the name look interactive (pointer cursor, hover underline or colour shift).
2. Clicks on the four editable cells open an inline edit dropdown in place, and do NOT open the detail panel: Priority, Owner (account_owner), Status (opportunity_status), Research Stage. Saving the dropdown selection writes immediately and shows an undo toast.
3. Clicks on any other cell do nothing.
4. Stop event propagation correctly so an inline edit click never bubbles up into the row handler.

Acceptance: clicking the Priority pill opens the priority dropdown and does not open the detail panel. Clicking the company name opens the detail panel.

# FIX 5: Company Detail tabs

The panel currently shows a bare overview card. Build it out.

Header of the panel: Company Name in large type, coloured Priority pill, Research Stage pill, Country label, and a "Promote to Monday" button pinned to the right. The button is a placeholder for now, wire an onClick that does nothing yet.

Six tabs inside the panel, URL synced, Overview is the default.

TAB 1, Overview. All 39 domain fields grouped into eight sections. Every field auto-saves on blur and shows an undo toast. Use exactly these database column names:

Company Info: company_name, country, website_url, industry, product_line
Priority and Research: priority, research_stage, account_owner, tracking
Product Offerings: refurbished_offered, sim_free_devices, annual_devices_sold, category
Geography and Structure: headquarter_location, parent_group, countries_selling_in
Financial and Market Data: estimated_revenue_gbp, employees, monthly_visits, creditsafe_rating
Insurance Capture: insurance_offered, insurance_provider, insurance_product_types, insurance_structure_type, insurance_monthly_price, insurance_annual_price, distribution_model, coverage_summary, customer_journey, policy_url
Opportunity and Notes: opportunity_status, usp_notes, additional_notes
Industry Meta: company_id, account_source, last_refreshed, date_added, source_urls, contacts_count

Schema corrections, these three fields DO NOT EXIST, do not add them and do not invent columns for them:
- "Priority Score". There is no priority_score column. Use tracking in the Priority and Research section instead, and do not sort by priority_score anywhere. If a previous prompt told you to sort by priority_score, sort by priority ascending (enum order, P0 first) then company_name ascending.
- "CRM Actions". There is no such column. Omit it.
- research_notes. There is no such column on companies.

TAB 2, Contacts. Mini table of contacts where contacts.company_id equals this company's id. Columns: Name (first_name plus last_name), Function, Seniority, Outreach Status. Row click opens contact detail, a placeholder is fine for now. This table will be empty until the contacts load runs, so implement a proper empty state, do not show a broken table.

TAB 3, Outreach. All outreach_log rows for contacts at this company. Join outreach_log to contacts on contact_id, filter where contacts.company_id equals this company's id. Note outreach_log also carries its own company_id, you may use that directly. Group as email style threads by thread_id, chronological, most recent first. Show a status pill for draft_status (pending_review, approved, sent, superseded, rejected). Empty until the outreach load runs, so implement an empty state.

TAB 4, Notes. Chronological view parsing [YYYY-MM-DD] prefixes out of usp_notes and additional_notes only (research_notes does not exist). Split each field on the [YYYY-MM-DD] marker, render each dated block as a card with the date as the header, sorted most recent first. Text with no date prefix goes into a single undated card at the bottom. These fields run past 1,000 characters, so cards must wrap and scroll rather than overflow.

TAB 5, Products. Mini table of insurance_products joined to insurers for this company. Columns: insurer name, product types, monthly price, annual price, structure. Show a placeholder empty state if none, these tables are currently empty.

TAB 6, Timeline. Render "Coming soon" only. This is V1.1.

# FIX 6: Missing columns in the visibility menu

The menu shows 36, it must show 39. Here is the authoritative list of the 39 domain columns of public.companies, verified from information_schema. Diff your menu against this list and add whatever is missing.

company_id, company_name, tracking, priority, research_stage, contacts_count, website_url, country, category, refurbished_offered, sim_free_devices, parent_group, headquarter_location, countries_selling_in, estimated_revenue_gbp, employees, monthly_visits, creditsafe_rating, insurance_offered, insurance_provider, insurance_product_types, insurance_structure_type, insurance_monthly_price, insurance_annual_price, distribution_model, coverage_summary, customer_journey, policy_url, opportunity_status, usp_notes, additional_notes, industry, product_line, account_owner, account_source, last_refreshed, source_urls, annual_devices_sold, date_added

The table has 49 physical columns. The other 10 are infrastructure and build columns and must NOT appear in the visibility menu: id, team_id, created_at, updated_at, archived_at, archive_reason, monday_deal_id, root_domain, legacy_source, migrated_at.

The three most likely omissions are tracking, contacts_count and source_urls, because they are trigger owned or derived. They are still Excel columns C, F and AK and must be shown. tracking and contacts_count are read only in the UI, they are maintained by database triggers, so render them but do not allow inline edit on them.

Report which three were actually missing.

# Acceptance criteria, all must pass before you say done

1. Revenue renders as £3,620,000,000, not £3,620,000,000.
2. Empty cells are blank. No — or em dash anywhere in the grid.
3. Save Current View persists across a page reload, and the restored view brings back its filters, sort and column visibility.
4. The Saved Views dropdown updates immediately after save, rename and delete, with no manual reload.
5. X, Esc and backdrop click all close the detail panel.
6. Only a Company Name click opens the detail. A Priority pill click opens the inline dropdown instead.
7. The detail panel has six tabs and Overview shows all 39 fields in eight sections.
8. The column visibility menu lists all 39 domain columns and none of the 10 infrastructure columns.
9. British English throughout, no em dashes, no en dashes, no ellipses in any UI copy.
10. No new tables, columns, enums or policies were created.

When you finish, report: which three columns were missing, what was causing the saved view state to serialise as empty, and anything you could not implement.
```
