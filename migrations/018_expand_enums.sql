-- Migration 018: expand function_type and outreach_status enums
--
-- Both additions exist to stop the Excel v09 load from destroying signal:
--
--   1. function_type += 'Strategy'
--      78 contacts carry Function = 'Strategy' in the workbook. Aliasing them to
--      'Executive' merged a distinct job family into the C-suite bucket and lost
--      the ability to segment strategy/corp-dev contacts.
--
--   2. outreach_status += 'Not relevant'
--      8 contacts carry Outreach Status = 'Not relevant'. Aliasing them to
--      'Do not contact' is semantically wrong and dangerous: 'Do not contact' is
--      a GDPR/consent suppression state, whereas 'Not relevant' is a commercial
--      qualification judgement. Conflating them would either over-suppress valid
--      prospects or pollute the suppression list.
--
-- ALTER TYPE ... ADD VALUE IF NOT EXISTS is idempotent. New values are appended
-- to the end of the enum's sort order, which does not affect existing rows.

ALTER TYPE function_type    ADD VALUE IF NOT EXISTS 'Strategy';
ALTER TYPE outreach_status  ADD VALUE IF NOT EXISTS 'Not relevant';
