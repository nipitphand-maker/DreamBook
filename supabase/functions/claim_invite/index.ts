// claim_invite Edge Function — Plan C-2 §5.2 (v2: anon key + SECURITY DEFINER RPC).
// Body: { code: string, device_pub_key: base64 }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { blake2b } from "https://esm.sh/blakejs@1.2.1";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

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

// PostgREST expects bytea as \x-prefixed hex string in JSON bodies.
function toByteaHex(b: Uint8Array): string {
  return "\\x" + hexFromBytes(b);
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return new Response("Unauthorized", { status: 401 });
  }

  const body = await req.json().catch(() => null) as
    | { code: string; device_pub_key: string }
    | null;
  if (!body?.code || !body.device_pub_key) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

  const devicePubKey = bytesFromBase64(body.device_pub_key);
  const deviceFp = new Uint8Array(
    await crypto.subtle.digest("SHA-256", devicePubKey),
  ).slice(0, 16);

  const normalised = normaliseCode(body.code);
  const codeHashHex = hexFromBytes(blake2b(new TextEncoder().encode(normalised), undefined, 64));

  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data, error } = await client.rpc("claim_invite_atomic", {
    p_code_hash: codeHashHex,
    p_device_fp: toByteaHex(deviceFp),
    p_device_pub_key: toByteaHex(devicePubKey),
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
