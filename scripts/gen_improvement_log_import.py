#!/usr/bin/env python3
"""F18.5(b)(d) - generate the improvement-log import migrations from the artifact export.

Source (authoritative): 260920_lovable_improvement_log_export.json (109 items, 34 comments).

Output, in /migrations (all under the reserved number 118b):
  118b_f18_5_improvement_log_import.sql            part 1 (items + their comments)
  118b_f18_5_improvement_log_import_p02.sql ...    further parts
  118b_f18_5_improvement_log_import_p<NN>_tail.sql legacy activity rows, links, activity
                                                   triggers, final count assertions

Why parts: the only write path to this database is the Supabase MCP apply_migration call,
which takes the SQL as one argument; ~300 KB of text does not fit in one call. File names sort
in apply order. Every part ends with a DO block that recomputes an md5 per item inside
Postgres and raises (rolling the part back) unless every field, timestamp and comment matches
the source byte for byte.

Text is dollar-quoted ($il$...$il$); the generator refuses to run if the tag occurs in the data.
The import writes NO improvement_activity rows of its own: the activity triggers are created
in the tail, after the data. The two activity_log entries that do exist in the export (i001,
i021: Oliver "reopened it") are carried over verbatim, nothing else is invented.
"""
import hashlib
import json
import sys
from pathlib import Path

SRC = Path("/Users/bradley/Documents/nAIled IT/Pier Insurance/260920_lovable_improvement_log_export.json")
OUT = Path(__file__).resolve().parent.parent / "migrations"
BASE = "118b_f18_5_improvement_log_import"
TAG = "$il$"
MAX_PART_BYTES = 38_000
US, RS = "\x1f", "\x1e"
TEAM = "(select id from public.teams limit 1)"
LINKS = [  # item_key, where-clause on contacts, label
    ("i094", "contact_id = 'P706'", "Florian Pfeiffer"),
    ("i053", "contact_id = 'P703'", "Urs Moeller"),
    ("i100", "last_name = 'Pelzer'", "Frank Pelzer"),
]


def q(s):
    if s is None:
        return "null"
    assert TAG not in s and "$il" not in s
    return f"{TAG}{s}{TAG}"


def arr(a):
    if not a:
        return "'{}'::text[]"
    return "array[" + ",".join(q(x) for x in a) + "]::text[]"


def ts(s):
    return "null" if s is None else f"'{s}'::timestamptz"


def seen_text(d):
    # jsonb::text normal form: keys by length then bytewise, ', ' and ': ' separators
    keys = sorted(d, key=lambda k: (len(k.encode()), k.encode()))
    return "{" + ", ".join(json.dumps(k, ensure_ascii=False) + ": " + json.dumps(d[k], ensure_ascii=False) for k in keys) + "}"


def item_md5(it):
    comments = RS.join(US.join([c["who"], c["at"], c["text"]]) for c in it["comments"])
    fields = [
        it["title"], it["category"], it["owner"], it["priority"], it["status"],
        it["raised_by"] or "", it["detail"], it["notes"], it["done_by"] or "",
        ",".join(it["blocks"]), ",".join(it["blocked_by"]),
        "" if it["build_wave"] is None else str(it["build_wave"]),
        "true" if it["pinned"] else "false", "true" if it["hidden"] else "false",
        it["created_at"], it["done_at"] or "", seen_text(it["seen_by"]), comments,
    ]
    return hashlib.md5(US.join(fields).encode("utf-8")).hexdigest()


ISO = """to_char({c} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')"""

MD5_SQL = f"""md5(concat_ws(chr(31),
      i.title, i.category, i.owner, i.priority, i.status, coalesce(i.raised_by,''), i.detail, i.notes,
      coalesce(i.done_by,''), array_to_string(i.blocks,','), array_to_string(i.blocked_by,','),
      coalesce(i.build_wave::text,''), i.pinned::text, i.hidden::text,
      {ISO.format(c='i.created_at')}, coalesce({ISO.format(c='i.done_at')},''), i.seen_by::text,
      coalesce((select string_agg(concat_ws(chr(31), c.who, {ISO.format(c='c.at')}, c.text), chr(30) order by c.at)
                from public.improvement_comments c where c.improvement_id = i.id), '')))"""


