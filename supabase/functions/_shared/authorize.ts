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

// F17.1 (2026-09-18): the JWT path. The Lovable app held INTERNAL_APP_SECRET as a string literal in its
// own source, so a rotation here locked every action out of the UI for three days. A signed-in member of
// the Pier team can now call the internal-class functions with their own Supabase access token, which
// rotates itself and never lives in source. The secret path stays for cron, Make and EF-to-EF calls.
//
// The token is verified by the auth server (getUser), never decoded and trusted locally, and the caller
// must hold a team_members row for PIER_TEAM_ID. A valid Supabase user who is not on the team is refused.

export type AuthResult = { ok: boolean; via: "secret" | "jwt" | null; user_id: string | null; email: string | null };

const looksLikeJwt = (t: string) => t.split(".").length === 3 && t.startsWith("eyJ");

/**
 * Secret first (unchanged behaviour), then a Supabase user JWT belonging to a Pier team member.
 * `supabase` must be a service-role client.
 */
// deno-lint-ignore no-explicit-any
export async function authorizeRequest(req: Request, cls: CallerClass, fnName: string, supabase: any): Promise<AuthResult> {
  if (authorize(req, cls, fnName)) return { ok: true, via: "secret", user_id: null, email: null };

  const authz = req.headers.get("authorization") ?? "";
  const token = authz.startsWith("Bearer ") ? authz.slice(7) : "";
  const denied: AuthResult = { ok: false, via: null, user_id: null, email: null };
  if (!token || !looksLikeJwt(token)) return denied;

  const teamId = Deno.env.get("PIER_TEAM_ID") ?? "";
  if (!teamId) return denied;
  try {
    const { data, error } = await supabase.auth.getUser(token);
    const user = data?.user;
    if (error || !user?.id) {
      console.warn(JSON.stringify({ event: "jwt_rejected", function_name: fnName, reason: error?.message ?? "no_user" }));
      return denied;
    }
    const { data: member, error: mErr } = await supabase.from("team_members").select("id")
      .eq("team_id", teamId).eq("user_id", user.id).limit(1).maybeSingle();
    if (mErr || !member) {
      console.warn(JSON.stringify({ event: "jwt_not_team_member", function_name: fnName, user_id: user.id }));
      return denied;
    }
    console.log(JSON.stringify({ event: "jwt_authorized", function_name: fnName, user_id: user.id }));
    return { ok: true, via: "jwt", user_id: user.id, email: user.email ?? null };
  } catch (e) {
    console.error(JSON.stringify({ event: "jwt_check_failed", function_name: fnName, message: (e as Error).message ?? String(e) }));
    return denied;
  }
}
