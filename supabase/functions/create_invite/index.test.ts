// supabase/functions/create_invite/index.test.ts
// Run via: deno test --allow-all supabase/functions/create_invite/index.test.ts
// Requires SUPABASE_URL + SUPABASE_ANON_KEY env vars (from `supabase start`).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const FN_URL = `${SUPABASE_URL}/functions/v1/create_invite`;

async function newAuthUser(email: string): Promise<string> {
  const c = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await c.auth.signUp({ email, password: "test-pw-12345!" });
  if (error || !data.session) throw error ?? new Error("no session");
  return data.session.access_token;
}

Deno.test("create_invite rejects non-admin auth user with 401", async () => {
  const token = await newAuthUser(`stranger-${crypto.randomUUID()}@example.com`);
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
