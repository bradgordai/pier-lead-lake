-- 073: F12 T1 (2026-09-09). Oli's three rulings from interim_intel.jsonl override the workbook,
-- plus the group-level duplicate-approach guard (master handover s5, acceptance test 3).
-- Run id in migration_audit: f12-pack-rulings-2026-09-09.
do $$
declare
  v_team uuid := 'ef73c15e-4d6f-4159-bcfa-cc76b5ae4972';
  v_run  text := 'f12-pack-rulings-2026-09-09';
  v_c295 uuid; v_c315 uuid; v_c316 uuid; v_c979 uuid; v_new uuid;
  v_unito_pg text := 'Otto Austria Group GmbH (UNITO Versand & Dienstleistungen GmbH), Wals-Siezenheim, subsidiary of Otto Group';
  v_conrad_pg text := 'Conrad Electronic SE, via RE-INvent Retail GmbH (ex Re-In Retail International GmbH), Klaus-Conrad-Strasse 2, 92533 Wernberg-Koeblitz, MD Heiko Voigt';
  v_c315_note text := E'[Ruling 2026-09-04, Oliver] Otto Austria Group / UNITO is worked as its own account with its own contacts in Salzburg and Graz. This SUPERSEDES the 30 Jul 2026 note on C315 that said to fold Otto Austria into the Hamburg conversation and not to run a parallel thread. Reason: the DACH flagship walk of 3 Sep 2026 established at BAUR that Otto Group companies decide locally and that a group-level approach to Hamburg misses the account; UNITO has ~400 staff, its own e-commerce platform and its own brands. The Hamburg thread is also cold - three contacts all Withdrawn, P286 and P287 in cooldown to 2027-02-25, and the 28 Aug GIVE chaser to P623 Dr Boris Ewenstein unanswered as at 4 Sep. Ackermann Vertriebs AG (CH) belongs to this group and must NOT be sourced as a separate Swiss retailer.';
  v_c315_evidence text := E'Evidence (interim_intel C315): Universal Impressum: ''Universal Versand GmbH, Alte Bundesstrasse 2a, 5071 Wals-Siezenheim, FN 235040y, Landesgericht Salzburg, Geschaeftsfuehrer Mag. Harald Gutschi'', shareholder ''Otto Austria Group GmbH'' at the same address. Otto Austria Group careers copy: ''Mit unseren Marken OTTO Oesterreich, Universal, Quelle, Lascana und Ackermann sind wir in Oesterreich, Deutschland und der Schweiz erfolgreich taetig'' and ''rund 400 Kolleginnen und Kollegen ... an unseren Standorten in Salzburg und Graz''. Ackermann Vertriebs AG CHE-115.455.663, Otelfingen, MD Arno Kerschbaumer, own Impressum names no parent; Handelsregister shareholder Otto Group GmbH & Co. KGaA, mail-order business acquired by UNITO in 2010, Quelle Vertriebs AG merged in 2023 per SHAB 30.06.2023. Source: Claude Code 4 Sep 2026 (WebFetch universal.at/impressum, ackermann.ch/impressum, Swiss Handelsregister), decision by Oliver on a question card, 4 Sep 2026.';
  v_c316_note text := E'[4 Sep 2026] GROUP MAP. getgoods.com = get your goods GmbH, formerly Sygonix GmbH, sole shareholder RE-INvent Retail GmbH. voelkner.de = C979 in this lake, same operator. digitalo.de = same operator. C316 Conrad is Contacted; C979 Voelkner is Untouched; getgoods sits on the DACH Flagship board where Oliver sourced leads on 4 Sep. THREE APPROACHES TO ONE GROUP ARE NOW POSSIBLE. Consolidate before sending. The live wedge is getgoods'': it sold an own-guarantee ''Anschluss-Garantie 24'' where ''Garantiegeber ist die get your goods GmbH'', then withdrew it from sale - demonstrated appetite plus demonstrated inability to carry the risk.';
  v_c316_evidence text := E'Evidence (interim_intel C316): getgoods.com Impressum and Handelsregister: get your goods GmbH, HRB 26515 Nuernberg, Klaus-Conrad-Strasse, Wernberg-Koeblitz, formerly Sygonix GmbH until May 2016, sole shareholder Re-In Retail International GmbH. voelkner Impressum: RE-INvent Retail GmbH, Klaus-Conrad-Strasse 2, 92533 Wernberg-Koeblitz, MD Heiko Voigt. Re-In acquired the Voelkner trade mark from Conrad in 2008. Source: Claude Code 4 Sep 2026, WebSearch of the Handelsregister and Impressum records, prompted by Oliver''s board note that getgoods showed only two people on LinkedIn.';
  v_c295_note text := E'[Ruling 2026-09-03, Oliver] DO NOT WORK. Telia owns its underwriter (Telia Insurance AB) and bills SEK 149/month across the range. Not a partner prospect - they are the insurer. Next action: none. Do not source, do not chase. Revisit only if Telia publicly exits its own underwriting. Evidence: ''Provided by Telia Insurance AB. SEK 149/month after one month. Deductible SEK 300. No commitment period, no notice period. No limit on the number of injuries [claims].'' Source: Oliver, Telia''s own insurance product page (SE), pasted into the DACH Sourcing Run artifact comment box on C295, 3 Sep 2026.';
  r record;
