import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { bodySha256Bytes32, signAnkyMirrorRequest } from "@anky/protocol";
import { AnkyAuthError, isFreshRequestTime, verifyAnkyBaseRequest } from "../server";

const fixtureRoot = resolve(import.meta.dir, "../../protocol/identity/fixtures");

describe("Base EIP-712 request auth", () => {
  test("verifies the shared mainnet fixture", async () => {
    const fixture = JSON.parse(await readFile(resolve(fixtureRoot, "base_eoa_v1_mainnet.json"), "utf8"));
    const body = new TextEncoder().encode(fixture.body);
    const identity = await verifyAnkyBaseRequest({
      allowedChainId: 8453,
      bodyBytes: body,
      headers: {
        identityVersion: fixture.identityVersion,
        account: fixture.accountId,
        signatureType: "eip712",
        signature: fixture.signature,
        requestTime: String(fixture.requestTime),
        client: fixture.client,
      },
    });

    expect(await bodySha256Bytes32(body)).toBe(fixture.bodySha256);
    expect(identity.accountId).toBe(fixture.accountId);
    expect(identity.address).toBe(fixture.address);
  });

  test("rejects unsupported identity versions cleanly", async () => {
    const signed = await signAnkyMirrorRequest({
      mnemonic: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      chainId: 8453,
      body: "body",
      requestTime: 1770000000000,
      client: "other",
    });

    await expect(
      verifyAnkyBaseRequest({
        allowedChainId: 8453,
        bodyBytes: new TextEncoder().encode("body"),
        headers: {
          identityVersion: "anky.base.erc1271.v1",
          account: signed.identity.accountId,
          signatureType: "eip712",
          signature: signed.signature,
          requestTime: "1770000000000",
          client: "other",
        },
      }),
    ).rejects.toThrow(new AnkyAuthError("UNSUPPORTED_IDENTITY_VERSION"));
  });

  test("rejects missing required Base identity headers cleanly", async () => {
    const signed = await signAnkyMirrorRequest({
      mnemonic: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      chainId: 8453,
      body: "body",
      requestTime: 1770000000000,
      client: "other",
    });
    const bodyBytes = new TextEncoder().encode("body");

    await expect(
      verifyAnkyBaseRequest({
        allowedChainId: 8453,
        bodyBytes,
        headers: {
          account: signed.identity.accountId,
          signatureType: "eip712",
          signature: signed.signature,
          requestTime: "1770000000000",
          client: "other",
        },
      }),
    ).rejects.toThrow(new AnkyAuthError("MISSING_IDENTITY_VERSION"));

    await expect(
      verifyAnkyBaseRequest({
        allowedChainId: 8453,
        bodyBytes,
        headers: {
          identityVersion: signed.identity.identityVersion,
          signatureType: "eip712",
          signature: signed.signature,
          requestTime: "1770000000000",
          client: "other",
        },
      }),
    ).rejects.toThrow(new AnkyAuthError("MISSING_ACCOUNT"));
  });

  test("rejects non-EIP-712 signature types", async () => {
    const signed = await signAnkyMirrorRequest({
      mnemonic: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      chainId: 8453,
      body: "body",
      requestTime: 1770000000000,
      client: "other",
    });

    await expect(
      verifyAnkyBaseRequest({
        allowedChainId: 8453,
        bodyBytes: new TextEncoder().encode("body"),
        headers: {
          identityVersion: signed.identity.identityVersion,
          account: signed.identity.accountId,
          signatureType: "personal_sign",
          signature: signed.signature,
          requestTime: "1770000000000",
          client: "other",
        },
      }),
    ).rejects.toThrow(new AnkyAuthError("INVALID_SIGNATURE_TYPE"));
  });

  test("rejects stale request times", () => {
    expect(isFreshRequestTime("1000", 300000, 1000)).toBe(true);
    expect(isFreshRequestTime("1000", 300000, 400001)).toBe(false);
  });
});
