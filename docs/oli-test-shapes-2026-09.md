# Oli's six test shapes — concrete mapping

Oli's handover §6. Three shapes must REFUSE. Reason codes are the closed set from
migration 054's `refusals_reason_code_check`.

**Status of this doc:** written from LIVE data as it stands 2026-09-03 18:xx BST,
**before** the Phase 2 migration. Shapes 1, 2, 3 and 5 need contacts that only exist in
full after the workbook import; the candidates named are live stand-ins where one exists,
and marked `POST-MIGRATION` where the population is not there yet.

## Gate precedence — settle this before testing

Several contacts trip more than one gate. The refusal must be deterministic, so gates are
evaluated in this order and the FIRST match is returned:

1. `promise_of_quiet`   — absolute, Oli: binding, not recoverable
2. `dnc_or_opted_out`   — absolute
3. `contact_parked`     — UK, Jack's territory
4. `cr_cooldown_active` — CR inside the six-month block
5. `allowance_exhausted`— per-channel cap reached
6. `channel_illegal_in_market`
7. `company_not_deep_researched`
8. `thread_text_missing`

Rationale: consent and territory gates outrank data-quality gates. A promise-of-quiet
contact must never come back as "company not deep researched" — that reads as a fixable
problem and invites someone to fix it and retry.

## The six shapes

| # | Shape | Expected | Reason code |
|---|---|---|---|
| 1 | First message after accept, English | DRAFT | — |
| 2 | Chaser, allowance fine | DRAFT | — |
| 3 | Chaser, allowance exhausted | **REFUSE** | `allowance_exhausted` |
| 4 | Promise-of-quiet contact | **REFUSE** | `promise_of_quiet` |
| 5 | German du + Sie pair | DRAFT ×2, register preserved | — |
| 6 | Thread text missing | **REFUSE** | `thread_text_missing` |

### Shape 1 — first message after accept, EN
Pool: 34 live contacts that are `Accepted` at a `Deep research done` company.
`POST-MIGRATION`: pick one with `language_code='EN'` and no prior outbound touch.
Expect a draft, `touch_type='Initial message'`, `channel='LinkedIn DM'` (free, per C1).

### Shape 2 — chaser within allowance
DM route, `chaser_count < dm_chaser_cap (3)`. Expect a draft on **LinkedIn DM, not InMail**
— this is the Batch B flag-3 fix; chasing an already-connected contact over InMail burns a
credit for nothing.

### Shape 3 — chaser, allowance exhausted  → MUST REFUSE
Two ways to construct, and both should be tested:
- **DM route**: `chaser_count >= 3`
- **InMail route**: `chaser_count >= 1` (Oli's correction 3a — one initial + one chaser)
The InMail case is the one that regressed before: the pre-correction engine run on
2026-09-03 06:15 drafted 25 InMail Chaser 1s, all now superseded.
Expect `{refused: true, reason_code: "allowance_exhausted"}` and a `refusals` row.

### Shape 4 — promise of quiet → MUST REFUSE
`POST-MIGRATION`: `contacts.promise_of_quiet = true`. Regex scan of the frozen workbook
returns **17 candidates** against Oli's 16 (list and delta in the Phase 2 report).
Strongest single test case: **P198 Dennis Backofen** — matches both `binding promise` and
`letzte Nachricht von mir`, so it is unambiguous in either language.
Expect `{refused: true, reason_code: "promise_of_quiet"}`. Must refuse on EVERY channel and
under EVERY rule, including a manual request.

**Known near-misses that must NOT be flagged** (verify they draft normally):
- **P101** — invited check-in Aug 2027. A scheduled future touch, not a promise to stop.
- **P398** — declined, wrong person. `Not relevant`, refuses as `dnc_or_opted_out` or is
  simply out of pool; it must not be recorded as a promise of quiet.

### Shape 5 — German du + Sie
78 live DE contacts; 53 at deep-researched companies. The register lives in the workbook's
`Formality` column, which **has no live counterpart yet** — the live `contacts` table has no
formality/register column. `POST-MIGRATION` and **blocked until the import adds it**.
Pick one `du` and one `Sie` contact at the same company where possible, so the only variable
is register. Expect two drafts whose register differs and survives the model call.

### Shape 6 — thread text missing → MUST REFUSE
Live candidates exist **today**. 81 of 193 `Sent` rows have no body at all, so `sent_body`
backfilled only 112. Verified candidates, each with exactly one sent outbound touch and an
empty body:

| ref | contact | company | connection | research stage |
|---|---|---|---|---|
| **P212** | Florian Hipfl | HOFER KG | Request sent | Light triage |
| **P215** | Alexander Stork | ALDI DX | Request sent | Light triage |
| **P219** | Robert Pauly | Tchibo | Accepted | Light triage |
| **P208** | Davit Gniech | Tchibo | Request sent | Light triage |

**Caution:** all four are at `Light triage` companies, so they trip
`company_not_deep_researched` too. Under the precedence above that gate fires FIRST (7
before 8), so these would refuse with the *wrong* code for this test. To test shape 6
cleanly, use a contact at a `Deep research done` company whose prior sent touches are empty
— or temporarily assert the expected code as `company_not_deep_researched` and note it.
**P219 is the best of the four** (Accepted, so it is a real chaser candidate).

## Sizing note that affects the whole test day

Only **58 of 361 companies (16%) are `Deep research done`**; 247 are `Light triage` and 58
`Untouched`. Since `company_not_deep_researched` refuses *message* drafts (blank CRs are
unaffected per Oli's board rule), the catch-up queue will return **far more refusals than
drafts**. That is the gate working as specified, but it sits against Oli's "happy with the
full backlog" expectation, and he should see the split before the test day rather than
discover it in the queue.
