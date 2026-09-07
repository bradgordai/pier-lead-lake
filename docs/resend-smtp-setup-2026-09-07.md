# Custom SMTP for Supabase Auth via Resend (F2)

Why: Supabase's built-in mailer allows about 2 auth emails per hour per project. Tomorrow's
invites (Oli, Jack) plus any password recovery would hit that limit. Custom SMTP lifts it.

## What Claude could and could not do
The SMTP settings live in the Supabase dashboard (Authentication > Emails > SMTP Settings) or
the Management API, neither of which the MCP tools reach. No `RESEND_API_KEY` is visible to
the tooling either (Edge Function secrets are write-only from the outside). So this is a
runbook; every value below is exact.

## Steps for Brad (15 minutes if the domain is at hand)

1. Resend account: https://resend.com, sign up with bradleyg@naileditai.com (or the Pier
   Google Workspace admin). Free tier covers 3,000 emails/month, 100/day, enough for auth.
2. Add the sending domain: Resend > Domains > Add Domain. Use a subdomain you control, e.g.
   `mail.naileditai.com` (or `mail.pierinsurance.com` if Pier's DNS admin is available
   tonight). Resend shows three DNS records: one MX and one TXT for SPF on the subdomain, one
   TXT for DKIM (`resend._domainkey`). Add them at the DNS host; verification usually
   completes within minutes, sometimes up to an hour.
3. Create an API key: Resend > API Keys > Create, permission "Sending access", domain
   restricted to the one above. Copy it once.
4. Supabase dashboard > project qzfrcfzeiagziqjnfarw > Authentication > Emails > SMTP
   Settings > Enable custom SMTP:
   - Sender email: `no-reply@mail.naileditai.com` (must be on the verified domain)
   - Sender name: `Pier Lead Lake`
   - Host: `smtp.resend.com`
   - Port: `465` (implicit TLS) or `587` (STARTTLS)
   - Username: `resend`
   - Password: the API key from step 3
   - Save. Then Authentication > Rate Limits: raise "emails per hour" from 2 to 30.
5. Test: on https://pier-lead-lake.lovable.app/auth click "Forgot password / first login"
   for your own address; the email should arrive from the new sender within seconds.
6. Templates (optional tonight): Authentication > Emails > Templates. The default Supabase
   copy works; if you edit, keep `{{ .ConfirmationURL }}` in Reset Password and Magic Link.

## Fallback if the domain cannot verify tonight
Stay on the built-in mailer and time the invites: at most 2 auth emails per rolling hour.
Plan: 08:00 send Oli's recovery link, 08:05 Jack's, then nothing else until 09:05. Tell both
to act on the link inside the hour (links expire). Any resend after that waits for the next
window. Brad's own account already has a password, so he does not consume a slot.

## Nothing to store in the repo
The API key goes only into the dashboard SMTP form. Do not add it as an Edge Function
secret; no function sends mail.
