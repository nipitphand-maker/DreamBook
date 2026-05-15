// compact_encrypted_rows — cron EF, runs daily. Calls compact_family_versions(family_id)
// for each family. Returns total deleted count.
// TODO: add event_type 'compaction_completed' to audit_events CHECK constraint in next migration cycle.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET")!;

serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== CRON_SECRET) {
    return new Response("Forbidden", { status: 403 });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  const { data: families, error: fetchErr } = await admin
    .from("families")
    .select("id");

  if (fetchErr || !families) {
    return new Response(JSON.stringify({ error: fetchErr?.message }), { status: 500 });
  }

  let totalDeleted = 0;
  for (const family of families) {
    const { data, error } = await admin.rpc("compact_family_versions", {
      p_family_id: family.id,
    });
    if (!error && Array.isArray(data) && data.length > 0) {
      totalDeleted += Number(data[0].deleted_count ?? 0);
    }
  }

  return new Response(JSON.stringify({ total_deleted: totalDeleted, families: families.length }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
