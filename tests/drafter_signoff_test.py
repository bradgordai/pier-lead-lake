"""F25.4d: Oliver's sign-off by register (i155, v10.13, 21 Sep 2026): "German du register: Oliver. German Sie register:
Oliver Müller. English: Oliver Muller. Never Oli, never Ollie, never Oliver Mueller in a German message."
Extracts registerLine, germanRegister, signOffFor, OLIVER_SIGN_OFF and enforceSignOff from generate-draft-from-context and
runs them under Node 22+ (--experimental-strip-types). Also asserts germanRegister agrees with registerLine on every input,
so the two cannot drift, and that the old "Oli where Oli was used before" resolution is gone.
Run: python3 tests/drafter_signoff_test.py"""
import subprocess, sys, tempfile, pathlib
SRC = pathlib.Path(__file__).resolve().parents[1] / "supabase/functions/generate-draft-from-context/index.ts"
s = SRC.read_text()
def grab(start, end):
    i = s.index(start); return s[i:s.index(end, i)]
code = "\n".join([grab("function registerLine", "\n}\n") + "\n}\n", grab("function germanRegister", "\n}\n") + "\n}\n",
                  grab("function signOffFor", "\n}\n") + "\n}\n", grab("const OLIVER_SIGN_OFF", "\n") + "\n",
                  grab("function enforceSignOff", "\n}\n") + "\n}\n"])
HARNESS = r'''let fail = 0; const t = (ok: boolean, label: string) => { console.log(ok ? "PASS" : "FAIL", label); if (!ok) fail++; };
const du = { register: "du" as const, source: "their reply" }, sie = { register: "Sie" as const, source: "our message" };
t(signOffFor("Oliver", "DE", "Informal", null) === "Oliver", "DE Informal -> Oliver");
t(signOffFor("Oliver", "DE", "Formal", null) === "Oliver Müller", "DE Formal -> Oliver Müller");
t(signOffFor("Oliver", "DE", null, null) === "Oliver Müller", "DE unrecorded -> Sie default -> Oliver Müller");
t(signOffFor("Oliver", "DE", "Formal", du) === "Oliver", "DE thread du beats Formal -> Oliver");
t(signOffFor("Oliver", "DE", "Informal", sie) === "Oliver Müller", "DE thread Sie beats Informal -> Oliver Müller");
t(signOffFor("Oliver", "EN", "Informal", null) === "Oliver Muller", "EN -> Oliver Muller");
t(signOffFor("Jack", "DE", "Informal", null) === "Jack", "another sender keeps their name");
for (const f of ["Formal", "Informal", null]) for (const th of [null, du, sie]) {
  const line = registerLine(f, "DE", th); const reg = germanRegister(f, th);
  t(line.startsWith(reg === "du" ? "du" : "Sie") || (reg === "Sie" && line.startsWith("not recorded")), `germanRegister agrees with registerLine (${f}, ${th?.register ?? "none"})`);
}
const e = (m: string, r: string) => enforceSignOff(m, r).message;
t(e("Hallo Herr X,\n\nText.\n\nViele Grüße\nOli", "Oliver Müller").endsWith("Viele Grüße\nOliver Müller"), "Oli rewritten to Oliver Müller");
t(e("Hi Anna,\n\nText.\n\nBest,\nOliver", "Oliver Muller").endsWith("Best,\nOliver Muller"), "EN Oliver rewritten to Oliver Muller");
t(e("Hallo Ralf,\n\nText.\n\nViele Grüße, Oliver Mueller", "Oliver").endsWith("Viele Grüße, Oliver"), "same-line Oliver Mueller -> Oliver");
t(e("Hallo Ralf,\n\nText.\n\nVG\nOllie", "Oliver").endsWith("VG\nOliver"), "Ollie -> Oliver");
t(e("Hi Anna,\n\nText.\n\nCheers", "Oliver Muller").endsWith("Cheers\n\nOliver Muller"), "missing name appended");
t(e("Hallo Herr X,\n\nText.\n\nViele Grüße\nOliver Müller", "Oliver Müller").endsWith("Viele Grüße\nOliver Müller"), "already correct, unchanged");
t(!e("Hallo,\n\nViele Grüße\nOliver Müller", "Oliver").includes("Müller"), "Sie name rewritten for du");
console.log(fail ? `${fail} FAILED` : "ALL PASS");
'''
with tempfile.NamedTemporaryFile("w", suffix=".ts", delete=False) as f:
    f.write(code + HARNESS); path = f.name
out = subprocess.run(["node", "--experimental-strip-types", "--no-warnings", path], capture_output=True, text=True)
print(out.stdout, out.stderr)
bad = 'sender = "Oli"' in s or "signedOli" in s
if bad: print("FAIL: the per-contact Oli resolution is still in the drafter")
sys.exit(0 if "FAIL" not in out.stdout and out.returncode == 0 and not bad else 1)
