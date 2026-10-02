-- 163 F25 Task 8: wrong channel for the connection state. A FLAG, never a refusal (soft guardrails, 30 Sep).
-- Oliver saw InMails drafted to connected people and DMs drafted to unconnected people. Measured 2 Oct: all four
-- candidate functions test connection_status, fn_evaluate_gates does not; the exposure is stale connection data at
-- drafting time rather than missing logic.
-- WHY A VIEW AND NOT A ROW FROM fn_evaluate_gates (deviation from the brief, stated): fn_evaluate_gates has no warning
-- channel. Every row it returns is treated as a REFUSAL by every caller (generate-draft-from-context, chase-engine x4,
-- send-approved-draft re-runs it immediately before launch). A "warning" row there would refuse the draft and block the
-- send. So the invariant is a read-only flag, the same pattern as v_draft_company_flags (F23.2a): it refuses nothing,
-- writes no refusals row (refusals_reason_code_check is unchanged), and Oliver decides on the draft card.
--   LinkedIn DM     and connection_status NOT IN (Accepted, Already connected) -> flag
--   LinkedIn inMail and connection_status     IN (Accepted, Already connected) -> flag
-- fn_channel_connection_mismatch(channel, connection_status) holds the rule once; v_draft_channel_flags applies it to
-- every OPEN draft (send_status Draft/Ready, draft_status pending_review/approved).

create or replace function public.fn_channel_connection_mismatch(p_channel text, p_connection_status text, p_first_name text default null)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $$
  select case
    when p_channel = 'LinkedIn DM' and coalesce(p_connection_status, 'Not connected') not in ('Accepted','Already connected') then
      'Drafted as a DM but LinkedIn shows ' || case coalesce(p_connection_status, 'Not connected')
        when 'Request sent' then 'the connection request still pending'
        when 'Withdrawn'    then 'the connection request withdrawn'
        when 'Ignored'      then 'the connection request ignored'
        else 'no connection' end
      || '. A DM needs a 1st-degree connection; this will not send as a DM.'
    when p_channel = 'LinkedIn inMail' and p_connection_status in ('Accepted','Already connected') then
      'Drafted as an InMail but ' || coalesce(nullif(btrim(p_first_name), ''), 'this contact') ||
      ' is already connected (' || p_connection_status || '). A DM is free; an InMail spends a credit.'
  end;
$$;

create or replace view public.v_draft_channel_flags with (security_invoker = true) as
select o.id as outreach_log_id, o.team_id, o.contact_id, o.channel::text as channel, o.touch_type::text as touch_type,
       c.connection_status::text as connection_status,
       public.fn_channel_connection_mismatch(o.channel::text, c.connection_status::text, c.first_name) as flag_text
  from public.outreach_log o join public.contacts c on c.id = o.contact_id
 where o.send_status::text in ('Draft','Ready') and o.draft_status::text in ('pending_review','approved')
   and public.fn_channel_connection_mismatch(o.channel::text, c.connection_status::text, c.first_name) is not null;
grant select on public.v_draft_channel_flags to authenticated;
