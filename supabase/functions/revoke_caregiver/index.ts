// revoke_caregiver Edge Function — Plan C-3.
// Body: { family_id: uuid, target_device_fp: hex32 }
// Looks up the caller's real device_fp via family_devices (auth_user_id + family match),
// then calls revoke_caregiver_atomic via the service role.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { writeAuditEvent } from "../_shared/audit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function toByteaHex(hex: string): string {
  return "\\x" + hex.replace(/^\\x/, "");
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return new Response("Unauthorized", { status: 401 });

  // Authenticate the caller via their JWT.
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  if (!userData?.user) return new Response("Unauthorized", { status: 401 });

  const body = await req.json().catch(() => null) as {
    family_id: string;
    target_device_fp: string;
  } | null;
  if (!body?.family_id || !body.target_device_fp) return new Response("Bad Request", { status: 400 });
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.family_id)) {
    return new Response("Bad Request", { status: 400 });
  }
  if (!/^[0-9a-f]{32}$/i.test(body.target_device_fp)) {
    return new Response("Bad Request", { status: 400 });
  }

  // Resolve the caller's device_fp within the specified family.
  // Filtering by family_id ensures correctness when a device is in multiple families.
  const { data: callerDevice, error: deviceErr } = await userClient
    .from("family_devices")
    .select("device_fp, family_id")
    .eq("auth_user_id", userData.user.id)
    .eq("family_id", body.family_id)
    .is("revoked_at", null)
    .limit(1)
    .single();

  if (deviceErr || !callerDevice?.device_fp) {
    return new Response("Unauthorized", { status: 401 });
  }

  // PostgREST returns bytea as "\x{hex}" string.
  const callerFpHex = String(callerDevice.device_fp).replace(/^\\x/, "");
  if (!/^[0-9a-f]{32}$/i.test(callerFpHex)) {
    return new Response("Unauthorized", { status: 401 });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data, error } = await admin.rpc("revoke_caregiver_atomic", {
    p_caller_device_fp: toByteaHex(callerFpHex),
    p_target_device_fp: toByteaHex(body.target_device_fp),
    p_family_id: body.family_id,
  });
  if (error) {
    if (error.message.includes("403")) return new Response("Forbidden", { status: 403 });
    if (error.message.includes("404")) return new Response("Not Found", { status: 404 });
    if (error.message.includes("409")) return new Response("Conflict", { status: 409 });
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  await writeAuditEvent(
    body.family_id,
    "device_revoked",
    callerFpHex,
    {
      target_device_fp: body.target_device_fp,
      new_key_version: typeof data === "object" && data !== null
        ? (data as Record<string, unknown>).new_key_version
        : null,
    },
  ).catch(() => {});

  return new Response(JSON.stringify(data), { status: 200, headers: { "Content-Type": "application/json" } });
});
