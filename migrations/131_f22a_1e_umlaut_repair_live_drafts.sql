-- 131 F22A.1(e): repair transliterated / stripped umlauts in the 10 LIVE pending_review drafts. Sent history untouched.
-- Source of the fault: the model copied transliterated spelling from Galaxus company/contact notes (8 of 10) and
-- the F15.3 routing-repair drafts (2). No code path transliterates. Swiss targets keep ss for ß (pier_rules German rule 9).
-- Each update is guarded by md5 of the exact old body, so a row that changed since measurement is left alone.
do $$ declare n int := 0; k int; begin
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22','f22a_1e_umlaut_repair','outreach_log','0b4583fc-1f89-485e-b83d-2fdf5de54523','body_repaired', o.id, jsonb_build_object('before', o.message_body, 'after', $b$Guten Tag Herr Freuler

Bei einem iPhone 17 aus Ihrem Sortiment kostet AppleCare+ CHF 149 für zwei Jahre, bei einem Galaxy S26 die Helvetia Elektronik-Versicherung CHF 170. Beides einmalig bezahlt, beides ohne Diebstahl- und Verlustschutz.

Wir bauen bei Pier genau diese Deckungslücke als wiederkehrendes Produkt statt als Einmalkauf, markenunabhängig und ohne Aufwand für das Produktteam. Habe ich das richtig gesehen, oder deckt eines Ihrer Programme Diebstahl und Verlust bereits ab?

Viele Grüsse
Oliver$b$)
    from public.outreach_log o where o.id='0b4583fc-1f89-485e-b83d-2fdf5de54523' and md5(o.message_body)='533fb76ef986446bf897e150f6e46df8' and o.draft_status='pending_review' and o.send_status='Draft';
  update public.outreach_log set message_body=$b$Guten Tag Herr Freuler

Bei einem iPhone 17 aus Ihrem Sortiment kostet AppleCare+ CHF 149 für zwei Jahre, bei einem Galaxy S26 die Helvetia Elektronik-Versicherung CHF 170. Beides einmalig bezahlt, beides ohne Diebstahl- und Verlustschutz.

Wir bauen bei Pier genau diese Deckungslücke als wiederkehrendes Produkt statt als Einmalkauf, markenunabhängig und ohne Aufwand für das Produktteam. Habe ich das richtig gesehen, oder deckt eines Ihrer Programme Diebstahl und Verlust bereits ab?

Viele Grüsse
Oliver$b$ where id='0b4583fc-1f89-485e-b83d-2fdf5de54523' and md5(message_body)='533fb76ef986446bf897e150f6e46df8' and draft_status='pending_review' and send_status='Draft';
  get diagnostics k = row_count; n := n + k;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22','f22a_1e_umlaut_repair','outreach_log','1f4174f7-a354-4334-8754-d36d1d403d47','body_repaired', o.id, jsonb_build_object('before', o.message_body, 'after', $b$Guten Tag Herr Stolle,

Beim Blick durch den Digitec-Galaxus- und Galaxus-Checkout ist mir aufgefallen, dass sowohl AppleCare+ als auch die Helvetia-Elektronikversicherung Diebstahl und Verlust ausdrücklich ausschliessen. Das gilt für beide Marken und für beide Länder.

Wir bei Pier haben mit Handels- und Retailpartnern in Europa genau diese Lücke geschlossen, meist als zusätzliche, wiederkehrende Umsatzquelle statt der bisherigen Einmalprämie.

Wäre ein kurzer Austausch dazu von Interesse für Sie?

Oliver$b$)
    from public.outreach_log o where o.id='1f4174f7-a354-4334-8754-d36d1d403d47' and md5(o.message_body)='5d0276ca436a1f7a6ee1de43951922ce' and o.draft_status='pending_review' and o.send_status='Draft';
  update public.outreach_log set message_body=$b$Guten Tag Herr Stolle,

Beim Blick durch den Digitec-Galaxus- und Galaxus-Checkout ist mir aufgefallen, dass sowohl AppleCare+ als auch die Helvetia-Elektronikversicherung Diebstahl und Verlust ausdrücklich ausschliessen. Das gilt für beide Marken und für beide Länder.

