// supabase/functions/create_invite/index.test.ts
// Run via: deno test --allow-all supabase/functions/create_invite/index.test.ts
// Requires SUPABASE_URL + SUPABASE_ANON_KEY env vars (from `supabase start`).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// HARD GUARD: these tests create + delete real auth.users rows. They must
// only run against a local `supabase start` instance, never against staging
// or prod. If you really want to run against a non-local URL, set
// ALLOW_NON_LOCAL_TEST=1 (you're on your own).
const isLocal = /^(http:\/\/)?(127\.0\.0\.1|localhost|host\.docker\.internal)(:\d+)?(\/.*)?$/.test(SUPABASE_URL);
if (!isLocal && Deno.env.get("ALLOW_NON_LOCAL_TEST") !== "1") {
  throw new Error(
    `Refusing to run: SUPABASE_URL is not local (${SUPABASE_URL}). ` +
    `Set ALLOW_NON_LOCAL_TEST=1 to override (don't).`
  );
}

const FN_URL = `${SUPABASE_URL}/functions/v1/create_invite`;

async function newAuthUser(email: string): Promise<{ token: string; userId: string }> {
  const c = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await c.auth.signUp({ email, password: "test-pw-12345!" });
  if (error || !data.session || !data.user) {
    throw error ?? new Error("no session — is email confirmation enabled? tests require local stack with autoconfirm on");
  }
  return { token: data.session.access_token, userId: data.user.id };
}

async function deleteAuthUser(userId: string): Promise<void> {
  if (!SERVICE_ROLE_KEY) return; // skip teardown if no service role key in env
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  await admin.auth.admin.deleteUser(userId).catch(() => { /* swallow — best-effort cleanup */ });
}

Deno.test("create_invite rejects non-admin auth user with 401", async () => {
  const { token, userId } = await newAuthUser(`stranger-${crypto.randomUUID()}@example.com`);
  try {
    const res = await fetch(FN_URL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        family_id: crypto.randomUUID(),
        code_hash: "00".repeat(64),
        salt: btoa("salt-16-bytes!!!"),
        wrapped_key: btoa("wrapped-key-payload"),
        device_pub_key: btoa("pub-key-32-bytes-padding-aaaaaaa"),
      }),
    });
    assertEquals(res.status, 401);
    await res.body?.cancel();
  } finally {
    await deleteAuthUser(userId);
  }
});

Deno.test("create_invite rejects request with no Authorization header", async () => {
  const res = await fetch(FN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  assertEquals(res.status, 401);
  await res.body?.cancel();
});
