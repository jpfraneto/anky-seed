import { getAddress, recoverTypedDataAddress, verifyTypedData } from "viem";
import { mnemonicToAccount } from "viem/accounts";
import { sha256Hex } from "./hash";

export const ANKY_BASE_EOA_IDENTITY_VERSION = "anky.base.eoa.v1" as const;
export const ANKY_BASE_ERC1271_IDENTITY_VERSION = "anky.base.erc1271.v1" as const;
export const ANKY_BASE_MAINNET_CHAIN_ID = 8453;
export const ANKY_BASE_SEPOLIA_CHAIN_ID = 84532;
export const ANKY_BASE_DERIVATION_PATH = "m/44'/60'/0'/0/0";

export type AnkyIdentityVersion = typeof ANKY_BASE_EOA_IDENTITY_VERSION;
export type FutureAnkyIdentityVersion = typeof ANKY_BASE_ERC1271_IDENTITY_VERSION;
export type AnkyAccountKind = "eoa";
export type FutureAnkyAccountKind = "erc1271";
export type Hex = `0x${string}`;
export type AnkyClient = "ios" | "android" | "other";

export type BaseAccountIdentity = {
  identityVersion: AnkyIdentityVersion;
  accountKind: AnkyAccountKind;
  chainId: number;
  accountId: Hex;
  address: Hex;
  signingScheme: "eip712";
  curve: "secp256k1";
  recovery: "bip39-english-12-word";
  derivationPath: typeof ANKY_BASE_DERIVATION_PATH;
};

export type AnkyMirrorRequestMessage = {
  identityVersion: AnkyIdentityVersion;
  account: Hex;
  method: "POST";
  path: "/anky";
  bodyHash: Hex;
  requestTime: bigint;
  client: AnkyClient;
};

export const ankyMirrorRequestTypes = {
  AnkyMirrorRequest: [
    { name: "identityVersion", type: "string" },
    { name: "account", type: "address" },
    { name: "method", type: "string" },
    { name: "path", type: "string" },
    { name: "bodyHash", type: "bytes32" },
    { name: "requestTime", type: "uint64" },
    { name: "client", type: "string" },
  ],
} as const;

export function baseEoaIdentityFromMnemonic(
  mnemonic: string,
  chainId = ANKY_BASE_MAINNET_CHAIN_ID,
): BaseAccountIdentity {
  const account = mnemonicToAccount(mnemonic, { path: ANKY_BASE_DERIVATION_PATH });
  const address = getAddress(account.address) as Hex;
  return {
    identityVersion: ANKY_BASE_EOA_IDENTITY_VERSION,
    accountKind: "eoa",
    chainId,
    accountId: accountIdFor(chainId, address),
    address,
    signingScheme: "eip712",
    curve: "secp256k1",
    recovery: "bip39-english-12-word",
    derivationPath: ANKY_BASE_DERIVATION_PATH,
  };
}

export function accountIdFor(chainId: number, address: string): Hex {
  void chainId;
  return getAddress(address) as Hex;
}

export function parseBaseAccountId(accountId: string): { chainId: number; address: Hex; accountId: Hex } {
  if (/^eip155:/i.test(accountId) || !/^0x[0-9a-fA-F]{40}$/.test(accountId)) {
    throw new Error("INVALID_ACCOUNT");
  }

  const address = getAddress(accountId) as Hex;
  return { chainId: ANKY_BASE_MAINNET_CHAIN_ID, address, accountId: address };
}

export async function bodySha256Bytes32(body: string | Uint8Array): Promise<Hex> {
  return `0x${await sha256Hex(body)}`;
}

export function ankyEip712Domain(chainId: number) {
  return {
    name: "Anky",
    version: "1",
    chainId,
  } as const;
}

export function ankyMirrorRequestMessage(input: {
  identityVersion?: AnkyIdentityVersion;
  address: string;
  bodyHash: Hex;
  requestTime: bigint | number | string;
  client: AnkyClient;
}): AnkyMirrorRequestMessage {
  return {
    identityVersion: input.identityVersion ?? ANKY_BASE_EOA_IDENTITY_VERSION,
    account: getAddress(input.address) as Hex,
    method: "POST",
    path: "/anky",
    bodyHash: input.bodyHash,
    requestTime: BigInt(input.requestTime),
    client: input.client,
  };
}

export async function signAnkyMirrorRequest(input: {
  mnemonic: string;
  chainId: number;
  body: string | Uint8Array;
  requestTime: bigint | number | string;
  client: AnkyClient;
}): Promise<{ identity: BaseAccountIdentity; bodyHash: Hex; signature: Hex; message: AnkyMirrorRequestMessage }> {
  const account = mnemonicToAccount(input.mnemonic, { path: ANKY_BASE_DERIVATION_PATH });
  const identity = baseEoaIdentityFromMnemonic(input.mnemonic, input.chainId);
  const bodyHash = await bodySha256Bytes32(input.body);
  const message = ankyMirrorRequestMessage({
    address: identity.address,
    bodyHash,
    requestTime: input.requestTime,
    client: input.client,
  });
  const signature = await account.signTypedData({
    domain: ankyEip712Domain(input.chainId),
    types: ankyMirrorRequestTypes,
    primaryType: "AnkyMirrorRequest",
    message,
  });
  return { identity, bodyHash, signature, message };
}

export async function recoverAnkyMirrorRequestAddress(input: {
  chainId: number;
  message: AnkyMirrorRequestMessage;
  signature: Hex;
}): Promise<Hex> {
  return getAddress(
    await recoverTypedDataAddress({
      domain: ankyEip712Domain(input.chainId),
      types: ankyMirrorRequestTypes,
      primaryType: "AnkyMirrorRequest",
      message: input.message,
      signature: input.signature,
    }),
  ) as Hex;
}

export async function verifyAnkyMirrorRequestSignature(input: {
  chainId: number;
  address: Hex;
  message: AnkyMirrorRequestMessage;
  signature: Hex;
}): Promise<boolean> {
  return verifyTypedData({
    address: input.address,
    domain: ankyEip712Domain(input.chainId),
    types: ankyMirrorRequestTypes,
    primaryType: "AnkyMirrorRequest",
    message: input.message,
    signature: input.signature,
  });
}
