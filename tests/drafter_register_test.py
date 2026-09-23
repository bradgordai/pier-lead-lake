"""F22B.11(c): unit test for the drafter's thread-register detection (du/Sie). Extracts LANG_MARKERS, detectLanguage,
messageRegister and threadRegister from generate-draft-from-context/index.ts and runs them under Node 22+
(--experimental-strip-types). Run: python3 tests/drafter_register_test.py"""
import subprocess, sys, tempfile, pathlib
SRC = pathlib.Path(__file__).resolve().parents[1] / "supabase/functions/generate-draft-from-context/index.ts"
s = SRC.read_text()
def grab(start, end):
    i = s.index(start); return s[i:s.index(end, i)]
code = "\n".join([grab("const LANG_MARKERS", "\n};\n") + "\n};\n", grab("function detectLanguage", "\n}\n") + "\n}\n",
                  grab("const DU_RE", "function registerLine")]).replace("export function", "function")
HARNESS = r'''const cases: Array<[string, string | null]> = [
  ["Hallo Oliver,\n\ndanke dir für die Nachricht, ich melde mich nächste Woche bei dir.", "du"],
  ["Sehr geehrter Herr Müller,\n\nvielen Dank für Ihre Nachricht. Gerne können wir nächste Woche sprechen, wie passt es Ihnen?", "Sie"],
  ["Hallo Frau Weber,\n\nich wollte kurz nachfragen, ob Sie meine Nachricht gesehen haben und wie das für Sie aussieht.", "Sie"],
  ["Bonjour, merci pour votre message, je suis intéressé du produit pour nous et vous.", null],
  ["Hi Oliver, thanks for reaching out, would love to hear more about this.", null],
  ["Hallo Ralf,\n\nunser Angebot ist ein kostenloser erster Monat Versicherung für eure Kunden, ohne zusätzliche Kosten für euch.", "du"],
  ["Hallo zusammen, ich bin nicht mehr für die GSD tätig. Die Profildaten wurden noch nicht aktualisiert.", null],
];
let ok = 0;
for (const [t, want] of cases) { const got = messageRegister(t); console.log(got === want ? "PASS" : "FAIL", want, got, JSON.stringify(t.slice(0, 50))); if (got === want) ok++; }
const thread = [
  { touch_type: "Initial message", touch_date: "2026-09-01", sent_body: "Sehr geehrter Herr X, wie geht es Ihnen? Ich würde gerne mit Ihnen sprechen." },
  { touch_type: "Reply", touch_date: "2026-09-05", reply_content: "Hallo Oliver, gerne, lass uns duzen. Wann passt es dir? Ich bin für dich da." },
];
const tr = threadRegister(thread); console.log("thread:", JSON.stringify(tr), tr?.register === "du" ? "PASS" : "FAIL");
const tr2 = threadRegister([thread[0], { touch_type: "Reply", touch_date: "2026-09-06", reply_content: "ok" }]); console.log("thread2:", JSON.stringify(tr2), tr2?.register === "Sie" ? "PASS" : "FAIL");
console.log(`${ok}/${cases.length} message cases`);
'''
with tempfile.NamedTemporaryFile("w", suffix=".ts", delete=False) as f:
    f.write(code + HARNESS); path = f.name
out = subprocess.run(["node", "--experimental-strip-types", "--no-warnings", path], capture_output=True, text=True)
print(out.stdout, out.stderr)
sys.exit(0 if "FAIL" not in out.stdout and out.returncode == 0 else 1)
