"""F24.4: the drafter infers the target language from the company's country when the contact's Language field is
empty, and records why. Extracts the pure functions from generate-draft-from-context/index.ts and runs them under Node
22+ (--experimental-strip-types). Run: python3 tests/drafter_language_test.py"""
import pathlib, subprocess, sys, tempfile
SRC = pathlib.Path(__file__).resolve().parents[1] / "supabase/functions/generate-draft-from-context/index.ts"
s = SRC.read_text()
def grab(start, end):
    i = s.index(start); return s[i:s.index(end, i)]
parts = [grab("const LANG_MARKERS", "\n};\n") + "\n};\n",
         grab("function detectLanguage", "\n}\n") + "\n}\n",
         grab("const WRITTEN_LANGUAGES", "\n") + "\n",
         grab("const COUNTRY_LANGUAGE", "\n};\n") + "\n};\n",
         grab("export function inferLanguageFromCountry", "\n}\n") + "\n}\n",
         grab("function resolveTargetLanguage", "\n}\n") + "\n}\n"]
code = "\n".join(parts).replace("export function", "function")
HARNESS = r'''
const cases: Array<[any[], string | null, string | null, string, string]> = [
  [[], null, "Germany", "DE", "company_country"],
  [[], null, "Austria", "DE", "company_country"],
  [[], null, "Switzerland", "DE", "company_country"],
  [[], null, "France", "EN", "not a written language"],
  [[], null, "UK", "EN", "company_country"],
  [[], null, null, "EN", "default: no reply, no Language field and no mappable company country (none)"],
  [[], null, "United States (parent HQ); operations across 57 countries", "EN", "default"],
  [[], "EN", "Germany", "EN", "contact_language"],
  [[{ touch_type: "Reply", touch_date: "2026-09-01", reply_content: "Hallo Oliver, danke für die Nachricht, ich melde mich bei dir." }], null, "UK", "DE", "their_reply"],
];
let fail = 0;
for (const [prev, lang, country, want, reasonHas] of cases) {
  const r = resolveTargetLanguage(prev, lang, country);
  const ok = r.language === want && r.reason.includes(reasonHas);
  if (!ok) fail++;
  console.log(ok ? "PASS" : "FAIL", JSON.stringify({ lang, country, got: r }));
}
console.log(fail ? `${fail} FAILED` : "ALL PASS");
'''
with tempfile.NamedTemporaryFile("w", suffix=".ts", delete=False) as f:
    f.write(code + HARNESS); path = f.name
out = subprocess.run(["node", "--experimental-strip-types", "--no-warnings", path], capture_output=True, text=True)
print(out.stdout, out.stderr)
sys.exit(0 if "ALL PASS" in out.stdout else 1)
