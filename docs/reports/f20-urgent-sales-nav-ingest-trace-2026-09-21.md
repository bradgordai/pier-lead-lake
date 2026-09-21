# F20 urgent: Sales Nav ingest trace (2026-09-21)

Read-only trace. Nothing was edited, run, replayed, launched or saved. All secrets redacted.

## Break point (plain statement)

The automated watcher does not watch "Lovable Master List" at all. The PhantomBuster agent "Pier Sales Nav Watcher" (id 2343586699386601) is pointed at Sales Navigator list id `7236596622934118401`, which PhantomBuster's own log names **"Recently Accepted Connections and InMails"** (43 leads). "Lovable Master List" is a different list, id `7470433735855935489` (130 leads on 14 Sep), and nothing scheduled reads it. Its contacts have only ever reached Supabase via one-off manual exports plus a bulk load; the last was 2026-09-15 04:47:29 UTC. Leads added to Lovable Master List today are therefore not ingested, and will not be until either a manual export + bulk load is repeated or a scheduled agent is pointed at that list.

Nothing in the chain is failing. Every hop is healthy and doing what it is configured to do; it is configured to watch the wrong list for this purpose.

## (a) What the Make scenario reads

Scenario 9589633 "Pier Sales Nav Watcher", team 586107, active, last edited 2026-08-26. Scheduling `immediately` (instant webhook), NOT a 4-hourly poll. The 4-hourly cadence comes from PhantomBuster calling the webhook at the end of each run.

Modules in order:
1. `gateway:CustomWebHook` (id 2), hook 4286276, maxResults 1. Receives PhantomBuster's end-of-run notification; payload contains `resultObject` (a JSON string).
2. `json:ParseJSON` (id 3) on `{{2.resultObject}}`. **Filter before it: `resultObject` does not contain the text `"error"`.** When PhantomBuster finds nothing new it sends `[{"error":"No new results found",...}]`, so the filter stops the run: that is every 1-operation execution.
3. `builtin:BasicFeeder` (id 5) over the parsed bundle.
4. `http:MakeRequest` (id 7): POST `https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/upsert-contact-from-sales-nav`, header `Authorization: Bearer <redacted>`, stopOnHttpError true. Body fields: `profileUrl`, `linkedInProfileUrl` (from `defaultProfileUrl`), `firstName`, `lastName`, `headline` (from `title`), `companyName`, `companyUrl`, `location`, `connectionDegree` (from `3.degree`), and a **hardcoded** `listName: "P0 Sales Nav List"`.

There is no Make-side "new" filter. "New" is decided entirely by PhantomBuster's watcher mode. Operation count formula: 2 + 2N for N leads (webhook 1, parse 1, feeder N, HTTP N). So 4 ops = 1 lead, 6 = 2, 8 = 3, 10 = 4, which matches PhantomBuster exactly (below).

Side findings:
- The scenario blueprint stores the function bearer as a literal header value (readable by anyone with blueprint access). Not printed here.
- `listName` is hardcoded, so every contact the watcher touches is tagged "P0 Sales Nav List" regardless of the real list.

## (b) The PhantomBuster agent

- Name "Pier Sales Nav Watcher", id 2343586699386601, script "Sales Navigator List Export.js" (phantombuster org, master/release), 338 launches.
- Target: a lead LIST, `https://www.linkedin.com/sales/lists/people/7236596622934118401?sortCriteria=CREATED_TIME&sortOrder=DESCENDING`. Log line on every run: "Loading list Recently Accepted Connections and InMails".
- Non-secret arguments: `numberOfResultsPerLaunch` 100, `numberOfResultsPerSearch` 1000, `watcherMode` **true**, `removeDuplicateResults` false, `csvName` pier-sales-nav-export. Session cookie and identity: `<redacted>`.
- Schedule: `launchType` repeatedly, hours 1,5,9,13,17,21 Europe/London, minute 0, every day = 00/04/08/12/16/20 UTC. Webhook notification set to a Make hook URL (`<redacted>`).
- Ran since 16 Sep: yes. 50 containers from 2026-09-13 08:00 UTC to 2026-09-21 12:00 UTC, one every 4 hours with no gaps, all `launchType` "scheduled repeatedly", `endType` finished, `exitCode` 0.
- Session cookie: healthy. Every inspected run logs "Connected successfully as Oliver Müller". No cookie/disconnect lines.
- Only-new behaviour: yes. `watcherMode: true` means it returns only leads not present in its own accumulated result file ("X already found"), otherwise `No new results found`.

