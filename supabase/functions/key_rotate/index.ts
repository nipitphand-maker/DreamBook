// key_rotate — Phase 3 stub. Accepts key rotation notification from admin device,
// writes key_rotated audit event. Full fan-out handled Dart-side via key_rotation_service.dart.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { writeAuditEvent } from "../_shared/audit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return new Response("Unauthorized", { status: 401 });

  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  if (!userData?.user) return new Response("Unauthorized", { status: 401 });

  const body = await req.json().catch(() => null) as { family_id?: string; new_key_version?: number } | null;
  if (!body?.family_id) return new Response("Bad Request", { status: 400 });

  await writeAuditEvent(
    body.family_id,
    'key_rotated',
    null,
    { new_key_version: body.new_key_version ?? null },
  ).catch(() => {});
  return new Response(JSON.stringify({ ok: true }), { status: 200 });
});
