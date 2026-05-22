// bootstrap_family Edge Function — Plan C-3 (v4: fp computed here, no pgcrypto).
// Body: { device_pub_key: base64 }
// Returns: { family_id: string, device_fp: hex }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

function bytesFromBase64(s: string): Uint8Array {
  const raw = atob(s.replace(/-/g, "+").replace(/_/g, "/"));
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
  if (!authHeader.startsWith("Bearer ")) {
    return new Response("Unauthorized", { status: 401 });
  }

  const body = await req.json().catch(() => null) as { device_pub_key: string } | null;
  if (!body?.device_pub_key) {
    return new Response(JSON.stringify({ error: "missing device_pub_key" }), { status: 400 });
  }

  const devicePubKey = bytesFromBase64(body.device_pub_key);

  // Compute device_fp = SHA-256(pub_key)[0:16] here — no pgcrypto needed in DB.
  const hashBuf = await crypto.subtle.digest("SHA-256", devicePubKey);
  const deviceFpHex = hexFromBytes(new Uint8Array(hashBuf).slice(0, 16));

  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  // Validate that the JWT represents a real Supabase auth user before
  // creating or updating any family record.
  const { data: userData } = await client.auth.getUser();
  if (!userData?.user) return new Response("Unauthorized", { status: 401 });

  const { data, error } = await client.rpc("bootstrap_family_atomic", {
    p_device_fp_hex: deviceFpHex,
    p_device_pub_key: toByteaHex(devicePubKey),
  });

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  return new Response(JSON.stringify(data), {
    status: 201,
    headers: { "Content-Type": "application/json" },
  });
});
