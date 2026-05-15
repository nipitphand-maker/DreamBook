// create_invite Edge Function — Plan C-3 (v4: fp computed here, no pgcrypto).
// Body: { family_id, code_hash (hex), salt (base64), wrapped_key (base64), device_pub_key (base64) }

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

  const body = await req.json().catch(() => null) as {
    family_id: string;
    code_hash: string;
    salt: string;
    wrapped_key: string;
    device_pub_key: string;
  } | null;

  if (!body?.family_id || !body.code_hash || !body.salt || !body.wrapped_key || !body.device_pub_key) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

  const saltBytes = bytesFromBase64(body.salt);
  const wrappedBytes = bytesFromBase64(body.wrapped_key);
  const devicePubKey = bytesFromBase64(body.device_pub_key);

  // Compute device_fp = SHA-256(pub_key)[0:16] — no pgcrypto needed in DB.
  const hashBuf = await crypto.subtle.digest("SHA-256", devicePubKey);
  const deviceFpHex = hexFromBytes(new Uint8Array(hashBuf).slice(0, 16));

  const client = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });

  const { data, error } = await client.rpc("create_invite_fn", {
    p_family_id: body.family_id,
    p_code_hash: body.code_hash,
    p_salt: toByteaHex(saltBytes),
    p_wrapped_key: toByteaHex(wrappedBytes),
    p_device_fp_hex: deviceFpHex,
  });

  if (error) {
    if (error.message.includes("403")) return new Response("Forbidden", { status: 403 });
    if (error.code === "23505") {
      return new Response(JSON.stringify({ error: "code_hash collision" }), { status: 409 });
    }
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  return new Response(JSON.stringify(data), {
    status: 201,
    headers: { "Content-Type": "application/json" },
  });
});
