# F19.7 / F19.8 - Scoring model storage proposal and DACH import dry run

Date: 2026-09-21. Status: READ-ONLY research and dry run. Nothing was written to the database, no
migration applied, no Edge Function called, Lovable / Make / PhantomBuster untouched. Every database
figure below came from a SELECT against project `qzfrcfzeiagziqjnfarw`. The only functions executed
were `STABLE` SQL read functions (`fn_group_siblings_engaged`, which calls `fn_company_group_pairs`).

Sources read in full: `260904_PIER_lead_scoring_model_v01_OM_C2.md` (header says Version 03),
`260904_PIER_opportunity_sizing_standard_v01_OM_C2.md` (v03). Parsed with python:
`260908_PIER_lovable_board_export_v01_OM_C2.csv` (73 rows x 40 cols, confirmed),
`260904_PIER_volume_estimates_v01_OM_C2.csv` (70 rows x 13 cols, confirmed), `interim_intel.jsonl`
(3 lines). `Lead_and_ICP_Brief.md` was found at `docs/pier-ea-source-files/Lead_and_ICP_Brief.md`;
it has a section 8 ("Lovable lead output") but NO section 8.1(g). The only "8.1" in the pack is the
master handover's "8.1 Ticketplan and Pier Protect must be separable". See assumption A12.

---

## PART A - The scoring model, faithfully summarised

### A.1 Four things kept apart (model section 2)

| | Answers | Form | Blended? |
|---|---|---|---|
| GATE | May we contact at all? | binary | Never. "No score unlocks a DNC." |
| VALUE | How big is it? | GBP per year | Reported next to the score, never inside it |
| SCORE | How ideal a customer? | 0 to 100 | GWP band is one component |
| ACCESS | What does a conversation cost? | 5 rungs: warm / open / sourcing / paid / locked | Reported beside value, "never averaged with it" |

The model is explicit that ACCESS (which is where "has contacts" lives) is never averaged into the
score: "An average hides which lever to pull." This matters for Part D.

### A.2 Company score, 100 points, four components

