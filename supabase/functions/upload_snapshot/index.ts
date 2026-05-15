// upload_snapshot — Phase 4 stub. Returns 503 but emits snapshot_uploaded audit event.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { writeAuditEvent } from "../_shared/audit.ts";

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
  const body = await req.json().catch(() => null) as { family_id?: string } | null;
  await writeAuditEvent(
    body?.family_id ?? null,
    'snapshot_uploaded',
    null,
    { phase: 'stub', status: 'not_implemented' },
  ).catch(() => {});
  return new Response(JSON.stringify({ error: "Not yet implemented" }), { status: 503 });
});
