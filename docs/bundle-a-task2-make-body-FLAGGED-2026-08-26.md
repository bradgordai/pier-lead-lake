# Bundle A Task 2 — Make body update: FLAGGED, NOT APPLIED

**Status:** Tier 2 stop-and-flag. Needs a 60-second edit by Brad in the Make UI.
**Scenario:** `Pier Sales Nav Watcher` (9589633), module **7** (HTTP MakeRequest), field *Body content*.
**Scenario state at time of writing:** `isActive: true`, `isinvalid: false`, `lastEdit: 2026-08-24T12:11:00Z`.

## Why this was flagged instead of applied

1. **The handover said "T2 already done by Brad — skip". That is only half true.**
   The `linkedInProfileUrl` / newline-escape work *was* done (the body correctly maps
   `"linkedInProfileUrl": "{{5.defaultProfileUrl}}"`). The Bundle A T2 changes —
   `associatedAccountName`, `regularCompanyUrl`, `outreachActivity`, and the
   real `listName` — were **not**. So there is a standing instruction to skip a
   task that is in fact outstanding.

2. **The blueprint cannot be faithfully round-tripped via MCP.** `scenarios_update`
   wholesale-replaces the blueprint, and `scenarios_get` returns
   `blueprint.metadata.designer.samples` with its long string values **truncated
   to "..."**. Writing that back would corrupt the cached sample bundles.

3. **Nothing is broken by waiting.** The Edge Function (platform v11) already
   degrades cleanly: absent `associatedAccountName` falls back to `companyName`
   (today's exact behaviour), and absent `regularCompanyUrl` just leaves
   `source_urls` NULL on auto-created companies.

Given a live scenario that fires at 01:00 and 05:00 London, an explicit
instruction to skip, and no functional breakage from deferring — writing the
blueprint unattended was the wrong risk.

## Current body (verbatim — keep this for rollback)

```
{
  "profileUrl": "{{5.profileUrl}}",
"linkedInProfileUrl": "{{5.defaultProfileUrl}}",
  "firstName": "{{5.firstName}}",
  "lastName": "{{5.lastName}}",
  "headline": "{{5.title}}",
  "companyName": "{{5.companyName}}",
  "companyUrl": "{{5.companyUrl}}",
  "location": "{{5.location}}",
  "connectionDegree": "{{3.degree}}",
  "listName": "P0 Sales Nav List"
}
```

## Replacement body (paste-ready)

```
{
  "profileUrl": "{{5.profileUrl}}",
  "linkedInProfileUrl": "{{5.defaultProfileUrl}}",
  "firstName": "{{5.firstName}}",
  "lastName": "{{5.lastName}}",
  "headline": "{{5.title}}",
  "companyName": "{{5.companyName}}",
  "associatedAccountName": "{{5.associatedAccountName}}",
  "companyUrl": "{{5.companyUrl}}",
  "regularCompanyUrl": "{{5.regularCompanyUrl}}",
  "location": "{{5.location}}",
  "connectionDegree": "{{5.degree}}",
  "outreachActivity": "{{5.outreachActivity}}",
  "listName": "{{ifempty(5.query; "Unknown Sales Nav list")}}"
}
```

## Two real bugs found in the current body

### Bug 1 — `{{3.degree}}` should be `{{5.degree}}` (module reference is wrong)

Module **3** is the ParseJSON output (the whole lead *array*); module **5** is the
BasicFeeder iterator that yields one lead at a time. Every other field correctly
reads from `5`. `connectionDegree` alone reads from `3`, so on a multi-lead run
every lead is stamped with the *first* lead's degree (or an empty string).

This directly undermines T1b, whose whole job is deriving `connection_status`
from the degree. **Fix this one even if you change nothing else.**

### Bug 2 — the phantom emits `"1st"`, not `"1st degree"` (already fixed in the EF)

The live sample bundle carries `"degree": "1st"`. The Edge Function's original
test was `connectionDegree === "1st degree"`, which therefore never matched — every
1st-degree lead was silently written as not-connected. Corroborated by the data:
only **1 of 259** contacts holds `Already connected`, and that one predates ingest.

Already fixed on the server side (platform v11, commit `2aae4f5`): `isFirstDegree`
now accepts `1`, `1st`, and `1st degree`. No Make-side change needed for this.

## One consequence to decide on: `listName` becomes a URL

`{{5.query}}` is verified present in the bundle, but its value is the full
Sales Nav list URL:

```
https://www.linkedin.com/sales/lists/people/7236596622934118401?sortCriteria=CREATED_TIME&sortOrder=...
```

That lands in `contacts.source_list` and `contacts.sn_lists`. The existing
vocabulary is human-readable:

| sn_list | contacts |
|---|---|
| P0 Sales Nav List | 23 |
| Retech Berlin - No Insurance In Place | 8 |
| Targets No Insurance in Place | 4 |
| Pier Protect - General Network (not a client as such) | 3 |
| Targets - Insurance in Place | 2 |
| Pier Protect - Client | 1 |
| Retech Berlin - Already Insurance In Place | 1 |

So this trades a *wrong* label for a *truthful but ugly* one, and mixes URLs into
a list of friendly names that the Reconciliation and Contacts filters group by.

**Recommendation:** keep `{{5.query}}` (truthful provenance is the point of the
fix), and add a small list-id → friendly-name mapping at render time, since
`7236596622934118401` is stable per list. Alternative if you'd rather not: leave
`listName` hardcoded for now and take only the four field additions plus Bug 1.
Your call — say which and it is a one-line change.

## Also worth knowing (relevant to the Inbox Watcher VMID blocker)

The Sales Nav bundle carries **both** URL forms for every lead:

- `defaultProfileUrl` → `https://linkedin.com/in/kim-ulmer-koldby-905903` (public slug)
- `linkedInProfileUrl` → `https://www.linkedin.com/in/ACwAAAAiRVUB1qYes.../` (opaque VMID)
- `vmid` → `ACwAAAAiRVUB1qYes1g1vX9Pw61Rp5RiRnflbJc` (bare)

The open blocker is that the Inbox Scraper emits only the opaque `/in/ACoAA…`
form while contacts store public slugs, so inbound matching scores 0. Ingest
already receives the VMID and simply discards it. Storing it in a
`contacts.linkedin_vmid` column at ingest time would give inbound replies an
exact key to match on — no fuzzy name matching, no phantom public URLs. That is
the cheapest route through that blocker, and it is a Bundle-A-adjacent one-column
migration rather than new machinery.

## Security note (for the read-only audit, prompt 5)

The module-7 header holds the shared secret in plaintext inside the blueprint:
`Authorization: Bearer 171b54a2…`. Anyone with read access to the Make scenario
has the Edge Function credential. Carried into the audit findings.
