-- 138 F22B.2: unblock the 100-lead Sales Nav import.
-- (a) connection_level gains 'Out of network' (network DISTANCE). upsert-contact-from-sales-nav v25 maps
--     "Out-of-Network" / "out of network" onto it. It is independent of invitation state: nothing reasons from
--     it to connection_status or back (F22B.2(d)).
-- (g) Guard: a status value can never be written into connection_level again. 'Not connected' is an INVITATION
--     STATE (contacts.connection_status) that also exists, wrongly, as a connection_level enum label; P664 Fiona
--     Vanderbroeck carries it today. New writes of it are refused; the existing row is REPORTED, not fixed.
--     The rest of fn_contacts_degree_guard is unchanged, verbatim.
alter type public.connection_level add value if not exists 'Out of network';

create or replace function public.fn_contacts_degree_guard() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $function$
begin
  if new.connection_level::text = 'Not connected'
     and (tg_op = 'INSERT' or new.connection_level is distinct from old.connection_level) then
    raise exception 'connection_level holds network distance (1st/2nd/3rd degree, Out of network). "Not connected" is an invitation state and belongs in connection_status (contact %).',
      coalesce(new.contact_id, new.id::text) using errcode = 'check_violation';
  end if;
  if new.connection_status::text in ('Accepted','Already connected') and new.connection_level is null then
    new.connection_level := '1st degree';
  end if;
  if new.connection_status::text = 'Request sent' and new.connection_level is null
     and (tg_op = 'INSERT' or new.connection_status is distinct from old.connection_status or new.connection_level is distinct from old.connection_level) then
    raise exception 'connection_level is required when connection_status is Request sent (contact %). Source the degree from Sales Nav before recording the request.', coalesce(new.contact_id, new.id::text) using errcode = 'check_violation';
  end if;
  return new;
end $function$;
