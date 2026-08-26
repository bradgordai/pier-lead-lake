// Shared auth helper: scoped bearer verification for Pier Edge Functions.
//
// Security audit CRITICAL 2. Today every Edge Function authenticates with ONE static
// MAKE_SHARED_SECRET, which also sits in plaintext in the Make blueprint and hardcoded in
// Lovable server functions. One leaked string is full control of ingest, drafting,
// enrichment and sending. This splits that into two scoped secrets by caller class:
//
//   INBOUND_WEBHOOK_SECRET  Make + PhantomBuster webhooks -> Supabase
//   INTERNAL_APP_SECRET     Lovable server functions and EF-to-EF calls -> Supabase
//
// Both are accepted ALONGSIDE the old MAKE_SHARED_SECRET during the transition, so adding
// the new secrets in the Supabase UI breaks nothing and the cutover can happen caller by
// caller. A request that authenticates on the old secret logs `deprecated_secret_used`, so
// the Edge Function logs tell you exactly when it is safe to delete MAKE_SHARED_SECRET.
//
// Deployment note: Supabase bundles each function independently. Ship this file as a
// sibling inside each function that imports it ("./_shared/authorize.ts"); this copy is the
// canonical one.

export type CallerClass = "inbound" | "internal";

/**
 * Returns true when the request carries an acceptable bearer for this caller class.
 * Logs (never the secret itself) which credential was used.
 */
export function authorize(req: Request, cls: CallerClass, fnName: string): boolean {
  const authz = req.headers.get("authorization") ?? "";
  const token = authz.startsWith("Bearer ") ? authz.slice(7) : "";
  if (!token) return false;

  const scoped = cls === "inbound"
    ? Deno.env.get("INBOUND_WEBHOOK_SECRET") ?? ""
    : Deno.env.get("INTERNAL_APP_SECRET") ?? "";
  const legacy = Deno.env.get("MAKE_SHARED_SECRET") ?? "";

  if (scoped && token === scoped) return true;

  if (legacy && token === legacy) {
    // Still valid, but this is what we are trying to retire. Every line here is a caller
    // that has not been cut over yet.
    console.warn(JSON.stringify({
      event: "deprecated_secret_used",
      function_name: fnName,
      caller_class: cls,
      detail: "Request authenticated with MAKE_SHARED_SECRET. Cut this caller over to the scoped secret, then delete MAKE_SHARED_SECRET.",
    }));
    return true;
  }

  return false;
}