begin
  select id into v_c295 from companies where company_id='C295' and team_id=v_team;
  select id into v_c315 from companies where company_id='C315' and team_id=v_team;
  select id into v_c316 from companies where company_id='C316' and team_id=v_team;
  select id into v_c979 from companies where company_id='C979' and team_id=v_team;

  -- ---------------- C295 Telia: out of scope, archived, outreach blocked
  insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
    select v_run, 't1_c295_telia', 'companies', 'C295', 'update', id,
      jsonb_build_object('before', jsonb_build_object('opportunity_status', opportunity_status, 'archived_at', archived_at, 'insurance_offered', insurance_offered, 'insurance_provider', insurance_provider, 'coverage_summary', coverage_summary))
    from companies where id=v_c295;
  update companies set
    opportunity_status = 'Out of Scope',
    archived_at = coalesce(archived_at, now()),
    archive_reason = 'out_of_scope',
    insurance_offered = 'Yes',
    insurance_provider = 'Telia Insurance AB (in-house underwriter)',
    coverage_summary = 'Covers sudden and unforeseen damage not covered by warranty; positioned as broader than warranty or home insurance. Exclusions: wear and tear, and damage that does not affect usability. Safety and care requirements apply. MONTHLY, SEK 149/month after a free first month. Deductible SEK 300. No commitment period, no notice period. No limit on the number of claims. Battery replacement included. Maximum insured value SEK 40,000. Underwritten in-house by Telia Insurance AB.',
    additional_notes = concat_ws(E'\n\n', v_c295_note, additional_notes),
    source_urls = concat_ws(E'\n', 'Telia insurance product page (SE), pasted by Oliver 3 Sep 2026', source_urls),
    needs_review = false,
    updated_at = now()
  where id=v_c295;
  for r in select id, contact_id, outreach_status, next_action from contacts where company_id=v_c295 loop
    insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
      values (v_run, 't1_c295_telia', 'contacts', r.contact_id, 'update', r.id, jsonb_build_object('before', jsonb_build_object('outreach_status', r.outreach_status, 'next_action', r.next_action)));
  end loop;
  update contacts set outreach_status='Not relevant',
    next_action = 'Ruling 3 Sep 2026 (Oliver): Telia is the insurer (Telia Insurance AB). Do not source, do not chase. Revisit only if Telia publicly exits its own underwriting.',
    next_action_date = '2027-09-03', updated_at = now()
  where company_id=v_c295;
  -- Telia Norge / DK / Finland: same parent, flagged for Oliver (not in the ruling, so not archived).
  update companies set parent_group = coalesce(parent_group, 'Telia Company AB'),
    additional_notes = concat_ws(E'\n\n', '[Flag 2026-09-09, from ruling C295] Sister operating company of Telia (SE), which Oliver ruled DO NOT WORK on 3 Sep 2026 because Telia Insurance AB underwrites in-house. Check whether the same in-house product applies here before any sourcing.', additional_notes),
    needs_review = true, updated_at = now()
  where company_id in ('C724','C755','C774') and team_id=v_team;

  -- ---------------- C315 Otto Group (Hamburg) + the UNITO account and its brands
  insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
    select v_run, 't1_c315_unito', 'companies', 'C315', 'update', id, jsonb_build_object('before', jsonb_build_object('parent_group', parent_group, 'opportunity_status', opportunity_status)) from companies where id=v_c315;
  update companies set
    parent_group = 'Otto Group (Otto GmbH & Co KG, Hamburg); decides locally per company (BAUR: Burgkunstadt; UNITO: Salzburg)',
    additional_notes = concat_ws(E'\n\n', v_c315_note, v_c315_evidence, additional_notes),
    updated_at = now()
  where id=v_c315;
  -- New rows so the group guard and the sourcing dedupe can see the group.
  insert into companies (team_id, company_id, company_name, country, website_url, parent_group, opportunity_status, research_stage, headquarter_location, additional_notes, source_urls, added_via, date_added, needs_review)
  values
   (v_team, 'C1343', 'Otto Austria Group (UNITO)', 'Austria', 'https://www.unito.at/', v_unito_pg, 'Prospect', 'Light triage', 'Wals-Siezenheim (Salzburg) and Graz',
     concat_ws(E'\n\n', '[Ruling 2026-09-04, Oliver] Worked as its OWN account from Salzburg, decision locus Salzburg. Brands: Universal, OTTO Austria, Quelle, Lascana, Ackermann (CH). Universal is greenfield: a free self-funded 3-year XXL-Garantie, no insurer, no IPID, nothing covering drop, liquid, theft or loss. ottoversand.at separately confirmed greenfield at checkout on 30 Jul 2026. Next action: source Otto Austria Group decision-makers in Salzburg and Graz into the Stage 0 Sales Nav list.', v_c315_note, v_c315_evidence),
     'interim_intel.jsonl C315 (4 Sep 2026)', 'ruling_C315_2026-09-04', '2026-09-09', false),
   (v_team, 'C1344', 'Universal Versand (universal.at)', 'Austria', 'https://www.universal.at/', v_unito_pg, 'Prospect', 'Light triage', 'Wals-Siezenheim (Salzburg)',
     '[Ruling 2026-09-04] Brand of Otto Austria Group (UNITO). Worked through the UNITO account (C1343), never as a separate approach. Greenfield: free self-funded 3-year XXL-Garantie, no insurer, no IPID.', 'universal.at/impressum (4 Sep 2026)', 'ruling_C315_2026-09-04', '2026-09-09', false),
   (v_team, 'C1345', 'OTTO Austria (ottoversand.at)', 'Austria', 'https://www.ottoversand.at/', v_unito_pg, 'Prospect', 'Light triage', 'Wals-Siezenheim (Salzburg)',
     '[Ruling 2026-09-04] Brand of Otto Austria Group (UNITO). Worked through the UNITO account (C1343). Confirmed greenfield at checkout 30 Jul 2026.', 'interim_intel.jsonl C315', 'ruling_C315_2026-09-04', '2026-09-09', false),
   (v_team, 'C1346', 'Quelle Austria (quelle.at)', 'Austria', 'https://www.quelle.at/', v_unito_pg, 'Prospect', 'Untouched', 'Wals-Siezenheim (Salzburg)',
     '[Ruling 2026-09-04] Brand of Otto Austria Group (UNITO). Worked through the UNITO account (C1343).', 'interim_intel.jsonl C315', 'ruling_C315_2026-09-04', '2026-09-09', false),
   (v_team, 'C1347', 'Lascana Austria (lascana.at)', 'Austria', 'https://www.lascana.at/', v_unito_pg, 'Prospect', 'Untouched', 'Wals-Siezenheim (Salzburg)',
     '[Ruling 2026-09-04] Brand of Otto Austria Group (UNITO). Lingerie/fashion, unlikely device volume. Worked through the UNITO account (C1343).', 'interim_intel.jsonl C315', 'ruling_C315_2026-09-04', '2026-09-09', false),
   (v_team, 'C1348', 'Ackermann Vertriebs AG (ackermann.ch)', 'Switzerland', 'https://www.ackermann.ch/', v_unito_pg, 'Prospect', 'Light triage', 'Otelfingen (ZH)',
     '[Ruling 2026-09-04, Oliver] DO NOT SOURCE AS A SEPARATE SWISS RETAILER. Ackermann Vertriebs AG (CHE-115.455.663, MD Arno Kerschbaumer) belongs to Otto Austria Group / UNITO; the mail-order business was acquired by UNITO in 2010 and Quelle Vertriebs AG merged into it in 2023 (SHAB 30.06.2023). Its own Impressum names no parent, which is why it looks independent on a Swiss sourcing run. Worked only through the UNITO account (C1343).', 'ackermann.ch/impressum; Swiss Handelsregister (4 Sep 2026)', 'ruling_C315_2026-09-04', '2026-09-09', false);
  insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
    select v_run, 't1_c315_unito', 'companies', company_id, 'insert', id, jsonb_build_object('company_name', company_name, 'parent_group', parent_group) from companies where company_id in ('C1343','C1344','C1345','C1346','C1347','C1348');

  -- ---------------- C316 Conrad + RE-INvent Retail group
  insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
    select v_run, 't1_c316_conrad', 'companies', company_id, 'update', id, jsonb_build_object('before', jsonb_build_object('parent_group', parent_group)) from companies where id in (v_c316, v_c979);
  update companies set parent_group = v_conrad_pg,
    additional_notes = concat_ws(E'\n\n', v_c316_note, v_c316_evidence, additional_notes), updated_at = now()
  where id in (v_c316, v_c979);
  insert into companies (team_id, company_id, company_name, country, website_url, parent_group, opportunity_status, research_stage, headquarter_location, additional_notes, source_urls, added_via, date_added, needs_review)
  values
   (v_team, 'C1349', 'getgoods.com (get your goods GmbH)', 'Germany', 'https://www.getgoods.com/', v_conrad_pg, 'Prospect', 'Light triage', 'Wernberg-Koeblitz',
     concat_ws(E'\n\n', '[Ruling 2026-09-04] Storefront of RE-INvent Retail GmbH (Conrad group), same operator as voelkner (C979) and digitalo. ONE group approach only; C316 Conrad is already in Monday. Live wedge: sold an own-guarantee ''Anschluss-Garantie 24'' (Garantiegeber get your goods GmbH), then withdrew it from sale. The getgoods leads Oliver sourced on 4 Sep sit on the DACH Flagship board, not in this lake yet.', v_c316_evidence), 'getgoods.com Impressum, Handelsregister HRB 26515 Nuernberg (4 Sep 2026)', 'ruling_C316_2026-09-04', '2026-09-09', false),
   (v_team, 'C1350', 'digitalo (digitalo.de)', 'Germany', 'https://www.digitalo.de/', v_conrad_pg, 'Prospect', 'Untouched', 'Wernberg-Koeblitz',
     '[Ruling 2026-09-04] Storefront of RE-INvent Retail GmbH (Conrad group), same operator as voelkner (C979) and getgoods. ONE group approach only.', 'interim_intel.jsonl C316', 'ruling_C316_2026-09-04', '2026-09-09', false),
   (v_team, 'C1351', 'SMDV (smdv.de)', 'Germany', 'https://www.smdv.de/', v_conrad_pg, 'Prospect', 'Untouched', 'Wernberg-Koeblitz',
     '[Ruling 2026-09-04] Fourth storefront named under RE-INvent Retail GmbH (Conrad group). ONE group approach only.', 'interim_intel.jsonl C316', 'ruling_C316_2026-09-04', '2026-09-09', false);
  insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
    select v_run, 't1_c316_conrad', 'companies', company_id, 'insert', id, jsonb_build_object('company_name', company_name, 'parent_group', parent_group) from companies where company_id in ('C1349','C1350','C1351');
