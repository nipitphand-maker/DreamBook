// claim_invite Edge Function — Plan C-2 §5.2.
// Atomic claim: BLAKE2b the code, lock invite row, verify TTL + state,
// insert family_devices + key_distribution, return wrap material.
//
// Auth: caller must be authenticated (anon JWT counts). Body fields:
//   { code: string, device_pub_key: base64 }
// device_fp is derived from auth.uid() so the client cannot impersonate.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { blake2b } from "https://deno.land/x/[email protected]/blake2b.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function normaliseCode(input: string): string {
  return input.replace(/[\s-]/g, "").toUpperCase();
}

function hexFromBytes(b: Uint8Array): string {
  return Array.from(b).map((x) => x.toString(16).padStart(2, "0")).join("");
}

function bytesFromBase64(s: string): Uint8Array {
  const raw = atob(s.replace(/-/g, "+").replace(/_/g, "/"));
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

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

  const body = await req.json().catch(() => null) as
    | { code: string; device_pub_key: string }
    | null;
  if (!body?.code || !body.device_pub_key) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

  const normalised = normaliseCode(body.code);
  const codeHashHex = hexFromBytes(blake2b(new TextEncoder().encode(normalised), 64));

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });

  // Begin atomic claim via SQL function — wrap in a stored procedure for transactionality.
  const { data, error } = await admin.rpc("claim_invite_atomic", {
    p_code_hash: codeHashHex,
    p_device_fp: deviceFpHex,
    p_device_pub_key: bytesFromBase64(body.device_pub_key),
  });

  if (error) {
    if (error.message.includes("404")) return new Response("Not Found", { status: 404 });
    if (error.message.includes("410")) return new Response("Gone", { status: 410 });
    if (error.message.includes("429")) return new Response("Too Many Requests", { status: 429 });
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