Inspected containers:

| Container | Start (UTC) | End | Exit | List total | New this launch | Already found |
|---|---|---|---|---|---|---|
| 7083078253909896 | 2026-09-16 08:00:42 | finished | 0 | 38 | 1 (Lennart Faix) | 37 |
| 6032206956077384 | 2026-09-17 04:00:33 | finished | 0 | 42 | 4 | 38 |
| 8827154486298831 | 2026-09-18 08:00:38 | finished | 0 | 44 | 2 | 42 |
| 106868906502191 | 2026-09-20 08:00:33 | finished | 0 | 43 | 3 | 40 |
| 6857618127269569 | 2026-09-21 12:00:32 | finished | 0 | 43 | 0 ("No new results found") | 43 |

All other containers since 14 Sep: finished, exit 0 (logs not individually opened; their Make counterparts are 1-op, i.e. "No new results found").

The other agent: "Untitled Sales Navigator List Export", id 4302832622364293, same script, `launchType` **manually**. Last run container 4197768042034077, 2026-09-14 22:07 to 22:10 UTC, exit 0: "Loading list Lovable Master List", list id `7470433735855935489`, total 130, 127 leads this launch, 3 already found. This is the only thing that reads Lovable Master List, and it has not run since 14 Sep.

## (c) The four Make executions

Make's `executions_get-detail` returned only `{"status":"SUCCESS"}` for these executions (tried 234bcd42... and d29d8aa9...), so per-module bundles and the function's HTTP response bodies were NOT readable. Inputs below are the PhantomBuster `resultObject` that was delivered to the webhook; outcomes are proven from the `contacts` table instead.

| Make execution | Time (UTC) | Ops | Leads sent | Outcome in `contacts` |
|---|---|---|---|---|
| d29d8aa99c474e128500a95cc16e4e3c | 2026-09-16 08:01:51 | 4 | Lennart Faix (COMSPOT) | CREATED: P888, created_at 2026-09-16 08:01:55, source_list "P0 Sales Nav List" |
| 5bcec5e57ad342578c95672ade7a8700 | 2026-09-17 04:01:41 | 10 | Philipp Lohmar, Ivana Petrovic, Bianca Pfaller, Robert Karl | all UPDATED: P772, P787, P773, P778 already existed (created 2026-09-15 04:47:29) |
| 30243059a75a47e8bedf79615bbc8de6 | 2026-09-18 08:06:00 | 6 | Milena Joksimovic, Natascha Wyss | both UPDATED: P791, P880 (created 2026-09-15 04:47:29) |
| 234bcd4224d2467a8909bb6beae51389 | 2026-09-20 08:01:41 | 8 | Erdinc Kanal, Matthias Lorenz, Julia Koellges | all UPDATED: P785, P857, P860 (created 2026-09-15 04:47:29) |

Proof that 20 Sep (and 17/18 Sep) were updates, not inserts: all nine rows have `created_at` 2026-09-15 04:47:29.575206 (one bulk transaction), `source_list` "Lovable Master List", and `sn_lists` = ["Lovable Master List","P0 Sales Nav List"]. The second tag is what the function's update branch appends (`uniquePush(existing.sn_lists, listName)`), i.e. the fingerprint of a `status: "updated"` response. Every lead in these payloads has `outreachActivity: ACCEPT_INVITATION`: they are people who accepted a connection request, so they were already in Pier by definition.

Note on 18 Sep: no Make executions exist between 2026-09-17 04:01 and 2026-09-18 08:05:59, then seven fire within 0.3 s (six 1-op plus the 6-op). PhantomBuster ran on schedule throughout, so Make held the webhook queue for about 28 hours and drained it at once. No data was lost, but it is an unexplained stall worth a separate look.

