"""F23 Task 1(c): regression guard for the silent draft death.

A skipped PhantomBuster send (exit 0, empty resultObject) used to set send_status='Cancelled'; send-approved-draft
only accepts Draft or Ready, so the draft could never be sent again. send-approved-callback v17 returns the row to
send_status='Draft' with hold_reason='phantom_skipped_duplicate'.

This test FAILS if:
  1. send-approved-draft's accepted send_status list stops including the status a hold_reason row carries (Draft);
  2. the callback's skip path stops writing that status together with hold_reason, or writes Cancelled again.

Run: python3 tests/send_hold_reason_test.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
DRAFT = (ROOT / "supabase/functions/send-approved-draft/index.ts").read_text()
CALLBACK = (ROOT / "supabase/functions/send-approved-callback/index.ts").read_text()

failures = []

# 1. The sendable guard in send-approved-draft: `!["Draft", "Ready"].includes(String(row.send_status))`.
guard = re.search(r'!\s*\[([^\]]*)\]\.includes\(String\(row\.send_status\)\)', DRAFT)
if not guard:
    failures.append("send-approved-draft: could not find the accepted send_status list (the not_sendable guard)")
    accepted = set()
else:
    accepted = set(re.findall(r'"([^"]+)"', guard.group(1)))

# 2. The skip branch of the callback: the block that starts at `if (results.length === 0) {`.
skip = re.search(r'if \(results\.length === 0\) \{(.*?)\n    \}\n', CALLBACK, re.S)
if not skip:
    failures.append("send-approved-callback: could not find the skip branch (results.length === 0)")
else:
    body = skip.group(1)
    status = re.search(r'send_status:\s*"([^"]+)"', body)
    hold = re.search(r'hold_reason:\s*"([^"]+)"', body)
    draft_status = re.search(r'draft_status:\s*"([^"]+)"', body)
    if not hold:
        failures.append("callback skip branch no longer writes hold_reason")
    if not status:
        failures.append("callback skip branch no longer writes send_status")
    else:
        if status.group(1) == "Cancelled":
            failures.append("callback skip branch writes send_status='Cancelled' again: the draft dies silently")
        if accepted and status.group(1) not in accepted:
            failures.append(
                f"a hold_reason row carries send_status='{status.group(1)}' but send-approved-draft only accepts "
                f"{sorted(accepted)}: the draft can never be sent again")
    if draft_status and draft_status.group(1) == "approved":
        failures.append("callback skip branch puts the row back to 'approved': it must go to review (pending_review)")

if "Draft" not in accepted:
    failures.append(f"send-approved-draft no longer accepts send_status='Draft' (accepts {sorted(accepted)})")

if failures:
    print("FAIL")
    for f in failures:
        print(" -", f)
    sys.exit(1)
print(f"PASS: send-approved-draft accepts {sorted(accepted)}; callback skip -> send_status='{status.group(1)}', "
      f"draft_status='{draft_status.group(1) if draft_status else '?'}', hold_reason='{hold.group(1)}'")
