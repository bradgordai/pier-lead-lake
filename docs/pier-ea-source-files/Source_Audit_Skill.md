# PIER SOURCE AUDIT

Version 1.0 | 23 April 2026 | Author: Oliver Mueller (OM) | C2

Produces a completed source audit report as a .docx file for any content piece that makes verifiable claims. Designed to catch fabricated Pier facts, misattributed statements, and unsupported claims before external release.

Pier specific facts must match the Capability Reference or a Living Context entry, anything else is flagged.

## 1. WHAT THIS SKILL DOES

1. Reads the content
2. Identifies every auditable claim
3. Scans for named entity attributions without citation (Step 1b)
4. Scans for Pier specific claims not supported by Capability Reference or Living Context (Step 1c)
5. Verifies each cited source via web_search and web_fetch
6. Assigns status: CORRECT / NEEDS FIX / REMOVE
7. Produces .docx audit report

## 2. INPUTS

Pasted text, uploaded .docx/.txt/.md/.pdf, URL, or source list only.

## 3. STEP 1, EXTRACT CLAIMS

Identify sentences that state a fact, name a person with attribution, reference a law/regulation, describe an action by a body, or make a forward looking prediction.

Number claims sequentially. Skip editorial opinions.

## 4. STEP 1b, UNSOURCED ATTRIBUTION DETECTION

Flag: named person + specific statement without source; named institution + specific action without source; named paper without citation; specific figure attributed to named entity without source.

Do NOT flag: general industry observations, editorial opinions, widely accepted regulatory background, logical inferences.

Verdicts: Citation needed / Citation recommended.

## 5. STEP 1c, PIER SPECIFIC CLAIM CHECK

Scans for Pier claims. Must be supported by Capability Reference, Living Context, or a source cited in content.

Categories: fabricated metric, unnamed partner attribution, unconfirmed capability, regulatory claim, service name, historical claim, forward looking Pier claim.

Verdicts: Fabrication / Needs confirmation / Supported.

## 6. STEP 2, VERIFY EACH CLAIM

Web fetch each cited URL. Read content. Locate specific passage. Record Content Match verdict. Apply A-E checks.

A: Factual claims (primary source, exists in source, publicly accessible, dated, in same context, same figure)
B: Speaker attribution (correct role at time, actually made statement, correct event/date, verbatim if quoted)
C: Legal references (correct law, correct paragraph, current version, says what claimed, correct enforcement basis)
D: URL accessibility (resolves, correct page, stable, stable alternative if not)
E: Forward looking (fact or forecast, source of forecast, labelled as inference, official body confirms timeline)

## 7. STEP 2b, CLAIM SOURCE CONTENT MATCH

Supported / Partially supported / Not supported / Unverifiable.

## 8. STEP 3, ASSIGN STATUS

CORRECT / NEEDS FIX / REMOVE.

## 9. STEP 4, PRODUCE .docx REPORT

Invoke docx skill.

Cover page (title, auditor, date, overall result).
Pier Claim Records section.
Claim Records section (external).
Unsourced Attributions section.
Summary Table.
Overall Result block.

Colour coding: green E2EFDA, amber FFF2CC, red FCE4D6, header navy 1F3864 with white text.

## 10. STEP 5, SAVE AND PRESENT

YYMMDD_PIER_source_audit_[shortTitle]_vsend_C2.docx

## 11. KEY RULES

- Always search before concluding
- Scan for missing attributions, not just bad ones
- Run Pier specific check on every piece mentioning Pier
- Fetch every cited URL and read it
- Attribution accuracy critical (predecessor/successor)
- Distinguish stated regulatory powers from actual enforcement
- Flag unsourced forward looking claims
- Do not soften findings
- If a Pier claim is Fabrication, overall result cannot be Pass
