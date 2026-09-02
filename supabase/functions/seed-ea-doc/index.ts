// Admin helper: seed/update a single Pier EA document (upsert on team_id+name).
// Scoped-secret gated (INTERNAL_APP_SECRET; legacy MAKE_SHARED_SECRET still accepted
// during the transition); service_role at boot. Lets a local script POST large file
// content straight to the DB without routing it through an agent context. Also usable
// later to refresh an EA doc: POST { name, category, content }. Safe to delete.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

// deno-lint-ignore no-explicit-any
const json = (s: number, b: any) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });
const CATEGORIES = ["rules", "template", "targeting", "context", "response", "skill"];

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured" });
  // Scoped-secret auth (CRITICAL 2). Not in the original five: this admin helper was
  // missed by the retrofit list, and while it accepts only the legacy secret
  // MAKE_SHARED_SECRET can never be deleted.
  if (!authorize(req, "internal", "seed-ea-doc")) return json(401, { error: "unauthorized" });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const name = String(body?.name ?? "").trim();
  const category = String(body?.category ?? "").trim();
  const content = typeof body?.content === "string" ? body.content : "";
  if (!name || !CATEGORIES.includes(category) || !content) {
    return json(400, { error: "missing_or_invalid_fields", detail: "name, valid category, non-empty content required" });
  }
  const { error } = await supabase
    .from("pier_ea_documents")
    .upsert({ team_id: PIER_TEAM_ID, name, category, content, is_active: true }, { onConflict: "team_id,name" });
  if (error) return json(500, { error: "db_error", detail: error.message });
  return json(200, { ok: true, name, category, length: content.length });
});
