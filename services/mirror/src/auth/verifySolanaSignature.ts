import { ed25519 } from "@noble/curves/ed25519.js";
import bs58 from "bs58";

export function verifySolanaSignature(input: {
  publicKey: string;
  signature: string;
  message: string;
}): boolean {
  try {
    const publicKeyBytes = bs58.decode(input.publicKey);
    const signatureBytes = decodeSignature(input.signature);
    const messageBytes = new TextEncoder().encode(input.message);

    if (publicKeyBytes.length !== 32 || signatureBytes.length !== 64) return false;
    return ed25519.verify(signatureBytes, messageBytes, publicKeyBytes);
  } catch {
    return false;
  }
}

function decodeSignature(signature: string): Uint8Array {
  try {
    return bs58.decode(signature);
  } catch {
    return Uint8Array.from(Buffer.from(signature, "base64"));
  }
}