Wir bei Pier haben mit Handels- und Retailpartnern in Europa genau diese Lücke geschlossen, meist als zusätzliche, wiederkehrende Umsatzquelle statt der bisherigen Einmalprämie.

Wäre ein kurzer Austausch dazu von Interesse für Sie?

Oliver$b$ where id='1f4174f7-a354-4334-8754-d36d1d403d47' and md5(message_body)='5d0276ca436a1f7a6ee1de43951922ce' and draft_status='pending_review' and send_status='Draft';
  get diagnostics k = row_count; n := n + k;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22','f22a_1e_umlaut_repair','outreach_log','3e5e09fe-5aac-4c30-a569-4d70a45726ba','body_repaired', o.id, jsonb_build_object('before', o.message_body, 'after', $b$Guten Tag Frau Arnold

Ich habe mir angeschaut, wie Digitec Galaxus Geräteschutz anbietet, und dabei etwas Konkretes gefunden: Weder bei AppleCare+ noch bei der Helvetia Elektronik-Versicherung ist Diebstahl oder Verlust mitversichert, in der Schweiz wie in Deutschland. Das gilt für jedes Gerät, jede Marke.

Ausserdem lässt sich der Schutz nur einmalig beim Kauf abschliessen, als Einmalzahlung für eine feste Laufzeit. Bei Pier arbeiten wir mit Händlern an Programmen, die genau diese Lücke schliessen und als wiederkehrendes Modell laufen statt als einmaliger Verkauf.

Habe ich da etwas übersehen, oder deckt einer Ihrer Partner das inzwischen ab?

Oliver$b$)
    from public.outreach_log o where o.id='3e5e09fe-5aac-4c30-a569-4d70a45726ba' and md5(o.message_body)='d486993fb8bd1e0fffe8e28927f6c933' and o.draft_status='pending_review' and o.send_status='Draft';
  update public.outreach_log set message_body=$b$Guten Tag Frau Arnold

Ich habe mir angeschaut, wie Digitec Galaxus Geräteschutz anbietet, und dabei etwas Konkretes gefunden: Weder bei AppleCare+ noch bei der Helvetia Elektronik-Versicherung ist Diebstahl oder Verlust mitversichert, in der Schweiz wie in Deutschland. Das gilt für jedes Gerät, jede Marke.

Ausserdem lässt sich der Schutz nur einmalig beim Kauf abschliessen, als Einmalzahlung für eine feste Laufzeit. Bei Pier arbeiten wir mit Händlern an Programmen, die genau diese Lücke schliessen und als wiederkehrendes Modell laufen statt als einmaliger Verkauf.

Habe ich da etwas übersehen, oder deckt einer Ihrer Partner das inzwischen ab?

Oliver$b$ where id='3e5e09fe-5aac-4c30-a569-4d70a45726ba' and md5(message_body)='d486993fb8bd1e0fffe8e28927f6c933' and draft_status='pending_review' and send_status='Draft';
  get diagnostics k = row_count; n := n + k;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22','f22a_1e_umlaut_repair','outreach_log','3f463e4e-41ea-46d5-94de-0818e9d5eaa3','body_repaired', o.id, jsonb_build_object('before', o.message_body, 'after', $b$Sehr geehrte Frau Arndt,

bei Galaxus DE ist die Geräteversicherung nur direkt beim Kauf abschließbar, laut AVB. Jeder Kunde, der im Moment nicht zugreift, ist für euch dauerhaft verloren.

Wir bauen bei Pier genau dafür ein Modell: erster Monat inklusive, Aktivierung erst nach dem Kauf, dadurch verkaufen wir auch nach dem Checkout weiter. Bei vergleichbaren Partnern hat das die Attachment-Rate um das 4-5-fache gesteigert.

Wäre es interessant, kurz zu vergleichen, wie das für euer Sortiment aussehen könnte?

Oliver

Oliver$b$)
    from public.outreach_log o where o.id='3f463e4e-41ea-46d5-94de-0818e9d5eaa3' and md5(o.message_body)='adba356954d994145294efbbce70c71c' and o.draft_status='pending_review' and o.send_status='Draft';
  update public.outreach_log set message_body=$b$Sehr geehrte Frau Arndt,

