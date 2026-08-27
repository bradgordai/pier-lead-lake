-- B2: enum extensions. ADDITIVE ONLY - nothing renamed, nothing removed.
--
-- Verified against the live schema 2026-08-28 BEFORE writing:
--   connection_status already contains BOTH 'Withdrawn' and 'Already connected'. No-op.
--   archive_reason is plain `text` on contacts AND companies, NOT an enum - nothing to
--     ALTER. 'out_of_scope' / 'not_a_fit' can simply be written. Flagged rather than
--     invented as an enum, which would be a destructive type change.
--   outreach_type already has 'Chaser 1'/'Chaser 2' (mig 038). 'Chaser 3' remains as a
--     DEAD value - chaser cap is now 2 and nothing may generate a third.
--
-- Only real change: outreach_status was missing three expected labels. The enum also
-- carries four the spec did not list (Not started, Ready, Do not contact, Left company),
-- all in active use, all retained.

ALTER TYPE outreach_status ADD VALUE IF NOT EXISTS 'To contact';
ALTER TYPE outreach_status ADD VALUE IF NOT EXISTS 'Meeting booked';
ALTER TYPE outreach_status ADD VALUE IF NOT EXISTS 'Opted out';
