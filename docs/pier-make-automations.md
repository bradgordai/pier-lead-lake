# Pier Make.com automations, build template

Purpose: single source of truth for every Make.com scenario Brad needs to build for the pier-lead-lake project. Add new scenarios as they are identified. Every webhook URL, every payload shape, every trigger, every downstream action captured here.

Last updated: 8 July 2026

## Naming convention

Every scenario name follows: `pier_[direction]_[purpose]`

- Direction: `lovable_to_pb` (Lovable to PhantomBuster), `pb_to_supabase` (PhantomBuster to Supabase), `supabase_to_monday`, etc.
- Purpose: short verb phrase (`send_linkedin_message`, `sync_replies`, `promote_lead`).

## Scenario overview table

| # | Scenario name | Trigger | Purpose | Webhook URL | Status |
|---|---|---|---|---|---|
| 1 | pier_lovable_to_pb_send_linkedin_message | Webhook from Lovable "Send Now" button | Send an approved outreach draft to a LinkedIn contact via PhantomBuster | `https://hook.eu2.make.com/dqzwscpiduqvrxag4mwwcxwsf1alocpd` | To build |
| 2 | pier_pb_to_supabase_sync_replies | Schedule every 3 hours | Poll PhantomBuster LinkedIn Inbox phantom, sync new replies back to outreach_log | TBD | To build |
| 3 | pier_pb_to_supabase_sync_sales_nav | Schedule daily 21:30 UK | Poll PhantomBuster Sales Nav List Export phantom, sync new contacts to raw_contacts table | TBD | To build |
| 4 | pier_pb_to_supabase_sync_recently_connected | Schedule daily 06:00 UK | Poll PhantomBuster Recently Connected phantom, update contact connection_status | TBD | V1.1 |
| 5 | pier_pb_to_supabase_sync_sent_crs | Schedule daily 06:15 UK | Poll PhantomBuster Sent Connection Requests phantom, record sent history | TBD | V1.1 |
| 6 | pier_supabase_to_monday_promote_warm | Webhook from Lovable "Promote to Monday" button | Create a Monday deal from a Lovable company record | TBD | V1.1 |
| 7 | pier_supabase_to_monday_reconcile | Schedule daily 04:00 UK | Reconcile warm leads between Lovable and Monday, flag divergences | TBD | V1.1 |
| 8 | pier_lovable_to_ms365_send_email | Webhook from Lovable "Send Email" button | Send an approved email draft via MS365 API | TBD | V2 |
| 9 | pier_ms365_to_supabase_sync_email_replies | Schedule every hour | Poll MS365 for new email replies to Pier outreach, sync to outreach_log | TBD | V2 |
| 10 | pier_supabase_scheduled_followup | Schedule daily 09:00 UK | Send scheduled follow-up chaser messages per cadence rules | TBD | V2 |

## Scenario 1: pier_lovable_to_pb_send_linkedin_message

**Status**: To build (webhook URL created, scenario not yet configured)

**Webhook URL**: `https://hook.eu2.make.com/dqzwscpiduqvrxag4mwwcxwsf1alocpd`

