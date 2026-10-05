# Parent and subsidiary — options for Brad (F26.1 Task 14, report only)

Nothing was built. This sets out two designs, what each does to the group-sibling gate, to archiving and to the existing data, and recommends one. Brad decides; it then becomes its own batch.

## What exists today (measured 5 Oct 2026)
- `companies.parent_group` is **free text**. 126 companies carry one, across **111 distinct strings**, and only **3** of those strings equal a real company name (re-measured; matches i172).
- The values are research notes, not keys. The two most common read "Otto Austria Group GmbH (UNITO …), Wals-Siezenheim, subsidiary of Otto Group" (6) and "Conrad Electronic SE, via RE-INvent Retail GmbH …, MD Heiko Voigt" (5).
- There is no subsidiary column and no group table.
- What reads `parent_group` today:
  - `fn_company_group_pairs` derives sibling pairs heuristically. R1 needs an exact equal parent_group string. R2 needs parent_group to contain the other company's domain. R3 needs parent_group to name the other company.
  - `fn_group_siblings_engaged` turns those pairs into the `group_sibling_engaged` gate refusal (one approach per group), minus the pairs `fn_company_duplicate_candidates` calls duplicates.
  - `fn_companies_inherit_parent_group` (trigger) copies a parent_group onto a new company with the same name.
  - The Lovable company page and Companies list show and edit it as text.
- Archiving a company sets `archived_at` and cascades `company_archived_at` to its contacts (`tg_company_archived_sync_contacts`). Nothing group-aware happens. i066 ("moving a parent must not archive the group") describes a manual workflow risk, not current code.
- Open items describing the same need: i047 (a real group structure), i066 (moving a parent must not archive the group), i068 (verify every group against the web), i172 (parent group must be a link, not free text).

## Option A — self-referencing `companies.parent_company_id`
`parent_company_id uuid null references companies(id)`, plus a CHECK that a company is not its own parent and a trigger refusing cycles. A group is then the tree under a top company, which is often a holding entity that would also have to exist as a company row.

**fn_group_siblings_engaged.** Siblings become "companies sharing an ancestor": a recursive walk to the root, then every company under that root. This replaces R1–R3 with a fact rather than a guess. The gate becomes stricter where the link exists and silent where it does not, so the heuristic would need to keep running for unlinked companies during the migration period.

**Archiving.** Archiving a parent must decide what happens to its children:
- (a) block while children are live, or
- (b) re-parent the children to the grandparent, or
- (c) leave them pointing at an archived row.

Option (a) answers i066 directly. Archiving a child never touches the parent. The contacts cascade is unchanged.

**The 126 free-text values.** Each must be resolved to a company row. The 3 exact matches link automatically. For the rest, the holding company often isn't in the table at all (Otto Group, Telia Company AB, Lenovo Group Limited), so linking means **creating holding-company rows**. Those rows then appear in the Companies list, in scoring and in the CR queue unless marked as non-prospects. That marker would be a new flag, and every list and candidate function would have to respect it.

**Cost:** one column, one cycle guard, a recursive helper, and a rewrite of `fn_company_group_pairs`. The holding-row problem is the real cost.

## Option B — a separate `company_groups` table with membership rows
`company_groups (id, team_id, name, verified_at, verified_by, source_url, notes)` and `company_group_members (group_id, company_id unique, role 'parent'|'subsidiary'|'sister'|'unknown', added_by, added_at, evidence)`. A company belongs to at most one group (unique on company_id), and the group itself is not a company.

**fn_group_siblings_engaged.** Siblings are "other members of my group", a single join. R1–R3 can be retired or kept as a *suggestion* generator that proposes memberships for a human to confirm (i068). The gate reads only confirmed memberships, so it refuses on fact, which matches the soft-guardrail rule (block only on fact or consent).

**Archiving.** Archiving any member, including the "parent" member, never archives the group or the other members; the group row is not a company and has no `archived_at` coupling. i066 is satisfied by construction. A group with no live members can be shown as dormant. The contacts cascade is unchanged.

**The 126 free-text values.**
- Create one group per distinct cleaned string (111), or fewer after a dedupe pass: "Otto Group" appears inside several strings.
- Attach the 126 companies as members with role 'unknown' and evidence = the old text.
- Set `verified_at` null, so the gate treats unverified groups exactly as today's heuristic until Oliver confirms them (i068).
- `parent_group` stays as a read-only legacy note during transition, then is dropped.
- No holding-company rows are needed, so nothing new enters scoring, lists or the CR queue.

**Cost:** two tables, RLS, a members editor on the company page, and a groups screen. That is more UI than Option A, but no new kind of company row.

## Recommendation: Option B
1. **It answers all four items without side effects.** i047 is a real structure. i066 holds by construction, because a group is not a company and cannot be archived with one. i068 becomes `verified_at` per group. i172 means members link by id.
2. **No phantom holding companies.** Option A would put Otto Group, Telia Company AB, Lenovo Group and similar into the company table, so into scoring (Anthropic spend), lists, the CR queue and the gates, unless every surface learned to exclude them.
3. **The gate becomes factual in steps.** Unverified groups behave as today; confirmed groups refuse on fact. That fits the 30 Sep soft-guardrail ruling, and the consent proof for the batch stays simple: refusal counts per reason_code before and after, with the only change on `group_sibling_engaged`.
4. **Migration is mechanical and reversible.** The groups are built from the 111 strings and the old text is kept as evidence. Nothing about a company row changes.

**Open decisions for Brad before the batch:**
- Can a company sit in more than one group, for example a joint venture? The recommendation assumes no (unique membership).
- Should unverified groups refuse (today's behaviour) or only flag?
- Does a confirmed group's "engaged" test stay as today (any member Contacted / Active Lead / Partner / in Monday, or any contact in conversation)?
