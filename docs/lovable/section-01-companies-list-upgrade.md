# Lovable section prompt: Companies list upgrade (6 columns → full spec)

Paste into Lovable after the current Companies list build. Scope is the Companies
list only. Backing tables `user_column_prefs` and `saved_views` already exist in
Supabase (migrations 019 and 009) — do NOT create them.

---

Update the Companies list only. Do not touch other pages, the app shell, auth, or the schema.

The current list renders ~6 columns. Upgrade it to the full specification below.

# Data
Source: `companies` where `archived_at IS NULL`. 39 domain columns. Query with
`.select('*', { count: 'exact' })`, `.range(from, to)`, 50 rows per page, and show
"N of TOTAL companies". Never fetch all rows client-side.

# 1. Full 39-column table
Render all 39 columns in one horizontally scrollable table. The table body scrolls
horizontally inside its own container; the page itself must never scroll sideways.

# 2. Frozen Company Name
`company_name` is pinned sticky-left and stays visible during horizontal scroll,
with a visible right-edge shadow/divider when the table is scrolled off zero.
The row checkbox (bulk select) pins with it.

# 3. Column visibility menu
Top-right of the table: a column menu with a checkbox per column, a search box, and
"Show all" / "Reset to default". Persist per user to `user_column_prefs`
(unique on `user_id + view_name`), using `view_name = 'companies_list'`:
- `visible_columns` JSONB: ordered array of column keys
- `column_widths` JSONB: optional `{column_key: px}`
Upsert on change (debounced). On load, read prefs; if none, use the default column
set. RLS restricts rows to the signed-in user; always set `team_id` on insert.

# 4. Filter bar, 10 primary chips
Above the table, a sticky filter bar with these 10 chips:
Priority, Country, Category, Research Stage, Insurance Offered, Owner,
Opportunity Status, Product Line, Insurance State, Size Tier.
Each opens a popover with multi-select checkboxes (radio for Insurance Offered:
Yes/No/Unknown). Chips show active-selection counts. Include a "Reset filters"
action. Enum-backed chips take their options from the enum; Country from
`SELECT DISTINCT country`.
Note: "Insurance State" and "Size Tier" are derived, not literal columns — define
them from existing fields (Insurance State from `insurance_offered` +
`insurance_structure_type`; Size Tier banded from `employees` / `estimated_revenue_gbp`)
and state the banding you chose in your summary.

# 5. + Add filter
A `+ Add filter` button lets the user add any of the remaining 29 columns as an
ad-hoc filter chip. Control type follows column type: enum → multi-select,
text → contains, number → min/max, date → range, boolean → tri-state.
Added chips are removable and participate in Saved Views.

# 6. AI Query bar (spec only, do not build the function)
A single-line natural-language input at the top of the filter bar:
"Show me P0 DACH prospects with monthly visits over 100000".
Wire the UI and a typed client call, but DO NOT implement the backend. Spec the
Edge Function contract as `nl-to-filter`:

- **Endpoint**: `POST /functions/v1/nl-to-filter`
- **Auth**: caller's Supabase JWT forwarded; function resolves team via RLS context
- **Request**: `{ "query": string, "target_table": "companies", "available_columns": string[] }`
- **Response 200**:
  ```json
  {
    "filters": [
      { "column": "priority", "op": "in",  "value": ["P0"] },
      { "column": "country",  "op": "in",  "value": ["Germany","Austria","Switzerland"] },
      { "column": "monthly_visits", "op": "gt", "value": 100000 }
    ],
    "sort": [{ "column": "priority", "direction": "asc" }],
    "unresolved": ["DACH mapped to DE/AT/CH"],
    "confidence": 0.0
  }
  ```
- **Ops**: `eq, neq, in, not_in, gt, gte, lt, lte, contains, is_null, not_null, between`
- **Errors**: `400` unparseable, `422` references unknown column (echo it in `unresolved`), `429` rate limited
- **Client rule**: the returned filter expression populates the SAME chip model as manual filters, so the user can see and edit what the AI produced before it applies. Never execute raw SQL from the model.
- Until the function exists, the bar shows "AI Query coming soon" and is disabled.

# 7. Saved Views
Dropdown top-left of the filter bar. A saved view captures current filters +
column visibility + sort. Persist to the EXISTING `saved_views` table
(`target_table = 'companies'`), using its existing columns: `filters` JSONB,
`sort` JSONB, `columns` JSONB, `view_name`, `is_shared`.
Actions: Save as new, Update current, Rename, Delete, and a shared/private toggle.
Unique on `(user_id, target_table, view_name)` — surface a friendly error on clash.
Always set `team_id` on insert.

# 8. Responsive split behaviour
- No company selected: table is FULL WIDTH with horizontal scroll, all visible columns.
- Company selected: table collapses to 35% left and switches to a COMPACT column set —
  Name, Priority, Owner, Status, Updated — with horizontal scroll disabled.
  Detail panel occupies 65% right.
- `Esc`, or a click outside the detail panel, closes the detail and returns the table
  to full width with the user's full column set restored.
- Selection state is in the URL so the view is shareable and back/forward works.

# 9. Default sort
Priority ascending with P0 first (enum order, not alphabetical), then
`priority_score` DESC. Any column header is clickable to re-sort; sort is part of
Saved Views.

# 10. Row height
Compact 32px rows. Dense Attio/Linear feel, not Salesforce.

# 11. Column type-aware rendering
- **Priority**: coloured pill — P0 grey, P1 red, P2 amber, P3 green, OoS light grey, Competitor purple.
- **Arrays** (e.g. `category`, `insurance_product_types`, `sn_lists`): chip stack, overflow collapses to "+N" with the remainder in a tooltip.
- **Dates**: relative ("2 hours ago", "3 days ago"), with the absolute date in a tooltip.
- **Numbers** (revenue, employees, monthly visits, prices): right-aligned, thousand separators, currency prefix where the column is a price.
- **URLs**: external-link icon opening in a new tab with `rel="noopener noreferrer"`; show the domain, not the raw URL.
- **Long text** (`usp_notes`, `additional_notes`, `coverage_summary`, `customer_journey`): truncate to one line with ellipsis and a tooltip / expand-on-hover. These fields can run to 1,000+ characters — they must never blow out row height.
- **Null**: render a muted em-dash placeholder, never "null" or an empty cell.

# Constraints
- Keep the current theme and typography. Use the Pier indigo tokens already in the design system; do not reintroduce gold.
- Every insert into `user_column_prefs` / `saved_views` sets `team_id` from the user's team.
- No client-side N+1: one query for the list, one for the selected detail.
- Virtualise table rows if the DOM node count becomes a performance problem at 50 rows × 39 columns.
- Handle empty state (no companies match), loading state (skeleton rows, not a spinner), and error state explicitly.
- Do not create, drop, or alter any table, column, enum, or policy — the schema is already migrated.

When done, summarise: the derived definitions you chose for Insurance State and
Size Tier, how column prefs persist, and anything you could not implement.
