# F13 (2026-09-10): send-state integrity and the Today activity log

Migrations 083-088, one per task, each its own commit. send-approved-callback v13, chase-engine v6.
Nothing sent, no phantom launched, no button clicked; Chrome was read-only (navigate, screenshot,
read the page). Every repair is in migration_audit under the run ids named below.

## The one new moving part
`fn_apply_send_effects(outreach_log_id, source)` (security definer, service_role only) is the ONE
place the consequences of a real send are written. send-approved-callback v13 calls it right after
it marks a row Sent, and every F13 repair went through it or was written next to it in the
migration. Its effects, in order:
1. touch_date := the London date of sent_at_actual (F13.1).
2. contact: cooldown_until := null; chase_state := awaiting_reply, or chaser_1_sent /
   chaser_2_sent when the sent row is a chaser; chaser_count := count of SENT chasers;
   chase_last_outbound_at := send date; chase_next_due_at := send date + team_settings interval
   (7); last_contacted := max(existing, send date) (F13.2).
3. contact.outreach_status := Contacted, only from Not started / To contact / Ready. In
   conversation, Meeting booked, Cooldown, Parked and every consent status are never touched (F13.3).
Every change is written to audit_log (action send_effects, source names the caller).

## F13.1 touch_date at send time (083, run f13-1-touch-date-2026-09-10)
Broken: the callback wrote sent_at_actual and froze sent_body but never touched touch_date, so
every date the app shows and the chase clock read the draft's date. Fixed as above.
Repaired 2 rows, the only two this system has ever dispatched (phantom_run_id set):
- Philipp Fischer T295, InMail, touch_date 2026-07-29 -> 2026-09-09
- Urs Moeller agent-cb820444, DM, touch_date 2026-09-02 -> 2026-09-10
Migrated legacy rows never dispatched here were not touched (their sent_at_actual is the
workbook date at midnight, which already equals touch_date).
Evidence: drift query 0 (London and UTC). Dry run before and after: 113 due, identical names;
neither Fischer nor Moeller due. Note on warning (a): Fischer was never due even on the old
clock. His route is cr_not_accepted, whose clock is the last SENT connection request, and he
has none (his CR was withdrawn), so last_outbound was null. His cooldown was not the only
guard. Moeller was blocked by the cooldown alone; with touch_date 2026-09-10 he is 0 days.

## F13.2 the three cooldowns (084, run f13-2-cooldown-artefacts-2026-09-10)
cr_blocked_until kept, gate untouched. Chase rest (exhausted + cooldown_until) kept.
Artefact rule: chase_state 'cooldown' with zero sent chasers and the migration stamp date
(2027-02-25 or 2027-03-01) is a cooldown nobody earned.
Repaired 9: Urs Moeller and Philipp Fischer through the send effects (awaiting_reply, next due
2026-09-17 and 2026-09-16); Kristjan Nemvalts, Tom Jonkman, Rogier Schuurmans, Oscar Hundman,
Maite Zubiaurre -> chase_state none; Benjamin Koehler and Gerdien van Vuurde -> replied (their
last event is a reply). All nine cooldown_until -> null.
Baseline drift: the pack's "9 messaged in the last 30 days in cooldown" counted Lutz
Schottenhammer and not Philipp Fischer (his last_contacted was still 2026-07-24, another symptom
of F13.1). Lutz is a legitimate rest and was left alone, Fischer was repaired, so the repaired
set is nine either way.
The 14 accepted contacts in cooldown (chase_state not none), classified:
- Migration artefact, cleared: Urs Moeller, Kristjan Nemvalts, Gerdien van Vuurde (3).
- Legitimate, left alone (11): Lutz Schottenhammer (operator Cooldown, chaser sent, reply
  2026-08-14, 2027-08-16); Robert Pauly (2 chasers, 2026-11-01); Martin Schwager (In
  conversation, 2026-10-26); Morten Jensen, Krisztina Polgar-Podonyi, Michal Ptasinski x2,
  Hendrik Verdirk, Antonio Capaldo (all status Cooldown, set by hand); Matteo Ferraris (Active,
  last send May, 2027-02-25); Sheila Ibanez (Contacted, CR only, 2027-02-25). The last two carry
  the migration stamp date but were not messaged in 30 days; they stay until Oli rules.
- Not counted (chase_state none, status Not relevant): Josephine Omaku, Frank Bahnmueller,
  Tobias Negwer.
Evidence: dry run after: 113 due, no new name. None of the nine became due: the Withdrawn ones
have no sent CR row (route clock null), Nemvalts has a pending draft, van Vuurde and Koehler
are 'replied', Moeller and Fischer are days 0 and 1.

