// create_invite Edge Function — Plan C-3.
// Admin device stores a pre-wrapped invite on the server.
// Body: { family_id, code_hash (hex), salt (base64), wrapped_key (base64), expires_at (ISO8601) }
// The client derives code_hash = blake2b(normalise(code)) and wraps the family
// key under Argon2id(code) before calling this endpoint — ciphertext only.

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

  // Verify the caller is an authenticated user.
  const userClient = createClient(SUPABASE_URL, authHeader.replace("Bearer ", ""), {
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    return new Response("Unauthorized", { status: 401 });
  }
  const callerDeviceFpHex = userData.user.id.replace(/-/g, "");
  const callerDeviceFp = Uint8Array.from(
    callerDeviceFpHex.match(/.{2}/g)!.map((b) => parseInt(b, 16)),
  );

  const body = await req.json().catch(() => null) as {
    family_id: string;
    code_hash: string;
    salt: string;
    wrapped_key: string;
    expires_at: string;
  } | null;

  if (!body?.family_id || !body.code_hash || !body.salt || !body.wrapped_key || !body.expires_at) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // Verify caller is an active admin of the claimed family.
  const { data: device, error: devErr } = await admin
    .from("family_devices")
    .select("role, revoked_at")
    .eq("device_fp", callerDeviceFp)
    .eq("family_id", body.family_id)
    .single();

  if (devErr || !device) return new Response("Forbidden", { status: 403 });
  if (device.role !== "admin" || device.revoked_at !== null) {
    return new Response("Forbidden", { status: 403 });
  }

  const saltBytes = Uint8Array.from(atob(body.salt), (c) => c.charCodeAt(0));
  const wrappedBytes = Uint8Array.from(atob(body.wrapped_key), (c) => c.charCodeAt(0));

  const { error: insertErr } = await admin.from("invites").insert({
    code_hash: body.code_hash,
    family_id: body.family_id,
    salt: saltBytes,
    wrapped_key: wrappedBytes,
    expires_at: body.expires_at,
  });

  if (insertErr) {
    if (insertErr.code === "23505") {
      return new Response(JSON.stringify({ error: "code_hash collision" }), { status: 409 });
    }
    return new Response(JSON.stringify({ error: insertErr.message }), { status: 500 });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 201,
    headers: { "Content-Type": "application/json" },
  });
});
