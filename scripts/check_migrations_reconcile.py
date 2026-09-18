#!/usr/bin/env python3
"""H1: reconcile /migrations with supabase_migrations.schema_migrations.

Usage:  python3 scripts/check_migrations_reconcile.py applied.txt
where applied.txt holds the applied names, whitespace separated, from:
  select string_agg(name, ' ' order by version) from supabase_migrations.schema_migrations;
The Supabase CLI is not the source of truth here: every migration has been applied through the MCP, which
records its own timestamp versions, so `supabase migration list` compares NNN_ file prefixes to timestamps
and can never reconcile. Names are the stable key. Exit 1 on any unexplained difference.
"""
import pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
files = {p.stem for p in (ROOT / "migrations").glob("*.sql")}
applied = set(pathlib.Path(sys.argv[1]).read_text().split())
HELD = {p for p in files if "DO_NOT_APPLY" in p}
only_files, only_db = sorted(files - applied - HELD), sorted(applied - files)
stray = sorted(str(p) for p in (ROOT / "supabase").glob("migrations/*.sql"))
print(f"files {len(files)}  applied {len(applied)}  held (never apply) {sorted(HELD)}")
print("in repo, not applied:", only_files or "none")
print("applied, no file    :", only_db or "none")
print("strays in supabase/migrations:", stray or "none")
sys.exit(1 if (only_files or only_db or stray) else 0)
