# Pier Executive Assistant source files

These are Oli's Executive Assistant instruction files from the Pier Cowork project, saved locally for reference during the Pier lead agent build.

## What's in here

- PIER_Rules.md, ambient rules that govern every output. Voice contracts, Mark's Sales DNA, size tier + insurance state framework, internal only lists.
- Lead_and_ICP_Brief.md, Companies Agent input. ICP definition, size tier estimation proxies, incumbent discovery framework, Lovable output format.
- LinkedIn_Message_Architect.md, Outbound Agent input for LinkedIn. Length caps, structures per message type, language handling.
- Email_Architect.md, Outbound Agent input for email. Structure, fidelity mode, event messages, sign off logic.
- PIER_Response_Bank.md, empty at v1. Populated as Oli reviews drafts and runs the Capture Processor.
- OUTREACH_QUICK_REFERENCE.md, one glance card. Priority tiers, qualifying tests, door in framings, cleared for external, internal only guardrails.
- Source_Audit_Skill.md, fact checking.
- Capture_Processor.md, structured extraction of feedback into Living Context / Response Bank entries.

## Priority for integrating into the lead agent build

Tier 1 (essential, drives system prompts):

1. PIER_Rules.md, ambient rules
2. Lead_and_ICP_Brief.md, Companies Agent ICP
3. LinkedIn_Message_Architect.md, Outbound Agent LinkedIn drafting
4. Email_Architect.md, Outbound Agent email drafting
5. OUTREACH_QUICK_REFERENCE.md, compressed cheat sheet
6. PIER_Response_Bank.md, empty for v1, wire the read but no content to inject yet

Tier 2 (helpful, informs reply classifier and future updates):

7. Source_Audit_Skill.md, background context for the audit rules
8. Capture_Processor.md, informs how the Response Bank populates over time

## Do NOT use for the lead agent build

- PIER_Living_Context.md (2,477 lines), Oli's personal context. Reference in the human curated Executive Assistant, not needed for the automated lead agent.
- PIER_Sparring_Partner.md, review agent not relevant for lead sourcing.
- PIER_Deck_Builder.md, V2 pitch deck automation feature; not V1.
- PIER_Capability_Reference.md, useful as reference for the Companies Agent but heavy. Bring in for V2 when refining.
