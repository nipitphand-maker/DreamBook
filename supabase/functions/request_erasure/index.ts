// request_erasure — authenticated admin requests GDPR/PDPA right-to-erasure.
// Deletes storage blobs first, then calls right_to_be_forgotten SQL function
// which removes all database rows for the family.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { writeAuditEvent } from "../_shared/audit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SNAPSHOT_BUCKET = "family-snapshots";

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return new Response("Unauthorized", { status: 401 });

  const body = await req.json().catch(() => null) as { family_id?: string } | null;
  if (!body?.family_id) return new Response(JSON.stringify({ error: "missing family_id" }), { status: 400 });

  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return new Response("Unauthorized", { status: 401 });

  const { data: callerDevice, error: devErr } = await userClient
    .from("family_devices")
    .select("role")
    .eq("auth_user_id", userData.user.id)
    .eq("family_id", body.family_id)
    .eq("role", "admin")
    .is("revoked_at", null)
    .limit(1)
    .maybeSingle();

  if (devErr || !callerDevice) return new Response("Forbidden", { status: 403 });

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // Delete storage blobs BEFORE deleting database rows. The right_to_be_forgotten
  // SQL function removes encrypted_snapshots rows, which contain the storage_path
  // pointers. Deleting storage after DB rows would leave orphaned blobs with no
  // way to enumerate them.
  const { data: snapshots } = await admin
    .from("encrypted_snapshots")
    .select("storage_path")
    .eq("family_id", body.family_id);

  if (snapshots && snapshots.length > 0) {
    const paths = snapshots
      .map((s: { storage_path: string }) => s.storage_path)
      .filter(Boolean);
    if (paths.length > 0) {
      const { error: storageErr } = await admin.storage.from(SNAPSHOT_BUCKET).remove(paths);
      if (storageErr) {
        console.warn("[request_erasure] storage delete failed:", storageErr.message);
        return new Response(JSON.stringify({ error: "storage_delete_failed" }), { status: 500 });
      }
    }
  }

  await writeAuditEvent(
    body.family_id,
    "erasure_requested",
    null,
    { source: "request_erasure_ef", requested_by: userData.user.id },
  ).catch(() => {});

  const { error: eraseErr } = await admin.rpc("right_to_be_forgotten", {
    p_family_id: body.family_id,
  });

  if (eraseErr) {
    return new Response(JSON.stringify({ error: eraseErr.message }), { status: 500 });
  }

  return new Response(JSON.stringify({ erased: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
