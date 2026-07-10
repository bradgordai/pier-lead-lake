# Lovable prompt: diagnose and fix the production build error

Paste this into Lovable. Before pasting, replace the placeholder block below with the
full error trace (see note at the bottom — the complete trace was not captured here yet).

---

The production build is failing while the dev preview renders correctly. Please diagnose and fix the build error.

Symptoms:
- Dev preview works and renders correctly.
- The production build fails during Vite / TanStack Start at `buildStartViteEnvironments` in `@tanstack/start-plugin-core`.

Constraints:
- Do not touch UI or business logic. Only change the build configuration or the specific file(s) causing the failure.
- Keep the app's behaviour and appearance identical; this is a build-config fix, not a feature change.
- Explain the root cause and exactly what you changed, then re-run the production build to confirm it passes.

Full error trace:

```
[PASTE THE FULL PRODUCTION BUILD ERROR TRACE HERE]
```

---

> Note for Brad: the full build error trace was not included in the message, so I left the
> placeholder above. Paste the complete terminal output (from the failing `build` command,
> including the stack frames and any `Caused by` / file-path lines) into the code block before
> sending this to Lovable — Lovable will diagnose far more reliably with the real trace than
> with the one-line summary. If you paste it to me, I'll drop it into this file for you.
