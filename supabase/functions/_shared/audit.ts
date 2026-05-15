// _shared/audit.ts — shared audit event writer for all Edge Functions.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export async function writeAuditEvent(
  familyId: string | null,
  eventType: string,
  actorDeviceFp: string | null,
  eventData: Record<string, unknown> = {},
): Promise<void> {
  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const fpHex = actorDeviceFp ? actorDeviceFp.replace(/^\\x/, "") : null;
  const { error } = await admin.from("audit_events").insert({
    family_id: familyId,
    event_type: eventType,
    actor_device_fp: fpHex ? `\\x${fpHex}` : null,
    event_data: eventData,
  });
  if (error) console.warn("[audit] writeAuditEvent failed:", error.message);
}
