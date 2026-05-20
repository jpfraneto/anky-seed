import {
  ANKY_BASE_EOA_IDENTITY_VERSION,
  ankyMirrorRequestMessage,
  bodySha256Bytes32,
  parseBaseAccountId,
  verifyAnkyMirrorRequestSignature,
  type AnkyClient,
  type Hex,
} from "@anky/protocol";
import type { ErrorCode } from "../errors";

export type VerifiedAnkyIdentity = {
  identityVersion: typeof ANKY_BASE_EOA_IDENTITY_VERSION;
  accountKind: "eoa";
  chainId: number;
  address: Hex;
  accountId: Hex;
  requestTime: string;
  client: AnkyClient;
  signature: Hex;
};

export type FutureErc1271Verifier = {
  identityVersion: "anky.base.erc1271.v1";
  accountKind: "erc1271";
  verifyTypedDataDigest(input: {
    chainId: number;
    account: Hex;
    digest: Hex;
    signature: Hex;
  }): Promise<boolean>;
};

export type AnkyAuthHeaders = {
  identityVersion?: string;
  account?: string;
  signatureType?: string;
  signature?: string;
  requestTime?: string;
  client?: string;
};

export class AnkyAuthError extends Error {
  constructor(readonly code: ErrorCode) {
    super(code);
  }
}

export async function verifyAnkyBaseRequest(input: {
  headers: AnkyAuthHeaders;
  bodyBytes: Uint8Array;
  allowedChainId: number;
}): Promise<VerifiedAnkyIdentity> {
  const { headers } = input;

  if (![8453, 84532].includes(input.allowedChainId)) {
    throw new AnkyAuthError("UNSUPPORTED_CHAIN");
  }

  if (!headers.identityVersion) throw new AnkyAuthError("MISSING_IDENTITY_VERSION");
  if (headers.identityVersion !== ANKY_BASE_EOA_IDENTITY_VERSION) {
    throw new AnkyAuthError("UNSUPPORTED_IDENTITY_VERSION");
  }
  if (!headers.account) throw new AnkyAuthError("MISSING_ACCOUNT");
  if (!headers.signature) throw new AnkyAuthError("MISSING_SIGNATURE");
  if (!headers.requestTime) throw new AnkyAuthError("MISSING_SIGNATURE");
  if (!headers.client) throw new AnkyAuthError("MISSING_SIGNATURE");
  if (headers.signatureType !== "eip712") throw new AnkyAuthError("INVALID_SIGNATURE_TYPE");
  if (!isKnownClient(headers.client)) throw new AnkyAuthError("INVALID_SIGNATURE");
  if (!/^0x[0-9a-fA-F]+$/.test(headers.signature)) throw new AnkyAuthError("INVALID_SIGNATURE");

  let parsed: ReturnType<typeof parseBaseAccountId>;
  try {
    parsed = parseBaseAccountId(headers.account);
  } catch {
    throw new AnkyAuthError("INVALID_ACCOUNT");
  }

  const bodyHash = await bodySha256Bytes32(input.bodyBytes);
  const message = ankyMirrorRequestMessage({
    address: parsed.address,
    bodyHash,
    requestTime: headers.requestTime,
    client: headers.client,
  });

  const ok = await verifyAnkyMirrorRequestSignature({
    chainId: input.allowedChainId,
    address: parsed.address,
    message,
    signature: headers.signature as Hex,
  });

  if (!ok) throw new AnkyAuthError("INVALID_SIGNATURE");

  return {
    identityVersion: ANKY_BASE_EOA_IDENTITY_VERSION,
    accountKind: "eoa",
    chainId: input.allowedChainId,
    address: parsed.address,
    accountId: parsed.accountId,
    requestTime: headers.requestTime,
    client: headers.client,
    signature: headers.signature as Hex,
  };
}

function isKnownClient(client: string): client is AnkyClient {
  return ["ios", "android", "other"].includes(client);
}
