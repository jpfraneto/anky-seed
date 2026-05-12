import { describe, expect, test } from "bun:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import bs58 from "bs58";
import { canonicalAnkyPostMessage } from "../src/auth/canonicalMessage";
import { isFreshRequestTime } from "../src/auth/replayProtection";
import { verifySolanaSignature } from "../src/auth/verifySolanaSignature";

describe("signature auth", () => {
  test("constructs the canonical POST /anky message", () => {
    expect(
      canonicalAnkyPostMessage({
        requestTime: "1770000000000",
        bodySha256: "abc123",
      }),
    ).toBe(
      [
        "ANKY_POST_V1",
        "method:POST",
        "path:/anky",
        "request_time:1770000000000",
        "body_sha256:abc123",
      ].join("\n"),
    );
  });

  test("verifies a Solana-compatible Ed25519 signature", () => {
    const secretKey = crypto.getRandomValues(new Uint8Array(32));
    const publicKey = ed25519.getPublicKey(secretKey);
    const message = "ANKY_POST_V1\nmethod:POST\npath:/anky\nrequest_time:1770000000000\nbody_sha256:abc123";
    const signature = ed25519.sign(new TextEncoder().encode(message), secretKey);

    expect(
      verifySolanaSignature({
        publicKey: bs58.encode(publicKey),
        signature: bs58.encode(signature),
        message,
      }),
    ).toBe(true);
  });

  test("rejects stale request times", () => {
    expect(isFreshRequestTime("1000", 300000, 1000)).toBe(true);
    expect(isFreshRequestTime("1000", 300000, 400001)).toBe(false);
  });
});
