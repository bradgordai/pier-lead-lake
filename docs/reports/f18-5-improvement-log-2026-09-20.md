# F18.5 (a)(b)(d)(e) - Improvement log moved into Supabase

Date: 2026-09-20. Project `qzfrcfzeiagziqjnfarw`. Nothing was sent, no Edge Function was called,
no table other than the three new ones was written. Not committed to git.

Source (authoritative): `nAIled IT/Pier Insurance/260920_lovable_improvement_log_export.json`
(109 items, 34 comments, exported 2026-09-20 from the shared artifact).

## 1. What landed

| Migration (file in `/migrations` = name in `supabase_migrations`) | Content |
|---|---|
| `118_f18_5_improvement_log_tables` | 3 tables, indexes, `updated_at` trigger, `fn_improvement_log_can_edit()`, grants, RLS |
| `118b_f18_5_improvement_log_import` | import part 1 of 12 |
| `118b_f18_5_improvement_log_import_p02` ... `_p11` | import parts 2-11 (items + their comments) |
| `118b_f18_5_improvement_log_import_p12_tail` | 2 legacy activity rows, the 3 links, activity triggers, final count gate |

Generator: `scripts/gen_improvement_log_import.py` (re-runnable, deterministic; rewrites the 118b files).

### Two deviations from the brief, both deliberate

1. **The import is 12 files under the reserved number 118b, not one file.** The only write path is
   the MCP `apply_migration` call, which takes the SQL as one argument; the import is ~390 KB and
   cannot be passed in one call. Every file carries the reserved `118b_f18_5_improvement_log_import`
   prefix, no other number was used, and file names sort in apply order. Each part was applied with
   its file's base name. Each part ends with a DO block that recomputes an md5 per item **inside
   Postgres** (all text fields, arrays, flags, timestamps re-rendered as the source ISO strings,
   `seen_by`, and every comment) and raises - rolling the part back - unless it equals the md5
   computed from the source JSON. All 11 data parts passed their gate and are recorded once each in the migration history.
   (Apply order in the history is p11, part 1, p03, p02, p04, p06, p05, p07-p10, tail: the data parts are
   independent of each other, only the tail had to be last, and it was.)
