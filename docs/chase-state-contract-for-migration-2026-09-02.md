# Chase-state contract — hand this to tonight's migration prompt

Migration **052** created these columns. The chase engine (`chase-engine`, cron jobid 4,
06:15 UTC daily) reads and writes them. **Tonight's catch-up scan must write the same
fields.** Two sources of truth here produce either duplicate chasers or silent gaps.

## The columns (all on `contacts`)

| Column | Type | Meaning |
|---|---|---|
| `chase_state` | text, NOT NULL, default `'none'` | cadence position |
| `chaser_count` | smallint, NOT NULL, default `0` | chasers actually **SENT** |
| `chase_last_outbound_at` | date | the outbound touch the clock runs from |
| `chase_next_due_at` | date | when the next chaser becomes due; NULL = not due |
| `chase_scheduled_for` | date | explicit future date; **overrides** the interval |
| `cooldown_until` | date | pre-existing. Reused, not duplicated. |

`chase_state` is constrained to:
`none | awaiting_reply | chaser_1_sent | chaser_2_sent | exhausted | replied | cooldown`

## Rules the migration must respect

1. **`chaser_count` counts SENT chasers, never drafts.** A draft in Pending Review has not
   been chased. Counting drafts would let the cap be consumed by drafts Oli never approves,
   and the cadence would stall silently.
2. **`chase_scheduled_for` overrides the interval.** This is what carries the 26 Oct
   re-engagement: park a contact with a future date and the engine ignores the normal
   7-day interval until that date arrives.
3. **`exhausted` is terminal for the cadence, not the contact.** Cap reached + cooldown set.
   A reply or an explicit reschedule can bring them back.
4. **`chase_state` is TEXT + CHECK, not an enum**, specifically so tonight's migration can
   widen it with a one-line ALTER instead of `ALTER TYPE ... ADD VALUE`.

## What the engine does NOT depend on

`fn_chase_candidates` (migration 053) recomputes the clock from `outreach_log` and only
falls back to `contacts.chaser_count` via `greatest(chaser_count, counted_sent_chasers)`.
So **the engine is already correct today, before the migration runs.** The migration should
populate these columns to make the state explicit and queryable, not to make the engine work.

## Current state, measured 2026-09-02 17:00 BST

- `fn_chase_candidates(team, 1000)` returns **112 contacts due**
  - 25 via `accepted_chase` (connected, initial message sent, no reply)
  - 87 via `cr_not_accepted` (CR sent, never accepted)
  - days-since ranges 107-128, i.e. the whole backlog
- `fn_chase_exhausted(...)` returns **0**
- At 25/run the backlog clears in ~5 days. If Brad wants it faster, raise `limit` in
  cron jobid 4's body, but see the cost note below.

## Cost note the migration prompt must account for

With B2 prompt caching live, a draft costs **~£0.0136** warm vs **~£0.118** cold (88% less).
The cache is 5-minute ephemeral: a serial run stays warm, but **a run with >5 min gaps pays
the cold price again**. ~200 catch-up drafts:
- warm throughout: ~£2.83
- fully cold: ~£19, which **exceeds the £10/day fail-closed budget** and would halt the run
  around draft 105.

Keep the catch-up generation continuous, or raise `ANTHROPIC_DAILY_BUDGET_GBP` for the night.
