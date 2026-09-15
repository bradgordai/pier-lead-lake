-- 104 F16.3 (2026-09-15): team_settings.reply_ignores_research_gate boolean NOT NULL DEFAULT false (a column, the
-- settings row is one wide row). fn_evaluate_gates: the research gate applies to initial_message, chaser and reply,
-- EXCEPT a reply when the flag is true. Every other gate (promise_of_quiet, dnc_or_opted_out, contact_parked,
-- pending_ruling, group_sibling_engaged, thread_text_missing) still applies to replies, flag or no flag.
-- Applied via apply_migration with the full fn_evaluate_gates body (unchanged apart from v_research_applies).
alter table public.team_settings add column if not exists reply_ignores_research_gate boolean not null default false;
