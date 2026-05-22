// cleanup_tombstones — cron EF, runs daily 03:00 UTC.
// Hard-deletes tombstoned rows (deleted_at != null) older than each family's
// tombstone_retention_days setting (default 365 days, per 0040 migration).
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { writeAuditEvent } from "../_shared/audit.ts";

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
    .select("id, tombstone_retention_days");

  if (fetchErr || !families) {
    return new Response(JSON.stringify({ error: fetchErr?.message }), { status: 500 });
  }

  const results: Array<{ family_id: string; purged: number }> = [];

  for (const family of families) {
    const retentionDays: number = family.tombstone_retention_days ?? 90;
    const cutoff = new Date(Date.now() - retentionDays * 86_400_000).toISOString();

    const { error, count } = await admin
      .from("encrypted_rows")
      .delete({ count: "exact" })
      .eq("family_id", family.id)
      .not("deleted_at", "is", null)
      .lt("deleted_at", cutoff);

    const purged = error ? 0 : (count ?? 0);
    results.push({ family_id: family.id, purged });
  }

  const total = results.reduce((s, r) => s + r.purged, 0);

  await writeAuditEvent(null, 'tombstone_purged', null, {
    total_purged: total,
    families_processed: results.length,
  }).catch(() => {});

  return new Response(JSON.stringify({ total_purged: total, families: results }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
