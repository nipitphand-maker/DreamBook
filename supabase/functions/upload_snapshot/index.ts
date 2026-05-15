// supabase/functions/upload_snapshot/index.ts
// upload_snapshot — creates an encrypted family snapshot in Supabase Storage.
// Body: {
//   wrapped_key_b64: string,
//   salt_b64: string,
//   key_version: number,
//   payload_b64: string,
//   payload_hash_b64: string,
// }
// Auth: Bearer JWT (authenticated device with active family).
// Returns: { success: true, version: number }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { writeAuditEvent } from "../_shared/audit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MAX_DAILY_UPLOADS = 3;

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
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return new Response("Unauthorized", { status: 401 });

  const body = await req.json().catch(() => null) as {
    wrapped_key_b64: string;
    salt_b64: string;
    key_version: number;
    payload_b64: string;
    payload_hash_b64: string;
  } | null;

  if (!body?.wrapped_key_b64 || !body.salt_b64 || !body.key_version ||
      !body.payload_b64 || !body.payload_hash_b64) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  if (!userData?.user) return new Response("Unauthorized", { status: 401 });

  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  const { data: deviceRow, error: deviceErr } = await userClient
    .from("family_devices")
    .select("family_id, device_fp")
    .eq("auth_user_id", userData.user.id)
    .is("revoked_at", null)
    .limit(1)
    .single();

  if (deviceErr || !deviceRow) {
    return new Response("Device not found in any family", { status: 403 });
  }
  const familyId: string = deviceRow.family_id;
  const deviceFpRaw = deviceRow.device_fp as string;
  const deviceFpHex = deviceFpRaw.startsWith("\\x") ? deviceFpRaw.slice(2) : deviceFpRaw;

  // Rate limit: max 3 uploads per day per family.
  const todayStart = new Date();
  todayStart.setUTCHours(0, 0, 0, 0);
  const { count: todayCount } = await svc
    .from("encrypted_snapshots")
    .select("id", { count: "exact", head: true })
    .eq("family_id", familyId)
    .gte("created_at", todayStart.toISOString());

  if ((todayCount ?? 0) >= MAX_DAILY_UPLOADS) {
    await writeAuditEvent(familyId, "snapshot_uploaded", deviceFpHex,
      { reason: "rate_limited" }).catch(() => {});
    return new Response("Too Many Requests", { status: 429 });
  }

  // Determine next version number.
  const { data: latestRow } = await svc
    .from("encrypted_snapshots")
    .select("version")
    .eq("family_id", familyId)
    .order("version", { ascending: false })
    .limit(1)
    .maybeSingle();
  const nextVersion = (latestRow?.version ?? 0) + 1;

  // Upload blob to Storage.
  const payloadBytes = bytesFromBase64(body.payload_b64);
  const storagePath = `${familyId}/v${nextVersion}.bin`;
  const { error: storageErr } = await svc.storage
    .from("family-snapshots")
    .upload(storagePath, payloadBytes, {
      contentType: "application/octet-stream",
      upsert: false,
    });

  if (storageErr) {
    return new Response(JSON.stringify({ error: storageErr.message }), { status: 500 });
  }

  // Insert metadata.
  const wrappedKey = bytesFromBase64(body.wrapped_key_b64);
  const salt = bytesFromBase64(body.salt_b64);
  const payloadHash = bytesFromBase64(body.payload_hash_b64);

  const { error: insertErr } = await svc.from("encrypted_snapshots").insert({
    family_id: familyId,
    version: nextVersion,
    storage_path: storagePath,
    wrapped_key: toByteaHex(wrappedKey),
    salt: toByteaHex(salt),
    payload_hash: toByteaHex(payloadHash),
    size_bytes: payloadBytes.length,
  });

  if (insertErr) {
    await svc.storage.from("family-snapshots").remove([storagePath]).catch(() => {});
    return new Response(JSON.stringify({ error: insertErr.message }), { status: 500 });
  }

  // Prune: keep only the latest 3 versions.
  const { data: allVersions } = await svc
    .from("encrypted_snapshots")
    .select("version, storage_path")
    .eq("family_id", familyId)
    .order("version", { ascending: false });

  if (allVersions && allVersions.length > 3) {
    const toDelete = allVersions.slice(3);
    const paths = toDelete.map((r: { storage_path: string }) => r.storage_path);
    await svc.storage.from("family-snapshots").remove(paths).catch(() => {});
    await svc.from("encrypted_snapshots")
      .delete()
      .in("version", toDelete.map((r: { version: number }) => r.version))
      .eq("family_id", familyId);
  }

  await writeAuditEvent(familyId, "snapshot_uploaded", deviceFpHex,
    { version: nextVersion, size_bytes: payloadBytes.length }).catch(() => {});

  return new Response(JSON.stringify({ success: true, version: nextVersion }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
