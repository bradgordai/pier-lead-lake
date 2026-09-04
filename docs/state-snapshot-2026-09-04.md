# State snapshot, 2026-09-04 17:40 BST, end of pre-handover run part 1

Live counts: companies 1107 (753 live, 354 archived: 288 out_of_scope, 66 promoted_to_monday),
contacts 685 (673 live), outreach_log 1067 (951 legacy). Pending review (canon) 70. Refusals
today 108 distinct contact+reason. InMail credits 129. Spend today GBP 1.83.

Deployed this run: send-approved-draft v9, send-approved-callback v10 (T3 sent_body freeze),
ai-edit-draft v1 (T4, Lovable rewired, commit 960911d in the Lovable repo), chase-engine v3
(refusal dedupe), generate-draft-from-context v26 (register line), migration-ingest v1 and
migration-classify v3 (temporary, to delete). Migrations 057 to 060 applied and in repo.

Crons: 1 weekly-dq-snapshot, 2 weekly-enrich-company-websites, 3 weekday-daily-insight,
5 daily-chase-engine (06:15 UTC, re-enabled this run).

Full migration report: docs/migration-verification-report-2026-09-04.md.
Test shapes: docs/oli-test-shapes-2026-09.md (results appended).