def item_sql(it):
    out = [
        "insert into public.improvements (team_id, item_key, title, category, owner, priority, status, raised_by,"
        " created_at, build_wave, blocks, blocked_by, done_by, done_at, pinned, hidden, seen_by, detail, notes)\n"
        f"values ({TEAM}, {q(it['id'])}, {q(it['title'])}, {q(it['category'])}, {q(it['owner'])}, {q(it['priority'])},"
        f" {q(it['status'])}, {q(it['raised_by'])}, {ts(it['created_at'])},"
        f" {'null' if it['build_wave'] is None else int(it['build_wave'])}, {arr(it['blocks'])}, {arr(it['blocked_by'])},"
        f" {q(it['done_by'])}, {ts(it['done_at'])}, {str(it['pinned']).lower()}, {str(it['hidden']).lower()},"
        f" {q(seen_text(it['seen_by']))}::jsonb,\n{q(it['detail'])},\n{q(it['notes'])});"
    ]
    for c in it["comments"]:
        out.append(
            "insert into public.improvement_comments (team_id, improvement_id, who, at, text)\n"
            f"select i.team_id, i.id, {q(c['who'])}, {ts(c['at'])},\n{q(c['text'])}\n"
            f"from public.improvements i where i.team_id = {TEAM} and i.item_key = {q(it['id'])};"
        )
    return "\n".join(out) + "\n"


def verify_sql(items):
    vals = ",\n    ".join(f"('{it['id']}', '{item_md5(it)}', {len(it['comments'])})" for it in items)
    return f"""
-- exactness gate: every item in this part must hash to the value computed from the source file
do $verify$
declare bad text;
begin
  select string_agg(e.item_key, ', ' order by e.item_key) into bad
  from (values
    {vals}
  ) as e(item_key, src_md5, n_comments)
  left join public.improvements i
    on i.item_key = e.item_key and i.team_id = {TEAM}
  where i.id is null
     or e.src_md5 is distinct from {MD5_SQL};
  if bad is not null then
    raise exception 'F18.5 import: rows differ from the source export: %', bad;
  end if;
end
$verify$;
"""


def tail_sql(data, n_items, n_comments):
    legacy = []
    for it in data["items"]:
        for a in it["activity_log"]:
            assert set(a) == {"who", "at", "what"}
            legacy.append(
                "insert into public.improvement_activity (team_id, improvement_id, item_key, who, at, action, before, after)\n"
                f"select i.team_id, i.id, i.item_key, {q(a['who'])}, {ts(a['at'])}, {q(a['what'])}, null,"
                f" {q(json.dumps({'imported_from': 'artifact activity_log', **a}, ensure_ascii=False))}::jsonb\n"
                f"from public.improvements i where i.team_id = {TEAM} and i.item_key = {q(it['id'])};"
            )
    links = []
    for key, where, label in LINKS:
        links.append(f"""
-- {key} -> {label}
do $link$
declare n int; cid uuid;
begin
  select count(*) into n from public.contacts where team_id = {TEAM} and {where};
  if n <> 1 then raise exception 'F18.5 link {key}: expected exactly 1 contact for ({where.replace("'", "")}), found %', n; end if;
  select id into cid from public.contacts where team_id = {TEAM} and {where};
  update public.improvements set linked_contact_id = cid where team_id = {TEAM} and item_key = '{key}';
  if not found then raise exception 'F18.5 link: item {key} not found'; end if;
end
$link$;""")
    return f"""-- {BASE} (tail)
-- F18.5(b)(d): legacy activity carried over verbatim, the three contact links, then the
-- activity triggers (created last so the import wrote no activity of its own), then counts.
-- GENERATED by scripts/gen_improvement_log_import.py - do not edit by hand.

-- the only activity_log entries present in the export ({len(legacy)} rows); `action` is the export's `what`
{chr(10).join(legacy)}

-- links (F18.5d)
{''.join(links)}

-- who is acting: the signed-in user's email, else 'system'
create or replace function public.fn_improvement_log_actor()
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((select u.email::text from auth.users u where u.id = (select auth.uid())), 'system');
$fn$;
revoke all on function public.fn_improvement_log_actor() from public;
revoke all on function public.fn_improvement_log_actor() from anon;

-- improvements -> improvement_activity. before/after hold only the columns that changed.
-- updated_at and seen_by are ignored: opening a card is not a change to the item.
create or replace function public.tg_improvements_activity()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_before jsonb;
  v_after  jsonb;
  v_action text;
begin
  if tg_op = 'INSERT' then
    insert into public.improvement_activity (team_id, improvement_id, item_key, who, action, before, after)
    values (new.team_id, new.id, new.item_key, public.fn_improvement_log_actor(), 'insert', null, to_jsonb(new));
    return new;
  elsif tg_op = 'DELETE' then
    -- the row is gone, so improvement_id stays null; item_key carries the identity
    insert into public.improvement_activity (team_id, improvement_id, item_key, who, action, before, after)
    values (old.team_id, null, old.item_key, public.fn_improvement_log_actor(), 'delete', to_jsonb(old), null);
    return old;
  end if;

  select coalesce(jsonb_object_agg(o.key, o.value), '{{}}'::jsonb), coalesce(jsonb_object_agg(o.key, n.value), '{{}}'::jsonb)
    into v_before, v_after
  from jsonb_each(to_jsonb(old)) o
  join jsonb_each(to_jsonb(new)) n on n.key = o.key
  where o.value is distinct from n.value
    and o.key not in ('updated_at', 'seen_by');

  if v_after = '{{}}'::jsonb then
    return new;
  end if;

  v_action := case
    when old.status is distinct from new.status and new.status = 'done' then 'done'
    when old.status is distinct from new.status and new.status = 'open' then 'reopened'
    else 'update'
  end;

  insert into public.improvement_activity (team_id, improvement_id, item_key, who, action, before, after)
  values (new.team_id, new.id, new.item_key, public.fn_improvement_log_actor(), v_action, v_before, v_after);
  return new;
end
$fn$;

create or replace function public.tg_improvement_comments_activity()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  insert into public.improvement_activity (team_id, improvement_id, item_key, who, action, before, after)
  values (new.team_id, new.improvement_id,
          (select i.item_key from public.improvements i where i.id = new.improvement_id),
          public.fn_improvement_log_actor(), 'comment', null,
          jsonb_build_object('comment_id', new.id, 'who', new.who, 'at', new.at, 'text', new.text));
  return new;
end
$fn$;

revoke all on function public.tg_improvements_activity() from public;
revoke all on function public.tg_improvements_activity() from anon;
revoke all on function public.tg_improvement_comments_activity() from public;
revoke all on function public.tg_improvement_comments_activity() from anon;

create trigger tg_improvements_activity
  after insert or update or delete on public.improvements
  for each row execute function public.tg_improvements_activity();

create trigger tg_improvement_comments_activity
  after insert on public.improvement_comments
  for each row execute function public.tg_improvement_comments_activity();

-- final gate
do $final$
declare ni int; nc int; na int; nl int;
begin
  select count(*) into ni from public.improvements;
  select count(*) into nc from public.improvement_comments;
  select count(*) into na from public.improvement_activity;
  select count(*) into nl from public.improvements where linked_contact_id is not null;
  if ni <> {n_items} or nc <> {n_comments} or na <> {len(legacy)} or nl <> {len(LINKS)} then
    raise exception 'F18.5 import totals wrong: items % (want {n_items}), comments % (want {n_comments}), activity % (want {len(legacy)}), links % (want {len(LINKS)})', ni, nc, na, nl;
  end if;
end
$final$;
"""


