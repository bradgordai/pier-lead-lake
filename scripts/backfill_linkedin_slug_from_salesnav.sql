-- One-off data backfill (applied 2026-08-24): linkedin_slug for existing Sales Nav imports.
--
-- Context: before the Sales Nav Watcher Make body was fixed to send the public /in/ URL
-- (linkedInProfileUrl -> {{5.defaultProfileUrl}}), Sales-Nav-imported contacts were stored
-- with linkedin_url = /sales/lead/{vmid} and linkedin_slug = NULL, so they never matched on
-- CR-accept. This backfills the canonical public slug for the 18 no-slug Pier-target contacts
-- (P271-P288) whose VMID appears in the phantom's Sales Nav export (pier-sales-nav-export.csv),
-- using each lead's real public slug from defaultProfileUrl. NOT guessed — every slug is the
-- phantom's own defaultProfileUrl value, matched by VMID.
--
-- The other 7 no-slug Pier targets (P264-P270) have linkedin_url = NULL and are NOT in the Sales
-- Nav export; they remain manual (add the LinkedIn URL + slug via Supabase Studio).
--
-- Idempotent: the WHERE clause only touches rows that are still NULL. The audit-trigger rows this
-- UPDATE produces (18 "Updated <name>" entries, only linkedin_slug changed) were pruned after
-- apply to keep the Actions Log clean, consistent with the migration-031 backfill handling.

UPDATE public.contacts c
SET linkedin_slug = m.slug
FROM (VALUES
  ('ACwAAAAiRVUB1qYes1g1vX9Pw61Rp5RiRnflbJc','kim-ulmer-koldby-905903'),
  ('ACwAAAAB4H4B51UtBDeaPHB7_gkyVGG7Fn9W6xU','nuessler'),
  ('ACwAABPykOEBRZm9YI3TYF7f0EHNIa1ZGpKJBJ8','brendan-lenane-2a90b394'),
  ('ACwAAA0jqGwBEwR2LDR7Md8RtARjpll9VWiAd4E','nick-mcbrien-a109a961'),
  ('ACwAACnQqtYBysw4ErDcpxCnw12EyI6HRldU-K0','aya-hamza-elmakrumi-506b40176'),
  ('ACwAABc8a2MBHGs60JkXjnrRRpA2Yx9FqCkriiQ','mario-fladt-39767baa'),
  ('ACwAADT4BwcB53hCtzQovNWQr5dz0nUp3DqbDNg','manuel-siebel-71b744209'),
  ('ACwAAA1p19IBU6CaxX3LqewFkcq5yPXgpRAI1GU','daniel-signer-81644763'),
  ('ACwAACix-sABaQSnImXMHAGKV07A09xB8M3OW3E','michael-schmid-62879b170'),
  ('ACwAADJGeZMB5DpNd6IsDTnh-F8gtnoFtFiTzXo','maik-friedrich-8175901b6'),
  ('ACwAAA6jZY0B3JSRhY5XZ8PWPrcXPXALzDJ7dn4','stephan-ide-5a52b76a'),
  ('ACwAACFliPUBCY7hDXVYPKXfQd1_FOox5I2kb-0','rodolphe-mulliez-045789137'),
  ('ACwAAADPuTYBeqp0T3f3sT06JXVbS0dDwCG7BFM','pailak-mzikian'),
  ('ACwAADLbPh8Bfc_jbp34Pts8IQ_f-p6yfrToHfs','ishnav'),
  ('ACwAAB8HeXYBy7Y-TwMacY2FRmiR00A5Er7eErE','dennis-backofen-75a413126'),
  ('ACwAABjodC0BS16c_fdi647RMGbm3dL7UdQnzB8','avkosar'),
  ('ACwAAAONN5cBizyn9Une2KRRODb8KNAk2Hg_wEA','davidgoodley'),
  ('ACwAAAT3qvUB2b9Cqb4fiENahYnuujLnvi1_XCs','matt-henry-219ab123')
) AS m(vmid, slug)
WHERE substring(c.linkedin_url from '/sales/lead/([^,?/#]+)') = m.vmid
  AND c.linkedin_slug IS NULL
  AND array_length(c.sn_lists, 1) > 0;
