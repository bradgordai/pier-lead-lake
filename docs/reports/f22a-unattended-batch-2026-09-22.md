# F22A unattended batch — 2026-09-22 (evening, Brad travelling)

Evidence type is stated on every item. "Done" is never used without it. Nothing was sent, approved or dispatched by this
session. TWO REAL SENDS HAPPENED WHILE THIS SESSION RAN, BOTH BY OLIVER (see section 0).

## 0. Read first — Oliver was live in the app during the batch

- **P676 Torsten Schimkowiak (Medimax) — the F22A.1(b) proof draft was SENT by Oliver.** This session created one real
  cold InMail draft (outreach_log 538c5870) as the AFTER proof, as the brief asked ("regenerate ONE cold InMail draft").
  audit_log: Oliver (oliver.muller@pierinsurance.com) edited it 20:23-20:24 UTC, approved 20:26:12, pressed Send; queued
  (Ready 20:26:14), launched 20:34, **Sent 20:35:11 UTC**, phantom 8074821230707320, subject
  "Pier Insurance x Medimax - Partnership". His edited body, not the proof body, is what went out.
- **P581 Deiminger — the reply draft this session created (686f17cf) was approved and sent by Oliver** at 20:21-20:22;
  the drainer launched it at 20:30; PhantomBuster SKIPPED it ("already messaged recently, or empty input"); row is
  approved / Cancelled. Nothing reached Deiminger.
- Neither send was triggered by this session. Both followed from drafts this session was instructed to create.

(sections below are filled task by task)

## 1. F22A.1 The drafter — generate-draft-from-context v42 -> v43
EVIDENCE: live v42 source diffed against the repo before any change (identical bar the F20 research block);
v43 deployed (ezbr 2d171585...), deployed files byte-compared with the repo by script (index.ts 65,101 bytes +
3 shared files IDENTICAL); commit b04c0c8. The permission system did NOT refuse this deploy (F22A.9(j)).
All four faults were confirmed in the file before changing: MARKET_LANGUAGE at :140/:165, layer-4 ternary :583-584,
subject_line null :757 + "no subject line" :661, ensureSignOff :171 called at :730.
(a) Country map DELETED. Order now: the contact's own replies -> Language field -> English. Anything resolved that is
    not EN/DE is written in EN and the reason says so. **350 of 885 contacts have no Language field** (EN 286, DE 196,
    FR 34, IT 8, Other 7, NL 4); all 350 now get English unless they replied in German.
(b) voice_oliver loads on EVERY touch type; label names the touch ("Initial message via LinkedIn inMail"); own cache
    breakpoint kept. BEFORE / AFTER below (section 1b).
(c) InMail subject "Pier Insurance x {company} - Partnership" written at draft time into subject_line (InMail only;
    no company -> null -> send fallback kept). **122 sent InMails have subject_line NULL** (they went with the
    "Pier Insurance" fallback unless typed in PhantomBuster); 104 carry a typed subject.
(d) InMail: model told to end on a closing line with NO name; any trailing bare name stripped; DMs/CRs/email keep
    ensureSignOff. The scraped InMails today show the fault live: "...Viele Grüße\n\n\nOliver" twice-signed.
