export async function accountIdHash(accountId: string): Promise<string> {
  return shortHash(accountId);
}

export async function addressHash(address: string): Promise<string> {
  return shortHash(address);
}

export async function shortHash(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16);
}

export function normalizeMetadataValue(value: string | undefined, maxLength = 64): string | undefined {
  if (!value) return undefined;

  const normalized = [...value]
    .slice(0, maxLength)
    .map((character) => (/[A-Za-z0-9._\-+()]/.test(character) ? character : "_"))
    .join("");

  return normalized.length > 0 ? normalized : undefined;
}