bei Galaxus DE ist die Geräteversicherung nur direkt beim Kauf abschließbar, laut AVB. Jeder Kunde, der im Moment nicht zugreift, ist für euch dauerhaft verloren.

Wir bauen bei Pier genau dafür ein Modell: erster Monat inklusive, Aktivierung erst nach dem Kauf, dadurch verkaufen wir auch nach dem Checkout weiter. Bei vergleichbaren Partnern hat das die Attachment-Rate um das 4-5-fache gesteigert.

Wäre es interessant, kurz zu vergleichen, wie das für euer Sortiment aussehen könnte?

Oliver

Oliver$b$ where id='3f463e4e-41ea-46d5-94de-0818e9d5eaa3' and md5(message_body)='adba356954d994145294efbbce70c71c' and draft_status='pending_review' and send_status='Draft';
  get diagnostics k = row_count; n := n + k;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22','f22a_1e_umlaut_repair','outreach_log','701918ec-dd94-4a00-bf7f-70d9e0d02685','body_repaired', o.id, jsonb_build_object('before', o.message_body, 'after', $b$Guten Tag Herr Dill

Ich habe mir den Checkout von Digitec Galaxus angesehen, insbesondere die Absicherung für Smartphones und Notebooks. Auffällig war, dass sowohl bei den Apple-Geräten als auch bei der Helvetia-Elektronikversicherung Diebstahl und Verlust ausgeschlossen sind. Das gilt offenbar für die gesamte Palette, unabhängig von der Marke.

Wir bei Pier arbeiten mit Händlern und Marktplätzen zusammen und bauen genau diese Deckungslücke in ein Programm ein, das vollständig verwaltet wird und zusätzlich als wiederkehrende Einnahmequelle funktioniert statt als einmaliger Kauf.

Oder habe ich das falsch eingeschätzt und es gibt bereits eine Lösung dafür, die ich übersehen habe?

Würde es sich lohnen, kurz zu vergleichen, wie das bei Ihnen heute gehandhabt wird?

Viele Grüsse
Oliver$b$)
    from public.outreach_log o where o.id='701918ec-dd94-4a00-bf7f-70d9e0d02685' and md5(o.message_body)='edc2dced003e881d8e989cea8a9e0e9a' and o.draft_status='pending_review' and o.send_status='Draft';
  update public.outreach_log set message_body=$b$Guten Tag Herr Dill

Ich habe mir den Checkout von Digitec Galaxus angesehen, insbesondere die Absicherung für Smartphones und Notebooks. Auffällig war, dass sowohl bei den Apple-Geräten als auch bei der Helvetia-Elektronikversicherung Diebstahl und Verlust ausgeschlossen sind. Das gilt offenbar für die gesamte Palette, unabhängig von der Marke.

Wir bei Pier arbeiten mit Händlern und Marktplätzen zusammen und bauen genau diese Deckungslücke in ein Programm ein, das vollständig verwaltet wird und zusätzlich als wiederkehrende Einnahmequelle funktioniert statt als einmaliger Kauf.

Oder habe ich das falsch eingeschätzt und es gibt bereits eine Lösung dafür, die ich übersehen habe?

Würde es sich lohnen, kurz zu vergleichen, wie das bei Ihnen heute gehandhabt wird?

Viele Grüsse
Oliver$b$ where id='701918ec-dd94-4a00-bf7f-70d9e0d02685' and md5(message_body)='edc2dced003e881d8e989cea8a9e0e9a' and draft_status='pending_review' and send_status='Draft';
  get diagnostics k = row_count; n := n + k;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22','f22a_1e_umlaut_repair','outreach_log','8c82771d-4fe7-4007-abb0-383b10ce0d7c','body_repaired', o.id, jsonb_build_object('before', o.message_body, 'after', $b$Guten Tag Herr Fugmann

Eine Beobachtung aus Ihrem Checkout, die ich Ihnen nicht vorenthalten wollte: Weder die AppleCare+ Police noch die Helvetia Elektronik-Versicherung, die Sie Ihren Kundinnen und Kunden anbieten, deckt Diebstahl oder Verlust ab. Das gilt für beide Marken und, soweit ich sehe, auch für den deutschen Arm der Gruppe. Aus Kundensicht bleibt damit ausgerechnet das Risiko unversichert, das bei einem Mobilgerät am häufigsten vorkommt.

