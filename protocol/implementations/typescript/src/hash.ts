export async function sha256Hex(input: string | Uint8Array): Promise<string> {
  const bytes = new Uint8Array(typeof input === "string" ? new TextEncoder().encode(input) : input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
