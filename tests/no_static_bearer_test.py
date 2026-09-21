#!/usr/bin/env python3
"""F17.1(d): no source file may hold a static bearer.

Fails if any tracked text file contains a 48-character hex literal within 200 characters of the word
Bearer or Authorization (either order, any case), or a quoted 48-hex literal assigned to a name that
contains SECRET / TOKEN / KEY. A rotated secret that lives in source locks the UI out on rotation
(i070 / i082, 15-18 Sep 2026) and is compromised the moment it is committed.

Run:  python3 tests/no_static_bearer_test.py        (exit 0 = clean, 1 = findings)
The finding is printed by path and line only. The literal itself is never echoed.
"""
import re, subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
# F19: the literal found in Lovable on 21 Sep 2026 was 64 hex characters, not 48. Any 40-128 hex run counts.
HEX48 = r"(?<![0-9a-fA-F])[0-9a-fA-F]{40,128}(?![0-9a-fA-F])"
NEAR = re.compile(rf"(bearer|authorization).{{0,200}}?{HEX48}|{HEX48}.{{0,200}}?(bearer|authorization)", re.I | re.S)
ASSIGNED = re.compile(rf"\w*(secret|token|key)\w*\s*[:=]\s*[\"'`]{HEX48}[\"'`]", re.I)
SKIP_SUFFIX = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".xlsx", ".zip", ".pyc", ".ico", ".woff", ".woff2"}


def tracked_files():
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return [ROOT / p for p in out.splitlines() if p and pathlib.Path(p).suffix.lower() not in SKIP_SUFFIX]


def scan(text):
    hits = []
    for rx, why in ((NEAR, "48-hex literal adjacent to Bearer/Authorization"), (ASSIGNED, "48-hex literal assigned to a secret-like name")):
        for m in rx.finditer(text):
            hits.append((text.count("\n", 0, m.start()) + 1, why))
    return hits


def self_test():
    fake = "ab12" * 12
    assert scan(f'headers: {{ Authorization: "Bearer {fake}" }}'), "must catch header literal"
    assert scan(f'const REPLY_EF_SECRET = "{fake}";'), "must catch assigned literal"
    assert scan(f'const secret = "{fake}";\n// ...\nfetch(u, {{ headers: {{ authorization: `Bearer ${{secret}}` }} }})'), "must catch split literal"
    assert not scan("authorization: `Bearer ${Deno.env.get('INTERNAL_APP_SECRET')}`"), "env read is fine"
    assert scan('const secret = "' + "ab" * 32 + '";'), "must catch a 64-hex assigned literal"
    assert not scan("ezbr_sha256 " + "a" * 64), "a bare hash with no Bearer/secret name nearby is fine"


def main():
    self_test()
    findings = []
    for f in tracked_files():
        try:
            text = f.read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
            continue
        for line, why in scan(text):
            findings.append(f"{f.relative_to(ROOT)}:{line}: {why}")
    if findings:
        print("STATIC BEARER FOUND (value not shown):")
        print("\n".join(sorted(set(findings))))
        return 1
    print(f"ok: no static bearer in {len(tracked_files())} tracked files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