end $$;

-- ---------------- Group-level duplicate-approach guard (acceptance test 3)
alter table public.refusals drop constraint if exists refusals_reason_code_check;
alter table public.refusals add constraint refusals_reason_code_check check (reason_code = any (array['allowance_exhausted','promise_of_quiet','dnc_or_opted_out','cr_cooldown_active','company_not_deep_researched','thread_text_missing','channel_illegal_in_market','contact_parked','contact_replied','group_sibling_engaged','country_unknown']));

create or replace function public.fn_group_siblings_engaged(p_team_id uuid, p_company_id uuid)
returns table(company_id uuid, company_ref text, company_name text, why text)
language sql stable set search_path to 'public','pg_temp' as $$
  select s.id, s.company_id, s.company_name,
         case when s.monday_deal_id is not null or s.archive_reason = 'promoted_to_monday' then 'in Monday'
              when s.opportunity_status::text in ('Contacted','Active Lead','Partner') then s.opportunity_status::text
              else 'contact engaged' end
    from public.companies me
    join public.companies s on s.team_id = me.team_id and s.id <> me.id
                           and s.parent_group is not null and btrim(s.parent_group) = btrim(me.parent_group)
   where me.id = p_company_id and me.team_id = p_team_id and me.parent_group is not null
     and ( s.monday_deal_id is not null or s.archive_reason = 'promoted_to_monday'
           or s.opportunity_status::text in ('Contacted','Active Lead','Partner')
           or exists (select 1 from public.contacts c where c.company_id = s.id and c.outreach_status::text in ('Contacted','In conversation','Meeting booked')) );
$$;
revoke execute on function public.fn_group_siblings_engaged(uuid, uuid) from public, anon;
