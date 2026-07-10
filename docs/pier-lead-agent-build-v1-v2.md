# Pier Lead Agent, V1 and V2 build documentation

Author: Brad Gordon (Nailed It AI) for Pier Insurance Managed Services Limited
Date: 7 July 2026
Classification: C2

## 0. How to use this document

This is the full build map for the Pier lead sourcing and outreach agent. It replaces every ad hoc note we've built over the last three weeks. Two audiences:

- Brad, as the builder. Sections 3 through 8 tell you exactly what to build, in what order, and how the parts connect.
- Oli, Paul, Mark, as sign off. Sections 1, 2, and 12 tell them what the system does, what it costs, and what human intervention it still needs.

Everything in sections 1 through 8 is V1, the 30 day MVP. Section 9 is V2, the features that come after go live. Section 10 is the migration from the current UK Lovable. Section 11 is operating rhythms. Section 12 is cost.

## 1. Executive summary

### 1.1 What we are building

A nightly, autonomous lead sourcing and outreach drafting system for Pier Protect. It scrapes Sales Navigator, researches companies, drafts LinkedIn messages in Oli's voice, and hands warm leads to Monday CRM. Oli reviews and sends. Brad monitors and operates.

### 1.2 What it replaces

- Manual company research (hours per prospect, gone)
- Manual copy paste from LinkedIn to spreadsheet (gone)
- Cold outreach drafting from scratch (gone, replaced by review)
- Ad hoc handoff between Oli's tools (structured through Lovable + Monday)

### 1.3 What it does NOT replace, V1