| Component | Points | How assessed |
|---|---|---|
| GWP potential band | 40 | Annual value to Pier in GBP, banded: XL 40 (GBP 250k+), L 30 (50k+), M 20 (10k+), S 10 (below). "Bands are on money, not units." Value = volume x attach x GBP 40; sizing standard prices online at 8% and in-store at 25%. Input is `devices_per_month` from the evidence ladder E1-E5. E0 = UNSIZED = component unassessed. |
| Incumbent switchability | 30 | `switchability = GAP - LOCK-IN`, range -4 to +4, and the 30 points scale on that. GAP 0-4 (4 no cover at all; 3 cover excludes drop/liquid/theft, or self-funded guarantee with no IPID/insurer; 2 real insurance billed one-off or annual; 1 monthly but buried/weak attach; 0 monthly, no excess, cancel anytime). LOCK-IN 0-4 (4 captive carrier sharing the retailer's name; 3 deep inline integration under own brand; 2 third-party inline standard embed; 1 links out; 0 nothing to displace; +1 if over 12 months of contract term remain, which must be asked). Captive test requires an explicit carrier phrase naming a company that shares a name token with the retailer (Conrad self-carried risk is NOT captive: Conrad 20/30, Telia 6). Observable evidence beats a missing classification. |
| Territory | 15 | One rank table, no hardcoded country logic. Rank 1 current focus = 15 (DE, AT, CH); rank 2 next = 11 (FR, ES, IT); rank 3 opportunistic = 7 (NL, BE, LU, IE); rank 0 not sequenced = 3 (PL, Nordics, HU, CZ, PT, EE); rank -1 someone else's = 0 (UK, and the gate blocks it). A country not in the table scores rank 0 "and says so in the output". |
| Wedge quality | 15 | Four independent pass/fail tests on text in the row: Exists 5 (or 2 for a stub under 60 chars); Evidenced 4 (dated AND re-openable source), 2 (date only), 0; Quote-safe 4 (verbatim quotation present); Specific 2 (names an uncovered peril or the incumbent insurer). Staleness: minus 4 when the walk is over 180 days old, floored at 2. |

Lead score is separate and hierarchical (decision power 50, channel 30, personalisation readiness
20): "You never rank a contact at company A against a contact at company B."

Timing (renewal date) is a multiplier fixed at 1.00 until a date is known, then x1.35 inside 180
days. Cooldown expiry belongs in the gate and diary, not the score.

### A.3 Every rule about unassessed components (R2), in the model's own words

Scoring model section 4.3, quoted:

> "A component with no data is **removed from the denominator**, not scored zero. A company reports
> **"90/100, 60 of 100 points assessed, GWP unassessed"**, never a flat 54."

> "Scoring a missing component zero penalises a company for our own research backlog and buries
> exactly the accounts nobody has looked at yet. Every output states what it could not assess."

Sizing standard section 3, quoted:

> "A company with no reachable rung is **UNSIZED**. It is not "S", not "T3", not zero. It is removed
> from the score denominator and reported as unassessed ... Scoring an unresearched company as small
> buries it, which is the same failure as the blanket incumbent rule that buried Galaxus."

Master handover section on scoring, quoted: a company reads "**77 of 100 assessed**" or
"**57, 60 of 100 assessed**".

Other unassessed rules:
- Incumbent: "Unknown, with nothing observed either way, scores **14 of 30** - never 0, so an
  unresearched company cannot sort below a known-bad one." NOTE: this is a neutral default, not a
  removal from the denominator. It is the one place the model does not follow its own 4.3 rule. All
  11 E0 board rows that show incumbent 14 are this default. Flagged for a ruling (assumption A3).
- Territory: an unknown country scores rank 0 (3 points) and must say so; it is visible, not silent.
- `explain` must print each component, its points, and what could not be assessed: "If a number
  cannot be explained by that command, it is a bug, not a judgement."
- E0 has two meanings that must stay distinguishable: "Untracked" (checked, below Similarweb's
  threshold, itself a size signal) and "Not reachable" (genuinely unknown).

### A.4 What the board actually stores (checked, not assumed)

`score_0_100` on the board is a PERCENTAGE OF ASSESSED, not raw points. Proof from the file:
porst-emsdetten has incumbent 30 + territory 15 + wedge 5 = 50 raw points, `score_assessed` = 60,
and `score_0_100` = 83 (50/60). complit-edv: 54/60 = 90. For the 62 rows with `score_assessed` = 100
the two are identical. Distribution: 62 rows at 100 assessed, 11 rows at 60 assessed (all 11 are E0,
GWP unassessed). So the importer must store raw points AND denominator, and must not read
`score_0_100` as points.

---

## PART B - Current database shape (SELECT only)

### B.1 `public.companies` columns relevant to score / priority / size

| Column | Type | Note |
|---|---|---|
| `priority` | enum `priority_level`, nullable, no default | labels: P0, P1, P2, P3, OoS, Competitor |
| `research_stage` | enum, NOT NULL default 'Untouched' | Untouched, Light triage, Deep research done, Outdated (confirmed via pg_enum) |
| `opportunity_status` | enum, NOT NULL default 'To Review' | To Review, Prospect, Contacted, Active Lead, Partner, Out of Scope (confirmed) |
| `contacts_count` | integer NOT NULL default 0 | the only "has contacts" signal on the row |
| `root_domain`, `website_url` | text | see B.4 |
| `parent_group` | text | drives the group guard |
| `estimated_revenue_gbp`, `employees`, `monthly_visits` | numeric / int / int | inputs to E2 / E3 / E4 |
| `annual_devices_sold` (+ `_evidence`, `_stated_by`) | text | legacy free text; guarded by `trg_companies_stated_figure_guard` |
| `insurance_offered`, `insurance_provider`, `insurance_structure_type` (enum: Optional Add-On, Bundled, Upsold, Embedded in T&Cs, Redirect to Third-Party, Other), `insurance_monthly_price`, `insurance_annual_price`, `coverage_summary`, `policy_url`, `distribution_model` | | incumbent inputs |
| `usp_notes`, `additional_notes`, `field_provenance` (jsonb), `needs_review`, `added_via`, `merged_from_refs` | | |

**No score column exists anywhere.** A search of every public table for columns named like score,
rung or devices found only `duplicate_candidates.match_score`, `insights_snapshots.similarity_scores`
and `outreach_log.lint_score`, none of which is a company score.

### B.2 `public.company_size` - exists, 0 rows

Columns: `id`, `team_id`, `company_id` (uuid FK to companies.id, on delete cascade), `recorded_at`,
`devices_per_month`, `devices_per_year`, `phones_share`, `laptops_share`, `accessories_note`,
`online_share`, `in_store_share`, `own_channel_share`, `rung` (NOT NULL), `confidence`, `basis`
(NOT NULL), `tier_mark`, `is_estimate` (NOT NULL), `stated_by`, `stated_on`, `evidence_verbatim`,
`ceiling_caveat`, `superseded_by`, `created_by`, `created_at`. View `v_company_size_current` exists.
Trigger `trg_company_size_append_only`. **Row count: 0.**

CHECK constraints that the import must satisfy (these already enforce R4):
- `rung` in (E0, E1, E2, E3, E4, E5) and NOT NULL: a devices figure with no rung cannot be inserted.
- `confidence` in (high, medium, low-medium, low, none).
- `tier_mark` null or in (T1, T2, T3, below_floor, unsized).
- E0 implies `devices_per_month` and `devices_per_year` are both NULL.
- `is_estimate = false` requires rung E1 AND non-empty `evidence_verbatim` AND `stated_by`;
  `is_estimate = true` requires rung <> E1.
- all share columns between 0 and 1.

### B.3 `companies.priority` distribution

All 1,137 companies: NULL 636, P3 182, OoS 167, P1 83, P2 44, P0 21, Competitor 4.
Live only (`archived_at is null`, 781): NULL 503, P3 149, P1 68, P2 38, P0 16, OoS 7.
So 64% of live companies have no priority; in every candidate function below they fall into the
`ELSE 4` bucket, which is the "unassessed sorts last" failure R2 exists to prevent.

### B.4 Domains

1,137 companies; 609 have `root_domain`, 609 have `website_url`, 609 have either (the same 609).
528 companies (46%) have no domain at all, so exact-domain matching cannot see them. `root_domain`
stores the HOST, not the registrable domain (example: `boutique.ateliers-du-bocage.fr`); 53 values
have three labels. 12 root_domain values are shared by more than one company.

### B.5 How `priority` is used in the six functions

| Function | Exact clause | What changes with a numeric score |
|---|---|---|
| `fn_chase_candidates(p_team_id, p_limit=25)` | returns `co.priority::text AS priority`; `ORDER BY CASE b.priority WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END, b.last_outbound ASC LIMIT p_limit` | Sort key becomes the score sort key (Part C). Return column `priority text` is in the signature, so callers (Edge Functions, Lovable) read it: keep the column and ADD score columns, or it is a breaking RETURNS TABLE change needing drop and recreate. NULL priority currently sorts last with OoS and Competitor. |
| `fn_cold_inmail_candidates(p_team_id, p_limit=5)` | returns `co.priority::text`; `ORDER BY CASE co.priority::text WHEN 'P0' ... ELSE 4 END, 3 ASC NULLS LAST LIMIT p_limit` | Same. This one spends InMail credits with a limit of 5, so ordering decides who gets paid outreach; it is the function where the score matters most and where R2 must hold. |
| `fn_first_message_candidates(p_team_id, p_limit=5)` | returns `co.priority::text`; `ORDER BY CASE co.priority::text WHEN 'P0' ... ELSE 4 END, c.last_contacted ASC NULLS LAST LIMIT p_limit` | Same. |
| `fn_send_ready_contacts(p_team_id)` | FILTER only: `AND co.priority IS DISTINCT FROM 'OoS'` (beside `co.opportunity_status::text NOT ILIKE 'out of scope%'` and `co.research_stage IN ('Light triage','Deep research done')`) | This is a GATE, not a rank. A numeric score cannot replace it: "No score unlocks a DNC." If `priority` is retired, OoS must survive as a gate flag (opportunity_status 'Out of Scope' already duplicates it). |
| `fn_supply_unlocks(p_team_id)` | FILTER only: `AND co.priority IS DISTINCT FROM 'OoS'` | Same as above. |
| `fn_capture_dq_snapshot(p_team_id)` | DQ counters: `count(*) FILTER (WHERE priority IS NULL)` and the combined gap counter `... OR priority IS NULL)` into `v_prio`, `v_cwg` | Would become "score missing or assessed denominator below threshold". Changing it breaks the time series in the snapshot table, so add a new counter rather than redefine `v_prio`. |

No view and no other public function references `priority` (checked `pg_views.definition` and
`pg_proc.prosrc`). Edge Function and Lovable code were not inspected for direct reads of
`companies.priority` (out of scope for a read-only DB pass; assumption A11).

Recommendation for the cutover, not for now: keep `priority` as a human override and gate
(OoS / Competitor), add the score as a second sort key, and only later swap the primary key. The
three ORDER BY clauses are identical, so one shared SQL function `fn_company_sort_key(company_id)`
would remove the triple maintenance.

---

## PART C - PROPOSED storage for the score (proposal only, no migration written)

### Option C1 - columns on `public.companies`

`score_gwp`, `score_incumbent`, `score_territory`, `score_wedge` (smallint, nullable); four
`*_assessed` booleans; generated `score_points`, `score_assessed_denominator`, `score_pct`,
`score_display`; `score_version`, `scored_at`, `scored_by`.

For: one join fewer, trivially sortable, Lovable reads it with the row.
Against: no history (a re-score overwrites the evidence of what changed and why); 13 more columns on
a 57-column table with 7 triggers including an audit trigger that would fire on every re-score; the
component working (gap, lock-in, wedge tests) has nowhere to live; it breaks the pattern the
handover asked for ("append-only, with its rung").

### Option C2 (RECOMMENDED) - append-only `company_score` table + `v_company_score_current`

Mirror `company_size` exactly, because the GWP component is derived from a `company_size` row and
the two must be re-computable together.

| Column | Type | Rule |
|---|---|---|
| `id`, `team_id`, `company_id` (uuid FK) | | as `company_size` |
| `gwp_points` | smallint null | CHECK in (10, 20, 30, 40) or null |
| `gwp_assessed` | boolean NOT NULL | CHECK `gwp_assessed = (gwp_points is not null)` |
| `gwp_size_id` | uuid null FK `company_size.id` | the sizing row the band came from; CHECK null when not assessed; MUST be a row with rung <> 'E0' |
| `incumbent_points` | smallint null, 0-30 | |
| `incumbent_assessed` | boolean NOT NULL | same equality CHECK |
| `incumbent_gap`, `incumbent_lock_in` | smallint null, 0-4 and 0-5 | the two axes, so the 30 is explainable |
| `incumbent_basis` | text | 'observed' or 'default_unknown_14' (see A3) |
| `territory_points`, `territory_assessed`, `territory_rank` | smallint / boolean / smallint | |
| `wedge_points`, `wedge_assessed` | smallint 0-15 / boolean | |
| `wedge_tests` | jsonb | {exists, evidenced, quote_safe, specific, stale} so every point is attributable |
| `score_points` | smallint GENERATED | sum of the non-null component points |
| `assessed_denominator` | smallint GENERATED | 40*gwp_assessed + 30*incumbent_assessed + 15*territory_assessed + 15*wedge_assessed |
| `score_pct` | numeric(5,1) GENERATED | `score_points * 100.0 / nullif(assessed_denominator, 0)`; NULL when nothing assessed |
| `score_display` | text GENERATED | '77 of 100 assessed'; '50 of 60 assessed (83%), GWP unassessed'; 'unscored' when denominator is 0 |
| `unassessed` | text[] GENERATED or set by scorer | e.g. {gwp} so "every output states what it could not assess" |
| `score_version` | text NOT NULL | e.g. 'company-v03' (the model file is Version 03) |
| `scored_at` | timestamptz NOT NULL default now() | |
| `scored_by` | text NOT NULL | 'import:board_260908', 'fn_score_company', or a user id |
| `source` | text | file or function that produced it |
| `superseded_by` | uuid null FK self | append-only, same trigger pattern as `trg_company_size_append_only` |

Hard CHECKs that make R2 structural, not a convention:
1. `assessed = (points is not null)` per component, so a zero can only mean a real zero
   (territory rank -1, or GAP - LOCK-IN at the floor), never "not looked at".
2. `assessed_denominator` is generated, so nobody can write 100 beside a partial score.
3. No NOT NULL default of 0 on any points column.

Display rule: `score_display` always carries the denominator. The bare number is never rendered.
Note the wording choice: the master handover writes "77 of 100 assessed" for a fully assessed
company and "57, 60 of 100 assessed" for a partial one, where 57 is a percentage. I recommend
showing RAW points with the denominator and the percentage in brackets ("34 of 60 assessed, 57%"),
because "57, 60 of 100" invites reading 57 as points. Needs Brad's ruling (A2).

### How sorting must treat different denominators

The problem: sorting by `score_pct` alone lets a company with 15 of 15 assessed (only the country is
known, 100%) outrank aetka at 94 of 100. Sorting by `score_points` alone does the opposite and
buries every unsized company, which is the Galaxus failure. The valid denominators are the subset
sums of {40, 30, 15, 15}: 15, 30, 45, 55, 60, 70, 85, 100.

| Approach | Behaviour | Verdict |
|---|---|---|
| Raw points desc | 50 of 60 sorts below 66 of 100 | Violates R2. Reject. |
| Percentage desc only | 15 of 15 = 100% tops the list | The accident the brief warns about. Reject. |
| Pessimistic bound (unassessed = 0) | same as raw points | Violates R2. Reject. |
| Optimistic bound (unassessed = max) | 15 of 15 becomes 100 of 100 | Rewards ignorance. Reject. |
| Shrinkage toward a prior (unassessed = portfolio mean for that component) | statistically tidy | It writes an invented number into the rank; hard to explain with `explain`. Reject for now. |
| **Coverage tier, then percentage (recommended)** | Tier 1 "rankable": `assessed_denominator >= 60`. Tier 2 "needs research": below 60. ORDER BY tier, `score_pct` DESC, `assessed_denominator` DESC, then a deterministic tie-break (`last_outbound`, as today). | Keeps R2 (nothing unassessed is zeroed), stops thin scores outranking full ones, and turns tier 2 into a research queue rather than a graveyard. |

Why 60: it is exactly the case the board already has (everything but GWP), and it means incumbent,
territory and wedge have all been looked at. At 60 the 11 E0 board rows stay in the rankable tier,
which is what the model intends ("90/100, 60 of 100 points assessed"). A threshold of 70 or 85
would push every unsized company out again. The threshold should be a `settings` value, not a literal.

Trade-offs to accept: (1) inside tier 1 a 54 of 60 (90%) does outrank an 84 of 100; that is the
model's stated intent, and the display makes the thinner basis visible; (2) tier 2 companies cannot
reach the top of a send queue until researched, which is correct because the send gate already
requires `research_stage IN ('Light triage','Deep research done')`; (3) `devices_per_month` appears
nowhere in the sort (R4): size enters only through the 4-step GWP band.

---

## PART D - PROPOSED "having contacts raises the score" weighting (needs Brad's approval)

Contact counts below are `companies.contacts_count` on the database row each board company would
most likely join to. Except getgoods, those joins are FUZZY and unconfirmed (Part E), so treat the
counts as illustrative.

| Board company | Stored score | Likely DB row | contacts |
|---|---|---|---|
| aetka | 94 of 100 | C1356 aetka GmbH | 4 |
| bueromarkt-ag | 84 of 100 | C1362 Boettcher AG | 5 |
| 1ashop.at | 84 of 100 | C1365 Primus office products | 2 |
| CLS-IT | 84 of 100 | none (new) | 0 |
| berlet | 77 of 100 | none (new) | 0 |
| getgoods.com | 76 of 100 | C1349 (exact) | 1, but group-guard blocked |
| complIT EDV | 54 of 60 (90%) | none (new) | 0 |

### Option D1 - bonus points outside the 100, capped at +10

+3 for one live contact, +6 for two or three, +10 for four or more. Shown as "84 of 100 assessed
+10 reach". Worked: bueromarkt 84+10 = 94 ties aetka's base 94 (aetka becomes 104); 1ashop 84+6 = 90;
CLS-IT stays 84; complIT 54 of 60 +0.
R2: technically intact if the bonus never enters the denominator, but the sum 104 is no longer a
score out of anything, percentages stop being comparable across denominators (is +10 added to 54 of
60 before or after the division?), and it blends ACCESS into SCORE, which the model forbids in
section 2. Not recommended.

### Option D2 - readiness multiplier on the sort key (x1.00 none, x1.05 one, x1.10 two or three, x1.15 four plus)

Precedent: the model's own renewal timing multiplier (section 8). Worked on `score_pct`:
bueromarkt 84 x 1.15 = 96.6; aetka 94 x 1.15 = 108.1; 1ashop 84 x 1.10 = 92.4; complIT 90 x 1.00 =
90.0; CLS-IT 84.0; berlet 77.0. So bueromarkt and 1ashop jump over complIT purely on contacts.
R2: intact only if the multiplier is applied to the sort key and never stored or displayed as the
score. Weakness, in the model's words about multiplying: "it hides which half is weak, so 'great
account, wrong people' becomes indistinguishable from 'right people, poor account'". It also
penalises exactly the unresearched accounts (0 contacts) that R2 protects. Not recommended.

### Option D3 (RECOMMENDED) - a separate reachability figure beside the score, used as the second sort key inside a score band

Store nothing in the score. Compute `reach` per company from contacts, using the model's ACCESS
ladder: warm (accepted connection) 4, open (live contacts, no credit needed) 3, paid (all known
contacts blocked or in cooldown) 2, sourcing (no contacts) 1, locked 0; show the contact count with
it. Display: "84 of 100 assessed | reach: open, 5 contacts".
Queue order: coverage tier, then score BAND (10-point bands of `score_pct`), then `reach` DESC, then
`score_pct` DESC.
Worked, band 90-100: aetka (94, 4 contacts) then complIT (90%, 0 contacts, reach "sourcing").
Band 80-89: bueromarkt (5 contacts), 1ashop (2), then CLS-IT (0). Band 70-79: getgoods would lead
on contacts but is withheld by the group guard, then berlet (0 contacts, reach "sourcing", which
tells Oliver the action is "find people", not "skip").
So having contacts DOES raise a company in the work queue, which is Brad's requirement, but only
among companies of comparable quality, and the stored score of CLS-IT or berlet is untouched.

**Which keeps R2 intact, plainly: D3 is the only option that keeps R2 fully intact.** The score and
its assessed denominator are never altered by something that is not one of the four components.
D1 and D2 can be made R2-safe only with care and both contradict the model's "access is never
averaged in". D3 also matches master handover guidance to show deal size and reach beside the score.
One caution for D3: reach must be computed from contact STATE (connection_status, outreach_status,
cooldown), not from `contacts_count` alone, since a company whose five contacts are all in cooldown
is "paid", not "open".

---

## PART E - DACH import dry run (NO WRITES)

### E.1 Method

Domain derivation per board row: lowercase, strip scheme, strip `www.`, strip path, extract every
hostname in the cell (some cells hold two, e.g. `post.ch / shop.post.ch`,
`complit.at (shop: verkauf.complit.at)`). Compared against `lower(companies.root_domain)` and against
the host parsed from `companies.website_url`. A registrable-domain-only match (same last two labels,
different host) was computed separately and would go to review, not merge: there were none.
Two board rows have no domain at all: John's Handy ("NONE WORKING") and BC-GmbH ("none - marketplace
seller only"). minaxum's domain is `minaxum.it`.

Fuzzy method (stated as required): names normalised (lowercase, umlauts transliterated, legal
suffixes and punctuation removed), then a candidate is raised when pg_trgm `similarity()` >= 0.45, OR
one normalised name contains the other (both >= 5 chars) AND similarity >= 0.20. This was run twice:
board `company` vs `companies.company_name`, and board `legal_entity` / `parent_group` vs
`companies.company_name`. The second pass was essential (see E.3). All 1,137 companies were
searched INCLUDING archived ones, deliberately, so an archived or Out of Scope twin is surfaced
rather than silently re-created.

### E.2 Tier 1 - EXACT DOMAIN matches: 3 (merge automatically)

| Board row | Company | Match |
|---|---|---|
| Ackermann (ackermann.ch) | C1348 "Ackermann Vertriebs AG (ackermann.ch)", Prospect, Light triage, 0 contacts | host, root_domain and website_url |
| getgoods.com | C1349 "getgoods.com (get your goods GmbH)", Prospect, Light triage, 1 contact | host |
| toredo (toredo.de) | C1367 "Toredo Shop", Prospect, Light triage, 1 contact | host |

C1348 and C1349 were created on 2026-09-09 by `added_via` = `ruling_C315_2026-09-04` /
`ruling_C316_2026-09-04`, i.e. the interim rulings have ALREADY been applied to the database.

### E.3 Tier 2 - FUZZY NAME candidates: 22 board rows (human review queue, never auto-merged)

Key finding: on 2026-09-15 a batch of companies was created with `added_via = 'reconciliation_confirm'`
under their LEGAL ENTITY names, with no domain, carrying the contacts Oliver sourced. The board names
the same businesses by storefront. Domain matching cannot see them (no domain) and storefront-name
matching misses most of them; only the legal-entity pass finds them.

Strong candidates (13 rows; similarity 1.00 on name or legal entity unless stated):

| Board row | Candidate | Note |
|---|---|---|
| aetka | C1356 aetka GmbH (To Review, 4 contacts) | |
| Buchmann | C1363 Buchmann Direct Electronics (1 contact) | |
| Foletti Computer | C1358 Foletti Computer (1 contact) | |
| GSMshop.at | C1360 AB Gsmshop.at GmbH (1 contact) | CONFLICT: DB says opportunity_status 'Out of Scope', board says Oliver 'sourced' |
| 1ashop.at | C1365 Primus office products Handelsges.m.b.H. & Co KG (2 contacts) | via legal entity |
| bueromarkt-ag | C1362 Boettcher AG (5 contacts) | via parent/legal |
| easynotebooks | C1353 Net Factory Gesellschaft fuer Netzwerkloesungen mbH (4 contacts) | ONE DB company |
| notebook.de | C1353 (same row) | maps to TWO board rows: a merge would collapse two storefronts; reviewer must decide parent vs storefront |
| kaufen.avatel | C1361 AVATEL Kommunikation (1 contact) | sim 0.29, containment |
| future-x | C1364 TAROX AG (1 contact) | parent, not the storefront; also weak hit C903 FutureDial (false) |
| technikdirekt | C1354 Duttenhofer GmbH & Co. KG (duttenhofer.de, 6 contacts) | DIFFERENT domain, same legal entity; also weak hit C331 HOFER KG (false) |
| preiswertepc | C892 ALSO Recommerce AG (2 contacts) | also weak hit C336 ALDI E-Commerce (false) |
| verkaufen.ch | C149 Recommerce Group (ARCHIVED, FR), C150 re/commerce Group (FR), C892 ALSO Recommerce AG | ambiguous: board legal entity is "Recommerce AG" (CH); none of the three is clearly it. Also C973 "Verkaufen.de Internet GmbH" (archived, Out of Scope) is a different company |

Weak candidates (9 rows; expected to be rejected by the reviewer, listed because the rule says review):

| Board row | Candidate(s) |
|---|---|
| **Handyshop.cc** | **C533 Handyshop Graz (handyshop-graz.at, ARCHIVED, Out of Scope), sim 0.53 - KNOWN FALSE PAIR** |
| **mobiledevice.ch** | **C1078 Mobile Device as a Service (mobile-device-as-a-service.de, ARCHIVED, Out of Scope), sim 0.50 - KNOWN FALSE PAIR**; C046 "Device" (containment); C1335 Tesco Mobile (containment artefact of legal entity "comob") |
| **fnac.ch** | **C412 Fnac (fnac.es), sim 0.50 - KNOWN FALSE PAIR (Fnac Spain)** |
| mobizone | C471 mobilezone (mobilezone.ch), sim 0.54 - different company, likely false |
| mobileking | C507 Mobile Vikings, C254 Mobiles |
| ElectronicShop24 | C059 Electronics Bazaar, C422 electronic4you, C1088 electronis |
| expert-technomarkt | C425 Expert (containment) - not a duplicate, but a possible GROUP relation (expert cooperative) |
| sabi-online | C425 Expert, via legal entity "Expert Sabitzer Livingstyle GmbH" - same group note |
| avento.shop | C233 Game, via parent "Gametime AG" - false |

**The three known false pairs are confirmed: all three land in "fuzzy, review". None has an exact
domain match, so none can merge.** Two of the three DB twins are archived and Out of Scope, so an
automatic name merge would have attached live DACH prospects to dead rows. Two pure containment
artefacts were excluded by the similarity >= 0.20 floor (i-cs -> "Alcom" inside
"individu-al-com-putersystems", sim 0.09; NeiFlex -> "Flexit", sim 0.17); both rows count as NEW.

### E.4 Tier 3 - NEW companies: 48

baur, berlet, xtreme.metacomp, mylemon.at, CLS-IT, c-nw, DiTech.at, cw-mobile, Haustechnik Hochrieder,
SKC Computer & Multimedia Store, orderflow.ch, zodis, PostShop (Swiss Post), maconline, macconsultshop,
25n, geniuzcom, itkadmin, jb-computer, itboost, Haushaltsparadies, BA-Computer, insachendruck, I-CS,
Singer Komputer, heinzsoft-shop, handy24, boomstore, allesfuerzuhause, price-guard, office discount,
electronova-luzern.ch, highdefinition.ch, freecall24 AG, minaxum, timia.ch, red-tech, porst-emsdetten,
complIT EDV, ms-it-beratung, NeiFlex, Handycenter Voecklabruck, cupertech, so-it.ch, John's Handy,
ofrex.ch, bohnettrade.ch, BC-GmbH.

Caveats on "new": John's Handy and BC-GmbH have no domain, so they can never be domain-matched later;
DiTech.at is an Oliver 'skip' and the sizing standard links it to e-tec (C426, e-tec.at, already in
the DB) through Wertgarantie; berlet is majority-owned by EURONICS Deutschland eG (C326 Euronics
Deutschland, Prospect, Deep research done, 5 contacts) so it is NEW as a company but NOT free to
contact (see E.9); baur is an Otto Group company (C315).

### E.5 Board column mapping

| Board column | Home | Note |
|---|---|---|
| `company` | `companies.company_name` | |
| `domain` | `root_domain` + `website_url` | multi-host cells need a rule: first host = root_domain; shop subdomain into notes |
| `country` | `country` | values Germany / Austria / Switzerland exist verbatim in the DB |
| `parent_group` | `parent_group` | CAUTION: on the board this often holds the OPERATOR or a person ('Sayadi', 'Andreas Lukawinsky'), not a group. The group guard rule R1 matches on exact parent_group text, so loading it blindly creates false "groups" only if two rows share it (easynotebooks / notebook.de will, correctly). interim_intel overrides it for getgoods and Ackermann |
| `sales_channel` | `distribution_model` (text) | |
| `insurance_on_site` | `insurance_offered` / `coverage_summary` | |
| `insurer_named` | `insurance_provider` | |
| `billing_shape` | NO clean home | free text with 21 distinct values; `insurance_structure_type` is an enum about placement (Optional Add-On, Bundled, ...) not billing. Do not coerce. Goes to the proposed `company_score.incumbent_*` working or notes |
| `wedge` | `usp_notes` | |
| `caveat` | `additional_notes`, or `company_size.ceiling_caveat` where it is a sizing caveat | |
| `devices_per_month`, `devices_per_year`, `in_store_share`, `size_rung`, `size_confidence`, `tier_mark` | `company_size` | value translation needed, see E.6 |
| `phones_per_year`, `laptops_tablets_per_year` | `company_size.phones_share`, `laptops_share` | derive as ratios of devices_per_year |
| `score_0_100`, `score_assessed`, `gwp_points`, `incumbent_points`, `territory_points`, `wedge_points` | NO HOME today | proposed `company_score` (Part C). `score_0_100` is a percentage, do not store as points |
| `legal_entity` | NO HOME | needed for matching (E.3). Suggest a `legal_entity` column or alias table |
| `band`, `band_meaning`, `verdict` | NO HOME | board triage vocabulary (A-K, X; GREENFIELD / INCUMBENT / REVIEW). Do NOT map onto `opportunity_status` or `priority` enums from memory |
| `device_sale` | NO HOME | 22 free-text variants; feeds the light-triage gate |
| `estate_kind`, `estate_n` | NO HOME | the sizing standard calls the estate "the single biggest multiplier"; deserves columns |
| `est_gwp_gbp_year`, `value_band`, `clears_2000_floor` | NO HOME, and should stay derived | recompute from `company_size`; never a sort key |
| `oliver_decision`, `oliver_reason`, `oliver_note` | NO HOME | see E.8 |
| `icp_roles`, `salesnav_search_term` | NO HOME | sourcing aids |
| `slug` | NO HOME | join key between the two CSVs only |
| (not on board) `research_stage` | must be set by the importer | board rows have had a checkout walk, so 'Light triage' is the honest value; 'Deep research done' would unlock sends |

### E.6 Volume CSV (70 rows)

- Rows with a rung: **70 of 70**. Distribution: **E4 50**, E0 8, E3 5, E2 4, E5 2, E1 1. This matches
  the sizing standard's table exactly (50 of 70 at E4).
- Rows with `devices_per_month` but no rung: **0. REJECTED list is empty.** Also 0 E0 rows carry a
  devices figure, 0 non-E0 rows lack one, 0 rows lack a `basis`. Board side: also 0.
- Join: **every one of the 70 volume rows joins to a board row on `slug`.** Three board rows have no
  volume row: ofrex.ch, bohnettrade.ch, BC-GmbH (all E0 on the board, so the board has 11 E0 against
  the volume file's 8).
- Confidence in the volume file: low 46, very low 13, checked-no-rung-reachable 8, low-medium 2,
  medium 1.

Three problems the import must solve BEFORE any insert (none is a data rejection; all are constraint
mismatches that would make the insert fail):
1. **The two files disagree on 26 rows.** The board (8 Sep) supersedes the volume file (4 Sep): 25 rows
   are `E4+E5` on the board with a higher two-lane figure (example: xtreme.metacomp 43 in the volume
   file, 2,143 on the board; Foletti 406 vs 1,106; DiTech 103 vs 553), and toredo is
   `E1 total / E4 own-channel` at 833 vs 25. `E4+E5` and the toredo string are NOT in
   `company_size_rung_check`. Options: (a) two append-only rows per company, one E4 online lane with
   `online_share = 1` and one E5 in-store lane, summed in the view; (b) widen the rung check. (a)
   keeps R4 intact and matches "E4 rows with a shop now carry two lanes". Needs a ruling (A6).
2. `confidence` values 'very low', 'very low - floor only', 'very low - known too low', 'checked, no
   rung reachable' and toredo's compound value are not in `company_size_confidence_check`
   (high, medium, low-medium, low, none). 'checked, no rung reachable' -> 'none' is natural; 'very low'
   has no equivalent and mapping it to 'low' would overstate it. Recommend adding 'very_low' and
   'floor_only' to the check rather than flattening.
3. `tier_mark` values 'below floor' and 'UNSIZED' must become 'below_floor' and 'unsized'.
4. verkaufen.ch is the only E1. `company_size_stated_or_estimate` requires `is_estimate = false`,
   non-empty `evidence_verbatim` and `stated_by`. The CSV basis says "Own site states >5.000
   devices/month" but does not carry the verbatim quotation. It will fail the check until the quote
   is fetched; do not paraphrase one in.

### E.7 interim_intel.jsonl - 3 rulings (applied LAST, override the board)

| Line | Verdict | Summary | Board rows overridden | Already in DB? |
|---|---|---|---|---|
| C295 Telia, 2026-09-03 | DO_NOT_WORK | Telia owns its underwriter (Telia Insurance AB), SEK 149/month; "they are the insurer". Sets Opportunity Status to an Out of Scope value, tier C | none (Telia is not on the 73-row board) | not checked further; out of board scope |
| C315 Otto Group / Otto Austria Group (UNITO), 2026-09-04 | PROMOTE | UNITO is worked as its OWN account from Salzburg, superseding the 30 Jul note to fold it into Hamburg. Five brands: Universal, OTTO Austria, Quelle, Lascana, Ackermann (CH). "Ackermann Vertriebs AG (CH) belongs to this group and must NOT be sourced as a separate Swiss retailer." P286 / P287 in cooldown to 2027-02-25 | **Ackermann**: board has it as a standalone Swiss row marked 'sourced' with parent "Otto Austria Group GmbH"; the ruling makes it a child of C1343. Indirectly **baur** (Otto Group company, decides locally) | YES: C1343 to C1348 exist, `added_via = ruling_C315_2026-09-04` |
| C316 Conrad Electronic + RE-INvent Retail, 2026-09-04 | INTEL | getgoods.com, voelkner.de (C979), digitalo.de and SMDV are one operator under MD Heiko Voigt. "THREE APPROACHES TO ONE GROUP ARE NOW POSSIBLE. Consolidate before sending." | **getgoods.com**: board parent "RE-INvent Retail GmbH" is overridden by the full "Conrad Electronic SE, via RE-INvent Retail GmbH ..." string, and Oliver's 'sourced' decision is overridden by "reconcile into ONE group approach before any send" | YES: C1349, C1350, C1351 exist, `added_via = ruling_C316_2026-09-04`; C979 carries the same parent_group |

The jsonl `fields` keys are Monday column titles ("Opportunity Status", "Parent / Group Company"),
and the Opportunity Status values are free text ("Out of Scope - operates its own insurer ...",
"Prospect - Austrian group ..."). They are NOT enum literals and must be mapped to 'Out of Scope' /
'Prospect' with the remainder moved to notes.

### E.8 Oliver's decisions

Column: **`oliver_decision`** (with `oliver_reason` and `oliver_note`). Counts found:
**sourced 13, skip 3, blank 57.** Both match expectation. 12 rows carry an `oliver_note`.
- sourced (13): aetka, verkaufen.ch, 1ashop.at, Foletti Computer, Ackermann, kaufen.avatel,
  easynotebooks, getgoods.com, technikdirekt, Buchmann, notebook.de, future-x, GSMshop.at.
- skip (3): DiTech.at (already sells a 2-year Wertgarantie), 25n (needs emailing a standard address
  if allowed in DE), BA-Computer (seems to sell mainly parts).
Cross-check: all 13 'sourced' rows have a database counterpart (2 exact, 11 fuzzy), consistent with
contacts having been sourced. verkaufen.ch is the one whose counterpart is ambiguous.
'skip' has no home and must NOT be auto-translated to `opportunity_status = 'Out of Scope'`: the 25n
reason is a channel question, not a disqualification.

### E.9 Group guard: getgoods.com and other engaged parents

Both functions exist: `fn_company_group_pairs(p_team_id uuid)` and
`fn_company_group_pairs(p_team_id uuid, p_company_id uuid)` returning (company_id, sibling_id, rule,
evidence), and `fn_group_siblings_engaged(p_team_id uuid, p_company_id uuid)` returning (company_id,
company_ref, company_name, why). Both are `STABLE` SQL. Also present: trigger function
`fn_companies_inherit_parent_group` (a new row with null parent_group inherits it from a same-named
company) and `fn_company_duplicate_candidates`, which the guard uses to exclude duplicates from
"siblings".

Pair rules: R1 exact `parent_group` text (case and trim insensitive); R2 a company's parent_group
names the sibling's domain (>= 6 chars); R3 parent_group names the sibling's company name as a whole
word (>= 6 chars with a space, or >= 8). A sibling is "engaged" when it is in Monday
(`monday_deal_id` set or `archive_reason = 'promoted_to_monday'`), or `opportunity_status` in
(Contacted, Active Lead, Partner), or has a contact with `outreach_status` in (Contacted, In
conversation, Meeting booked). All seven literals were confirmed against pg_enum.

Read-only run of the guard today:
- **C1349 getgoods.com -> C316 Conrad Electronic: "in Monday; linked by R1 exact parent_group".**
  C316 is archived with `archive_reason = promoted_to_monday`, 14 contacts. The guard fires. Same
  result for C1350 digitalo, C1351 SMDV and C979 Voelkner.
- **C1348 Ackermann -> C315 Otto Group: "contact engaged; linked by R3"** (parent_group names "Otto
  Group").
- C1367 toredo: no engaged sibling.

How to run it over new companies at import: (1) stage the 48 new and any review-approved rows with
`parent_group` populated AFTER interim_intel overrides; (2) for each, call
`fn_group_siblings_engaged(team_id, id)`; any row returned means the company is inserted but held
(not send-eligible) with the `why` text surfaced to the reviewer. Because the functions read
`public.companies`, the check only works post-insert or against a staging copy; a pre-insert variant
taking (name, domain, parent_group) as parameters would be needed to guard before writing.
Limits found: the guard is text-driven, so it will NOT catch **berlet -> EURONICS** (board
parent_group is blank; C326's parent_group is "Euronics International (cooperative)"), **baur -> Otto
Group** (blank on the board), **DiTech -> e-tec**, or **expert-technomarkt / sabi-online -> Expert**
(C425) unless parent_group is filled in first. These four relations need a human to set
parent_group at import.

### E.10 Exact counts

| Bucket | Count |
|---|---|
| Board rows | 73 |
| **Matched (exact domain, auto-merge)** | **3** |
| **Fuzzy (human review queue, never auto-merged)** | **22** (13 strong, 9 weak; includes all 3 known false pairs) |
| **New** | **48** |
| **Rejected (devices_per_month with no rung)** | **0** |
| Volume rows with a rung | 70 of 70 (E4 50, E0 8, E3 5, E2 4, E5 2, E1 1) |
| Volume rows joining to the board | 70 of 70; 3 board rows without a volume row |
| Rows that would FAIL current `company_size` CHECKs untranslated | 26 board rung strings; confidence strings outside the check: 33 of 73 on the board, 21 of 70 in the volume file; all 'below floor' / 'UNSIZED' tier marks, 1 E1 row lacking a verbatim quote |
| Oliver decisions | sourced 13, skip 3 |
| interim rulings | 3 (2 touch board rows: Ackermann, getgoods; both already applied in the DB) |
| Group guard fires | 2 of the 3 exact matches (getgoods, Ackermann) |

### E.11 Assumptions made

- A1. "Exact domain" means exact HOST equality after normalisation, because `root_domain` stores
  hosts. A same-registrable-domain, different-host match would go to review. None occurred.
- A2. The board's `score_0_100` is a percentage of assessed (proved for the 11 E0 rows). Display
  wording for partial scores needs Brad's ruling (raw points vs percentage first).
- A3. Incumbent "unknown = 14 of 30" is kept as the model states, but stored with
  `incumbent_basis = 'default_unknown_14'` so it can be switched to "leaves the denominator" if Brad
  rules that R2 overrides the model here. Under a strict R2 reading those 11 rows would become
  "x of 30 assessed" and drop below the 60 threshold.
- A4. Fuzzy thresholds (trigram >= 0.45, or containment with >= 0.20) are my choice; they were tuned
  only to the point where all three known false pairs surface and two obvious artefacts drop.
- A5. Archived companies are included in matching on purpose.
- A6. Where the board (8 Sep) and volume CSV (4 Sep) disagree, the board is newer and wins, loaded as
  two lanes. Not confirmed by Oliver.
- A7. Multi-host domain cells: the first host is the canonical domain.
- A8. `research_stage` for imported board rows would be 'Light triage'. Not stated in the pack.
- A9. `contacts_count` is trusted as maintained; it was not recomputed from `contacts`.
- A10. "Recommerce AG" (verkaufen.ch, CH) is treated as NOT the same as Recommerce Group (FR) until a
  human says otherwise.
- A11. Only database objects were searched for `priority` usage. Edge Functions and the Lovable
  front end were not inspected and may read `companies.priority` directly.
- A12. `Lead_and_ICP_Brief.md` section 8.1(g) does not exist in the copy in this repo
  (`docs/pier-ea-source-files/`); two other copies exist outside the repo and were not compared.
- A13. Single team: `companies` holds one `team_id`, so no team scoping was applied to matching.
- A14. Telia (C295) is outside the 73-row board; its ruling was summarised but its DB state was not
  verified.
