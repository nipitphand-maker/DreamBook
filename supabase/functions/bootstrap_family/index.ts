// bootstrap_family Edge Function — Plan C-3.
// Called once per device that initiates a new family (role='admin').
// Body: { device_pub_key: base64 }
// Returns: { family_id: string, device_fp: hex }
// The server generates the family UUID; the client then calls
// FamilyKeyService.generate(familyId) to create and store K_family locally.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return new Response("Unauthorized", { status: 401 });
  }

  const userClient = createClient(SUPABASE_URL, authHeader.replace("Bearer ", ""), {
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    return new Response("Unauthorized", { status: 401 });
  }
  const deviceFpHex = userData.user.id.replace(/-/g, "");
  const deviceFp = Uint8Array.from(deviceFpHex.match(/.{2}/g)!.map((b) => parseInt(b, 16)));

  const body = await req.json().catch(() => null) as { device_pub_key: string } | null;
  if (!body?.device_pub_key) {
    return new Response(JSON.stringify({ error: "missing device_pub_key" }), { status: 400 });
  }
  const devicePubKey = Uint8Array.from(atob(body.device_pub_key), (c) => c.charCodeAt(0));

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // Idempotency: if this device is already an admin, return its family_id.
  const { data: existing } = await admin
    .from("family_devices")
    .select("family_id")
    .eq("device_fp", deviceFp)
    .eq("role", "admin")
    .is("revoked_at", null)
    .maybeSingle();

  if (existing) {
    return new Response(
      JSON.stringify({ family_id: existing.family_id, device_fp: deviceFpHex }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // Create family row (server generates UUID).
  const { data: family, error: familyErr } = await admin
    .from("families")
    .insert({})
    .select("id")
    .single();

  if (familyErr || !family) {
    return new Response(JSON.stringify({ error: "failed to create family" }), { status: 500 });
  }

  // Register calling device as admin.
  const { error: devErr } = await admin.from("family_devices").insert({
    device_fp: deviceFp,
    family_id: family.id,
    device_pub_key: devicePubKey,
    role: "admin",
    key_version_at_join: 1,
  });

  if (devErr) {
    return new Response(JSON.stringify({ error: devErr.message }), { status: 500 });
  }

  return new Response(
    JSON.stringify({ family_id: family.id, device_fp: deviceFpHex }),
    { status: 201, headers: { "Content-Type": "application/json" } },
  );
});
