# F17.1 Restore the action layer (i070 + i082) — 2026-09-18

No secret value appears in this file. The literal is written `<literal>` throughout.

## Headline

The literal is in **7 Lovable files, 8 copies, 11 call sites, 7 Edge Functions**. Brad's list had 1 file and
2 copies. Replacing the two known strings would have fixed Regenerate and the reply sync and left **Send now,
AI edit, enrichment, the daily insight refresh, the companies query parser and both Reconciliation actions
still returning `unauthorized`**. All 8 copies are the same value.

## (a) Every static bearer, complete list

### A. Lovable project `Pier Lead Lake` (fc695882…), read-only audit of every `*.functions.ts` / `*.server.ts`

| File | Exported function | Variable | Edge Function |
|---|---|---|---|
| src/lib/queries/outreach.functions.ts | `regenerateDraftsFn` | `secret` (in handler) | generate-draft-from-context |
| src/lib/queries/outreach.functions.ts | `syncLinkedinRepliesStartFn`, `syncLinkedinRepliesStatusFn` via `callReplyEdgeFn` | `REPLY_EF_SECRET` (module level) | capture-and-classify-reply |
| src/lib/queries/outreach.server.ts | `callSendApprovedDraft` (used by `sendNowFn`) | `secret` | send-approved-draft |
| src/lib/queries/drafts.functions.ts | `aiEditDraftFn` | `secret` (in handler) | ai-edit-draft |
| src/lib/queries/enrichment.server.ts | `callEnrichmentEdgeFn` (used by `enrichMissingWebsitesFn`, `sendCompaniesToEnrichmentFn`) | `secret` | enrich-company-websites |
| src/lib/queries/insights-daily.functions.ts | `refreshDailyInsightFn` | `secret` (in handler) | generate-daily-insight |
| src/lib/queries/prefs.functions.ts | `parseCompaniesQueryFn` | `secret` (in handler) | parse-companies-query |
| src/lib/queries/reconciliation.functions.ts | `assignUnmatchedReplyFn`, `dismissUnmatchedReplyFn` via `callReplyEf` | `EDGE_SECRET` (module level) | capture-and-classify-reply |

The Edge Function base URL is also a literal in each of these files. Component and route files were not all
read; every `fetch` found sits in a server handler or `.server.ts` module.

**Exposure worth checking in the built JS:** `REPLY_EF_SECRET` and `EDGE_SECRET` are MODULE-LEVEL consts in
`*.functions.ts` files that client components import. Handler bodies are stripped by the compiler; a
module-level const leaves the browser bundle only if tree-shaking drops it. The app is published publicly.
Whatever value Brad pastes in today must be treated as short-lived until the JWT change lands.

### B. This repo

- Source, migrations, docs, scripts: **0** 48-hex literals. Every sender reads the environment:
  chase-engine (3 calls), update-contact-on-cr-accepted, upsert-contact-from-sales-nav,
  capture-and-classify-reply (EF-to-EF, `INTERNAL_APP_SECRET`).
- migrations/034 and 036 carry the placeholder `<PASTE_MAKE_SHARED_SECRET_HERE_BEFORE_RUNNING>`, which means
  the real value was pasted at apply time and lives in the database instead:

### C. pg_cron (database, not repo) — checked with the command redacted

| jobid | job | target | literal bearer in command |
|---|---|---|---|
| 2 | weekly-enrich-company-websites | enrich-company-websites | YES |
| 3 | weekday-daily-insight | generate-daily-insight | YES |
| 5 | daily-chase-engine | chase-engine | YES |

