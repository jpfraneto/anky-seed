// Phase-3 live proof — run: bun scripts/phase3-live-proof.ts
// Throwaway identity; proves against production:
//   1. POST /events/funnel stores a signed funnel event (200)
//   2. POST /anky for a free account is entitlement-gated (402, no LLM)
//   3. POST /subscription/sync rejects a non-Apple JWS (400)
// Prints status codes and error codes only.

import { english, generateMnemonic } from "viem/accounts";
import { signAnkyMirrorRequest } from "@anky/protocol";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const BASE = process.env.ANKY_LIVE_BASE ?? "https://mirror-production-a23c.up.railway.app";
const mnemonic = generateMnemonic(english);

async function signed(body: Uint8Array, extra: Record<string, string> = {}) {
  const requestTime = String(Date.now());
  const signedPost = await signAnkyMirrorRequest({
    mnemonic,
    chainId: 8453,
    body,
    requestTime,
    client: "other",
  });
  return {
    "X-Anky-Identity-Version": signedPost.identity.identityVersion,
    "X-Anky-Account": signedPost.identity.accountId,
    "X-Anky-Signature-Type": "eip712",
    "X-Anky-Signature": signedPost.signature,
    "X-Anky-Request-Time": requestTime,
    "X-Anky-Client": "other",
    ...extra,
  };
}

// 1. funnel event
{
  const body = new TextEncoder().encode(
    JSON.stringify({ event: "boundary_reached", origin: "live_proof" }),
  );
  const res = await fetch(`${BASE}/events/funnel`, {
    method: "POST",
    headers: await signed(body, { "Content-Type": "application/json" }),
    body,
  });
  console.log("funnel:", res.status, await res.text());
}

// 2. free /anky
{
  const body = await readFile(
    resolve(import.meta.dir, "../../protocol/fixtures/valid-complete.anky"),
  );
  const res = await fetch(`${BASE}/anky`, {
    method: "POST",
    headers: await signed(body, { "Content-Type": "text/plain; charset=utf-8" }),
    body,
  });
  const text = await res.text();
  console.log("anky(free):", res.status, text.slice(0, 200));
}

// 3. sync with junk JWS
{
  const body = new TextEncoder().encode(
    JSON.stringify({ signedTransaction: "aaa.bbb.ccc" }),
  );
  const res = await fetch(`${BASE}/subscription/sync`, {
    method: "POST",
    headers: await signed(body, { "Content-Type": "application/json" }),
    body,
  });
  console.log("sync(junk):", res.status, await res.text());
}
