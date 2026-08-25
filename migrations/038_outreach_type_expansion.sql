-- 038_outreach_type_expansion.sql
-- Bundle B, Task 1: chaser-cadence + reply-continuation values for draft categorization.
--
-- NAME CORRECTION vs the Bundle B spec: the spec says `ALTER TYPE touch_type`, but there is
-- no type called touch_type. The COLUMN is outreach_log.touch_type; its TYPE is
-- `outreach_type` (verified 2026-08-26). The spec's statement would fail with 42704.
--
-- Pre-existing labels: Initial message, Connection request, Chase, Reply, Event follow-up,
-- Introduction, Meeting confirmation, Other.
--
-- Note the overlap this introduces, deliberately: `Chase` (unnumbered, unused) and
-- `Event follow-up` already exist. Chase automation needs to record *which* chaser in the
-- 7d/3-cap cadence a touch was, which a single unnumbered `Chase` cannot express, and
-- `Follow up` (reply-to-reply on an live thread) is a different thing from `Event
-- follow-up` (post-event outreach). Left alongside rather than repurposed so no existing
-- row changes meaning.
--
-- ADD VALUE IF NOT EXISTS is idempotent, and additive enum values are safe to leave in
-- place on rollback.

ALTER TYPE outreach_type ADD VALUE IF NOT EXISTS 'Chaser 1';
ALTER TYPE outreach_type ADD VALUE IF NOT EXISTS 'Chaser 2';
ALTER TYPE outreach_type ADD VALUE IF NOT EXISTS 'Chaser 3';
ALTER TYPE outreach_type ADD VALUE IF NOT EXISTS 'Follow up';