Job 5 returned HTTP 200 today, so its literal is still accepted (scoped or the legacy fallback). These three
are the next rotation casualty. Fix proposed, NOT applied (it needs a secret written to Vault, which is
Brad's to do): store it once with `vault.create_secret`, and have each job read
`(select decrypted_secret from vault.decrypted_secrets where name='internal_app_secret')`.

### D. Make scenarios and PhantomBuster webhooks
Inbound class (`INBOUND_WEBHOOK_SECRET`), not part of this fault, not re-audited today. Make was paused on
quota from 17 Sep 03:04 regardless.

## (b) JWT path — built

`supabase/functions/_shared/authorize.ts` gains `authorizeRequest(req, cls, fnName, supabase)`:
1. the existing secret check, unchanged (cron, Make, EF-to-EF keep working);
2. otherwise, if the bearer is shaped like a JWT, it is verified BY THE AUTH SERVER (`auth.getUser(token)`,
   never decoded and trusted locally) and the user must hold a `team_members` row for `PIER_TEAM_ID`.
   A valid Supabase user who is not on the Pier team is refused. Logs `jwt_authorized` / `jwt_rejected` /
   `jwt_not_team_member` with the user id, never the token.

Wired into the four named functions AND the three others Lovable calls with the same literal
(enrich-company-websites, generate-daily-insight, parse-companies-query), because leaving them out leaves
the literal in Lovable. The secret path is not removed anywhere.

Deployment status: see "Deploy results" at the foot of this file.

NOT TESTED END TO END. A positive test needs a signed-in user's access token, which I do not have and will
not mint. The negative path (garbage bearer -> 401) is unchanged code. First real proof is Brad or Oliver
clicking Regenerate after the Lovable change below; the function log will show `jwt_authorized`.

## (c) What Lovable must change — paste this into Lovable

> Do not pause for a plan. Remove every hardcoded Edge Function bearer and call Edge Functions with the
> signed-in user's own access token instead. The Edge Functions now accept a Supabase user JWT from a Pier
> team member.
>
> 1. Create `src/lib/queries/edge.server.ts` exporting
>    `callEdgeFunction(slug: string, body: unknown, init?: { method?: "GET" | "POST"; query?: string })`.
>    It must: read the incoming request's Authorization header using the same request accessor that
>    `src/integrations/supabase/auth-middleware.ts` uses (the header is already attached to every server
>    function call by `attachSupabaseAuth` in `src/integrations/supabase/auth-attacher.ts`, registered in
>    `src/start.ts`); throw `new Error("not_signed_in")` if it is missing or does not start with `Bearer `;
>    build the URL from `process.env.SUPABASE_URL` (fall back to `import.meta.env.VITE_SUPABASE_URL`) +
>    `/functions/v1/` + slug; forward that same Authorization header unchanged; send JSON; return
>    `{ ok, status, data }`. Do NOT edit auth-middleware.ts, client.ts or client.server.ts (generated).
> 2. Replace the literal and the hand-built fetch in each of these with `callEdgeFunction`:
>    - `src/lib/queries/outreach.functions.ts`: delete `const secret` inside `regenerateDraftsFn`; delete
>      module-level `REPLY_EF_SECRET` and `REPLY_EF_BASE_URL`; rewrite `callReplyEdgeFn` on top of
>      `callEdgeFunction` (used by `syncLinkedinRepliesStartFn`, `syncLinkedinRepliesStatusFn`).
>    - `src/lib/queries/outreach.server.ts`: `callSendApprovedDraft` (used by `sendNowFn`).
>    - `src/lib/queries/drafts.functions.ts`: `aiEditDraftFn`.
>    - `src/lib/queries/enrichment.server.ts`: `callEnrichmentEdgeFn`.
>    - `src/lib/queries/insights-daily.functions.ts`: `refreshDailyInsightFn`.
>    - `src/lib/queries/prefs.functions.ts`: `parseCompaniesQueryFn`.
>    - `src/lib/queries/reconciliation.functions.ts`: delete module-level `EDGE_SECRET` and
>      `EDGE_BASE_URL`; rewrite `callReplyEf` (used by `assignUnmatchedReplyFn`, `dismissUnmatchedReplyFn`).
> 3. Every one of those server functions must keep `.middleware([requireSupabaseAuth])`.
> 4. Delete both "TODO: move to Supabase Vault + JWT auth" comments. When done, a project-wide search for a
>    48-character hex string must return nothing.
> 5. A 401 from an Edge Function must surface to the user as "Your session has expired, sign in again",
>    not as a generic failure.
> Change nothing else. Do not touch the Send now or Approve behaviour.

After it ships: (1) confirm `jwt_authorized` in the function logs for one Regenerate, (2) rotate
`INTERNAL_APP_SECRET` once more, since the current value has been in Lovable source, (3) remove
`MAKE_SHARED_SECRET` once the three cron jobs read from Vault.

## (d) Test — added, passing

`tests/no_static_bearer_test.py`: fails on a 48-hex literal within 200 characters of Bearer/Authorization
(either order), or assigned to a name containing SECRET/TOKEN/KEY. Self-tests the three shapes found in
Lovable, prints path and line only. Today: `ok: no static bearer in 192 tracked files`. It guards THIS repo;
the Lovable repo needs step 4 above as its equivalent.

## (e) Git history

All 201 commits on all refs, full patch text: **0** 48-hex runs, **0** `Bearer <hex>` strings, no stashes.
The old value has never been in this repo. It has been in the Lovable project's git history since the
functions were written; that history was not rewritten and cannot be from here. Rotation is the remedy.

## Deviations from earlier reports

- docs/security-critical-2 (26 Aug) and memory "scoped-secret retrofit COMPLETE" described the Lovable
  callers as cut over. They were cut over to a new LITERAL, which is why rotation broke them.
- The same memory says 2 pg_cron jobs hardcode the secret. It is 3 (job 5, the chase engine, was added later).
- The brief says migrations live in supabase/migrations/. That directory did not exist; all 105 so far are
  in /migrations. From F17.2 on I write to supabase/migrations/ as instructed; Brad should pick one home.

## i-number status
- i070 / i082 (one fault): server side FIXED on 6 of 7 functions (daily insight refused, see below); UI unblocked today only by
  Brad's string replacement in ALL 7 files (not 2); permanent fix is the Lovable prompt above.

## Deploy results
Every deploy was preceded by a scripted diff of the DEPLOYED source against the repo, and followed by a
diff of the deployed files against local. No function was called after deploying.

| Function | Before -> after | JWT path live | Note |
|---|---|---|---|
| send-approved-draft | v15 -> v16 | YES | exact match |
| ai-edit-draft | v7 -> v8 | YES | exact match |
| generate-draft-from-context | v39 -> v40 | YES | exact match. First attempt HELD: see drift below |
| capture-and-classify-reply | v24 -> v25 | YES | one line differs in form only: the accent-strip regex arrives with `\uXXXX` decoded to the literal characters, as it already did in v24. Same regex |
| enrich-company-websites | v14 -> v15 | YES | exact match |
| parse-companies-query | v4 -> v5 | YES | exact match |
| generate-daily-insight | v17, UNCHANGED | **NO** | the permission system refused this production deploy. I did not retry or route around it. Source is ready and committed; Brad deploys it or approves it. Until then `refreshDailyInsightFn` in Lovable must keep a secret |

### Source drift found by the safety check (both are bugs in my earlier work)
- generate-draft-from-context: the v38 I deployed on 15 Sep returned `research_note` and `group_note`; the
  file I committed in c04ee92 did not. The repo was behind production. Ported, now identical.
- generate-daily-insight: the repo copy had unescaped backticks inside the system prompt template literal
  (it would not have booted) and lacked two log fields the deployed v17 has. Ported, now identical apart
  from the auth change. Had either been deployed blind, production would have regressed.