- Sending LinkedIn messages (Oli sends manually, tracked by PhantomBuster)
- Final judgement calls on ICP fit (Oli's decision, Reconciliation Agent surfaces flags)
- Warm relationship management (Monday CRM, Oli owns)
- Deep discovery calls (human led)

### 1.4 V1 vs V2 at a glance

| Capability | V1 | V2 |
|---|---|---|
| Nightly company research | Yes, Companies Agent Stage 1 + Stage 2 | Yes, enhanced with pitch deck generation |
| Contact matching from Sales Nav | Yes, Contact Matcher agent | Yes, multi list SN buckets |
| Outbound drafting (LinkedIn) | Yes, Outbound Agent | Yes, plus auto send first message |
| Reply classification | Yes, Reply Classifier | Yes |
| Follow up cadence | Manual (Oli) | Automated, MS365 + scheduled tasks |
| Reconciliation (Lovable vs Monday) | Read only summary + flags | Full loop, auto dedup |
| Pitch deck automation | No | Yes, Deck Builder agent |
| Companies data source | Lovable (Supabase) + web research | Same, plus Semrush + Creditsafe |
| Contact source | Sales Nav sweep + LinkedIn Inbox | Same, plus Recently Connected phantom |
| Cross agent handover | Direct Supabase reads | Dedicated handover table |

### 1.5 Success criteria for V1

- 30 qualified companies researched per night (Stage 1 triage, ~5 min each)
- 10 to 15 qualified companies deep researched per night (Stage 2, ~15-20 min each, capped post triage)
- Outbound Agent produces drafts that pass Oli's voice contracts with no manual rewrite in ≥ 80% of cases
- Zero fabricated Pier facts (loss ratios, LTV, comms cadence never appear in outputs)
- Migration of 350 companies, 397 contacts, 222 outreach touches from UK Lovable complete before go live

## 2. Architecture overview

### 2.1 The layers

Layer 1, storage: Supabase (pier-lead-lake-prod, EU/Dublin)
Layer 2, UI: Lovable (pan European lead lake, Oli's daily interface)
Layer 3, agent runtime: Claude Code CLI running on Brad's Mac (Anthropic API billing)
Layer 4, automation glue: Make.com (PhantomBuster + Monday + Klaviyo webhooks)
Layer 5, external tools: PhantomBuster, Apify, Semrush, MS365 MCP, Monday MCP
Layer 6, warm CRM: Monday.com (Oli's warm leads)

### 2.2 The agents in V1

1. Coordinator, orchestrates the nightly run and enforces caps
2. Companies Agent, researches companies in two stages (light triage + deep research)
3. Contact Agent, matches Sales Nav contacts to companies and owns the Contacts tab (was "Contact Matcher" in the earlier draft; renamed to match Oli's actual model)
4. Outbound Agent, drafts LinkedIn welcomes and applies voice contracts. Also owns Path A/B/C classification
5. Outreach Agent, sentiment scores replies, writes to Outreach Log, handles chaser cadence in V2 (was "Reply Classifier" in the earlier draft; renamed to match Oli's actual model)
6. Reconciliation Agent, produces daily read only summary of Lovable vs Monday overlap

All six run as Claude Code subagents (`.claude/agents/*.md` frontmatter files), invoked by the Coordinator via the Task tool.

### 2.2a Ownership boundaries (from Oli's Companies Agent bootstrap, 2026-05-18)

Every agent has WRITE access only to its own tab. Reads across tabs are allowed. Cross agent requests happen via the `agent_handover` table (or `inter_agent_handover.md` in Oli's current Excel model).

| Tab | Write owner | Read only |
|---|---|---|
| Companies (39 cols) | Companies Agent | All others |
| Contacts | Contact Agent | Companies (narrow exception: set CoID and Company Name when resolving a handoff) |
| Outreach Log | Outreach Agent | Companies (narrow exception: stamp resolution marker on `[to COMPANIES AGENT]` tags in col L) |
| Dashboard sections 1-4 (aggregations) | Any agent | All |
| Dashboard section 5 (Today's Focus) | Outbound Agent only | All |
| agent_handover | All (append only) | All |

Hard rules:
- Companies Agent NEVER writes Connection Status, Outreach Status, Path classification, or Lead Priority. Those are contact workflow state owned by Outbound and Contact Agents.
- Never refresh Dashboard section 5 outside Outbound Agent. It applies per contact workflow classification.
- If an agent needs a change outside its scope, it requests via `agent_handover`. It never silently writes cross tab.

### 2.3 The data flow, one sentence

Sales Nav > PhantomBuster (via Make.com) > Supabase (raw contacts table) > Contact Matcher (matches to companies) > Companies Agent (triage + deep research) > Outbound Agent (drafts) > Lovable (Oli's review UI) > Oli sends manually > PhantomBuster tracks acceptance > Reply Classifier scores > Monday (warm leads) or Reconciliation Agent (flags).

### 2.4 What runs where

| Component | Where it runs | Why |
|---|---|---|
| Coordinator + agents | Brad's Mac overnight | Anthropic API billing, no daily message caps, cheap and simple |
| Supabase | Cloud (Ireland/EU) | Persistent state, GDPR compliant |
| Lovable | Cloud (Ireland/EU) | Oli's daily UI, integrated with Supabase |
| Make.com | Cloud | Native modules for PhantomBuster + Monday |
| PhantomBuster | Cloud | Sales Nav sweep + LinkedIn Inbox + Recently Connected phantoms |
| Apify | Cloud | Customer journey walks (PDP + Cart + Checkout) via ai-web-agent actor |
| Monday CRM | Cloud | Warm leads, Oli's existing tool |
| Klaviyo | Cloud | Downstream email flows (partner comms), not V1 for lead outreach |

## 3. The nightly run, end to end workflow

### 3.1 Timing

Kick off: 22:00 UK local, when Brad's Mac is idle and Oli's day is done.
Complete by: 04:00 UK local, ready for Oli's morning review.
Failure timeout: 06:00 UK local, hard cut, whatever is done is done.

### 3.2 Hour by hour

**22:00, Coordinator wake up.**
- Reads Supabase for open work queue
- Reads Monday CRM (via MCP) for warm leads to skip
- Kicks off PhantomBuster Sales Nav sweep via Make.com webhook
- Waits for Sales Nav sweep completion (typically 20-40 min)

**22:40, Contact Matcher.**
- New contacts land in Supabase raw_contacts table (Make.com pushed them from PhantomBuster)
- Contact Matcher agent matches each contact to a company in the companies tab (fuzzy match on domain + company name)
- Unmatched contacts land in unmatched_contacts (for Brad's morning review)
- Matched contacts appended to contacts tab, linked to their company

**23:00, Companies Agent Stage 1 (light triage).**
- Reads work queue of companies needing triage (typically 30-50 companies)
- For each company, Haiku pass: fetches homepage + About page, checks CCE (does the company sell hardware?), does the sniff test on ICP fit
- ~5 minutes per company
- Assigns priority: P0 / P1 / P2 / P3 / OoS / Competitor
- Populates size tier + insurance state (via revenue/ASP proxy, headcount proxy, or qualitative match)
- Writes back to companies tab

**00:30, Coordinator caps the queue.**
- Reads triage results
- Takes top 10-15 P0/P1 companies from Stage 1 output (cap is post triage, not pre triage)
- Passes them to Stage 2

**00:45, Companies Agent Stage 2 (deep research).**
- For each qualified company, Sonnet pass: deep dive
- Uses Apify ai-web-agent for customer journey walk (PDP > Cart > Checkout), captures existing insurance if present
- Runs site search sweep for GDPR terms, competitor mentions, insurance keywords
- Populates full 39 column companies schema
- ~15-20 minutes per company
- Completes ~10 companies by 04:00

**03:00, Outbound Agent.**
- Reads companies ready for outreach (deep researched, matched to a contact)
- Reads contacts tab for the LinkedIn URL and name of the target person
- Drafts LinkedIn welcome message applying:
  - Mark's Sales DNA six point checklist
  - Voice contracts (no em/en dash, no ellipsis, no banned words)
  - Size tier + insurance state door in framing
  - Pillar priority from the Companies Agent output
  - Signature opener with self deprecating tag if Oli's style
- Writes draft to outreach_log tab, status "ready for review"
- Runs pre delivery lint before saving (blocks any draft with em dash U+2014, en dash U+2013, ellipsis U+2026, spaced hyphen surrounded by spaces)

**04:00, Reconciliation Agent.**
- Reads Lovable companies tab (fresh from tonight's run)
- Reads Monday CRM (via MCP) for all warm leads
- Produces summary:
  - Companies in Lovable but flagged as warm in Monday (Companies Agent should have skipped, flag if it didn't)
  - Contacts in both systems (dedupe review)
  - Companies in Monday but missing from Lovable (potential backfill)
- Writes summary to daily_reconciliation table
- Emails summary to Oli (via MS365 MCP)

**04:15, Coordinator wind down.**
- Health check: rows added, drafts produced, errors caught
- Writes nightly_summary to Supabase
- Emails Brad the run summary (via MS365 MCP)

### 3.3 The next morning (Oli's day)

- Oli opens Lovable, sees ~10 companies deep researched with drafts ready
- Oli reviews each draft in Lovable
- Approved drafts get copy pasted to Sales Nav manually (V1) and sent
- PhantomBuster's LinkedIn Inbox phantom captures acceptance and replies through the day
- Warm leads move from Lovable to Monday via Oli's manual promotion + Add to CRM Chrome extension
- Reply Classifier runs every 3 hours during the day, classifies replies, updates Lovable

## 4. The agents in detail

### 4.1 Coordinator

File: `.claude/agents/coordinator.md`
Model: Sonnet (needs judgement on cap logic + error handling)
Tools: Task (invokes other agents), Read/Write, Bash (for Supabase queries via psql or Edge Functions)

Responsibilities:
- Enforce the post triage cap of 10-15 deep researches per night
- Handle failures: any agent that times out or errors gets logged and the run continues
- Write nightly summary
- Trigger Make.com webhooks for PhantomBuster and Klaviyo where needed

System prompt highlights:
- You are the Coordinator for Pier's lead sourcing system
- Read the work queue in strict order: contacts unmatched, companies untriaged, companies P0/P1 without deep research, companies deep researched without drafts
- Cap Stage 2 deep research at 10-15 companies per run
- If any subagent errors, log to errors table and continue; do not fail the whole run

### 4.2 Companies Agent

File: `.claude/agents/companies-agent.md`
Model: Haiku for Stage 1 (triage), Sonnet for Stage 2 (deep research)
Tools: Read/Write, Bash (curl to Apify + Semrush), Web search fallback via CLI

Responsibilities:
Stage 1, light triage (~5 min per company):
- Fetch homepage + About page (Apify rag web browser or simple curl)
- Run CCE qualifying test: does the prospect sell hardware?
- Estimate size tier via revenue/ASP proxy or qualitative match
- Estimate insurance state via checkout inspection
- Assign priority: P0 / P1 / P2 / P3 / OoS / Competitor
- Write to companies tab (columns 1-15)

Stage 2, deep research (~15-20 min per company):
- Apify ai-web-agent walks PDP > Cart > Checkout
- Captures existing insurance offer if present (name, price, coverage)
- Site search sweep: "insurance", "warranty", "protection", "GDPR", competitor names
- Semrush pull for Monthly Visits
- Populates full 39 column schema
- Writes proposed pillar priority (P1/P2/P3) for Outbound Agent

System prompt highlights (integrating Lead_and_ICP_Brief.md logic):
- Follow the 10 section brief structure from Lead_and_ICP_Brief.md
- Apply the CCE qualifying test BEFORE assigning priority
- Never invent partner names or metrics
- Capture size tier proxy method in USP / Notes (col AD) as an inline structured note
- For Annual/Monthly recurring state prospects, populate the 10 question incumbent discovery framework as open questions
- Do NOT draft outbound (that's the Outbound Agent's job)
- Do NOT classify Path A/B/C, that's Outbound's decision space
- Voice contracts (PIER_Rules.md section 3) apply to any text you write

Rules imported from Oli's Companies Agent bootstrap (2026-05-18):
- Insurance Offered? requires full customer journey walk (PDP > Cart > Checkout) AND site search sweep for locale terms (insurance / protection / cover / warranty / Versicherung / Schutz / assurance / garantie / verzekering). Homepage only triage misses hidden insurance products (ViberStore Tier 4 at €169.99, invisible on PDPs, only findable via /search?q=insurance). Failure to walk means classifying No when the answer is Yes, cascading to wrong Pier messaging.
- Stage 1 mandatory pages: homepage AND About page (or equivalent /uber-uns, /qui-sommes-nous). Homepage only triage caused the Tech Tiger C268 misclassification (Refurbished Offered? = No became Yes once About page was read).
- Verified only rule: every factual claim in USP/Notes cites a source (URL, LinkedIn profile, Companies House, prior agent stamp). No inferred facts without an "inferred from X" qualifier.
- Internal Review block on gaps: any USP/Notes content with verification gaps includes an Internal Review block listing Verified facts and GAPS. Prefix `DELETE BEFORE SENDING` so it never leaks into external content.
- Geo ICP role based not location based: judge on the lead's role responsibility / market scope, not personal base location. Where role scope is unclear from LinkedIn, flag for Oli review rather than auto OoS.
- Never write to Contacts tab (Contact Agent territory) or Outreach Log (Outreach Agent territory). Narrow exceptions: setting CoID + Company Name in Contacts when resolving a handoff, stamping resolution markers on `[to COMPANIES AGENT]` tags in Outreach Log col L.
- Pre/Act/Post Verify pattern on every write: read pre state, write, re read post state, assert equality. In Supabase this is a SELECT before and after the UPDATE. Halt on mismatch.

### 4.3 Contact Agent (owns the Contacts tab)

File: `.claude/agents/contact-agent.md`
Model: Haiku (simple matching logic, cheap)
Tools: Read/Write, Bash (psql)

Responsibilities:
- Fuzzy match each raw contact from PhantomBuster to a company in the companies tab
- Match on: (a) email domain, (b) company name normalised (lowercase, strip Ltd/GmbH/SA suffixes), (c) LinkedIn company URL
- If matched: append to contacts tab, link to company, mark status "matched"
- If no match: append to unmatched_contacts for Brad's morning review
- Own workflow state fields: Connection Status, Outreach Status, Lead Priority

3 condition match check for CoID claims (Oli's rule, "outbound_claims_are_hints_not_law"): before stamping a match, all three must pass:
(a) name match OR documented subsidiary of / parent of relationship in USP/Notes
(b) country match OR multi country operations explicitly documented
(c) no contradicting evidence in USP/Notes

If any condition fails: do NOT stamp the match. Options:
- Re-route to Outbound Agent with a `[to OUTBOUND AGENT]` tag explaining the mismatch, OR
- Ask Companies Agent to create a new C row for the correct entity (via agent_handover request)

Historical failures this rule prevents (all locked 2026-05-15):
- P257 Marek Grabowski "at Orange Polska" wrong matched to Orange France (C132)
- P262 Yousuf "SER FZCO / Mobile Phones LLC" wrong matched to Grade Mobile UK (C086)
- P276 Bahnmüller "Reuseit Germany GmbH" wrong matched to Vodafone Germany (C307)

System prompt highlights:
- Outbound Agent's claims are HINTS not law. Independently verify every match before stamping.
- Geo assessment is role based, not location based. A Singapore based EMEA country manager is IN SCOPE; a DACH based APAC only exec is OUT OF SCOPE.
- Never write to Companies tab. If new company row needed, request via agent_handover.

### 4.4 Outbound Agent

File: `.claude/agents/outbound-agent.md`
Model: Sonnet (voice quality matters)
Tools: Read/Write only (no external calls, data only agent)

Non negotiable contracts (from Oli's Outbound Agent spec):
1. Data only, no partner facing communication happens without a human sending it
2. Atomic save, one draft = one row in outreach_log, no batching
3. Pre delivery lint, blocks em dash (U+2014), en dash (U+2013), ellipsis (U+2026), spaced hyphen (space hyphen space), banned words
4. Verified only, cite only facts from PIER_Rules.md, PIER_Capability_Reference.md, OUTREACH_QUICK_REFERENCE.md

Standard workflows:
- New CR accept intake, when PhantomBuster reports a new connection accepted, produce a welcome message
- Sales Nav sweep, when new contacts land from Sales Nav, produce cold connection request notes (30-50 words)
- Cold email drafting, only when explicitly requested (V1 default is LinkedIn only)
- Reply detection sweep, categorise inbound and mark drafts as superseded if the thread has moved on
- Chaser cadence, V2 (not V1)

System prompt highlights (integrating LinkedIn_Message_Architect.md + Email_Architect.md):
- Follow Mark's Sales DNA six point checklist for every cold draft
- Length caps by message type (see LinkedIn_Message_Architect.md section 2)
- Apply v10.1 additional rules (soft phrasing, meeting CTA pattern, pre output verification)
- Sign as the user, ask once if unclear, never default to Oli
- Voice: British English default, Sie for German cold, du when signalled
- Never use em or en dashes anywhere in output
- Signature opener with self deprecating tag for LinkedIn ("Welcome to my humble network")
- Classify Path A/B/C for every draft (this is YOUR decision, not Companies Agent's, per Oli's Companies Agent bootstrap 2026-05-18). Path stores in outreach_log column.
- Recommended frame (Discovery / Diagnostic / Alternative / Ally / Peer) and recommended arc (A/B/C/D/E) are YOUR outputs too, per Lead & ICP Brief section 3.4 and 3.5.

### 4.5 Outreach Agent (owns the Outreach Log tab)

File: `.claude/agents/outreach-agent.md`
Model: Haiku (classification is cheap)
Tools: Read/Write

Responsibilities:
- Read inbound replies from LinkedIn Inbox phantom output (Make.com pushes them to Supabase)
- Classify sentiment: Positive interest / Neutral / Objection / Not interested / Out of office / Wrong person / Do not contact
- If Positive interest, flag for manual promotion to Monday
- If Objection, categorise (which of the common objections in OUTREACH_QUICK_REFERENCE.md section 6a)
- Write classification to outreach_log
- If Do not contact, add to blocklist table (Companies Agent skips these)
- Own the Outreach Log tab as write authority (drafts saved by Outbound Agent land here; Outreach Agent stamps sent/reply/classification workflow state)

System prompt highlights:
- You classify only, you never draft replies (V1). Draft chasers become V2 via the follow up agent.
- For any Objection, name the objection category from the Quick Reference (section 6a)
- If the reply mentions a competitor by name, extract the competitor for Companies Agent's next pass
- Never write to Companies tab. If a company's insurance state has clearly changed (e.g. prospect says "we just launched insurance last month"), request an update via agent_handover.

### 4.6 Reconciliation Agent

File: `.claude/agents/reconciliation-agent.md`
Model: Haiku (data comparison, cheap)
Tools: Read/Write, Monday MCP (read only), MS365 MCP (send email)

Responsibilities (V1, read only summary):
- Read Lovable companies tab
- Read Monday CRM (via MCP) warm leads pipeline
- Match on company name + domain
- Produce daily summary:
  - Companies flagged as warm in Monday but still active in Lovable (Companies Agent guardrail check)
  - Duplicate contacts across systems (dedupe review)
  - Companies in Monday but missing from Lovable (backfill candidates)
- Write to daily_reconciliation table
- Email summary to Oli (via MS365 MCP)

System prompt highlights:
- Read only, never write to Monday
- Flag, don't fix (V1)
- If you find a Companies Agent guardrail miss (a company being researched that's already warm in Monday), flag it clearly in the top of the summary

## 5. The data model

### 5.1 Supabase tables

Primary tables:
- `companies` (39 columns, A through AM)
- `contacts` (contact records linked to companies)
- `outreach_log` (drafts, sent, replies)
- `raw_contacts` (PhantomBuster landing zone before matching)
- `unmatched_contacts` (contacts that didn't match a company)

Supporting tables:
- `nightly_summary` (Coordinator writes end of run)
- `daily_reconciliation` (Reconciliation Agent writes daily)
- `errors` (any agent writes on failure)
- `blocklist` (Do not contact list from Outreach Agent)
- `agent_runs` (audit trail: which agent ran when, took how long, cost how much in tokens)
- `agent_handover` (append only cross agent request channel, replaces Oli's inter_agent_handover.md pattern)

### 5.1a agent_handover table (from Oli's inter_agent_handover.md pattern)

Every cross agent request goes through this table instead of direct writes to another agent's tab. Append only, audit trail preserved.

Columns:
- id (uuid)
- from_agent (companies / contact / outbound / outreach / reconciliation / coordinator)
- to_agent (same enum)
- request_type (create_c_row / verify_match / correct_match / update_insurance_state / update_contact_status / other)
- payload (json, the actual request content)
- status (open / resolved / blocked)
- created_at (timestamp)
- resolved_at (nullable timestamp)
- resolution_marker (text, e.g. "[CompA verified 2026-07-15] created C412 for SER FZCO Dubai based on LinkedIn profile URL")
- resolved_by_agent (nullable)

Read at session start by every agent: SELECT * from agent_handover WHERE to_agent = $me AND status = 'open' ORDER BY created_at DESC.

Rules:
- Never delete a resolved row. Audit trail.
- If correcting a prior wrong resolution, append a new row with a supersedes reference in the payload, don't overwrite.
- Escalation chain: Companies Agent to Outbound Agent to Oli. Never skip Outbound to tag Oli for contact level ambiguity.

### 5.2 Companies tab schema (39 columns, matches Oli's current Excel workbook)

This schema mirrors Oli's Companies tab in the current Excel Pier Lead Lake workbook (A through AM). The Supabase version keeps the same field names so migration is a straight column map, not a re-model.

Ownership: Companies Agent has WRITE access to all 39 columns. Other agents have READ only, with narrow exceptions in section 2.2a.

| Col | Field | Type |
|---|---|---|
| A | Company ID (Cnnn sequential) | text, primary key |
| B | Company Name | text |
| C | Tracking (VLOOKUP cascade: Pier Pipeline > Lovable Database > EUREFAS > manual override) | text (or generated column in Supabase) |
| D | Priority | enum: P0 / P1 / P2 / P3 / OoS / Competitor |
| E | Research Stage | enum: Untouched / Light triage / Deep research done / Outdated |
| F | Contacts (count of matching contacts) | integer (generated column in Supabase) |
| G | Website URL | text |
| H | Country | text (canonical full name, "United Kingdom" not "UK") |
| I | Category | enum: Pure Online Phone Retailer / Refurbished Specialist / Electronics / Multi-Category Retailer / Operator / Manufacturer / Marketplace / Comparison Site / Industry Media / Influencer / Other |
| J | Refurbished Offered? | text (Yes/No + descriptor) |
| K | Sim-Free Devices? | boolean |
| L | Parent / Group Company | text |
| M | Headquarter Location | text |
| N | Countries Selling In | text |
| O | Estimated Revenue (£) | numeric |
| P | Employees | integer |
| Q | Monthly Visits | integer (Semrush) |
| R | Creditsafe Rating | integer |
| S | Insurance Offered? | text (Yes/No + full description of HOW) |
| T | Insurance Provider / Underwriter | text |
| U | Product Type(s) | text (ADLD / Extended Warranty / Theft / Battery / etc.) |
| V | Insurance Structure | enum: Optional Add-On / Bundled / Upsold / Embedded in T&Cs / Redirect to Third-Party / Other |
| W | Monthly Price (£) | numeric |
| X | Annual Price (£) | numeric |
| Y | Distribution Model | text |
| Z | Coverage Summary | text |
| AA | Customer Journey | text (describes PDP > Cart > Checkout flow) |
| AB | Policy URL | text |
| AC | Opportunity Status | enum: Prospect / Contacted / Active Lead / Partner / Out of Scope |
| AD | USP / Notes | text (multi line, primary narrative field, carries handoff tags AND size_tier + insurance_state as inline notes) |
| AE | Additional Notes | text |
| AF | Industry | enum: Mobile/Gadget Retail / Refurb / Recommerce / Telco / Manufacturer / Software / Telco Infrastructure / Industry Media / Influencer |
| AG | Product Line | enum: Pier Protect / Ticketplan / TIGA / Multiple / Unknown |
| AH | Account Owner | enum: Oliver Müller / Phil / Mark |
| AI | Account Source | text (e.g. "Retech Berlin 2026", "Cowork Research", "Outbound Agent sweep #N") |
| AJ | Last Refreshed | date |
| AK | Source URLs | text (multiline) |
| AL | Annual Devices Sold | text (Small/Medium/Large or numeric with description) |
| AM | Date Added | date |

Important: `size_tier` (T1/T2/T3), `insurance_state` (Greenfield/Annual recurring/Monthly recurring), `pillar_primary`, and `pillar_secondary` are captured INSIDE the USP / Notes field (col AD) as structured inline notes, NOT as their own columns. This keeps the schema aligned with Oli's current model and lets Oli see the reasoning in one place.

Path A/B/C classification, recommended frame, recommended arc are NOT Companies Agent output. Those are Outbound Agent's decision space and live in the outreach_log table (see 5.4).

### 5.3 Contacts tab schema

Column 1: id (uuid)
Column 2: company_id (foreign key)
Column 3: first_name
Column 4: last_name
Column 5: linkedin_url
Column 6: job_title
Column 7: seniority (C level / Head of / MD / Director / Manager / Other)
Column 8: email (nullable)
Column 9: phone (nullable, rarely populated)
Column 10: source_phantom (Sales Nav / Recently Connected / LinkedIn Inbox)
Column 11: source_run_id
Column 12: matched_at
Column 13: status (active / do_not_contact / left_company)

### 5.4 Outreach log schema

Column 1: id (uuid)
Column 2: contact_id (foreign key)
Column 3: company_id (foreign key)
Column 4: channel (LinkedIn / Email)
Column 5: message_type (connection_request / first_dm / cold_inmail / reply / event_follow_up)
Column 6: draft_content
Column 7: draft_status (pending_review / approved / sent / superseded / rejected)
Column 8: draft_created_at
Column 9: sent_at (nullable, set when Oli confirms send)
Column 10: reply_received_at (nullable)
Column 11: reply_content (nullable)
Column 12: reply_classification (nullable)
Column 13: pre_lint_pass (bool, must be true before draft_status can be pending_review)
Column 14: voice_contract_violations (json array of any linter flags)

## 6. External integrations

### 6.1 PhantomBuster

Account: Pier's own PhantomBuster subscription (not Brad's, per GDPR posture confirmed in prior conversation)
Login: Oli's LinkedIn cookie sits inside Pier's PhantomBuster account
Confirmed by Pier's PhantomBuster support: no MCP, must use Make.com or direct webhook

Phantoms configured:
1. Sales Navigator List Export, sweeps Oli's Sales Nav list, extracts contacts + companies. Runs 21:30 UK, before Coordinator wakes.
2. LinkedIn Inbox, sweeps Oli's LinkedIn inbox every 3 hours during the day for new replies.
3. Recently Connected, sweeps Oli's recent LinkedIn connections daily.
4. Sales Nav Sent Connection Requests, tracks what Oli has sent to prevent double sends.

Data flow: PhantomBuster > Make.com scenario (webhook out from PhantomBuster) > Supabase HTTP module writes to raw_contacts (or outreach_log for replies).

### 6.2 Make.com scenarios

Scenario 1, PhantomBuster to Supabase (contacts):
- Trigger: PhantomBuster Sales Nav List Export completes
- Steps: parse JSON payload > iterate > Supabase HTTP module writes each contact to raw_contacts

Scenario 2, PhantomBuster to Supabase (replies):
- Trigger: PhantomBuster LinkedIn Inbox phantom completes
- Steps: parse JSON > iterate > Supabase HTTP module writes each new message to outreach_log (with reply_received_at set)

Scenario 3, Companies Agent to PhantomBuster (V2 only):
- Trigger: Companies Agent flags a company ready for auto send
- Not V1

Scenario 4, Reconciliation summary to Monday (V2 only):
- Trigger: Reconciliation Agent daily summary
- Not V1

### 6.3 Apify actors

Actor 1, apify/ai-web-agent (for customer journey walks):
- Used by Companies Agent Stage 2
- Natural language instructions: "walk the PDP for iPhone 15, add to cart, proceed to checkout, capture any insurance or extended warranty offered"
- Adapts across sites without per site custom code
- Cost: ~$0.05 to $0.15 per site walk

Actor 2, apify/rag-web-browser (for clean markdown scraping):
- Used by Companies Agent Stage 1 (homepage + About)
- Returns clean markdown, strips ads and navigation
- Cost: ~$0.01 to $0.03 per fetch

### 6.4 Semrush MCP

Used by Companies Agent Stage 2 for Monthly Visits column.
Access: Pier's Semrush account (Brad requests token from Oli).
Fallback if unavailable: SimilarWeb estimate via Apify web fetch.

### 6.5 MS365 MCP

Used by:
- Coordinator (nightly run summary to Brad)
- Reconciliation Agent (daily summary to Oli)
- V2 follow up agent (Rebump replacement, sending chasers)

Access: Oli's Pier email account, permissions scoped to send only.

### 6.6 Monday MCP

Used by:
- Companies Agent (skip guardrail, read Monday warm leads before triage)
- Reconciliation Agent (daily reconciliation)

Oli agreed to configure Monday MCP for this purpose (per earlier conversation). Access: read only on the warm leads pipeline.

### 6.7 Klaviyo (post V1 for outreach)

Klaviyo is used for downstream partner comms (Pier Protect customer journey) NOT for cold outreach in V1. Wire Klaviyo when Pier Protect goes live with the first partner, not during the lead agent build.

## 7. The voice contracts

### 7.1 Non negotiable pre delivery lint

Any Outbound Agent draft that contains any of the following FAILS the lint and does NOT save to outreach_log with status pending_review. The draft is rewritten by the Outbound Agent until it passes.

Banned characters:
- em dash (U+2014)
- en dash (U+2013)
- ellipsis (U+2026)
- spaced hyphen (space hyphen space)
- horizontal bar (U+2015)

Banned words (from PIER_Rules.md and the pier terminology skill):
- insurtech
- transform
- transformation
- synergies
- synergy
- activation rate
- activation conversion
- leverage
- streamline
- unique
- uniquely positioned
- best in class
- delve (common LLM tell)
- tapestry (common LLM tell)
- landscape (common LLM tell in this context)
- I hope this finds you well
- I hope you are well
- I'll keep this brief
- I wanted to reach out
- I noticed you work at
- I came across your profile

Required substitutions:
- "attachment rate" or "attach rate" NEVER "activation rate"
- "partner" NEVER "client"
- "programme" NEVER "product" (when referring to the partner's insurance offering)
- "managed service" NEVER "SaaS" or "platform"
- Pier is the administrator NEVER "underwrites" or "underwriter"

Style rules:
- British English (colour, organisation, recognise, focussed)
- One space after full stop
- No exclamation marks in first contact or formal messages
- No positive or evaluative adjectives about Pier ("helpful", "useful", "clearly", "this should")

### 7.2 Voice contracts by market

For DACH prospects:
- Lead with AGS Pier GmbH regulatory framing, NOT FCA
- Never claim BaFin authorisation directly
- Sie default for cold, du when signalled
- Standard German for German output

For UK and non DACH European prospects:
- FCA regulation as primary credibility anchor
- British English

### 7.3 Signature openers

LinkedIn welcomes use one of these signature openers with the self deprecating tag:
- English: "Welcome to my humble network"
- German (du): "Willkommen in meinem bescheidenen Netzwerk" (with self deprecating tag)
- German (Sie): "Willkommen in meinem bescheidenen Netzwerk" (with formal wrapping)

The self deprecating tag varies. Outbound Agent picks one that matches Oli's style. Never repeats the same tag twice in the same week.

## 8. Build sequence (order of operations)

### 8.1 Week 1: Foundations

Day 1-2: Supabase setup
- Confirm pier-lead-lake-prod is provisioned in EU/Dublin
- Apply migrations for all tables in section 5
- Deploy agent-db Edge Function with x-agent-key header auth
- Seed test data: 5 companies, 10 contacts, 3 outreach drafts
- Verify: psql query from Brad's Mac connects and reads

Day 3-4: Lovable UI
- Point Lovable at pier-lead-lake-prod
- Build companies tab UI (39 columns, filterable by priority/state/tier)
- Build contacts tab UI (linked to companies)
- Build outreach log UI (drafts with approve/reject buttons)
- Build daily reconciliation summary card

Day 5-7: Migration from UK Lovable
- Export existing UK Lovable data (companies, contacts, outreach touches)
- Transform to new schema (map old columns to new 39 column layout)
- Load into pier-lead-lake-prod
- Verify counts: ~350 companies, ~397 contacts, ~222 outreach touches
- Oli spot check: 10 random companies, does the data look right?

### 8.2 Week 2: Companies Agent + PhantomBuster

Day 8-10: PhantomBuster + Make.com wiring
- Pier sets up own PhantomBuster subscription (if not done)
- Configure Sales Nav List Export phantom
- Configure LinkedIn Inbox phantom
- Configure Recently Connected phantom
- Build Make.com scenario 1 (contacts landing)
- Build Make.com scenario 2 (replies landing)
- Test: manually trigger phantom, watch data land in Supabase

Day 11-14: Companies Agent build
- Write `.claude/agents/companies-agent.md` system prompt
- Wire Stage 1 (Haiku, ~5 min per company)
- Wire Stage 2 (Sonnet, ~15-20 min per company)
- Integrate Apify ai-web-agent for customer journey
- Integrate Semrush MCP for Monthly Visits (or Apify fallback)
- Test: 5 companies end to end, review with Oli

### 8.3 Week 3: Outbound Agent + Contact Matcher + Reply Classifier

Day 15-17: Contact Matcher + Reply Classifier
- Write `.claude/agents/contact-matcher.md` (fuzzy match logic)
- Write `.claude/agents/reply-classifier.md` (sentiment + objection categorisation)
- Test on real Sales Nav output

Day 18-21: Outbound Agent
- Write `.claude/agents/outbound-agent.md` system prompt (integrating Email_Architect.md + LinkedIn_Message_Architect.md + OUTREACH_QUICK_REFERENCE.md + PIER_Rules.md)
- Build the pre delivery lint (regex + banned word list)
- Wire the non negotiable contracts
- Test on 10 real companies with Oli reviewing drafts

### 8.4 Week 4: Coordinator + Reconciliation + End to end

Day 22-24: Coordinator + Reconciliation Agent
- Write `.claude/agents/coordinator.md` orchestration logic
- Write `.claude/agents/reconciliation-agent.md`
- Wire MS365 MCP for summary emails
- Wire Monday MCP for read only Monday access

Day 25-27: End to end test runs
- Run 3 full nightly cycles with Oli reviewing outputs
- Fix regressions, tighten prompts
- Confirm success criteria from section 1.5

Day 28-30: Go live prep + handover
- Documentation review with Oli, Paul, Mark
- Set up Cowork scheduled task for automated 22:00 kick off
- Set up monitoring alerts (agent errors, Anthropic API costs, PhantomBuster credit burn)
- Brad shadow support for the first week of live running

## 9. V2 features (post go live)

### 9.1 Follow up agent (Rebump replacement)

Uses MS365 MCP + Cowork scheduled tasks. No third party tool needed.

Cadence: day 3, day 7, day 14, day 21. Each follow up is a fresh draft respecting the "no repeat" rule (never send the same message twice).

For prospects who replied "no" or "not now", apply the lifecycle clarification: pivot to OPEN questions.

Wire Rebump style tracking: unsubscribes on any reply, exits the sequence.

### 9.2 Auto send first LinkedIn message

V1 has Oli sending manually. V2 automates the connection request send once Oli has approved a draft. Uses PhantomBuster Sales Nav Sender phantom + Make.com trigger from Lovable ("send now" button).

Guardrail: never send more than X per day (LinkedIn rate limit). Never send to a contact marked "do not contact" or already sent within 90 days.

### 9.3 Multi list Sales Nav buckets

V1 uses one Sales Nav list. V2 supports multiple lists (e.g. "UK phone retailers", "DACH refurb", "EU travel insurance"). Each list has its own Sales Nav List Export phantom in PhantomBuster, its own priority weighting, its own Outbound Agent draft template.

### 9.4 Pitch deck automation

Deck Builder agent (from Oli's PIER_Deck_Builder.md), three stage methodology (Storyline > Slide Content > Visual Build). Uses the pptx skill for visual build. Not part of lead sourcing directly, but plugs in when a warm lead requests a proposal deck.

### 9.5 Full loop Reconciliation

V1 Reconciliation Agent is read only. V2 writes back:
- Auto skip in Companies Agent when Monday flags warm (rather than flagging after the fact)
- Auto dedup contacts across systems
- Auto promote warm leads from Lovable to Monday (with human confirmation prompt)

### 9.6 Cross agent handover table

V1 agents read/write directly to companies/contacts/outreach_log tables. V2 introduces a dedicated `agent_handover` table for asynchronous message passing between agents. Cleaner audit trail, easier debug, enables agent chaining beyond the coordinator.

### 9.7 Semrush + Creditsafe deep integrations

V1 uses Semrush for Monthly Visits column only. V2 pulls organic keyword rankings, backlink profile, traffic trend. Adds Creditsafe rating for credit risk assessment (deprioritise prospects with recent credit deterioration).

### 9.8 Pitch deck personalisation using Lovable data

When a warm lead is promoted to Monday, the Deck Builder agent (from V2) auto generates a personalised proposal deck using the company's actual size tier, insurance state, and known pain points from the Companies Agent output. Feeds into Rich's static overlay pattern for the customer journey mockup.

## 10. Migration plan (UK Lovable to pan European Lovable)

### 10.1 Sources

Existing UK Lovable has:
- ~350 companies
- ~397 contacts
- ~222 outreach touches

### 10.2 Path A: direct Supabase access via Lovable

Check Lovable settings for the Supabase URL of the existing UK project. If exposed:
- Use pg_dump to export companies, contacts, outreach tables
- Transform via a Python script (map old columns to new 39 column layout)
- pg_restore into pier-lead-lake-prod

### 10.3 Path B: CSV export fallback

If Supabase URL isn't exposed in Lovable settings (Lovable might obscure this):
- Export each table to CSV from Lovable's UI (companies, contacts, outreach)
- Transform via Python or pandas notebook
- Load into pier-lead-lake-prod via psql \COPY

### 10.4 Migration order

1. Companies (populate first, foreign keys depend on it)
2. Contacts (linked to companies)
3. Outreach log (linked to contacts + companies)

### 10.5 Verification

- Row count matches (allow ~5% drift for duplicates being deduped)
- Oli spot check: 20 random companies, does the data look right in the new Lovable UI?
- Companies Agent test: run Stage 1 triage on 5 migrated companies, do the results match Oli's memory?

### 10.6 Cutover

- Point Oli's daily workflow at the new Lovable
- Keep old UK Lovable running read only for 30 days as backup
- After 30 days, archive the old project

## 11. Operating rhythms

### 11.1 Brad's daily ops

Morning (~9:00 UK):
- Read Coordinator's nightly summary email
- Check for errors in Supabase errors table
- Review any unmatched contacts (Contact Matcher failures)
- Check Anthropic API costs (should be < £50/day for V1)

Weekly (Monday):
- Review Reconciliation Agent's week of summaries with Oli
- Tune prompts based on Oli's feedback on drafts
- Review Supabase agent_runs table for slow agents or timeouts

Monthly:
- Full audit: what's the ratio of drafts that pass Oli's review with no rewrite?
- Cost review: are we within budget?
- V2 feature prioritisation with Oli and Mark

### 11.2 Oli's daily workflow

Morning:
- Open Lovable, review ~10 deep researched companies
- Review each Outbound Agent draft
- Approve, send via Sales Nav manually, or reject with feedback
- Reject reasons feed the Capture Processor if pattern worth capturing

Throughout the day:
- LinkedIn Inbox phantom sweeps every 3 hours
- Positive replies get flagged in Lovable
- Oli manually promotes warm leads to Monday via Add to CRM extension

End of day:
- Quick check on outbound sent count (target: 20-30/day depending on capacity)

### 11.3 Monitoring and health checks

- Anthropic API dashboard for token spend
- Supabase dashboard for row count trends and query performance
- PhantomBuster dashboard for phantom health (execution success rate)
- Apify dashboard for actor runs and costs
- Make.com scenarios execution log
- MS365 admin for send limits (if we hit follow up automation)

## 12. Cost model

### 12.1 Recurring costs

| Item | Monthly cost (est.) | Notes |
|---|---|---|
| Anthropic API tokens | £150-£300 | Sonnet for Stage 2 + Outbound Agent, Haiku for the rest |
| PhantomBuster subscription | £60 | Pier's own account |
| Apify credits | £30-£60 | ai-web-agent + rag-web-browser |
| Make.com Core plan | £8 | Base ops volume |
| Semrush (existing) | included in Pier's subscription | No extra cost |
| Supabase Pro | £20 | pier-lead-lake-prod EU/Dublin |
| Lovable (existing) | included in Pier's subscription | No extra cost |
| Monday CRM (existing) | included in Pier's subscription | No extra cost |
| MS365 (existing) | included in Pier's subscription | No extra cost |
| Add to CRM Chrome extension | £75 | Oli's LinkedIn to Monday sync post warm |
| **Monthly total** | **£343-£563** | |

Annual total: ~£4,100-£6,750

### 12.2 One time build costs

- Brad's consulting for 30 day build (Nailed It AI invoice): agreed separately with Mark
- No hardware, no cloud VM (running on Brad's Mac in V1)
- Cowork scheduled tasks for automated 22:00 kick off: included in Cowork Pro Max

### 12.3 Cost per prospect

- Stage 1 triage: ~£0.10 per company (Haiku, homepage + About)
- Stage 2 deep research: ~£1.50 per company (Sonnet + Apify + Semrush)
- Outbound draft: ~£0.30 per contact (Sonnet, ~1000 output tokens)
- Total cost per qualified prospect ready for Oli's review: ~£2.00

At 10-15 deep researched prospects per night, ~£20-£30/day in API costs = ~£600-£900/month API.
Adding PhantomBuster, Apify, Make, Supabase: ~£720-£1,050/month all in.

The £150-£300 API figure at the top of section 12.1 is the CONSERVATIVE case (Haiku dominates, Sonnet is used sparingly). Real world will land in the middle depending on how deep Stage 2 goes per prospect.

## 13. Open decisions and pending items

Locked in after Oli call (2026-05-11):
- Cold leads in Lovable, warm leads in Monday
- LinkedIn only in DACH (GDPR)
- V1 has manual LinkedIn sending, V2 automates
- Reconciliation Agent V1 is read only

Still to confirm (Brad to nail before Week 2 build):
- Sales Nav list name (Brad is using SN URL of digits, will confirm)
- Pier's Semrush access for Companies Agent
- Monday MCP setup timing with Oli
- Migration path (A vs B) once Lovable Cloud Supabase URL is checked

Decisions punted to post V1:
- Klaviyo integration for downstream partner comms (comes with Pier Protect go live)
- Auto send first LinkedIn message (V2)
- Pitch deck automation (V2)
- Reconciliation Agent write back (V2)

## 14. Next steps for Brad (immediate actions on your return)

1. Confirm Sales Nav list name in PhantomBuster
2. Check Lovable UK Cloud settings for Supabase URL exposure (migration Path A or B decision)
3. Confirm with Oli that Monday MCP is being configured his side, deadline for that to be ready
4. Request Semrush access from Oli for the Companies Agent
5. Review this document with Mark, Oli, Paul before starting Week 1 build
6. Rework the current 6 subagent scaffold in the `pier-lead-agent` GitHub repo to match the six agent design (coordinator, companies-agent, contact-agent, outbound-agent, outreach-agent, reconciliation-agent)
7. Set up Cowork scheduled task for 22:00 nightly kick off (test with a dry run first)
8. Ask Oli for the machine readable `companies_agent_rules.yml` and the `companies_agent_lessons.md` file. Import both into `docs/pier-source-files/` so the Companies Agent system prompt can reference them at session start (his existing pattern).
9. Confirm with Oli whether the new Supabase Lovable system replaces the current Excel workbook entirely, or runs in parallel for a transition period. If parallel, we need a sync layer between Excel and Supabase.

## Appendix A: Repo structure (target for pier-lead-agent GitHub)

```
pier-lead-agent/
├── .claude/
│   └── agents/
│       ├── coordinator.md
│       ├── companies-agent.md
│       ├── contact-agent.md
│       ├── outbound-agent.md
│       ├── outreach-agent.md
│       └── reconciliation-agent.md
├── docs/
│   ├── architecture.md (link to this build doc)
│   ├── pier-source-files/ (Oli's EA source files)
│   │   ├── PIER_Rules.md
│   │   ├── Lead_and_ICP_Brief.md
│   │   ├── Email_Architect.md
│   │   ├── LinkedIn_Message_Architect.md
│   │   ├── OUTREACH_QUICK_REFERENCE.md
│   │   ├── PIER_Response_Bank.md
│   │   ├── Source_Audit_Skill.md
│   │   └── Capture_Processor.md
│   ├── data-model.md
│   ├── make-scenarios.md
│   └── voice-contracts.md
├── src/
│   ├── coordinator.py (or ts, depending on language choice)
│   ├── agents/ (agent utility scripts)
│   ├── supabase/ (edge functions, migrations)
│   └── lint/ (voice contract linter)
├── migrations/
│   ├── 001_initial_schema.sql
│   ├── 002_seed_test_data.sql
│   └── ...
├── scripts/
│   ├── migrate-from-uk-lovable.py
│   └── verify-run.sh
├── .env.example
├── .env (gitignored)
├── .gitignore
└── README.md
```

## Appendix B: Environment variables

Required in `.env` (all real values, never committed):

```
ANTHROPIC_API_KEY=<your key or Pier's production key>
SUPABASE_URL=https://<pier-lead-lake-prod-ref>.supabase.co
SUPABASE_ANON_KEY=<Pier's anon key>
SUPABASE_SERVICE_ROLE_KEY=<Pier's service role key, sensitive>
AGENT_DB_KEY=<64 char hex, openssl rand -hex 32>
APIFY_TOKEN=<Pier's Apify token>
PHANTOMBUSTER_API_KEY=<Pier's PhantomBuster key>
SEMRUSH_API_KEY=<Pier's Semrush key>
MAKE_WEBHOOK_URL=<Make.com incoming webhook for coordinator triggers>
MS365_ACCESS_TOKEN=<via MS365 MCP OAuth>
MONDAY_API_TOKEN=<via Monday MCP OAuth>
```

Fake placeholders in `.env.example` (committed):

```
ANTHROPIC_API_KEY=sk-ant-api03-xxxxx
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJhbGc-xxxxx
SUPABASE_SERVICE_ROLE_KEY=eyJhbGc-xxxxx
AGENT_DB_KEY=abc123def456...
APIFY_TOKEN=apify_api_xxxxx
PHANTOMBUSTER_API_KEY=xxxxx
SEMRUSH_API_KEY=xxxxx
MAKE_WEBHOOK_URL=https://hook.eu2.make.com/xxxxx
MS365_ACCESS_TOKEN=xxxxx
MONDAY_API_TOKEN=xxxxx
```

## Appendix C: Sample Coordinator system prompt (starter)

```
You are the Coordinator for Pier Insurance's lead sourcing and outreach system.

Your role: orchestrate the nightly run. Invoke other agents via the Task tool. Enforce caps. Handle errors.

Environment:
- Supabase project pier-lead-lake-prod (EU/Dublin)
- Access via agent-db Edge Function with x-agent-key header (env: AGENT_DB_KEY)
- Make.com webhook for triggering PhantomBuster (env: MAKE_WEBHOOK_URL)

Nightly run sequence:
1. 22:00 UK, trigger Sales Nav sweep via Make.com webhook, wait for completion
2. 22:40 UK, invoke Contact Matcher on raw_contacts
3. 23:00 UK, invoke Companies Agent Stage 1 on untriaged companies (batch of 30)
4. 00:30 UK, read Stage 1 results, pick top 10-15 P0/P1 by priority for Stage 2
5. 00:45 UK, invoke Companies Agent Stage 2 on the capped batch
6. 03:00 UK, invoke Outbound Agent on companies with drafts pending
7. 04:00 UK, invoke Reconciliation Agent
8. 04:15 UK, write nightly_summary, email Brad via MS365 MCP

Cap logic:
- Stage 2 cap is POST triage: 10-15 qualified companies per night
- Do NOT cap Stage 1 (light triage is cheap)

Error handling:
- Any subagent that errors or times out gets logged to errors table
- Continue the run, do not abort
- If more than 3 errors in a single agent, escalate to Brad in the run summary

Voice contracts:
- These do NOT apply to you (you don't draft outbound)
- But you enforce that Outbound Agent's pre delivery lint has run before marking a draft as pending_review
```

## Appendix D: Sample Companies Agent system prompt (starter)

```
You are the Pier Companies Agent. You research companies for Pier Protect fit.

You do NOT draft outbound. That's the Outbound Agent's job.

Two stages:

STAGE 1 (light triage, Haiku, ~5 min per company):
- Fetch homepage and About page via Apify rag-web-browser
- Run the CCE qualifying test: does the prospect sell hardware (phones/tablets/laptops/wearables)?
- Estimate size tier via revenue/ASP proxy, headcount proxy, or qualitative match
- Estimate insurance state via checkout inspection
- Assign priority: P0 / P1 / P2 / P3 / OoS / Competitor
- Write to companies tab columns 1-24

STAGE 2 (deep research, Sonnet, ~15-20 min per company):
- Use Apify ai-web-agent to walk PDP > Cart > Checkout
- Capture existing insurance offer if present (name, price, coverage)
- Site search sweep for insurance/warranty/protection/GDPR/competitor names
- Pull Monthly Visits via Semrush MCP
- Populate full 39 column companies schema
- Propose pillar priority (P1/P2/P3) for Outbound Agent

Follow the 10 section brief structure from Lead_and_ICP_Brief.md (attached to your context).

Apply Pier Rules ambient contracts (PIER_Rules.md attached):
- Never invent partner names or metrics
- Never claim regulatory positions not in the Capability Reference
- Voice: British English, no em/en dashes anywhere you write

Prospect profile:
- Every Pier Protect prospect carries TWO dimensions: size tier + insurance state
- Name both explicitly in the priority assignment
- Size tier bands (Mark, 3 June 2026): T1 25,000+/mo, T2 5,000-25,000/mo, T3 2,000-5,000/mo
- Country floor: UK 1,000+/mo, Europe 2,000+/mo
- Insurance state: Greenfield / Annual recurring / Monthly recurring
- Priority default: Highest T1/T2 Greenfield, High T1/T2 Annual, T3 Greenfield, Medium T1/T2 Monthly with optimisation, T3 Annual, Lower T3 Monthly

For Annual/Monthly recurring state prospects, populate the 10 question incumbent discovery framework as open questions (Lead_and_ICP_Brief.md section 3.11).

Cost budget: no more than £2 per company deep researched.

Rules imported from Oli's Companies Agent bootstrap 2026-05-18:

INSURANCE OFFERED requires full journey walk. Never stamp Insurance Offered? = No without walking PDP > Cart > Checkout AND running a site search sweep for insurance / protection / cover / warranty in EN plus locale terms (Versicherung, Schutz, assurance, garantie, verzekering). Case in point: ViberStore has a real €169.99 insurance product invisible on PDPs, only findable via /search?q=insurance.

STAGE 1 mandatory pages: homepage AND About page (or equivalent /uber-uns, /qui-sommes-nous). Homepage only misses fundamentals.

VERIFIED ONLY: every factual claim in USP/Notes cites a source (URL, LinkedIn profile URL, Companies House lookup, prior agent stamp). No inferred facts without an "inferred from X" qualifier.

INTERNAL REVIEW block: any USP/Notes with verification gaps includes:
--- INTERNAL REVIEW, DELETE BEFORE SENDING ---
Verified: [list of facts used, with source]
GAPS: [list of what's missing]
--- END INTERNAL ---

GEO ICP role based not location based: a Singapore based EMEA country manager is IN SCOPE; a DACH based APAC only exec is OUT OF SCOPE.

NEVER write to Contacts or Outreach Log. If you need contact changes, request via agent_handover.

PRE/ACT/POST VERIFY: every UPDATE to companies is preceded by a SELECT and followed by a SELECT to confirm the write took. Halt on mismatch.
```

## Appendix E: Sample Outbound Agent system prompt (starter)

```
You are the Pier Outbound Agent. You draft LinkedIn welcomes and email outreach for Pier Protect.

Your four non negotiable contracts:
1. DATA ONLY. You never send anything. You save drafts to outreach_log with status pending_review.
2. ATOMIC SAVE. One draft = one row. No batching.
3. PRE DELIVERY LINT. Every draft goes through the linter (attached script). Any draft with em dash (U+2014), en dash (U+2013), ellipsis (U+2026), spaced hyphen, or a banned word FAILS and gets rewritten. Do not save a failing draft.
4. VERIFIED ONLY. Cite only facts from PIER_Rules.md, PIER_Capability_Reference.md, and OUTREACH_QUICK_REFERENCE.md.

For every cold outbound draft, apply Mark's Sales DNA six point checklist BEFORE finalising:
1. Substance anchor in the opener
2. Closed yes/no question at the end
3. Discovery before pitch
4. Partner outcome framing (4-5x their numbers, NEVER Pier's 8-12% attach as headline)
5. Peer to peer register
6. Always closing next step ask

Length caps (LinkedIn):
- Connection request: 30-50 words, hard cap 60
- Connection accepted follow up: 60-100 words, hard cap 120
- Cold inMail: 80-120 words, hard cap 140
- Reply to inbound: match their length, cap at 1.5x

Voice:
- British English default
- Sie for German cold contact, du when signalled
- Sign as the user (from context), never default to Oli
- LinkedIn signature opener with self deprecating tag: "Welcome to my humble network" (English), "Willkommen in meinem bescheidenen Netzwerk" (German)
- Do not use the same self deprecating tag twice in the same week

Banned:
- em dash, en dash, ellipsis, spaced hyphen
- "insurtech", "transform", "synergies", "activation rate", "leverage", "streamline", "uniquely positioned", "best in class"
- "I hope this finds you well", "I trust you are well", "I'll keep this brief"
- "delve", "tapestry", "landscape" (LLM tells)

Door in framing keyed to insurance state:
- Greenfield: "recurring revenue stream at zero implementation cost, fully managed"
- Annual recurring: "recurring revenue model alongside what you already do", 4-5x partner outcome, do NOT reveal Pier's mechanic in cold contact
- Monthly recurring: pillar three optimisation curiosity, do NOT propose a switch in first contact

Sales motion adjusts for size tier:
- T1: multi stakeholder, longer cycle, more formal register
- T2: peer to peer, 3-6 month cycle
- T3: single decision maker, shorter cycle, lighter peer to peer

If any input is unclear, ask ONCE. Do not invent context.
```
