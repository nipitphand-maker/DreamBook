import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function hexToUint8Array(hex: string): Uint8Array {
  return Uint8Array.from(hex.match(/.{2}/g)!.map((b) => parseInt(b, 16)));
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return new Response("Unauthorized", { status: 401 });

  const userClient = createClient(SUPABASE_URL, authHeader.replace("Bearer ", ""), {
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  if (!userData?.user) return new Response("Unauthorized", { status: 401 });

  const callerHex = userData.user.id.replace(/-/g, "");
  const body = await req.json().catch(() => null) as { target_device_fp: string } | null;
  if (!body?.target_device_fp) return new Response("Bad Request", { status: 400 });

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data, error } = await admin.rpc("revoke_caregiver_atomic", {
    p_caller_device_fp: hexToUint8Array(callerHex),
    p_target_device_fp: hexToUint8Array(body.target_device_fp),
  });
  if (error) {
    if (error.message.includes("403")) return new Response("Forbidden", { status: 403 });
    if (error.message.includes("404")) return new Response("Not Found", { status: 404 });
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
  return new Response(JSON.stringify(data), { status: 200, headers: { "Content-Type": "application/json" } });
});