2. **`activity_log` is NOT empty in the export.** Two items carry one entry each:
   i001 `{who: Oliver, at: 2026-09-15T13:06:14.708Z, what: "reopened it"}` and
   i021 `{who: Oliver, at: 2026-09-09T11:55:16.754Z, what: "reopened it"}`.
   These are real history, so they were carried into `improvement_activity` verbatim
   (`action` = the export's `what`, `after` = the original object plus `imported_from`). Nothing
   else was invented; the import itself generated zero activity rows (triggers are created in the tail,
   after the data). Delete those two rows if you would rather start the tracker empty.

## 2. Table definitions (summary)

**`public.improvements`**
`id uuid pk`, `team_id uuid not null -> teams`, `item_key text not null` (the i-number exactly as
exported, e.g. `i094`; `unique (team_id, item_key)`; never renumber), `title`, `category`, `owner`,
`priority` (check: blocker/must/nice/question/parked), `status` (check: open/done, default open),
`raised_by`, `created_at timestamptz`, `build_wave int null`, `blocks text[]`, `blocked_by text[]`
(both hold item_keys), `done_by text null`, `done_at timestamptz null`, `pinned bool`, `hidden bool`,
`seen_by jsonb` (`{"Brad": "<iso>", "Oliver": "<iso>"}`), `detail text`, `notes text`,
`linked_company_id uuid null -> companies(id)`, `linked_contact_id uuid null -> contacts(id)`,
`updated_at timestamptz` (trigger `tg_improvements_updated_at` using the repo's standard
`tg_update_updated_at()`).

**`public.improvement_comments`**
`id uuid pk`, `team_id uuid not null`, `improvement_id uuid not null -> improvements on delete cascade`,
`who text`, `at timestamptz default now()`, `text text`.

**`public.improvement_activity`**
`id uuid pk`, `team_id uuid not null`, `improvement_id uuid null -> improvements on delete set null`,
`item_key text` (added so a 'delete' row still says which item it was), `who text default 'system'`,
`at timestamptz default now()`, `action text`, `before jsonb`, `after jsonb`.

**Activity triggers (live from now on)**
- `tg_improvements_activity` AFTER INSERT/UPDATE/DELETE on `improvements`. `action` = `insert` |
  `update` | `done` (status -> done) | `reopened` (status -> open) | `delete`. For updates `before`/`after`
  hold only the columns that changed. Changes to `seen_by` and `updated_at` alone are NOT logged
  (opening a card is not an edit).
- `tg_improvement_comments_activity` AFTER INSERT on `improvement_comments`, `action = 'comment'`.
- `who` = `fn_improvement_log_actor()` = the `auth.uid()` user's email from `auth.users`, else `'system'`.
  Both trigger functions are SECURITY DEFINER; users have no write grant on `improvement_activity`.

## 3. RLS design (e)

What I found: `team_members.role` exists, values in use are only `admin` (Brad) and `member`
(Oliver and Jack). The role therefore cannot separate Oliver (editor) from Jack (read-only), and
changing Jack's row in `team_members` was out of scope ("touch only the three tables").

What I chose: one SQL function, no fourth table -
`fn_improvement_log_can_edit(team_id)` = caller is a member of that team AND
(`role in ('admin','editor')` OR auth email is `oliver.muller@pierinsurance.com`).
If an `editor` role is introduced later, set Oliver to it and drop the email from the function;
policies do not change. Team scoping mirrors `refusals` / `company_alerts`
(`team_id in (select fn_user_teams())`).

| Who | improvements | improvement_comments | improvement_activity |
|---|---|---|---|
| bradleyg@naileditai.com (admin) | read, insert, update | read, insert, update, delete | read |
| oliver.muller@pierinsurance.com (member, in editor list) | read, insert, update | read, insert, update, delete | read |
| jack.stevens@pierinsurance.com (member) | read only | read only | read |
| any other authenticated team member | read only | read only | read |
| authenticated, not in the team | nothing | nothing | nothing |
| anon | nothing: no policy, `revoke all` | same | same |

Notes: there is deliberately **no DELETE policy or grant on `improvements`** (the log never deletes;
ticking sets status = done). Service role can still delete, and that is logged. `authenticated` had
its default blanket grants revoked and only the privileges above granted back. RLS is enabled on
all three tables (verified).

## 4. Verification (SQL after import vs expected)

| Figure | Expected | Source file | Database | |
|---|---|---|---|---|
| items | 109 | 109 | 109 | ok |
| comments | 34 | 34 | 34 | ok |
| priority must / blocker / nice / parked / question | 70 / 7 / 27 / 3 / 2 | same | 70 / 7 / 27 / 3 / 2 | ok |
| status open / done | 101 / 8 | same | 101 / 8 | ok |
| Lovable UI | 32 | 32 | 32 | ok |
| Data & schema | 28 | 28 | 28 | ok |
| Outreach & drafting | 22 | 22 | 22 | ok |
| Integrations | 11 | 11 | 11 | ok |
| Research agent | 7 | 7 | 7 | ok |
| Guards | 6 | 6 | 6 | ok |
| Voice | 3 | 3 | 3 | ok |
| owner Brad / Both / Oliver | 67 / 40 / 2 | same | 67 / 40 / 2 | ok |
| i999 | exists, hidden, art intact | - | hidden = true, detail 422 chars / 860 bytes, 98 block glyphs, md5 equal to source | ok |
| whole-log md5 (every field of every item + comment) | `48a6559ff9028dddbf9ce31cce286ed4` (python, from the JSON) | | `48a6559ff9028dddbf9ce31cce286ed4` (Postgres) | ok |
| improvement_activity rows | 0 per brief | 2 in the file | 2 (see deviation 2) | differs from brief, matches source |

Every figure reproduces. The only mismatch with the brief is the `activity_log` claim, and it is the
brief that differs from the source file, not the data.

## 5. Links (d)

Each lookup was asserted to resolve to exactly one contact inside the migration before updating.

| Item | Contact | contacts.contact_id |
|---|---|---|
| i094 | Florian Pfeiffer | P706 |
| i053 | Urs Moeller | P703 |
| i100 | Frank Pelzer | P858 (only contact with last_name = 'Pelzer') |

`linked_company_id` is null everywhere for now.

## 6. Lovable prompt for F18.5(c) - ready to paste

```
Do not pause for a plan. Implement this now.

Add a new top-level tab "Improvement Log" (same nav level as the other main tabs). It reads and writes three existing Supabase tables. Do NOT create or alter tables, policies or functions: they already exist and are populated (109 items, 34 comments).

TABLES (public schema, all team-scoped by team_id, RLS already on)
1. improvements: id uuid, team_id uuid, item_key text (human ID such as "i094"; unique per team; never renumber, never edit), title text, category text, owner text, priority text (one of blocker, must, nice, question, parked), status text (open or done), raised_by text, created_at timestamptz, build_wave int null, blocks text[] (item_keys this item unblocks), blocked_by text[] (item_keys it waits on), done_by text null, done_at timestamptz null, pinned bool, hidden bool, seen_by jsonb (object: display name -> ISO timestamp), detail text, notes text, linked_company_id uuid null (companies.id), linked_contact_id uuid null (contacts.id), updated_at timestamptz (set by a DB trigger, never write it).
2. improvement_comments: id uuid, team_id uuid, improvement_id uuid (fk improvements.id), who text, at timestamptz, text text.
3. improvement_activity: id uuid, team_id uuid, improvement_id uuid null, item_key text, who text, at timestamptz, action text (insert, update, done, reopened, delete, comment, plus two legacy rows "reopened it"), before jsonb, after jsonb. READ ONLY from the app: the database writes it via triggers on every insert/update/delete of improvements and every new comment. Never insert into it from the client.

PERMISSIONS
Brad and Oliver have full edit. Everyone else (Jack) is read-only. Decide this by calling the existing RPC once on load: supabase.rpc('fn_improvement_log_can_edit', { p_team_id: <current team id> }) -> boolean. If false, render the whole tab read-only: no checkboxes, no inline edits, no comment box, no "New item" button. RLS enforces the same on the server, so also surface a toast if a write is rejected. When writing, always send team_id = the current team id. The display name for who/done_by/seen_by is "Brad" for bradleyg@naileditai.com and "Oliver" for oliver.muller@pierinsurance.com (fallback: the part of the email before @).

LIST
- One card per item: item_key badge, title, priority chip, category, owner, build_wave if set, comment count, "unlocks: iNNN..." from blocks and "waiting on: iNNN..." from blocked_by (each key is a link that scrolls to and expands that item).
- Filters, combinable, each multi-select: priority, owner, category, status. Default status filter: open and done both shown, with done handled as below.
- Search box: matches item_key (typing "i094" or "94" finds it) and free text across title, detail, notes and comment text. Case-insensitive.
- "Expand all" / "Collapse all" buttons.
- Group by: None | Build order | Category | Owner | Priority. "Build order" groups by build_wave ascending (null wave last, labelled "No wave") and NESTS items: an item whose blocked_by contains key X is rendered indented under X (if X is present in the current filter result; otherwise top-level). Guard against cycles and render each item once, under its first blocker.
- Sort inside any group: pinned = true first, then priority order blocker, must, question, nice, parked, then item_key ascending.
- Done items: ticking the checkbox sets status = 'done', done_by = current display name, done_at = now(). The item moves to a collapsed "Done (n)" section at the BOTTOM of the list showing "done by X on <date>". Unticking sets status = 'open', done_by = null, done_at = null. NEVER delete a row; there is no delete button anywhere and the API will refuse deletes on improvements.
- Hidden: rows with hidden = true are excluded by default. Add a "Show hidden" toggle (off by default) that includes them, marked with a "hidden" chip. Keep item i999 exactly as it is: hidden, never deleted or edited by any cleanup, and render its detail in a monospace, whitespace-preserving block (white-space: pre) because it is ASCII art.
- Editors can toggle pinned and hidden from the card menu.

CARD (expanded)
- Opens on `detail` (render with preserved line breaks, white-space: pre-wrap). `notes` sits underneath inside a collapsed "Notes" disclosure, folded by default; hide the disclosure when notes is empty.
- Inline edit for editors: title, category, owner (Brad, Oliver, Both), priority, build_wave, blocks, blocked_by (pick from existing item_keys), detail, notes, pinned, hidden. item_key is read-only. Save with a single update on improvements per change.
- New item (editors only): item_key = next free number as "i" + 3 digits, zero padded, computed as max numeric key below 900 plus one (i900 and i999 are reserved specials; never reuse or renumber a key). raised_by = current display name.
- Link chips: if linked_contact_id is set, show a chip with the contact's first_name + last_name (from contacts) that opens that contact's record in the app; if linked_company_id is set, a chip with the company name that opens the company record. Editors get "Link contact" / "Link company" search pickers that write those two columns, and a remove (set null) action.
- Comments: list improvement_comments for the item ordered by `at` ascending (who, relative time, text with preserved line breaks). Editors get an add-comment box: insert { team_id, improvement_id, who: display name, text }; let `at` default.
- Seen: when a signed-in editor expands a card, merge { [display name]: new Date().toISOString() } into seen_by and update the row. Show a small "new for you" dot when the item's updated_at or newest comment is later than the viewer's seen_by entry. Skip this write for read-only users.

ACTIVITY TRACKER PANEL
- A right-hand (or bottom, on narrow screens) panel "Activity" reading improvement_activity ordered by `at` desc, 50 rows with "load more". Each row: who, relative time, item_key (click to open that card), and a human sentence built from action + before/after: e.g. "marked i042 done", "reopened i001", "changed priority must -> blocker on i017" (before/after only contain the changed columns), "commented on i100: <first 80 chars of after.text>", "created i108". Treat the legacy action "reopened it" like "reopened".
- Each expanded card also shows its own activity (filter by improvement_id).
- Subscribe with Supabase Realtime to improvements, improvement_comments and improvement_activity so two people see each other's changes without refresh; on any event, refetch the affected item.

Do not touch any other tab, table, Edge Function or automation.
```

Note for whoever pastes this: Realtime is only live if the three tables are added to the
`supabase_realtime` publication; that was NOT done here (out of scope). If Lovable reports no
events, run `alter publication supabase_realtime add table public.improvements,
public.improvement_comments, public.improvement_activity;` as a small follow-up migration.
