# Bundle A Task 6 — Reconciliation LinkedIn UX: SHIPPED + VERIFIED LIVE

**Lovable project:** `fc695882-94ec-4791-8c82-8795c90c7291` (Pier Lead Lake)
**Lovable commit:** `8539bfc43485d55082c65936f332edbb9c5e874a` — "Rebuilt LinkedIn tab & badge"
**Deployed to:** https://pier-lead-lake.lovable.app (deployment `6e191243-9145-4c90-ac9f-5ff23a898c6c`)

## Root cause of "a dropdown with no candidates"

`reconLinkedinFn` scored its suggestions with `similarityPct(ref, company_name)` where
`ref` is `contacts.company_ref`. For every unmatched contact `company_ref` is the **empty
string** — the ingest sets it to `''` when it cannot match (the column is NOT NULL). So
every score was 0, and the code then filtered `confidence > 60`. The suggestion list was
mathematically always empty. Confirmed against all 12 unmatched contacts: `company_ref` is
`''` for every one.

Compounding it: the Sales Nav company name for those 12 was **never persisted anywhere**.
There is no field on the contact holding "Coolblue". So for those rows there genuinely is
no text to match against, and the UI now says so rather than pretending.

## The two populations the tab now shows

Ingest behaviour changed today (T3b), which splits the queue in two:

- **Group A — "No company captured"** (`contacts.company_id IS NULL`). Sales Nav supplied no
  company name at all. Suggestions are impossible. These are the 12 rows today.
- **Group B — "Auto-created, needs confirming"** (contact linked to a company with
  `needs_review = true`). Here the Sales Nav name *is* preserved, as the stub company's own
  name, so similarity suggestions are meaningful and merge-vs-keep matters.

Group B was previously invisible in this tab because the query only selected
`company_id IS NULL`. Post-T3b that filter alone would have hidden every auto-created row.

## Verified live in Chrome

| Check | Result |
|---|---|
| Sidebar badge | red **12**, hidden at zero |
| Three-column row (contact / where they say they work / suggestions) | renders |
| Group A honest empty state | "No company data captured from Sales Nav." |
| "Assign to existing" combobox | **populated** — searchable by name or C ref, shows country + C ref |
| Group B amber card | pinned top, "Auto-created from Sales Nav, needs confirming" |
| Group B suggestions | 4Gadgets **UK · P1 · 53% match** ranked first, 3 shown |
| Badge live update | 12 → 13 on insert, 13 → 12 on merge |
| Merge action | toast "Merged into 4Gadgets", row cleared |
| `contacts.company_ref` after merge | **C214** — previously left stale, now correct |
| Orphaned stub cleanup | C900 deleted, `needs_review` back to 0 |
| Alias learned | "4Gadgets Europe" → 4Gadgets |

Group B was exercised with a synthetic contact (P900 / C900) rather than any of Brad's real
12, so no real contact was assigned a company. All test rows and the learned test alias were
deleted afterwards; final state 259 contacts / 12 unmatched / 352 companies / 0 needs_review.

## Latent nit, not blocking

`createCompanyForContactFn` mints its C### ref without zero-padding
(`` `C${currentMax + 1 + attempt}` ``). Correct at today's values (max C353 → C354) but it
would emit `C55` rather than `C055` in a low-numbered range. The Edge Function pads with
`padStart(3, "0")`. Worth aligning if the series is ever reset.