## (d) Dedupe paths that could discard a new lead

1. PhantomBuster watcher mode: a lead is "new" only if absent from the agent's accumulated result file. A lead removed from and re-added to the list is never re-emitted. Correct for genuinely new leads.
2. Make filter `resultObject` not-contains `"error"`: a text match over the whole payload. If a genuinely new lead's data contained the string `"error"` with quotes (unlikely), the whole batch would be dropped silently as a 1-op run.
3. Function `upsert-contact-from-sales-nav` (`/Users/bradley/Documents/pier-lead-lake/supabase/functions/upsert-contact-from-sales-nav/index.ts`, lines ~260-300): matches an existing contact by `linkedin_slug`, then `linkedin_url`, then `linkedin_sales_nav_url`; on a match it only fills blank URLs and appends the list tag, returning `status: "updated"`. Otherwise it inserts and returns `status: "created"`. This is correct upsert behaviour, not a silent discard.

None of these is the cause. The new leads never enter the chain, because the list they were added to is not the list being watched.

## (e) Conclusion

Broken at the very first hop: list targeting. The watcher agent reads "Recently Accepted Connections and InMails" (`7236596622934118401`), not "Lovable Master List" (`7470433735855935489`). `contacts` by source_list confirms it: "Lovable Master List" has 123 rows, newest 2026-09-15 04:47:29 (bulk load after the manual 14 Sep export); "P0 Sales Nav List" has 46 rows, newest 2026-09-16 08:01:55 (the watcher's last insert).

Not determined:
- The function's actual HTTP response bodies (Make execution detail unavailable through the API; check the Make UI history or edge function logs if needed).
- Which path performed the 15 Sep 04:47 bulk load (likely the gated ingest function; not traced).
- Whether today's additions are visible to the Oliver Müller Sales Nav seat that PhantomBuster logs in as. If the list was edited from a different seat, confirm it is shared.
- Cause of the 17-18 Sep Make webhook queue stall.

## Addendum: second read-only pass, 2026-09-21 ~14:30 UTC

Independently re-verified the blueprint, agent arguments, container list and the 20 Sep result object; all agree with the above. New facts:

- Someone launched the watcher agent by hand today: container 1621014097560249, `launchType` **manual**, 14:06:42 to 14:08:09 UTC, exit 0 (launch count now 339). It again loaded "Recently Accepted Connections and InMails", total 43, "Got 0 lead from page 1 (0 this launch) (25 already found)". Result object: `[{"error":"No new results found", ...}]`. Make execution 149e0f1fbe924439a018c077dd9b9a51 at 14:08:11 UTC = 1 op (stopped by the `"error"` filter). So a manual launch of this agent cannot ingest Lovable Master List leads either.
- In that run page 2 returned "No results found on this page" followed by `[error] List couldn't be loaded using Oliver Müller`, yet the run exited 0. On 20 Sep page 2 loaded normally (18 already found). Login itself succeeded, so this is a page-2 load failure, not a dead cookie. It did not matter here (list is sorted newest first and page 1 had nothing new), but it is a silent partial-read: exit 0 with an error line.
- `executions_get-detail` again returned only `{"status":"SUCCESS"}` for both 234bcd42... (8 ops) and 149e0f1f... (1 op). First-module input was therefore read from the PhantomBuster container result objects: 20 Sep = 1 webhook bundle whose `resultObject` holds 3 leads (Kanal, Lorenz, Koellges; all `ACCEPT_INVITATION`, `dateAdded` 2026-09-20 01:03); today = 1 webhook bundle holding the single "No new results found" error object. Make is being handed nothing new; it is not filtering real leads out.

Options for the owner to decide (none actioned): schedule a second Sales Navigator List Export agent on list `7470433735855935489` with watcher mode on and the same webhook, and make `listName` dynamic in the Make body rather than hardcoded; or repeat the manual export + bulk load as a stopgap.