Wir bei Pier bauen genau diese Deckung in bestehende Verkaufsprozesse ein, ohne dass der Handelspartner selbst zum Versicherer wird. Ausserdem läuft bei Ihnen aktuell alles als Einmalzahlung über die Vertragslaufzeit, während ein wiederkehrendes Modell auf derselben Kundenbasis in der Regel deutlich mehr Ertrag über die Zeit bringt.

Wäre es interessant, kurz zu vergleichen, wie Ihr heutiges Modell im Verhältnis zu einem wiederkehrenden Ansatz abschneidet?

Oliver$b$)
    from public.outreach_log o where o.id='8c82771d-4fe7-4007-abb0-383b10ce0d7c' and md5(o.message_body)='d496661d959daf2506c8ff803256afc3' and o.draft_status='pending_review' and o.send_status='Draft';
  update public.outreach_log set message_body=$b$Guten Tag Herr Fugmann

Eine Beobachtung aus Ihrem Checkout, die ich Ihnen nicht vorenthalten wollte: Weder die AppleCare+ Police noch die Helvetia Elektronik-Versicherung, die Sie Ihren Kundinnen und Kunden anbieten, deckt Diebstahl oder Verlust ab. Das gilt für beide Marken und, soweit ich sehe, auch für den deutschen Arm der Gruppe. Aus Kundensicht bleibt damit ausgerechnet das Risiko unversichert, das bei einem Mobilgerät am häufigsten vorkommt.

Wir bei Pier bauen genau diese Deckung in bestehende Verkaufsprozesse ein, ohne dass der Handelspartner selbst zum Versicherer wird. Ausserdem läuft bei Ihnen aktuell alles als Einmalzahlung über die Vertragslaufzeit, während ein wiederkehrendes Modell auf derselben Kundenbasis in der Regel deutlich mehr Ertrag über die Zeit bringt.

Wäre es interessant, kurz zu vergleichen, wie Ihr heutiges Modell im Verhältnis zu einem wiederkehrenden Ansatz abschneidet?

Oliver$b$ where id='8c82771d-4fe7-4007-abb0-383b10ce0d7c' and md5(message_body)='d496661d959daf2506c8ff803256afc3' and draft_status='pending_review' and send_status='Draft';
  get diagnostics k = row_count; n := n + k;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22','f22a_1e_umlaut_repair','outreach_log','8f6c06b4-7442-456e-af29-825396ca4329','body_repaired', o.id, jsonb_build_object('before', o.message_body, 'after', $b$Hey Alexander, dein Wechsel von Razor Group zu MMS Marketplace ist ein spannender Schritt, gerade weil du jetzt auf der Marketplace-Seite des Elektronik-Handels sitzt statt auf der Brand-Seite. Bei Pier sehen wir immer wieder, wie unterschiedlich Versicherungsschutz für Marketplace- und Refurbished-Geräte gedacht werden muss im Vergleich zu Neugeräten im stationären Handel. Wie geht ihr das bei MMS Marketplace aktuell an, gibt es da schon ein Schutzangebot für eure Verkäufer und Kunden?

Oliver$b$)
    from public.outreach_log o where o.id='8f6c06b4-7442-456e-af29-825396ca4329' and md5(o.message_body)='98fc2c5f8ce794c8237659014b64ab4e' and o.draft_status='pending_review' and o.send_status='Draft';
  update public.outreach_log set message_body=$b$Hey Alexander, dein Wechsel von Razor Group zu MMS Marketplace ist ein spannender Schritt, gerade weil du jetzt auf der Marketplace-Seite des Elektronik-Handels sitzt statt auf der Brand-Seite. Bei Pier sehen wir immer wieder, wie unterschiedlich Versicherungsschutz für Marketplace- und Refurbished-Geräte gedacht werden muss im Vergleich zu Neugeräten im stationären Handel. Wie geht ihr das bei MMS Marketplace aktuell an, gibt es da schon ein Schutzangebot für eure Verkäufer und Kunden?

