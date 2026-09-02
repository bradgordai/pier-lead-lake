# CRITICAL 2 — scoped secrets: code side done, secret values need Brad

## What shipped tonight (autonomous)

`supabase/functions/_shared/authorize.ts` — canonical helper. Accepts, for a given caller
class, either the new scoped secret **or** the old `MAKE_SHARED_SECRET`, and logs
`deprecated_secret_used` whenever the old one is what worked.

Applied and deployed to:

| Function | Caller class | Status |
|---|---|---|
| `send-approved-draft` | `internal` (Lovable "Send now") | ✅ deployed |
| `send-approved-callback` | `inbound` (PhantomBuster webhook) | ✅ deployed |

## Still to apply — same three-line change each

| Function | Caller class |
|---|---|
| `upsert-contact-from-sales-nav` | `inbound` |
| `update-contact-on-cr-accepted` | `inbound` |
| `capture-and-classify-reply` | `inbound` |
| `enrich-contact-metadata` | `internal` (chained from upsert) |
| `generate-draft-from-context` | `internal` (chained from update-cr) |
| `enrich-company-websites` | `internal` (cron) |
| `generate-daily-insight` | `internal` (cron) |

The change in each is mechanical — replace the inline bearer check:

```ts
const authz = req.headers.get("authorization") ?? "";
if ((authz.startsWith("Bearer ") ? authz.slice(7) : "") !== MAKE_SHARED_SECRET) {
  return json(401, { error: "unauthorized" });
}
```

with:

```ts
import { authorize } from "./_shared/authorize.ts";
...
if (!authorize(req, "inbound", "upsert-contact-from-sales-nav")) {
  return json(401, { error: "unauthorized" });
}
```

Note the EF-to-EF chained calls (`upsert` → `enrich-contact-metadata`, `update-cr` →
`generate-draft-from-context`) currently send `MAKE_SHARED_SECRET` as their bearer. Those
call sites must switch to `INTERNAL_APP_SECRET` at the same time as their callees, or they
will keep emitting `deprecated_secret_used` forever.

## Needs Brad — hard-stopped here, nothing below was done

1. **Generate the two secret values.** e.g. `openssl rand -hex 16` twice.
2. **Add them in Supabase → Settings → Functions → Secrets:**
   - `INBOUND_WEBHOOK_SECRET`
   - `INTERNAL_APP_SECRET`
   - **leave `MAKE_SHARED_SECRET` in place** — the transition depends on it.
3. **Update the three Make scenarios' Bearer headers** to `INBOUND_WEBHOOK_SECRET`:
   9589633 Sales Nav Watcher, 9590745 Connection Watcher, 9704543 Inbox Watcher.
4. **Update the Lovable server functions** that hardcode the secret to use
   `INTERNAL_APP_SECRET`.
5. **After 24h**, check the Edge Function logs for `deprecated_secret_used`. Zero hits means
   every caller is on a scoped secret and `MAKE_SHARED_SECRET` can be deleted.

Also still outstanding from CRITICAL 1, and more urgent than any of the above: **rotate the
LinkedIn session cookie and the PhantomBuster API key.** The cookie is retrievable in full
via `agents_fetch` → `agentObject.originalSessionCookie`.

---

# STATUS 2026-09-02 — code side COMPLETE, deletion still BLOCKED

## Retrofit finished

All remaining functions now use `authorize()`. The five on the list, plus one that was not:

| Function | Class | Version |
|---|---|---|
| `update-contact-on-cr-accepted` | inbound | v13 |
| `capture-and-classify-reply` | inbound | v12 |
| `enrich-contact-metadata` | internal | v12 |
| `enrich-company-websites` | internal | v10 |
| `generate-daily-insight` | internal | v13 |
| `seed-ea-doc` | internal | v11 |

**`seed-ea-doc` was missing from this document's list.** It accepted only the legacy
secret, so while it stood, `MAKE_SHARED_SECRET` could never be deleted no matter what
happened to the other five.