## F13.3 a send moves the contact to Contacted (085, run f13-3-contacted-2026-09-10)
Repaired 9: Urs Moeller, Massimo Mucciolella, Mario Opua, Leonard Coen, Marco Stiemert,
Christian Timothy v. Banhans, Hermann-Wilhelm Wantia, Stefano Petrillo (Not started ->
Contacted) and Jean-Emile Rosenblum (To contact -> Contacted). All have a sent message that is
not a connection request; the other 47 "To contact with a Sent row" in my first query only have
a sent CR, which is not a message, and were left alone. Evidence: remaining count 0.

## F13.4 chase_state never claims a send (086, run f13-4-chaser-drafted-2026-09-10)
New value chaser_drafted in the CHECK; chase-engine v6 writes it at draft time; chaser_N_sent is
written by fn_apply_send_effects when the chaser goes out. Repaired Elena Panova and Antonius
Fromme (chaser_1_sent -> chaser_drafted, each has one pending chaser draft). Evidence: count 0.

## F13.5 Today activity log (088 + Lovable)
View v_sent_touches: sent rows keyed on sent_on = London date of sent_at_actual, else
touch_date; security_invoker so RLS applies; owner_user_id exposed for scoping. The app's
todayActivityLogFn resolves scope through getTaskScope (fn_task_scope) like every other Today
widget; the three send tiles read their counts from the same rows. Toggle Today / This week,
remembered per user. Verified in Chrome on the published build (Lovable commit f1b69461): Cold DMs tile 1/15,
InMails 0/9 (Fischer went yesterday); panel Today = one row, Urs Moeller 12:40; This week + All =
two rows, Urs Moeller Thu 10 Sept 12:40 and Philipp Fischer Wed 9 Sept 13:57. Owner chip All /
Oliver / Jack scopes the panel through the same server fn.

## F13.6 the sends are visible
Touch popout: Fischer's conversation panel lists 24 Jul 2026 InMail then 9 Sep 2026 InMail Sent;
Moeller's lists 28 Aug 2026 CR then 10 Sep 2026 DM Sent. Contact popout Conversation tab: the
same two bubbles each, dated 9 Sep and 10 Sep. Before F13.1 the Fischer send rendered as 29 Jul,
above the July message, which is why Brad could not find it.

## F13.7 the clock reads the truth (087)
fn_chase_candidates now takes coalesce(London date of sent_at_actual, touch_date) for
last_msg and last_cr. Due list unchanged (113, same names, same dates) because after F13.1 no
Sent row disagrees with its send date. Route semantics unchanged.

## Tomorrow's cron (job 5, 06:15 UTC, active, limit 25)
Dry run after all of F13 (dry_run writes nothing): 113 due, 25 considered, 0 would draft,
25 refused (23 thread_text_missing, 2 company_not_deep_researched). Over the whole backlog of
113: 5 would draft (3 DM chaser 3, 2 InMail chaser 1), 108 refused (85 thread_text_missing, 23
company_not_deep_researched). The 25 the cron actually considers are the P0/P1 oldest and all
refuse, so Oliver should expect 0 new chaser drafts and 25 refusal rows tomorrow. F13.2 added
nobody to that list.

## Flagged, not fixed
- Touch popout on a SENT row still renders the draft editor with Approve / Send now (disabled)
  and "On send: logged as message 2 of 3", the "why this now" reads "LEGACY draft ... never sent"
  and Touch history omits the sent row itself. Cosmetic but misleading on the two real sends.
- cr_not_accepted route clocks from the last SENT connection request only. A contact with no
  Sent CR row (CR withdrawn before the migration, e.g. Fischer) is never due, and a later InMail
  does not move that clock. Withdrawn contacts messaged by InMail on 2026-08-27 (Jonkman,
  Schuurmans, Hundman, Zubiaurre) are likewise invisible to the chase.
- Fischer's dispatched row is touch_type 'Chase' on a migrated legacy draft, so it does not count
  toward the InMail chaser cap (which counts 'Chaser %'). One more InMail chaser could be drafted
  for him once his clock allows, which would be his second.
- chase_next_due_at is written by the engine and the send effects but fn_chase_candidates does
  not read it; the interval is recomputed from the rows. Harmless today, two clocks tomorrow.
- last_contacted is not maintained by the callback path before F13; the send effects now set it.
- Baseline: the pack's "9 in cooldown" and "14 accepted in cooldown" match only under the
  definitions above (chase_state = 'cooldown', last_contacted); a definition on outreach rows
  gives different numbers. The regression tests pin the definitions.
