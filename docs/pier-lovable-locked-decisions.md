# Pier Lovable, locked UX decisions

Consolidated list of every UX decision locked for the pier-lead-lake Lovable build. Reference for Claude Code when writing the founding prompt and section prompts. Supersedes the 20 UX decisions memo where they conflict.

Last updated: 8 July 2026

## Auth and access

1. **Login method**: email + password with invite-only registration. Brad invites Oli, Paul, Mark, Phil via their Pier email addresses. Nobody outside the invite list can register. Microsoft OAuth deferred to V1.1 if requested.

## Navigation and layout

2. **Nav layout**: left sidebar, collapsible. Logo top left, vertical sidebar with tab icons + labels (Today, Companies, Contacts, Outreach Log, Reconciliation, Archive, Insights). Attio, Linear, Notion pattern.
3. **Row density**: compact 32px rows. Attio and Linear style. Fits ~20 companies per screen.
4. **Detail open pattern**: split screen. Companies list stays visible on left (~35% width), Company detail opens on right (~65% width). Sidebar stays intact.
5. **Company Detail layout**: tabs within the detail panel. Overview / Contacts / Outreach / Notes / Products / Timeline. Overview is default.

## Build order

6. **First page after shell**: Companies list. Then Company Detail, then Contacts list, then Contact Detail, then Outreach Log, then Reconciliation Queue, then Archive. Today tab and Insights are built last once other data exists.

## Interaction patterns

7. **Save behavior**: auto-save on blur with undo toast. Field commits when Oli clicks away or presses Enter. Toast shows "Priority changed to P0. Undo" bottom-right for 10 seconds. No Save button.
8. **Inline edit**: click a pill (Priority, Owner, Status, Research Stage) in any row, dropdown appears in place, save automatically on selection.
9. **Cmd+K quick search**: global search across Company Name, Contact Name.
10. **Bulk actions**: checkbox column on left of each row. When ≥1 selected, action bar appears at top: Change Owner / Change Priority / Change Research Stage / Archive / Export CSV. All actions apply to all selected rows in one operation.

## Companies list specifics

11. **Frozen column**: Company Name column stays pinned to the left when scrolling horizontally through the 39 columns. Sticky column pattern (Excel, Google Sheets).
12. **Filter model**:
    - Sidebar shows ~10 primary filters: Priority, Country, Category, Research Stage, Insurance Offered, Owner, Opportunity Status, Product Line, Insurance State, Size Tier
    - "+ Add filter" button lets Oli add filters on any of the remaining 29 columns dynamically
    - AI Query bar at top: natural language filter ("show me P0 Greenfield DACH with monthly visits over 100000")
    - Saved views to persist named filter configurations per user
13. **Default sorted by**: Priority (P0 first), then Priority Score (numeric) descending
14. **Row click**: opens split-screen Company Detail on right

## Outreach Log specifics

15. **Top-level tabs** (not filter dropdown): Pending Review (badge count) | Approved | Sent | Rejected | All
16. **Draft rejection feedback**: structured form (reason dropdown: Voice off / Fact wrong / Framing wrong / Timing wrong / Register wrong / Other, plus detail text field). Writes to drafts_feedback table.
17. **AI edit option**: Lovable's built-in AI editor available on any Draft. User can either manually edit OR prompt AI ("shorter", "more formal", "translate to German") and save new version.
18. **Message threads**: display as email-style conversation, chronological, grouped by contact.

## LinkedIn send integration

19. **Send Now button on approved drafts**: triggers Make.com webhook `https://hook.eu2.make.com/dqzwscpiduqvrxag4mwwcxwsf1alocpd`
20. **Payload to webhook**: `{contact_name, contact_id, company_name, company_id, linkedin_url, message_body, message_type, draft_id, sent_by}`
21. **On send success**: Lovable optimistically shows "Sent, awaiting response". Make.com scenario updates Supabase, Lovable refreshes.
22. **Reply monitoring**: separate Make.com scenario polls PhantomBuster LinkedIn Inbox every 3 hours, syncs new replies back to Supabase outreach_log. Lovable UI shows replies on next refresh.

## Landing and daily flow

23. **Today tab as landing**: first thing Oli sees after login. Nightly run summary, drafts to review, replies overnight, warm leads ready to promote, agent errors.
24. **CRM Kanban toggle**: on Contacts list, toggle between Table view (default) and Kanban view. Kanban columns: Not started > Contacted > In conversation > Cooldown > Ready > Warm promoted.

## Company Detail extras

25. **Company Detail Overview tab**: 8 sections organised like Excel form (Company Info, Priority & Research, Product Offerings, Geography & Structure, Financial & Market Data, Insurance Capture, Opportunity & Notes, Industry Meta). Auto-save on blur.
26. **Company Detail Contacts tab**: mini table of contacts linked to this company. Click a contact opens their detail page.
27. **Company Detail Outreach tab**: all touches to any contact at this company, grouped as email threads chronologically. AI Edit button on drafts.
28. **Company Detail Notes tab**: chronological view of USP/Notes + Additional Notes + Research Notes with timestamps parsed from [YYYY-MM-DD] prefixes.
29. **Company Detail Products tab**: mini table of insurance products this company sells.
30. **Company Detail Timeline tab (V1.1)**: auto-generated story of the company through time.
31. **Promote to Monday button**: pinned right side of Company Detail top bar. On click, confirmation modal, then sets archived_at + archive_reason, generates a Monday create URL with pre-filled data, opens in new tab. Company moves to Archive tab.

## Design language

32. **Dark mode first** with light-mode toggle top right
33. **Primary colour**: Pier navy #11144D
34. **Accent**: gold #FFAE00
35. **Font**: Inter throughout, no font mixing
36. **Table density**: dense, Attio/Linear feel, not Salesforce
37. **Colour coding on Priority pill**: P0 grey, P1 red, P2 amber, P3 green, OoS light grey, Competitor purple

## Voice and copy rules (mirrors Pier Rules)

38. **British English** (colour, organisation, recognise)
39. **No em dashes, no en dashes, no ellipses** in UI copy
40. **"Partner" not "client"**
41. **"Programme" not "product"** when referring to partner insurance offerings

## What NOT to build

42. No BD Targets as a separate tab (becomes a saved view of Companies with Insurance Offered = No, sorted by Priority Score DESC)
43. No Actions tab (consolidated entirely into Outreach Log)
44. No keyboard shortcuts (J/K nav, etc) in V1, Brad skipped
45. No user-facing "Similar companies" feature, backend only for Research Agent
46. No two-way Monday sync visibility in V1 (V2)

## V1.1 features (build after V1 shell is stable)

- Timeline tab on Company Detail
- Reconciliation Queue (Lovable vs Monday summary)
- Microsoft OAuth login option
- Semrush MCP integration for Monthly Visits enrichment
- Recently Connected phantom (scenario 4)

## V2 features (build after V1.1)

- Email drafts + MS365 send integration
- Auto-send first LinkedIn message (partial: scenario 1 already handles per-draft send)
- Pitch deck automation via Deck Builder agent
- Full loop Reconciliation with write-back to Companies
- Semrush + Creditsafe deep integrations

## Progress notes

- 2026-07-08: 46 decisions locked. All 20 original UX decisions merged with 7 fresh decisions from mapping session plus LinkedIn integration and filter model.
