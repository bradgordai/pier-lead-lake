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
