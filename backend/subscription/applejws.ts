// -----------------------------------------------------------------------------
// Apple JWS verification — StoreKit 2 signed transactions and App Store Server
// Notifications V2 both arrive as compact JWS whose x5c header carries the
// certificate chain. We verify the chain down to the pinned Apple Root CA-G3
// (embedded below so no deploy step can drop it), check Apple's marker OIDs,
// and verify the ES256 signature with the leaf key. No writing, no identity —
// this module only ever sees Apple-signed receipts.
//
// This is the covenant's shape too: the server learns *that* a subscription
// exists and when it ends. It never learns what was written to earn it.
// -----------------------------------------------------------------------------

import { X509Certificate } from "node:crypto";

// Apple Root CA - G3, DER, sha256
// 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
// https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
const APPLE_ROOT_CA_G3_B64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

// Marker OIDs Apple places in its App Store signing chain (DER-encoded,
// including the 0x06 tag), mirroring apple/app-store-server-library.
// Leaf: 1.2.840.113635.100.6.11.1 — "receipt signing"
const LEAF_MARKER_OID = Uint8Array.from([
  0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x0b, 0x01,
]);
// Intermediate: 1.2.840.113635.100.6.2.1 — "Apple WWDR intermediate"
const INTERMEDIATE_MARKER_OID = Uint8Array.from([
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x02, 0x01,
]);

export type AppleJwsVerifyOptions = {
  // Test seam: replaces the pinned Apple root (never used in production).
  pinnedRootDerBase64?: string;
  // Test seam: skip the marker-OID checks for locally minted chains.
  requireMarkerOids?: boolean;
  // Verified against payload.signedDate; defaults to now.
  atMs?: number;
};

export type AppleJwsResult =
  | { ok: true; payload: Record<string, unknown> }
  | { ok: false; reason: string };

function base64UrlDecode(part: string): Uint8Array {
  const padded = part.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(Buffer.from(padded, "base64"));
}

function containsBytes(haystack: Uint8Array, needle: Uint8Array): boolean {
  outer: for (let i = 0; i + needle.length <= haystack.length; i += 1) {
    for (let j = 0; j < needle.length; j += 1) {
      if (haystack[i + j] !== needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

function certValidAt(cert: X509Certificate, atMs: number): boolean {
  const from = Date.parse(cert.validFrom);
  const to = Date.parse(cert.validTo);
  if (!Number.isFinite(from) || !Number.isFinite(to)) return false;
  return from <= atMs && atMs <= to;
}

/**
 * Verifies an Apple compact JWS (transaction, renewal info, or notification
 * envelope) and returns its decoded payload. The chain in the x5c header must
 * terminate at the pinned Apple Root CA-G3 byte-for-byte.
 */
export async function verifyAppleJws(
  jws: string,
  options: AppleJwsVerifyOptions = {},
): Promise<AppleJwsResult> {
  const parts = jws.split(".");
  if (parts.length !== 3) return { ok: false, reason: "MALFORMED_JWS" };
  const [headerPart, payloadPart, signaturePart] = parts;

  let header: { alg?: unknown; x5c?: unknown };
  let payload: Record<string, unknown>;
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlDecode(headerPart)));
    payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(payloadPart)));
  } catch {
    return { ok: false, reason: "MALFORMED_JWS" };
  }
  if (header.alg !== "ES256") return { ok: false, reason: "UNSUPPORTED_ALG" };
  if (!Array.isArray(header.x5c) || header.x5c.length < 2) {
    return { ok: false, reason: "MISSING_CHAIN" };
  }

  let chain: X509Certificate[];
  try {
    chain = header.x5c.map(
      (der) => new X509Certificate(Buffer.from(String(der), "base64")),
    );
  } catch {
    return { ok: false, reason: "MALFORMED_CERTIFICATE" };
  }

  // Every certificate must be signed by the next one in the chain.
  for (let i = 0; i < chain.length - 1; i += 1) {
    if (!chain[i].verify(chain[i + 1].publicKey)) {
      return { ok: false, reason: "BROKEN_CHAIN" };
    }
  }

  // The chain must end at the pinned Apple root, byte-for-byte.
  const pinnedRoot = Buffer.from(
    options.pinnedRootDerBase64 ?? APPLE_ROOT_CA_G3_B64,
    "base64",
  );
  const presentedRoot = chain[chain.length - 1].raw;
  if (!pinnedRoot.equals(presentedRoot)) {
    return { ok: false, reason: "UNTRUSTED_ROOT" };
  }

  // Validity is checked at Apple's signing time, not receipt time, so old
  // transactions signed with since-rotated certificates still verify.
  const signedDate =
    typeof payload.signedDate === "number" ? payload.signedDate : undefined;
  const atMs = signedDate ?? options.atMs ?? Date.now();
  for (const cert of chain) {
    if (!certValidAt(cert, atMs)) {
      return { ok: false, reason: "CERTIFICATE_EXPIRED" };
    }
  }

  if (options.requireMarkerOids ?? true) {
    if (!containsBytes(new Uint8Array(chain[0].raw), LEAF_MARKER_OID)) {
      return { ok: false, reason: "WRONG_LEAF_CERTIFICATE" };
    }
    if (
      !containsBytes(new Uint8Array(chain[1].raw), INTERMEDIATE_MARKER_OID)
    ) {
      return { ok: false, reason: "WRONG_INTERMEDIATE_CERTIFICATE" };
    }
  }

  // ES256 signature over "header.payload" with the leaf key. JWS signatures
  // are raw r||s, which is exactly what WebCrypto ECDSA expects.
  const spki = chain[0].publicKey.export({ type: "spki", format: "der" });
  let verified = false;
  try {
    const key = await crypto.subtle.importKey(
      "spki",
      spki,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    const signature = base64UrlDecode(signaturePart);
    verified = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      signature.buffer as ArrayBuffer,
      new TextEncoder().encode(`${headerPart}.${payloadPart}`),
    );
  } catch {
    return { ok: false, reason: "INVALID_SIGNATURE" };
  }
  if (!verified) return { ok: false, reason: "INVALID_SIGNATURE" };

  return { ok: true, payload };
}

// --- Decoded payload shapes (the fields we actually read) -------------------

export type AppleTransactionPayload = {
  bundleId?: string;
  productId?: string;
  originalTransactionId?: string;
  transactionId?: string;
  purchaseDate?: number;
  expiresDate?: number;
  signedDate?: number;
  revocationDate?: number;
  revocationReason?: number;
  offerType?: number; // 1 = introductory (the 3-day trial)
  appAccountToken?: string;
  environment?: string; // "Production" | "Sandbox"
  type?: string;
};

export type AppleRenewalInfoPayload = {
  originalTransactionId?: string;
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
  environment?: string;
};

export type AppleNotificationPayload = {
  notificationType?: string;
  subtype?: string;
  notificationUUID?: string;
  signedDate?: number;
  data?: {
    bundleId?: string;
    environment?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
};
