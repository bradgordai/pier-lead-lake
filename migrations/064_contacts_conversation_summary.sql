-- 064: F6.7 conversation notes. One text field, two sections separated by a marker line:
--   user-written bullets (top, never touched by automation)
--   --- AI state of play (auto-maintained, edit above this line) ---
--   AI-written bullets (refreshed by generate-draft-from-context and capture-and-classify-reply)
alter table public.contacts add column if not exists conversation_summary text;
comment on column public.contacts.conversation_summary is
  'F6.7 conversation notes. User bullets above the marker line "--- AI state of play (auto-maintained, edit above this line) ---", AI bullets below it. Automation only ever rewrites the section below the marker.';
