# Lovable prompt: diagnose and fix the production build error

Paste this into Lovable. The full error trace and a preliminary diagnosis are included below.

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
build failed with exit status 1: stderr: node_modules/vite/dist/node/chunks/node.js:33675:19) at async buildStartViteEnvironments (file:///dev-server/node_modules/@tanstack/start-plugin-core/dist/esm/vite/planning.js:95:23) at async Object.buildApp (file:///dev-server/node_modules/@tanstack/start-plugin-core/dist/esm/vite/plugin.js:113:8) at async Object.buildApp (file:///dev-server/node_modules/vite/dist/node/chunks/node.js:33667:6) at async CAC.<anonymous> (file:///dev-server/node_modules/vite/dist/node/cli.js:777:3) { errors: [Getter/Setter] } error: script "build:dev" exited with code 1
stdout: lient/assets/dist-CGLcxLQE.js 29.14 kB │ gzip: 9.58 kB dist/client/assets/formatDistanceToNow-BQlgO3EV.js 32.58 kB │ gzip: 10.79 kB dist/client/assets/link-DyP-I3ri.js 34.05 kB │ gzip: 11.75 kB dist/client/assets/route-D_U_fE11.js 39.91 kB │ gzip: 11.24 kB dist/client/assets/companies-BgF1wpbG.js 45.62 kB │ gzip: 11.96 kB dist/client/assets/skeleton--gcOn3fn.js 53.09 kB │ gzip: 19.23 kB dist/client/assets/index-TnX0Sbgy.js 588.65 kB │ gzip: 174.61 kB
```

## Preliminary diagnosis (hints — please verify, do not take as fact)

The trace points to a **server/SSR environment build failure, not a client failure**. Read it this way:

1. The **client build succeeded** — stdout lists emitted `dist/client/assets/*.js` chunks (including `index-TnX0Sbgy.js` at 588 kB). So client bundling and transforms completed.
2. The crash happens **after** that, inside `buildStartViteEnvironments` (`@tanstack/start-plugin-core/.../vite/planning.js:95`). TanStack Start builds multiple Vite environments in sequence (client, then server/SSR). The client one printed its assets; the **next environment threw**, which is why it fails only in the full production build and not in the dev preview (dev never produces the bundled server build).
3. The error object is `{ errors: [Getter/Setter] }` — the shape of an **esbuild `BuildFailure`**. The real message is inside that `errors` array and is **truncated/hidden** in this trace. The single most useful next step is to surface it.

Likely root causes, in order of probability:
- **A client-only import leaking into the server/SSR build** — a module referencing `window`, `document`, `localStorage`, or a browser-only library imported at the top level of a route, loader, or shared file. Dev tolerates it; the SSR bundle does not. Guard with `typeof window !== 'undefined'`, move it into a client-only boundary, or lazy-import it.
- **A dependency that is not SSR/externalisation-safe** being pulled into the server build (may need `ssr.noExternal` / `ssr.external` config, or `optimizeDeps` adjustment).
- **A regression / version mismatch** in `@tanstack/start-plugin-core` or `vite` (check for a recent bump; try pinning to the last known-good versions).

Recommended actions for Lovable:
1. Re-run `build:dev` with esbuild errors fully expanded (surface the hidden `errors[]` message — the failing file and reason). Do not stop at the stack trace.
2. Identify the exact module the **server** environment fails on and apply the smallest fix (SSR guard, client-only boundary, or Vite SSR config) — **no UI or business-logic changes**.
3. If it is a plugin/vite version regression, pin to known-good versions.
4. Re-run the full production build to confirm all environments (client and server) complete.

---

> Note for Brad: I could **not** reproduce this locally — the pier-lead-lake repo holds only docs,
> migrations, and scripts; the Lovable frontend (package.json, vite/TanStack config, routes) lives
> in Lovable's own dev-server container (see the `file:///dev-server/...` paths in the trace), so
> there is nothing here to `npm run build:dev` against. The diagnosis above is inferred from the
> trace alone, so treat it as a starting hint, not a verified fix. It is safe to paste this while
> Lovable's Try-to-Fix is still running; if Try-to-Fix succeeds you can ignore it, and if it fails
> this points at the server-environment / hidden-esbuild-error angle.
