// supabase/functions/restore_snapshot/index.ts
// restore_snapshot — retrieves an encrypted snapshot for a family.
// Body: { lookup_hash_b64: string, device_pub_key_b64: string, version?: number }
// Auth: Bearer JWT (anonymous auth — new device).
// Returns: { wrapped_key_b64, salt_b64, key_version, version, payload_b64, payload_hash_b64, family_id }

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

function base64FromBytes(b: Uint8Array): string {
  let s = "";
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s);
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
    version?: number;
  } | null;

  if (!body?.lookup_hash_b64 || !body.device_pub_key_b64) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

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

  // Pre-resolution rate limit: count recent failures by auth_user_id BEFORE
  // resolving lookup_hash so the 404 path cannot be used to brute-force hashes.
  const windowStart = new Date(Date.now() - RATE_WINDOW_HOURS * 3600 * 1000).toISOString();
  const { count: preCount } = await svc
    .from("recovery_attempts")
    .select("id", { count: "exact", head: true })
    .eq("auth_user_id", userData.user.id)
    .eq("success", false)
    .gte("attempted_at", windowStart);

  if ((preCount ?? 0) >= RATE_LIMIT) {
    return new Response("Too Many Requests", { status: 429 });
  }

  // Resolve family_id from lookup_hash (privacy-preserving indirection).
  const lookupHashBytes = bytesFromBase64(body.lookup_hash_b64);
  const { data: lookupRow, error: lookupErr } = await svc
    .from("recovery_lookup")
    .select("family_id")
    .eq("lookup_hash", toByteaHex(lookupHashBytes))
    .single();

  if (lookupErr || !lookupRow) {
    // Record pre-resolution miss so the pre-check stays accurate.
    await svc.from("recovery_attempts")
      .insert({ family_id: null, auth_user_id: userData.user.id, success: false })
      .catch(() => {});
    await writeAuditEvent(null, "snapshot_restored", deviceFpHex,
      { reason: "lookup_not_found" }).catch(() => {});
    return new Response("Not Found", { status: 404 });
  }
  const familyId = lookupRow.family_id as string;

  // Find the snapshot.
  let snapshotQuery = svc
    .from("encrypted_snapshots")
    .select("version, storage_path, wrapped_key, salt, key_version, payload_hash, size_bytes")
    .eq("family_id", familyId)
    .order("version", { ascending: false })
    .limit(1);

  if (body.version != null) {
    snapshotQuery = svc
      .from("encrypted_snapshots")
      .select("version, storage_path, wrapped_key, salt, key_version, payload_hash, size_bytes")
      .eq("family_id", familyId)
      .eq("version", body.version)
      .limit(1);
  }

  const { data: snapshotRow, error: snapErr } = await snapshotQuery.single();

  if (snapErr || !snapshotRow) {
    // Count this probe toward the rate limit — prevents not-found path from bypassing it.
    await svc.from("recovery_attempts")
      .insert({ family_id: familyId, auth_user_id: userData.user.id, success: false })
      .catch(() => {});
    await writeAuditEvent(familyId, "snapshot_restored", deviceFpHex,
      { reason: "not_found" }).catch(() => {});
    return new Response("Not Found", { status: 404 });
  }

  // Record attempt (initially failed; updated to success on completion).
  const { data: attemptRow } = await svc
    .from("recovery_attempts")
    .insert({ family_id: familyId, auth_user_id: userData.user.id, success: false })
    .select("id")
    .single();
  const attemptId: string | null = attemptRow?.id ?? null;

  // Download blob from Storage.
  const { data: blobData, error: downloadErr } = await svc.storage
    .from("family-snapshots")
    .download(snapshotRow.storage_path);

  if (downloadErr || !blobData) {
    await writeAuditEvent(familyId, "snapshot_restored", deviceFpHex,
      { reason: "storage_error" }).catch(() => {});
    return new Response("Snapshot blob unavailable", { status: 503 });
  }

  const blobBytes = new Uint8Array(await blobData.arrayBuffer());

  // Register the new device in family_devices.
  const { data: familyRow } = await svc
    .from("families")
    .select("current_key_version")
    .eq("id", familyId)
    .single();
  const keyVersionAtJoin = familyRow?.current_key_version ?? snapshotRow.key_version;

  await svc.from("family_devices").upsert(
    {
      device_fp: toByteaHex(deviceFp),
      family_id: familyId,
      device_pub_key: toByteaHex(devicePubKey),
      role: "editor",
      joined_at: new Date().toISOString(),
      key_version_at_join: keyVersionAtJoin,
      auth_user_id: userData.user.id,
    },
    { onConflict: "device_fp,family_id", ignoreDuplicates: false },
  );

  // Mark attempt successful.
  if (attemptId) {
    await svc.from("recovery_attempts").update({ success: true }).eq("id", attemptId);
  }

  // Update last_accessed_at.
  await svc.from("encrypted_snapshots")
    .update({ last_accessed_at: new Date().toISOString() })
    .eq("family_id", familyId)
    .eq("version", snapshotRow.version);

  await writeAuditEvent(familyId, "snapshot_restored", deviceFpHex,
    { version: snapshotRow.version, size_bytes: snapshotRow.size_bytes }).catch(() => {});

  const wrappedKeyHex = typeof snapshotRow.wrapped_key === "string"
    ? snapshotRow.wrapped_key
    : "\\x" + hexFromBytes(new Uint8Array(snapshotRow.wrapped_key));
  const saltHex = typeof snapshotRow.salt === "string"
    ? snapshotRow.salt
    : "\\x" + hexFromBytes(new Uint8Array(snapshotRow.salt));
  const payloadHashHex = typeof snapshotRow.payload_hash === "string"
    ? snapshotRow.payload_hash
    : "\\x" + hexFromBytes(new Uint8Array(snapshotRow.payload_hash));

  return new Response(
    JSON.stringify({
      wrapped_key_b64: base64FromHex(wrappedKeyHex),
      salt_b64: base64FromHex(saltHex),
      key_version: snapshotRow.key_version,
      version: snapshotRow.version,
      payload_b64: base64FromBytes(blobBytes),
      payload_hash_b64: base64FromHex(payloadHashHex),
      family_id: familyId,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
