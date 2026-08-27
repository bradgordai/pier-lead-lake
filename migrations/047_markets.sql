-- B4: per-country channel legality, so outreach never defaults to cold email where it is
-- not lawful. cold_email_legal is the B2B cold-email position, not a general GDPR verdict.
-- Switzerland is seeded false deliberately: targeted B2B contact is tolerated in practice,
-- but the conservative default keeps LinkedIn primary.

CREATE TABLE IF NOT EXISTS public.markets (
  country          text PRIMARY KEY,
  cold_email_legal boolean NOT NULL,
  primary_channel  text NOT NULL DEFAULT 'LinkedIn',
  notes            text
);

INSERT INTO public.markets (country, cold_email_legal, primary_channel, notes) VALUES
  ('Germany',     false, 'LinkedIn', 'UWG: prior consent required for B2B cold email.'),
  ('Austria',     false, 'LinkedIn', 'TKG: opt-in required.'),
  ('Spain',       false, 'LinkedIn', 'LSSI: consent required.'),
  ('Luxembourg',  false, 'LinkedIn', 'Consent required.'),
  ('Switzerland', false, 'LinkedIn', 'Targeted B2B contact tolerated in practice; conservative default keeps LinkedIn primary.'),
  ('Netherlands', true,  'LinkedIn', 'B2B cold email permitted with clear opt-out.'),
  ('Belgium',     true,  'LinkedIn', 'B2B cold email permitted with clear opt-out.'),
  ('France',      true,  'LinkedIn', 'B2B cold email permitted, opt-out required.'),
  ('UK',          true,  'LinkedIn', 'PECR: B2B cold email permitted to corporate subscribers.')
ON CONFLICT (country) DO NOTHING;

ALTER TABLE public.markets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS markets_read ON public.markets;
CREATE POLICY markets_read ON public.markets FOR SELECT TO authenticated USING (true);

COMMENT ON TABLE public.markets IS
  'Channel legality by country. cold_email_legal governs whether cold email is an option; primary_channel is the default outreach channel.';
