import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  ankyEip712Domain,
  ankyMirrorRequestTypes,
  baseEoaIdentityFromMnemonic,
  bodySha256Bytes32,
  recoverAnkyMirrorRequestAddress,
  signAnkyMirrorRequest,
  verifyAnkyMirrorRequestSignature,
  type AnkyMirrorRequestMessage,
  type Hex,
} from "../src";

const fixtureRoot = resolve(import.meta.dir, "../../../identity/fixtures");

type IdentityFixture = {
  chainId: number;
  accountId: Hex;
  address: Hex;
  mnemonic: string;
  derivationPath: "m/44'/60'/0'/0/0";
  body: string;
  bodySha256: Hex;
  requestTime: number;
  client: "ios";
  eip712Domain: { name: "Anky"; version: "1"; chainId: number };
  eip712Message: Omit<AnkyMirrorRequestMessage, "requestTime"> & { requestTime: number };
  signature: Hex;
  recoveredAddress: Hex;
};

describe("Base EOA identity fixtures", () => {
  test("derives the fixture address from the public BIP39 test mnemonic", async () => {
    const fixture = await loadFixture("base_eoa_v1_mainnet.json");
    const identity = baseEoaIdentityFromMnemonic(fixture.mnemonic, fixture.chainId);

    expect(identity.derivationPath).toBe(fixture.derivationPath);
    expect(identity.address).toBe(fixture.address);
    expect(identity.accountId).toBe(fixture.accountId);
  });

  test("hashes exact .anky body bytes as a bytes32 EIP-712 value", async () => {
    const fixture = await loadFixture("base_eoa_v1_mainnet.json");

    expect(await bodySha256Bytes32(fixture.body)).toBe(fixture.bodySha256);
    expect(await bodySha256Bytes32(`${fixture.body} `)).not.toBe(fixture.bodySha256);
  });

  test("signs deterministic EIP-712 mirror requests", async () => {
    const fixture = await loadFixture("base_eoa_v1_mainnet.json");
    const signed = await signAnkyMirrorRequest({
      mnemonic: fixture.mnemonic,
      chainId: fixture.chainId,
      body: fixture.body,
      requestTime: fixture.requestTime,
      client: fixture.client,
    });

    expect(ankyEip712Domain(fixture.chainId)).toEqual(fixture.eip712Domain);
    expect(ankyMirrorRequestTypes).toEqual((await rawFixture("base_eoa_v1_mainnet.json")).eip712Types);
    expect({ ...signed.message, requestTime: Number(signed.message.requestTime) }).toEqual(fixture.eip712Message);
    expect(signed.signature).toBe(fixture.signature);
  });

  test("recovers and verifies the fixture signer address", async () => {
    const fixture = await loadFixture("base_eoa_v1_sepolia.json");
    const message = { ...fixture.eip712Message, requestTime: BigInt(fixture.eip712Message.requestTime) };

    await expect(
      recoverAnkyMirrorRequestAddress({
        chainId: fixture.chainId,
        message,
        signature: fixture.signature,
      }),
    ).resolves.toBe(fixture.recoveredAddress);

    await expect(
      verifyAnkyMirrorRequestSignature({
        chainId: fixture.chainId,
        address: fixture.address,
        message,
        signature: fixture.signature,
      }),
    ).resolves.toBe(true);
  });
});

async function loadFixture(name: string): Promise<IdentityFixture> {
  return rawFixture(name) as Promise<IdentityFixture>;
}

async function rawFixture(name: string): Promise<any> {
  return JSON.parse(await readFile(resolve(fixtureRoot, name), "utf8"));
}