Oliver$b$ where id='8f6c06b4-7442-456e-af29-825396ca4329' and md5(message_body)='98fc2c5f8ce794c8237659014b64ab4e' and draft_status='pending_review' and send_status='Draft';
  get diagnostics k = row_count; n := n + k;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22','f22a_1e_umlaut_repair','outreach_log','b6f2a211-8d80-42f0-8a61-722dcf160e69','body_repaired', o.id, jsonb_build_object('before', o.message_body, 'after', $b$Guten Tag Frau Keller,

Ihr Beitrag zum Marketplace-Wachstum bei MediaMarkt Saturn ist mir aufgefallen, insbesondere die Zahl zu Refurbished-Produkten: 15 Prozent des Marketplace-Umsatzes, zuletzt schon über 20 Prozent, vierfaches Wachstum im Jahresvergleich. Das ist ein Signal, das wir bei Pier auch bei anderen Händlern sehen: Käufer von Refurbished-Geräten legen oft mehr Wert auf Schutz als Käufer von Neugeräten, weil das Gerät für sie einen anderen Wert hat.

Wir bei Pier Insurance entwickeln eingebettete Gadget-Versicherungen speziell für den Refurbished- und Marketplace-Bereich, dort, wo klassische Versicherer meist nur ein generisches Produkt anbieten. Bei einem Wachstum wie Ihrem stellt sich die Frage, ob der Schutz für diese Kategorie schon so funktioniert, wie er könnte.

Wie deckt MediaMarkt Saturn den Schutz für Marketplace- und Refurbished-Geräte aktuell ab?

Viele Grüße
Oliver$b$)
    from public.outreach_log o where o.id='b6f2a211-8d80-42f0-8a61-722dcf160e69' and md5(o.message_body)='bb94d8b88600d8992c86f9dc28d1fa11' and o.draft_status='pending_review' and o.send_status='Draft';
  update public.outreach_log set message_body=$b$Guten Tag Frau Keller,

Ihr Beitrag zum Marketplace-Wachstum bei MediaMarkt Saturn ist mir aufgefallen, insbesondere die Zahl zu Refurbished-Produkten: 15 Prozent des Marketplace-Umsatzes, zuletzt schon über 20 Prozent, vierfaches Wachstum im Jahresvergleich. Das ist ein Signal, das wir bei Pier auch bei anderen Händlern sehen: Käufer von Refurbished-Geräten legen oft mehr Wert auf Schutz als Käufer von Neugeräten, weil das Gerät für sie einen anderen Wert hat.

Wir bei Pier Insurance entwickeln eingebettete Gadget-Versicherungen speziell für den Refurbished- und Marketplace-Bereich, dort, wo klassische Versicherer meist nur ein generisches Produkt anbieten. Bei einem Wachstum wie Ihrem stellt sich die Frage, ob der Schutz für diese Kategorie schon so funktioniert, wie er könnte.

Wie deckt MediaMarkt Saturn den Schutz für Marketplace- und Refurbished-Geräte aktuell ab?

Viele Grüße
Oliver$b$ where id='b6f2a211-8d80-42f0-8a61-722dcf160e69' and md5(message_body)='bb94d8b88600d8992c86f9dc28d1fa11' and draft_status='pending_review' and send_status='Draft';
  get diagnostics k = row_count; n := n + k;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22','f22a_1e_umlaut_repair','outreach_log','c94176a5-1932-46a4-9e6f-c65d7f70d29f','body_repaired', o.id, jsonb_build_object('before', o.message_body, 'after', $b$Sehr geehrter Herr Teuteberg,

ich habe mir Ihren Checkout für ein iPhone und ein Samsung-Gerät angesehen. Auffällig: sowohl AppleCare+ als auch die Helvetia Elektronik-Versicherung schliessen Verlust und Diebstahl aus. Der Kunde trägt dieses Risiko in beiden Fällen selbst, unabhängig von der Marke.

Wir bei Pier arbeiten mit Händlern an genau dieser Lücke, meist als zusätzliche Deckung neben der bestehenden Versicherung, nicht als Ersatz. Bei einem Geschäft Ihrer Grössenordnung kann das eine relevante wiederkehrende Ertragslinie werden.

