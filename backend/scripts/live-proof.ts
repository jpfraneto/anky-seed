// -----------------------------------------------------------------------------
// Live pipeline proof — one real end-to-end painting generation against the
// deployed mirror service, exactly as an iOS client would do it:
//   throwaway identity → sync one session → prepare level 2 (sync SSE) →
//   download the 4-file package for inspection.
//
//   bun scripts/live-proof.ts [output-dir]
//
// Talks to the deployed service; costs one real gpt-image-2 generation.
// -----------------------------------------------------------------------------

import { mkdirSync } from "node:fs";
import { english, generateMnemonic } from "viem/accounts";
import { signAnkyMirrorRequest } from "@anky/protocol";

const BASE =
  process.env.PROOF_BASE_URL ?? "https://mirror-production-a23c.up.railway.app";
const outDir = process.argv[2] ?? "./live-proof-package";
mkdirSync(outDir, { recursive: true });

const mnemonic = generateMnemonic(english);
console.log(`throwaway account (mnemonic withheld from logs)`);

async function signed(
  path: string,
  method: "GET" | "POST",
  body: Uint8Array,
): Promise<Response> {
  const requestTime = String(Date.now());
  const signedRequest = await signAnkyMirrorRequest({
    mnemonic,
    chainId: 8453,
    body,
    requestTime,
    client: "other",
  });
  return fetch(`${BASE}${path}`, {
    method,
    headers: {
      ...(method === "POST" ? { "Content-Type": "application/json" } : {}),
      "X-Anky-Identity-Version": signedRequest.identity.identityVersion,
      "X-Anky-Account": signedRequest.identity.accountId,
      "X-Anky-Signature-Type": "eip712",
      "X-Anky-Signature": signedRequest.signature,
      "X-Anky-Request-Time": requestTime,
      "X-Anky-Client": "other",
    },
    ...(method === "POST" ? { body } : {}),
  });
}

// 1. Sync one qualifying session (500s ≥ the 480s level-2 threshold).
const sessionBody = new TextEncoder().encode(
  JSON.stringify({
    sessions: [
      {
        hash: crypto.randomUUID().replaceAll("-", "").padEnd(64, "0"),
        seconds: 500,
        sealedAtMs: Date.now() - 60_000,
      },
    ],
  }),
);
const sessionsRes = await signed("/level/sessions", "POST", sessionBody);
console.log(`POST /level/sessions -> ${sessionsRes.status}`);
console.log(await sessionsRes.text());
if (!sessionsRes.ok) process.exit(1);

// 2. Prepare level 2 asynchronously (the app's pre-generation path), then
//    poll for the package — immune to any proxy dropping long streams.
const text = await Bun.file(
  new URL("../test/fixtures/distill/grief.txt", import.meta.url),
).text();
const prepareBody = new TextEncoder().encode(JSON.stringify({ level: 2, text }));
const prepareRes = await signed("/level/prepare", "POST", prepareBody);
console.log(`POST /level/prepare -> ${prepareRes.status}`);
console.log(await prepareRes.text());
if (prepareRes.status !== 202 && prepareRes.status !== 200) process.exit(1);

const startedAt = Date.now();
let ready = false;
while (Date.now() - startedAt < 8 * 60_000) {
  await new Promise((resolve) => setTimeout(resolve, 15_000));
  const probe = await signed("/level/assets/2/meta.json", "GET", new Uint8Array());
  const elapsed = Math.round((Date.now() - startedAt) / 1000);
  console.log(`poll ${elapsed}s: meta.json -> ${probe.status}`);
  if (probe.ok) {
    ready = true;
    break;
  }
}
if (!ready) {
  console.error("package did not appear within 8 minutes");
  process.exit(1);
}

// 3. Download the package.
for (const file of ["final.png", "underdrawing.png", "revealmap.png", "meta.json"]) {
  const res = await signed(`/level/assets/2/${file}`, "GET", new Uint8Array());
  if (!res.ok) {
    console.error(`GET /level/assets/2/${file} -> ${res.status}`);
    process.exit(1);
  }
  const bytes = new Uint8Array(await res.arrayBuffer());
  await Bun.write(`${outDir}/${file}`, bytes);
  console.log(`saved ${outDir}/${file} (${bytes.byteLength} bytes)`);
}
console.log(`\nmeta.json:`);
console.log(await Bun.file(`${outDir}/meta.json`).text());