def main():
    data = json.loads(SRC.read_text(encoding="utf-8"))
    items = data["items"]
    n_comments = sum(len(i["comments"]) for i in items)
    assert len(items) == data["item_count"] and n_comments == data["comment_count"]
    assert len({i["id"] for i in items}) == len(items)

    parts, cur, size = [], [], 0
    for it in items:
        s = item_sql(it)
        b = len(s.encode("utf-8"))
        if cur and size + b > MAX_PART_BYTES:
            parts.append(cur)
            cur, size = [], 0
        cur.append((it, s))
        size += b
    parts.append(cur)

    for old in OUT.glob(BASE + "*.sql"):
        old.unlink()

    total = len(parts) + 1
    names = []
    for n, part in enumerate(parts, 1):
        name = BASE if n == 1 else f"{BASE}_p{n:02d}"
        its = [p[0] for p in part]
        head = (
            f"-- {name}\n-- F18.5(b) improvement log import, part {n} of {total}: {its[0]['id']}..{its[-1]['id']}"
            f" ({len(its)} items, {sum(len(i['comments']) for i in its)} comments).\n"
            f"-- GENERATED by scripts/gen_improvement_log_import.py from {SRC.name} - do not edit by hand.\n"
            "-- Text is dollar-quoted and must stay byte-for-byte; the DO block at the end rolls the part back if not.\n\n"
        )
        (OUT / f"{name}.sql").write_text(head + "\n".join(p[1] for p in part) + verify_sql(its), encoding="utf-8")
        names.append(name)
    tail = f"{BASE}_p{total:02d}_tail"
    (OUT / f"{tail}.sql").write_text(tail_sql(data, len(items), n_comments).replace(f"-- {BASE} (tail)", f"-- {tail}"), encoding="utf-8")
    names.append(tail)
    for nm in names:
        p = OUT / f"{nm}.sql"
        print(nm, p.stat().st_size, hashlib.md5(p.read_bytes()).hexdigest())


if __name__ == "__main__":
    sys.exit(main())
