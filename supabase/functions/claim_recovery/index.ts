// claim_recovery — Phase 3 stub. Returns 503 but emits recovery_attempted audit event.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { writeAuditEvent } from "../_shared/audit.ts";

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
  const body = await req.json().catch(() => null) as { family_id?: string } | null;
  await writeAuditEvent(
    body?.family_id ?? null,
    'recovery_attempted',
    null,
    { phase: 'stub', status: 'not_implemented' },
  ).catch(() => {});
  return new Response(JSON.stringify({ error: "Not yet implemented" }), { status: 503 });
});
