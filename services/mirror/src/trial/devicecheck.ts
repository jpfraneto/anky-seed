import type { Env } from "../env";

type DeviceCheckFetch = (url: string, init: RequestInit) => Promise<Response>;

export type DeviceCheckResult =
  | { ok: true; claimed: boolean }
  | { ok: false; reason: "not_configured" | "invalid_token" | "apple_unavailable" };

export async function queryDeviceCheckTrialBit(input: {
  env: Env;
  token: string;
  fetchImpl?: DeviceCheckFetch;
}): Promise<DeviceCheckResult> {
  const request = await makeDeviceCheckRequest(input.env, input.token);
  if (!request.ok) return request;

  return callAppleDeviceCheck({
    env: input.env,
    path: "query_two_bits",
    body: request.body,
    fetchImpl: input.fetchImpl,
    parse: async (response) => {
      const body = await response.json().catch(() => null);
      return { ok: true, claimed: body?.bit0 === true };
    },
  });
}

export async function markDeviceCheckTrialClaimed(input: {
  env: Env;
  token: string;
  fetchImpl?: DeviceCheckFetch;
}): Promise<{ ok: true } | { ok: false; reason: "not_configured" | "invalid_token" | "apple_unavailable" }> {
  const request = await makeDeviceCheckRequest(input.env, input.token);
  if (!request.ok) return request;

  return callAppleDeviceCheck({
    env: input.env,
    path: "update_two_bits",
    body: {
      ...request.body,
      bit0: true,
      bit1: false,
    },
    fetchImpl: input.fetchImpl,
    parse: async () => ({ ok: true }),
  });
}

async function callAppleDeviceCheck<T>(input: {
  env: Env;
  path: "query_two_bits" | "update_two_bits";
  body: Record<string, unknown>;
  fetchImpl?: DeviceCheckFetch;
  parse(response: Response): Promise<T>;
}): Promise<T | { ok: false; reason: "invalid_token" | "apple_unavailable" }> {
  const fetcher = input.fetchImpl ?? fetch;
  const jwt = await makeAppleJwt(input.env);

  try {
    const response = await fetcher(`${deviceCheckBaseURL(input.env)}/v1/${input.path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input.body),
    });

    if (response.status === 400 || response.status === 401) {
      return { ok: false, reason: "invalid_token" };
    }

    if (!response.ok) {
      return { ok: false, reason: "apple_unavailable" };
    }

    return input.parse(response);
  } catch {
    return { ok: false, reason: "apple_unavailable" };
  }
}

async function makeDeviceCheckRequest(
  env: Env,
  token: string,
): Promise<
  | { ok: true; body: { device_token: string; transaction_id: string; timestamp: number } }
  | { ok: false; reason: "not_configured" | "invalid_token" }
> {
  if (!env.appleDeviceCheckTeamId || !env.appleDeviceCheckKeyId || !env.appleDeviceCheckPrivateKey) {
    return { ok: false, reason: "not_configured" };
  }
  if (!token.trim()) {
    return { ok: false, reason: "invalid_token" };
  }

  return {
    ok: true,
    body: {
      device_token: token,
      transaction_id: crypto.randomUUID(),
      timestamp: Date.now(),
    },
  };
}

async function makeAppleJwt(env: Env): Promise<string> {
  const header = base64UrlJson({ alg: "ES256", kid: env.appleDeviceCheckKeyId });
  const claims = base64UrlJson({
    iss: env.appleDeviceCheckTeamId,
    iat: Math.floor(Date.now() / 1000),
  });
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(env.appleDeviceCheckPrivateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function deviceCheckBaseURL(env: Env): string {
  if (env.appleDeviceCheckEnv === "development") {
    return "https://api.development.devicecheck.apple.com";
  }
  return "https://api.devicecheck.apple.com";
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const normalized = pem
    .replace(/\\n/g, "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}
