-- 115 F17 i067 (2026-09-20, applied by Cowork via MCP; commit the file into the repo).
-- RECORDED FROM supabase_migrations.schema_migrations ON 2026-09-20. ALREADY APPLIED. DO NOT RE-APPLY.
--
-- Migration 114 put the sign-off rule into the always-on voice layers and corrected the bulk of the
-- drafts. Eleven were left signing "Oli". Applying Oliver's own rule to the remainder:
--
--   Sign as Oliver, UNLESS that contact has previously received a message from him signed "Oli",
--   in which case keep Oli. The short form is only used where a relationship already exists.
--
-- Measured before applying: of the 11, exactly ONE contact has a prior SENT message signed "Oli" —
-- Sanmeet Singh Kochhar (P651), whose pending Chaser 1 therefore keeps it. The other 10 have none:
-- Hille (itsco), Ktorza and Dosso (CertiDeal), Gibfried and Wursthorn (Pearl), Saint-Pol Cousteix
-- (Smaaart), Lorenz (Vodafone Germany), Nathalie D (AfB), Blanchard (Largo), Amarir (DBC Electronics).
-- All ten are pending_review Initial messages, so none is approved and none is at risk of sending.
--
-- Only the sign-off line changes. The body is untouched, so nothing else in the message moves.

update public.outreach_log o
   set message_body = regexp_replace(o.message_body, '(?m)^([ \t]*)Oli([ \t]*)$', '\1Oliver\2'),
       updated_at = now()
 where o.send_status::text = 'Draft'
   and o.message_body ~ '(?m)^\s*Oli\s*$'
   and not exists (
     select 1 from public.outreach_log p
      where p.contact_id = o.contact_id
        and p.send_status::text = 'Sent'
        and coalesce(p.sent_body, p.message_body) ~ '(?m)^\s*Oli\s*$');
