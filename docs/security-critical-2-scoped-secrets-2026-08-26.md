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
