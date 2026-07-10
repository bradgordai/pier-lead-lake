# Context
Pier Lead Lake: a bespoke B2B CRM for Pier Insurance, a UK broker selling embedded gadget insurance to retailer partners. Users: 3 to 6 sales/ops; primary Oliver Müller (DACH). Volume ~420 companies, 261 contacts, 222 touches (to ~2000). Stack: Lovable, Supabase Postgres 17 (project qzfrcfzeiagziqjnfarw, eu-west-1, already provisioned), Make.com CRM sync, PhantomBuster LinkedIn. Design like Attio/Linear: dark-mode-first, dense tables, indigo #1D237A on #030F42/#11144D, white text, Inter.

# Data model
Full schema in the Project Knowledge Base. Highlights:
- companies: 39 domain + 6 build fields; FKs to pier_pipeline, eurefas_members
- contacts: 31 domain fields, FK to companies; email_normalised = lowercased email, non-unique btree (email not unique)
- outreach_log: ~17 legacy + ~15 agent/draft fields; FKs to contacts, companies; thread_id groups threads
- pier_pipeline (64) and eurefas_members (27) populated; companies/contacts/outreach_log empty (load pending), so build empty states
- 8 supporting tables (see KB)

All FKs btree-indexed. pg_trgm on. GIN trigram on lower(company_name), lower(usp_notes), contacts full name; email_normalised plain btree.

# Auth and RLS
Team-scoped RLS on every table, membership via fn_user_teams(), auth.uid() wrapped as `(SELECT auth.uid())`. Never use user_metadata. RLS already enabled everywhere.

# Pages
1. Today (landing)
2. Companies list (split-screen, sticky filters, saved views)
3. Company detail (overview, contacts, outreach, products, timeline)
4. Contacts list (table default; Kanban toggle by outreach status)
5. Contact detail (linked to Company)
6. Outreach Log (tabs: Pending/Approved/Sent/Rejected/All; AI edit on drafts)
7. Reconciliation Queue (duplicate review, side-by-side)
8. Archive (archived_at not null, read-only)
9. Insights (auto-generated)

# UI style
Bulk row checkboxes. Cmd+K search. Inline edit on Priority, Owner, Status, Research Stage pills.

# Constraints
- Every list uses .range() with a total count.
- Child collections separately keyed in TanStack Query.
- No client-side N+1: use PostgREST nested selects.
- No SECURITY DEFINER views exposed via API.
- Realtime subscriptions clean up on unmount.
- Never ship bulk-merge without an undo path.
- Every insert sets team_id from the user's team (team_members); never surface team_id.
- Server-side uses port 6543 (Supavisor), never 5432.

# Extras
Ask clarifying questions first. Build the app shell and Companies list only, not Today, Contacts, Outreach, Reconciliation, Archive, or Insights yet: per our locked build order, Today and Insights come last, once tables hold data. Do not create, drop, or alter any table, column, enum, or policy; the schema is already migrated (001 to 016). Verify against it; if something's missing, ask, don't create.
