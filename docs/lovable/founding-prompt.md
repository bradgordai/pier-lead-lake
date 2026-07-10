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
