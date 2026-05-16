// upload_recovery — registers BIP-39 recovery envelope + lookup hash.
// Body: { lookup_hash_b64: string, wrapped_key_b64: string, salt_b64: string, key_version: number }
// Auth: Bearer JWT (authenticated admin device with an active family).
// Returns: { success: true }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { writeAuditEvent } from "../_shared/audit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function bytesFromBase64(s: string): Uint8Array {
  const clean = s.replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(clean);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

function hexFromBytes(b: Uint8Array): string {
  return Array.from(b).map((x) => x.toString(16).padStart(2, "0")).join("");
}

function toByteaHex(b: Uint8Array): string {
  return "\\x" + hexFromBytes(b);
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return new Response("Unauthorized", { status: 401 });
  }

  const body = await req.json().catch(() => null) as {
    lookup_hash_b64: string;
    wrapped_key_b64: string;
    salt_b64: string;
    key_version: number;
  } | null;

  if (
    !body?.lookup_hash_b64 ||
    !body.wrapped_key_b64 ||
    !body.salt_b64 ||
    !body.key_version
  ) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

  // Authenticate caller and resolve their device's family_id.
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: userData } = await userClient.auth.getUser();
  if (!userData?.user) {
    return new Response("Unauthorized", { status: 401 });
  }

  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // Use service role to lookup device so an editor cannot spoof the role field.
  const { data: deviceRow, error: deviceErr } = await svc
    .from("family_devices")
    .select("device_fp, family_id, role")
    .eq("auth_user_id", userData.user.id)
    .eq("role", "admin")
    .is("revoked_at", null)
    .limit(1)
    .single();

  if (deviceErr || !deviceRow) {
    return new Response("Forbidden: admin role required", { status: 403 });
  }
  const familyId: string = deviceRow.family_id;
  const deviceFpRaw = deviceRow.device_fp as string;
  const deviceFpHex = deviceFpRaw.startsWith("\\x") ? deviceFpRaw.slice(2) : deviceFpRaw;

  // Upsert the recovery envelope (one row per family).
  const wrappedKey = bytesFromBase64(body.wrapped_key_b64);
  const salt = bytesFromBase64(body.salt_b64);

  const { error: envErr } = await svc.from("family_recovery_envelopes").upsert(
    {
      family_id: familyId,
      wrapped_key: toByteaHex(wrappedKey),
      salt: toByteaHex(salt),
      key_version: body.key_version,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "family_id" },
  );

  if (envErr) {
    return new Response(JSON.stringify({ error: envErr.message }), { status: 500 });
  }

  // Atomically upsert the lookup entry (unique constraint on family_id added in 0030).
  const lookupHash = bytesFromBase64(body.lookup_hash_b64);
  const { error: lookupErr } = await svc.from("recovery_lookup").upsert(
    { lookup_hash: toByteaHex(lookupHash), family_id: familyId },
    { onConflict: "family_id" },
  );

  if (lookupErr) {
    return new Response(JSON.stringify({ error: lookupErr.message }), { status: 500 });
  }

  await writeAuditEvent(
    familyId,
    "recovery_code_registered",
    deviceFpHex,
    { key_version: body.key_version },
  ).catch(() => {});

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
