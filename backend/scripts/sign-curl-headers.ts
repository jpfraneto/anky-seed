import { readFileSync } from "node:fs";
import { signAnkyMirrorRequest } from "@anky/protocol";

const args = Bun.argv.slice(2);

function valueAfter(flag: string): string | undefined {
  const index = args.indexOf(flag);
  if (index < 0) return undefined;
  return args[index + 1];
}

const file = valueAfter("--file");
const text = valueAfter("--text");
const contentType = valueAfter("--content-type") ?? "application/json";
const intent = valueAfter("--intent");
const mnemonic =
  process.env.ANKY_ACCEPTANCE_MNEMONIC ??
  "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

if ((file ? 1 : 0) + (text ? 1 : 0) !== 1) {
  console.error("usage: bun scripts/sign-curl-headers.ts (--file PATH | --text BODY) [--content-type TYPE] [--intent reflection|nudge]");
  process.exit(2);
}

const body = file ? new Uint8Array(readFileSync(file)) : new TextEncoder().encode(text);
const requestTime = String(Date.now());
const signed = await signAnkyMirrorRequest({
  mnemonic,
  chainId: 8453,
  body,
  requestTime,
  client: "other",
});

const headers: Record<string, string> = {
  "Content-Type": contentType,
  "X-Anky-Identity-Version": signed.identity.identityVersion,
  "X-Anky-Account": signed.identity.accountId,
  "X-Anky-Signature-Type": "eip712",
  "X-Anky-Signature": signed.signature,
  "X-Anky-Request-Time": requestTime,
  "X-Anky-Client": "other",
};
if (intent) headers["X-Anky-Intent"] = intent;

for (const [key, value] of Object.entries(headers)) {
  console.log(`-H ${JSON.stringify(`${key}: ${value}`)}`);
}
