// claim_recovery — BIP-39 recovery: looks up family via phrase hash, rate-limits,
// registers new device, and returns the wrapped K_family envelope.
// Body: { lookup_hash_b64: string, device_pub_key_b64: string }
// Auth: Bearer JWT (signInAnonymously on new device first).
// Returns: { wrapped_key_b64, salt_b64, key_version, family_id }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { writeAuditEvent } from "../_shared/audit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RATE_LIMIT = 5;
const RATE_WINDOW_HOURS = 1;

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

function base64FromHex(hex: string): string {
  const clean = hex.replace(/^\\x/, "");
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
  }
  return btoa(String.fromCharCode(...bytes));
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return new Response("Unauthorized", { status: 401 });

  const body = await req.json().catch(() => null) as {
    lookup_hash_b64: string;
    device_pub_key_b64: string;
  } | null;

  if (!body?.lookup_hash_b64 || !body.device_pub_key_b64) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

  // Authenticate caller (new device with anonymous JWT).
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  if (!userData?.user) return new Response("Unauthorized", { status: 401 });

  // Compute device_fp = SHA-256(pubkey)[0:16].
  const devicePubKey = bytesFromBase64(body.device_pub_key_b64);
  const hashBuf = await crypto.subtle.digest("SHA-256", devicePubKey);
  const deviceFp = new Uint8Array(hashBuf).slice(0, 16);
  const deviceFpHex = hexFromBytes(deviceFp);

  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // Look up family_id via recovery_lookup.
  const lookupHash = bytesFromBase64(body.lookup_hash_b64);
  const { data: lookupRow, error: lookupErr } = await svc
    .from("recovery_lookup")
    .select("family_id")
    .eq("lookup_hash", toByteaHex(lookupHash))
    .single();

  if (lookupErr || !lookupRow) {
    await writeAuditEvent(null, "recovery_attempted", deviceFpHex, { reason: "not_found" }).catch(() => {});
    return new Response("Not Found", { status: 404 });
  }
  const familyId: string = lookupRow.family_id;

  // Rate limit: count failed attempts in the last RATE_WINDOW_HOURS.
  const windowStart = new Date(Date.now() - RATE_WINDOW_HOURS * 3600 * 1000).toISOString();
  const { count } = await svc
    .from("recovery_attempts")
    .select("id", { count: "exact", head: true })
    .eq("family_id", familyId)
    .eq("success", false)
    .gte("attempted_at", windowStart);

  if ((count ?? 0) >= RATE_LIMIT) {
    await writeAuditEvent(familyId, "recovery_attempted", deviceFpHex, { reason: "rate_limited" }).catch(() => {});
    return new Response("Too Many Requests", { status: 429 });
  }

  // Record this attempt (initially failed; updated to success on completion).
  const { data: attemptRow } = await svc
    .from("recovery_attempts")
    .insert({ family_id: familyId, success: false })
    .select("id")
    .single();
  const attemptId: string | null = attemptRow?.id ?? null;

  // Fetch the recovery envelope.
  const { data: envelope, error: envelopeErr } = await svc
    .from("family_recovery_envelopes")
    .select("wrapped_key, salt, key_version")
    .eq("family_id", familyId)
    .single();

  if (envelopeErr || !envelope) {
    await writeAuditEvent(familyId, "recovery_attempted", deviceFpHex, { reason: "no_envelope" }).catch(() => {});
    return new Response("Recovery envelope not found", { status: 404 });
  }

  // Register the new device in family_devices.
  await svc.from("family_devices").upsert(
    {
      device_fp: toByteaHex(deviceFp),
      family_id: familyId,
      device_pub_key: toByteaHex(devicePubKey),
      role: "editor",
      joined_at: new Date().toISOString(),
      key_version_at_join: envelope.key_version,
      auth_user_id: userData.user.id,
    },
    { onConflict: "device_fp", ignoreDuplicates: false },
  );

  // Mark attempt as successful.
  if (attemptId) {
    await svc.from("recovery_attempts").update({ success: true }).eq("id", attemptId);
  }

  await writeAuditEvent(
    familyId,
    "recovery_succeeded",
    deviceFpHex,
    { key_version: envelope.key_version },
  ).catch(() => {});

  // Encode bytea values for the client (PostgREST returns \\x-prefixed hex).
  const wrappedKeyHex = typeof envelope.wrapped_key === "string"
    ? envelope.wrapped_key
    : "\\x" + hexFromBytes(new Uint8Array(envelope.wrapped_key));
  const saltHex = typeof envelope.salt === "string"
    ? envelope.salt
    : "\\x" + hexFromBytes(new Uint8Array(envelope.salt));

  return new Response(
    JSON.stringify({
      wrapped_key_b64: base64FromHex(wrappedKeyHex),
      salt_b64: base64FromHex(saltHex),
      key_version: envelope.key_version,
      family_id: familyId,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
