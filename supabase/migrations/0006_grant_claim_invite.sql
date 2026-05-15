-- 0006: Grant execute on claim_invite_atomic to anon role.
-- Without this the Edge Function (using anon key) gets 403 when calling the RPC.
GRANT EXECUTE ON FUNCTION public.claim_invite_atomic(TEXT, BYTEA, BYTEA) TO anon;