Also fixed: `update-contact-on-cr-accepted` was *sending* `MAKE_SHARED_SECRET` as the bearer
on its chained call to `generate-draft-from-context`. That single call site produced **all 90**
`deprecated_secret_used` events in the last 24 hours.

Scoping is confirmed real, not just wired: the two inbound functions **reject**
`INTERNAL_APP_SECRET` (401) while the internal ones accept it.

## MAKE_SHARED_SECRET is NOT safe to delete. Two concrete blockers.

**1. Both pg_cron jobs send the legacy secret.** Not mentioned anywhere in the original plan.

- jobid 2 `weekly-enrich-company-websites` (Sundays 06:00)
- jobid 3 `weekday-daily-insight` (weekdays 08:00)

Each hardcodes a 32-char hex literal in its `cron.job.command` — verified not equal to
`INTERNAL_APP_SECRET` (48 chars). The secret therefore also sits in plaintext in a **database
table**, which is a second copy nobody was tracking. Deleting `MAKE_SHARED_SECRET` today
breaks both crons.

Fix (Brad — replace the placeholder, do not commit the real value):

```sql
SELECT cron.alter_job(2, command := $$
  SELECT net.http_post(
    url := 'https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/enrich-company-websites',
    headers := jsonb_build_object('Content-Type','application/json',
                                  'Authorization','Bearer <INTERNAL_APP_SECRET>'),
    body := jsonb_build_object('mode','missing','limit',60));
$$);
```

…and the same for jobid 3. Better still, read it from Vault rather than embedding a literal.

**2. The 24-hour clock only starts now.** Until today, the two busiest inbound endpoints did
not use `authorize()` and so logged nothing:

- `update-contact-on-cr-accepted` — **181 requests/24h**
- `capture-and-classify-reply` — **121 requests/24h**

Both are driven by Make. Their secret has never been observable. From this deploy onward a
legacy call logs `deprecated_secret_used`, so ~300 events/day will appear if Make is still on
the old secret. **Zero hits before today is not evidence of anything.**

Unknown, not proven: `upsert-contact-from-sales-nav` received **0 requests** in 24h, so the
Sales Nav Watcher's secret is untested either way.

## The actual green light

Delete `MAKE_SHARED_SECRET` only when ALL of these hold:

1. Both cron jobs re-pointed at `INTERNAL_APP_SECRET` (above).
2. The three Make scenarios re-pointed at `INBOUND_WEBHOOK_SECRET`
   (9589633 Sales Nav Watcher, 9590745 Connection Watcher, 9704543 Inbox Watcher).
3. A full 24h has elapsed **since those changes**, with the Sales Nav Watcher having actually
   fired at least once, and this returning zero:

```sql
-- via the logs explorer, last 24h
select count(*) from logs where position(event_message, 'deprecated_secret_used') > 0;
```

Still outstanding from CRITICAL 1 and more urgent than any of this: **rotate the LinkedIn
session cookie and the PhantomBuster API key.**

## 2026-09-02 (later) — B1: both crons re-pointed

`cron.job` ids 2 and 3 now send `INTERNAL_APP_SECRET` instead of the legacy secret.
Verified by re-reading `cron.job`: bearer length 48 (was 32), equality against
`INTERNAL_APP_SECRET` true, URLs / bodies / schedules / active flags unchanged.

**Deprecation note.** Blocker 1 from the section above is cleared. `MAKE_SHARED_SECRET` now
has exactly one known remaining consumer class: the three Make scenarios
(9589633 Sales Nav Watcher, 9590745 Connection Watcher, 9704543 Inbox Watcher), which only
Brad can re-point. **The 24h deletion clock starts when those three are changed**, not now.

The secret value is still a plaintext literal inside `cron.job.command`, i.e. inside a
database table. Re-pointing swapped which secret is exposed there, it did not remove the
exposure. Moving both jobs to a Vault read is the real fix and is still outstanding.