(e) Umlauts. NO code path transliterates: stripHtml only unescapes HTML entities; the phantom payload passes
    messageText verbatim; voice_assets have 0 transliterations and pier_rules/pier_terminology already state the rule.
    SOURCE FOUND: 8 of the 10 live transliterated drafts are Galaxus contacts whose company/contact notes are written
    without umlauts; the model copied them. The other 2 are F15.3 routing-repair drafts (one, Keller, had umlauts
    DELETED: "uber", "Handlern"). Explicit rule added to the prompt for DE; lint flag `german_transliteration` (-20).
    **10 live drafts repaired, not 9** (migration 131, md5-guarded, audit in migration_audit): P793 Benjamin Freuler,
    P698 Michael Stolle, P794 Luisa Arnold, P701 Sabrina Arndt, P783 Rotsch Dill, P796 Thomas Fugmann, P699 Florian
    Teuteberg, P702 Julia Kaltenecker (all Galaxus), P055 Alexander Klinger, P056 Janette Keller (MediaMarkt Saturn).
    Swiss targets keep ss for ß (pier_rules German rule 9). Sent history untouched: 43 sent non-agent rows are
    transliterated (Oliver's own typing/migrated) and stay as sent. Chrome render of Keller confirms the repair.
    FLAG (not fixed): P701 Arndt's draft ends "Oliver\n\nOliver" (model double name, pre-v43).

### 1b. BEFORE and AFTER — P676 Torsten Schimkowiak, Medimax, cold InMail, German
BEFORE (v42, dry run, no row written). voice_stack_versions: pier_rules v2.0 (24 Jul 2026) + sign-off rule 18 Sep 2026;
pier_terminology v10.11 (3 Sep 2026); linkedin_architect v1.7 (24 Jul 2026). layer4 null. subject null. Cost £0.129599
(cold cache, 60,519 written).

> Guten Tag Herr Schimkowiak, ich bin auf ElectronicPartner Nederland und Ihre Rolle im Vertrieb gestossen. Bei Medimax in Deutschland faellt uns auf, dass Geraete wie das Galaxy A57 ohne Schutzprodukt an der Produktseite verkauft werden, obwohl Domestic & General und WERTGARANTIE im Haus vertreten sind. Wir bei Pier bauen eingebettete Geraeteversicherung fuer Haendler auf, die als zusaetzliche Einnahmequelle laeuft, ohne operativen Aufwand auf Haendlerseite. Deckt Ihr Bereich auch die deutsche Medimax-Organisation ab, oder liegt der Fokus rein auf den Niederlanden?
>
> Oliver

AFTER (v43, real draft 538c5870). voice_stack_versions: the three above + voice_oliver "olivers-voice canonical, pack
copy of 9 Sep 2026"; layer4 "Initial message via LinkedIn inMail"; subject "Pier Insurance x Medimax - Partnership";
no name appended; lint 100. Cost £0.161512 (cold cache, 76,158 written).

> Hallo Herr Schimkowiak,
>
> MEDIMAX führt bei einigen Geräten keine Versicherung im Checkout, etwa beim Samsung Galaxy A57 für 349 Euro. Das dürfte einiges an Zusatzumsatz liegen lassen, gerade bei den Einstiegsgeräten.
>
> Wir bei Pier bauen Geräteversicherung für Händler wie MEDIMAX ein, ohne Aufwand auf eurer Seite. Unsere Partner erzielen damit typischerweise ein Vielfaches der Abschlussquote klassischer Versicherungsangebote, als zusätzliche, wiederkehrende Einnahme.
>
> Fällt die Entscheidung darüber bei Ihnen, oder liegt das eher bei ElectronicPartner zentral? Würde gerne kurz verstehen, wo das Thema bei Ihnen aufgehängt ist.
>
> Viele Grüße

FLAG for Brad: AFTER mixes registers ("eurer Seite" is du; "Ihnen" is Sie). Oliver rewrote it before sending (section 0).

### 1c. Cost per draft (api_call_log)
Before (v42, 7 days): Initial message avg £0.0475 (41 calls), Chaser 1 £0.0797, Chaser 3 £0.0381, Follow up £0.0550;
the only layer-4 path (first message after CR) £0.1627 cold.
After (v43, measured tonight): cold cache £0.1615 (76k written) — warm cache £0.0242 (20:10 call, 76,158 read)
— partially warm £0.0528 (60,519 read + 15,639 written). So voice_oliver adds ~15.6k cached tokens (not ~40k: the
asset is 40,361 CHARACTERS), about +£0.003 per warm call and +£0.03 on a cold one. The 06:15 engine run will be the
first real average; re-measure tomorrow.

## 2. F22A.2 The reply pipeline — capture-and-classify-reply v25 -> v26
EVIDENCE: live v25 diffed with the repo first (identical except an equivalent regex escape); v26 deployed
(ezbr 9b1e6c34...), byte-compared by script: identical except line 132, where the deploy transport renders the
̀-ͯ regex escape as literal combining characters (same quirk as v25, equivalent). Commit 3c45c7b.
Migration 132 (schema_migrations 20260922201224), commit 124ec2d.

(b) WHY DEIMINGER DID NOT LAND. Traced end to end:
  1. Phantom 7307653238072765 DID capture it (container 3030490462696064 at 15:46 and 650785751803234 at 19:45):
     lastMessageType "INMAIL_ACCEPT", lastName truncated to "D.", profileUrl /sales/people/ACwAACEVSUcB-...,NAME_SEARCH,02Ia,
     timestamp ISO (NOT unix seconds as the brief said).
  2. 14:55 and 15:46: the payload went through Make scenario 9704543 (the LINKEDIN inbox watcher, hook bx735...)
     and reached the function. **The function read it with LinkedIn-inbox field names** (message, firstnameFrom,
     lastMessageFromUrl): body empty -> "(no text)", no sender, no URN. It was queued unmatched at 15:46:34. FAILURE
     POINT 1 = capture-and-classify-reply's parser.
  3. 16:37 Brad built "Pier Inbox Watcher (copy)" 9850348 with the right mapping, listening on hook bz7reab...
     The phantom's webhook is set to .../pvfyton1djs2sgrt4l9gjm5nsnslyh6m, which is NEITHER active Pier hook
     (hooks_get: 4389339 = bz7reab..., 4332353 = bx735...). The 19:45 run produced **zero executions** anywhere.
     FAILURE POINT 2 = PhantomBuster webhook points at a hook no scenario owns. **BRAD: set phantom
     7307653238072765's webhook to https://hook.eu2.make.com/bz7reab1u22b8p5s0v1hprhqotx7il95** (not done here:
     phantom config is Brad's). CLAUDE.md section 12 has the wrong hook for this scraper.
  4. FIX + RECOVERY: v26 reads both shapes; replay of container 650785751803234 filed his reply (touch f7a3c0bc,
     channel LinkedIn inMail, classified "Wrong person") and drafted the reply below. 20 junk "(no text)" queue rows
     from 14:55/15:46 dismissed (audit phase f22a_2b_junk_queue).
  SECURITY FLAG: the Make scenario 9850348 HTTP module carries a literal bearer in its header (not quoted here).
(a) Normalisation table (one internal Payload):
  | internal | Sales Nav inbox | LinkedIn inbox |
  |---|---|---|
  | message | lastMessageBody | message |
  | sender name | participants[0].firstName/lastName ("D." dropped) | firstnameFrom/lastnameFrom |
  | counterparty url | participants[0].profileUrl (for both directions) | lastMessageFromUrl (inbound only) |
  | urn | ACwAA token from profileUrl | ACwAA token if present (LinkedIn inbox gives ACoAA ids: different family) |
  | direction | isLastMessageFromMe | isLastMessageFromMe |
  | channel | lastMessageType: *INMAIL* -> inMail, MESSAGE -> DM | same rule; /sales/inbox/ url -> inMail |
  | date | lastMessageDate ISO, else timestamp (ISO / unix s / unix ms) | lastMessageDate |
  | degree | participants[0].degree NUMBER, 1..3 only | none |
  | totalMessageCount | totalMessageCount | none |
(c) URN rule: contacts.linkedin_urn (indexed, trigger-maintained, backfilled). **626 of 885 contacts resolve by URN**
    (542 distinct tokens: 84 contacts share a token with a duplicate row -> queued with both as candidates, preferring a
    non "-dup" ref). Old rule: a Sales Nav payload resolved by identifier for ~0 (exact alias match on a URL whose
    NAME_SEARCH suffix changes per search; no slug in the payload). 764 resolve by URN or public slug; 121 by neither.
    Note: 674 contacts have a public /in/ URL, not 322 as measured by Cowork (it likely counted linkedin_slug).
(d) Direction from isLastMessageFromMe only. **6 mislabelled rows relabelled Reply -> Follow up (not 5 names):**
    P045 Plater, P044 Brunner (1 of his 4 Reply rows; the other 3 are his words or summaries of them), P190 Torsting,
    P076 Jensen, P136 Hargreaves, **P075 Suvi Ruoppa** (missing from the brief). Nothing deleted; before/after in
    migration_audit phase f22a_2d_reply_direction. chase_state NOT touched: Plater/Brunner/Torsting are still
    "replied" and each has other genuine Reply rows, so the state is supported.
(e) channel from lastMessageType; degree writes connection_level only (0/null/>3 ignored); never connection_status.
(f) DEDUPE PROVEN: key = direction + day + whitespace-folded text (thread-independent), legacy key still honoured.
    Replay #1: 20 processed, 1 matched, 1 own filed, 5 queued, 13 duplicates. Replay #2 of the same container:
    **20/20 duplicates, 0 new rows**. Cross-scraper probe (the same Deiminger message in LinkedIn-inbox shape, another
    thread url) -> **"duplicate", touch_id f7a3c0bc** (the existing row). Probe thread row deleted.
(g) linkedin_threads stores total_message_count vs held_count; incomplete is a generated column; the contact page now
    shows the flag (Lovable L2). Back-scrape scope, NOT built: a separate "thread fetcher" phantom (LinkedIn Message
    Thread Scraper / Sales Navigator thread export) launched only for incomplete=true threads, one per run, same
    one-at-a-time lock as intake-refresh, output into capture-and-classify-reply (idempotent via the v2 key).
(h) Inbound never seen: **2** open (Brian Egan 15 Sep; one unnamed 20 Sep) + Deiminger now filed. Both scrapers only
    return the 20 newest threads, so anything older is invisible to both.
    DEIMINGER REPLY DRAFT (686f17cf, v43, InMail, subject "Pier Insurance x Greenpanda.de (GSD Remarketing GmbH) -
    Partnership" — the company name makes an ugly subject; edit before any send):

> Hallo Herr Deiminger,
>
> danke für die Rückmeldung und alles Gute für Ihren weiteren Weg.
>
> Könnten Sie mir sagen, wer bei Greenpanda aktuell für das Thema Kundenbindung bzw. Zusatzleistungen im Shop zuständig ist? Dann wende ich mich direkt an die richtige Person.
>
> Viele Grüße

    Read: correct for "I no longer work for GSD" (GSD = Greenpanda's legal entity). Oliver approved and pressed Send
    at 20:21; PhantomBuster skipped it. FLAG: his contact is now "In conversation" (F15.8 rule) though he has LEFT
    the company; outreach_status "Left company" is Oliver's call, not changed here.

## 3. F22A.3 Sales Nav Watcher — SKIPPED (THE ONE STOP)
EVIDENCE: result object of the watcher's latest container 755735876989557 (66 rows).
**hasPendingInvitation is ABSENT from every row.** Keys present: associatedAccountName, associatedAccountUrl,
companyName, companyUrl, dateAdded, defaultProfileUrl, degree, firstName, fullName, imgUrl, lastName,
linkedInProfileUrl, location, name, note, outreachActivity, outreachDate, profileUrl, query, regularCompanyUrl,
searchAccountProfileId, searchAccountProfileName, timestamp, title, vmid.
Candidate for Brad: **outreachActivity** = SEND_INVITATION (25), ACCEPT_INVITATION (3), SEND_MESSAGE (3), blank (35).
degree = 2nd 38, 3rd 23, 1st 4, "Out of Network" 1.
Nothing deployed; upsert-contact-from-sales-nav stays v24, so **"Out of Network" still returns 422. Brad should
NOT rerun the 100 until (a) is fixed.** Root cause confirmed: v24's degree regex accepts only 1st/2nd/3rd.
**CLAUDE.md section 8 is wrong: contacts.connection_level is an ENUM (1st degree | 2nd degree | 3rd degree |
Not connected), not free text. It has no "Out of network" value**, so (a) needs `ALTER TYPE connection_level ADD
VALUE 'Out of network'` as well as the regex. "Not connected" is a legal enum value, so P664 is a semantic error,
not a type corruption; the guard must reject it at write time.
(c) CRs a rerun would log under the CURRENT code: all 66 already exist (matched by URN), and CRs log only on
    insert -> **0 for these 66**. For genuinely new leads v24 logs a CR for EVERY non-1st lead regardless of
    invitation state (the 100-manufactured-rows risk is real for new leads). Using outreachActivity=SEND_INVITATION
    would log 25 of 66.
(d) 25 of the 66 contradict stored connection_status (SEND_INVITATION in Sales Nav, "Not connected"/"Withdrawn" in the
    Lake): P840 Anna Hoetzeneder, P859 Sophia Wilkening, P007 Konstantinos Stamatopoulos (Withdrawn), P042 Christine
    Böhmer (Withdrawn), P837 Marcus Willbold, P849 Doris Karl, P842 Erik Heinrich, P843 David Pojer-Glück, P848 Petra
    Seisenberger, P835 Michele Santo, P839 Maximilian Ziegler, P836 Marcel Tully, P838 Aron Murati, P864 Julian
    Prause, P846 Tim Vogtländer, P867 Serdar Budak, P844 Martin Döring, P850 Patrick Tschischka, P863 Harald Gutschi,
    P831 Florian Birke, P868 Marina Prähauser, P879 Nico Hörnlein, P866 Robin Prause, P841 Sebastian Deichsel,
    P872 Sabine Ott.
(e) OLIVER'S SALES NAVIGATOR CHECK LIST — all 23 confirmed as stated (read-only, nothing changed):
    Accepted but 2nd/3rd: P037 Elena Panova (A1 Telekom Austria, 2nd), P671 Marco Stiemert (coolblue, 2nd), P787
    Ivana Petrovic (Digitec Galaxus, 3rd), P773 Bianca Pfaller (Drei Austria, 2nd), P778 Robert Karl (Drei Austria,
    2nd), P146 Anne-Catherine Péchinot (EasyCash, 3rd), P012 Adam Ferguson (HMD, 2nd), P673 Christiaan de Groot
    (iUsed, 2nd), P022 Adrian Turrin (Lenovo, 3rd), P058 Miryam Verbeek-Teres (MediaMarkt Saturn, 2nd), P880 Natascha
    Wyss (re/commerce, 2nd), P772 Philipp Lohmar (Tchibo, 2nd), P786 Steffen Woerner (Telefónica, 2nd), P791 Milena
    Joksimovic (Telefónica, 3rd), P785 Erdinc Kanal (Telefónica, 2nd), P231 Violeta Luca (Vodafone CZ, 2nd), P860 Julia
    Koellges (Vodafone DE, 2nd — Oliver DM'd her successfully 21 Sep, so "Accepted" is right and the degree is stale),
    P857 Matthias Lorenz (Vodafone DE, 2nd).
    Withdrawn but 1st: P283 Yasin Cakiroglu, P282 Marjorie Bonfils, P279 Oriol Chimenos, P278 Leonardo Ramirez Peña.
    Level holds a status: P664 Fiona Vanderbroeck (bol.com) connection_level "Not connected", status "Request sent".
(f) NOT deployed. Brad may NOT rerun 100 yet.
Also: Make scenario 9589633 "Pier Sales Nav Watcher" was switched OFF at 20:06 UTC (last edit), presumably by Brad.

## 4. F22A.4 Feedback capture (stage one only)
EVIDENCE: migration 133 (schema_migrations row, commit 5948147); rolled-back proof insert showed the trigger filling
contact/touch_type/channel/language/body and the check constraint refusing a regenerate with no reason; Lovable
commit 1a0e8c2 (logDraftFeedbackFn + required 8-reason picker + note + "Use for training" default ON on Reject
(single and bulk), Regenerate (dialog before regenerating, DraftEditor and contact page) and AI edit (before/after
captured)); code read in the diff; build clean; published (#1). Nothing reads draft_feedback; the drafter is not wired
(Prompt B). NOT verified in Chrome: opening the Regenerate dialog on a live draft would, on stale code, regenerate for
real, so the dialogs were verified in code only.

## 5. F22A.5 Guidance notes
EVIDENCE: migration 134 (commit 13f22f8); drafter v43 reads contact_guidance_notes into its own block and states that a
note never overrides a consent gate (the gates run before the note is read). Proof: a labelled test note on P676
("lead with the free first month") -> dry-run draft contained "dass der erste Monat kostenlos inklusive ist";
api_call_log request_context.guidance_notes = true; input tokens 3,145 -> 3,654; test note deleted. Lovable 9b4c139:
GuidanceNotes panel on the contact page and the draft editor (draft and sent views), all notes newest first, author +
London timestamp + "edited", edit/delete only on your own notes (RLS also enforces it). Chrome: "Guidance for next
drafts" and "Add note" render on the P676 page. Published (#2).

## 6. F22A.6 The spinning Send button
MECHANISM (reported before fixing): the button spun on `send.pending || touch.send_status === "Scheduled"`. (1) Queued
sends: useSendDraft polled with NO give-up, so pending stayed true for the whole queue wait; position appeared once in
a toast. (2) Direct sends: the hook gave up after 4 min, but the button also spun on the CACHED detail row "Scheduled";
if Sent landed after the hook stopped (5 of 33 sends in 2 days took > 4 min end to end) nothing refreshed that query
because realtime runs through the browser client, which is likely unauthenticated under RLS -> "spins until refresh".
The server function and send-approved-draft return promptly (median launch -> finish 69 s, max 163 s).
FIX (Lovable a852d01, published #3): state read from the row every 5 s with no give-up; disabled at click; "Queued,
position N, sends about HH:MM" (no spinner) from send_queue; "Sending via LinkedIn..." only while Scheduled; Sent ->
read-only; Cancelled -> "Not sent: <reason>" and Send only if still approved. Chrome: Deiminger's draft shows
"Not sent: phantom_skipped_duplicate_or_empty" with Send available (not clicked). NOT verified with a real send (no
sends from this session).

## 7. F22A.7 Outreach categories
(a) NOTHING LOST. 0 outreach_log rows deleted since 21 Sep (audit_log). Of the drafts pending on 21 Sep 20:00: cold
InMail 39 -> 29 still pending, 7 sent, 2 superseded, 1 rejected; InMail chasers 9 -> 6 sent, 1 approved/cancelled, 1
rejected, 1 superseded (0 pending, so the category vanished); DM chasers 12 -> 10 pending, 2 sent; first message 1;
replies 1 rejected. Brad's 44/9/16 reconciles as cold InMail ~44 incl. that night's engine drafts, InMail chasers 9,
and 16 first DMs after CR which Oliver has since APPROVED (16 approved DM Initial messages, created 26 Aug - 15 Sep,
approved by oliver.muller) so they left Pending Review. Live now: cold InMail 32, InMail chaser 0, DM chasers 14,
first DM 0 pending (16 approved), replies 0 pending.
(b)-(d): see Lovable L4 below.

## Cross-logic
(A) CONSENT LAYER UNTOUCHED. 1,770 evaluations before, 1,772 after (one new contact), channel LinkedIn DM, both
    request types. promise_of_quiet 17=17, dnc_or_opted_out 67=67, contact_parked 69=69, pending_ruling 41=41
    (x2 request types); allowance_exhausted 2=2. Changed: P581 Deiminger chaser PASS->contact_replied (reply filed by
    this batch); P538 Friedrich thread_text_missing->PASS and P562 Mian contact_replied->PASS (Oliver sent Follow ups
    at 20:41, live); P949 Wehner group_sibling_engaged->PASS x2 (live data, CR 20:04). fn_evaluate_gates not edited.
    Recorded in migration_audit phase f22a_consent_proof.
(B) PRIORITY: no function reading priority was edited (drafter only passes it through unchanged).
(C) Cost: section 1c.
(D) Weekly CRs 71; CR rows created during the batch 0; accepted/already connected 171. F22A.3 wrote nothing.
    Migration 136 changed draft_status only; the CR count reads send_status.