**Trigger**: Webhook (Make.com's Custom Webhook module)

**Payload from Lovable (POST body, JSON)**:

```json
{
  "contact_name": "Peter Stolzlederer",
  "contact_id": "P001",
  "company_name": "A1 Telekom Austria",
  "company_id": "C001",
  "linkedin_url": "https://linkedin.com/in/peter-stolzlederer",
  "message_body": "Hallo Peter, thanks for connecting...",
  "message_type": "Initial message",
  "draft_id": "T042",
  "sent_by": "Oliver"
}
```

**Steps to build in Make.com**:

1. Add "Webhooks" module: "Custom webhook", copy URL, paste back here (already done, URL above)
2. Add "PhantomBuster" module: "Launch a phantom", pick "LinkedIn Sales Nav Sender" phantom
3. Map webhook payload to phantom inputs:
   - Session cookie: Oli's LinkedIn cookie (stored in phantom config)
   - Recipient URL: `{{ linkedin_url }}`
   - Message: `{{ message_body }}`
4. Add "Supabase HTTP" module: "Make a request", POST to Supabase Edge Function `send-status-update`
5. Payload to Supabase: `{"draft_id": "{{ draft_id }}", "send_status": "Sent", "sent_at": "{{ now }}"}`
6. Add error handler: if phantom launch fails, POST error back to Supabase agent_errors table

**Supabase Edge Function needed**: `send-status-update` (not yet built)
- Receives draft_id, send_status, sent_at
- Updates outreach_log row via service role key
- Returns 200 OK

**Testing plan**:

1. In Make.com, run the scenario once manually with a test payload
2. Verify PhantomBuster shows a launched phantom (test contact)
3. Verify Supabase outreach_log row has send_status = "Sent"
4. Verify Lovable UI reflects the update on next refresh

## Scenario 2: pier_pb_to_supabase_sync_replies

**Status**: To build (not started)

**Webhook URL**: TBD

**Trigger**: Schedule, every 3 hours during Pier's working day (08:00, 11:00, 14:00, 17:00, 20:00 UK)

**Steps to build**:

1. Add scheduler module (Every 3 hours between 08:00 and 20:00 UK)
2. Add PhantomBuster module: "Get results from a phantom", pick "LinkedIn Inbox" phantom
3. Add router: for each new message not yet processed
4. Add Supabase HTTP module: POST to Supabase Edge Function `sync-reply`
5. Payload to Supabase: `{"linkedin_url": "...", "message_body": "...", "reply_received_at": "..."}`

**Supabase Edge Function needed**: `sync-reply` (not yet built)
- Receives linkedin_url, message_body, reply_received_at
- Looks up contact by linkedin_url
- Finds most recent outreach_log row for that contact
- Updates that row: reply_content, reply_received_at
- Calls Anthropic API to classify (Positive interest / Objection / etc)
- Sets reply_classification
- Returns 200 OK

**Testing plan**:

1. Manually send a test message on LinkedIn to Oli
2. Have Oli reply
3. Wait for next scheduled run
4. Verify Supabase outreach_log has the reply captured
5. Verify Lovable UI shows the reply on next refresh

## Scenario 3: pier_pb_to_supabase_sync_sales_nav

**Status**: To build (not started)

**Webhook URL**: TBD

**Trigger**: Schedule, daily 21:30 UK

**Steps to build**:

1. Add scheduler module (Daily at 21:30 UK)
2. Add PhantomBuster module: "Get results from a phantom", pick "Sales Nav List Export" phantom
3. Filter for contacts added since last run
4. Add Supabase HTTP module per contact: INSERT into raw_contacts table
5. Trigger Contact Agent for matching (via Supabase pg_cron or Edge Function)

**Testing plan**:

1. Add a test contact to Oli's Sales Nav list
2. Wait for 21:30 UK scheduled run
3. Verify Supabase raw_contacts table has the new contact
4. Verify Contact Agent picks it up next nightly run

## Scenario templates for later

Scenarios 4-10 will be spec'd out in detail when we reach their build phase. For now, only the overview table above tracks them.

## Environment variables to set in Make.com

Under Make.com > Team Settings > Data stores or Connections:

- `PHANTOMBUSTER_API_KEY`: Pier's PhantomBuster API key
- `SUPABASE_URL`: `https://qzfrcfzeiagziqjnfarw.supabase.co`
- `SUPABASE_SERVICE_ROLE_KEY`: from Supabase dashboard, keep secret
- `ANTHROPIC_API_KEY`: for reply classification (V1.1)

Do NOT hardcode these in individual scenarios. Use Make.com's shared connection or data store so rotation is one-place.

## Supabase Edge Functions needed

To be built alongside these scenarios:

1. `send-status-update` (scenario 1)
2. `sync-reply` (scenario 2)
3. `create-contact` (scenario 3, if not using direct table insert)
4. `promote-to-monday` (scenario 6, V1.1)
5. `email-reply-sync` (scenario 9, V2)

## Testing pattern for every scenario

Before considering any scenario "done":

1. Manual test run in Make.com with sample payload
2. Verify downstream state (Supabase table has expected row)
3. Verify Lovable UI reflects the change
4. Verify error path (broken payload, PhantomBuster fails, etc)
5. Document any credential rotation needed

## Progress notes

- 2026-07-08: initial doc created, scenario 1 webhook URL added
- Next: build scenario 1 in Make.com and test end-to-end before Lovable UI is ready
