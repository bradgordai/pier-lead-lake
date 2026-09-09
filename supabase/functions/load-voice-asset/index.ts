// Edge Function: load-voice-asset  (F12 T6, 2026-09-09)
//
// The ONE update path for the draft stack (manifest s4): Oliver edits the canonical file in the
// console, Claude Code pushes it here as a new version. Never edited in two places.
//
// Body: { id, layer (1-4), applies_to: string[] (empty = all message types), version, body, updated_by? }
// Upserts public.voice_assets; the DB trigger records every version in voice_asset_versions and
// refuses a body change that does not carry a new version.
// Auth: internal class bearer. verify_jwt=false.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { authorize } from "./_shared/authorize.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PIER_TEAM_ID = Deno.env.get("PIER_TEAM_ID") ?? "";
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const json = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!PIER_TEAM_ID) return json(500, { error: "server_misconfigured" });
  if (!authorize(req, "internal", "load-voice-asset")) return json(401, { error: "unauthorized" });
  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const id = String(body?.id ?? "").trim();
  const layer = Number(body?.layer);
  const version = String(body?.version ?? "").trim();
  const text = String(body?.body ?? "");
  const appliesTo = Array.isArray(body?.applies_to) ? body.applies_to.map(String) : [];
  if (!id || !(layer >= 1 && layer <= 4) || !version || text.trim().length < 100) {
    return json(400, { error: "missing_required_fields", detail: "id, layer 1-4, version and a body of at least 100 characters are required" });
  }
  const { data, error } = await supabase.from("voice_assets")
    .upsert({ id, team_id: PIER_TEAM_ID, layer, applies_to: appliesTo, version, body: text, updated_by: String(body?.updated_by ?? "load-voice-asset") }, { onConflict: "id" })
    .select("id, layer, version, updated_at").single();
  if (error) return json(409, { error: "load_refused", detail: error.message });
  console.log(JSON.stringify({ event: "voice_asset_loaded", id, layer, version, bytes: text.length }));
  return json(200, { ok: true, asset: data, bytes: text.length });
});