Habe ich hier etwas übersehen, oder ist Verlust/Diebstahl bei Ihnen tatsächlich nicht abgedeckt?

Oliver$b$)
    from public.outreach_log o where o.id='c94176a5-1932-46a4-9e6f-c65d7f70d29f' and md5(o.message_body)='b2f646c83b2638c28c05dc22ae1acc7f' and o.draft_status='pending_review' and o.send_status='Draft';
  update public.outreach_log set message_body=$b$Sehr geehrter Herr Teuteberg,

ich habe mir Ihren Checkout für ein iPhone und ein Samsung-Gerät angesehen. Auffällig: sowohl AppleCare+ als auch die Helvetia Elektronik-Versicherung schliessen Verlust und Diebstahl aus. Der Kunde trägt dieses Risiko in beiden Fällen selbst, unabhängig von der Marke.

Wir bei Pier arbeiten mit Händlern an genau dieser Lücke, meist als zusätzliche Deckung neben der bestehenden Versicherung, nicht als Ersatz. Bei einem Geschäft Ihrer Grössenordnung kann das eine relevante wiederkehrende Ertragslinie werden.

Habe ich hier etwas übersehen, oder ist Verlust/Diebstahl bei Ihnen tatsächlich nicht abgedeckt?

Oliver$b$ where id='c94176a5-1932-46a4-9e6f-c65d7f70d29f' and md5(message_body)='b2f646c83b2638c28c05dc22ae1acc7f' and draft_status='pending_review' and send_status='Draft';
  get diagnostics k = row_count; n := n + k;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22','f22a_1e_umlaut_repair','outreach_log','fb299f5e-2472-4049-b902-cd4c8af5f5b7','body_repaired', o.id, jsonb_build_object('before', o.message_body, 'after', $b$Guten Tag Frau Kaltenecker,

Ich habe mir Galaxus' Absicherungsangebot für Elektronikgeräte angeschaut. Auffällig: Diebstahl und Verlust sind ausgeschlossen, und die Deckung lässt sich nur einmalig beim Kauf abschließen, wer diesen Moment verpasst, ist dauerhaft außen vor.

Wir bei Pier haben ein Modell entwickelt, bei dem der Schutz nach dem Kauf aktiviert wird, monatlich statt einmalig läuft und dadurch bei vergleichbaren Partnern die Attachment-Rate und den Versicherungsumsatz um das 4-5-fache steigert, bei vollem Betrieb durch uns.

Wäre es interessant, einmal zu vergleichen, wie sich das auf Ihr Sortiment übertragen ließe?

Oliver$b$)
    from public.outreach_log o where o.id='fb299f5e-2472-4049-b902-cd4c8af5f5b7' and md5(o.message_body)='ef69452615b1d07c5c2dc9e7671a9dcf' and o.draft_status='pending_review' and o.send_status='Draft';
  update public.outreach_log set message_body=$b$Guten Tag Frau Kaltenecker,

Ich habe mir Galaxus' Absicherungsangebot für Elektronikgeräte angeschaut. Auffällig: Diebstahl und Verlust sind ausgeschlossen, und die Deckung lässt sich nur einmalig beim Kauf abschließen, wer diesen Moment verpasst, ist dauerhaft außen vor.

Wir bei Pier haben ein Modell entwickelt, bei dem der Schutz nach dem Kauf aktiviert wird, monatlich statt einmalig läuft und dadurch bei vergleichbaren Partnern die Attachment-Rate und den Versicherungsumsatz um das 4-5-fache steigert, bei vollem Betrieb durch uns.

Wäre es interessant, einmal zu vergleichen, wie sich das auf Ihr Sortiment übertragen ließe?

Oliver$b$ where id='fb299f5e-2472-4049-b902-cd4c8af5f5b7' and md5(message_body)='ef69452615b1d07c5c2dc9e7671a9dcf' and draft_status='pending_review' and send_status='Draft';
  get diagnostics k = row_count; n := n + k;
  raise notice 'umlaut repair rows updated: %', n;
  if n <> 10 then raise exception 'expected 10 rows, updated %', n; end if;
end $$;
