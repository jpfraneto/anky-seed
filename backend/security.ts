import type { Context } from "hono";

export class BodyTooLargeError extends Error {
  constructor() {
    super("BODY_TOO_LARGE");
  }
}

export async function readLimitedBody(
  c: Context,
  maxBytes: number,
): Promise<Uint8Array> {
  const contentLength = c.req.header("content-length");
  if (contentLength) {
    const parsed = Number(contentLength);
    if (Number.isFinite(parsed) && parsed > maxBytes) {
      throw new BodyTooLargeError();
    }
  }

  const body = c.req.raw.body;
  if (!body) return new Uint8Array();

  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel().catch(() => {});
        throw new BodyTooLargeError();
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const output = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

export function clientIp(c: Context): string {
  const forwarded = c.req.header("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0]?.trim() || "unknown";
  return (
    c.req.header("cf-connecting-ip") ??
    c.req.header("x-real-ip") ??
    "unknown"
  );
}

type WindowEntry = {
  count: number;
  resetAtMs: number;
};

export class MemoryWindowRateLimiter {
  private readonly entries = new Map<string, WindowEntry>();

  constructor(
    private readonly limit: number,
    private readonly windowMs: number,
  ) {}

  check(key: string, nowMs = Date.now()):
    | { allowed: true; remaining: number }
    | { allowed: false; retryAfterSeconds: number } {
    for (const [entryKey, entry] of this.entries) {
      if (entry.resetAtMs <= nowMs) this.entries.delete(entryKey);
    }

    const existing = this.entries.get(key);
    if (!existing || existing.resetAtMs <= nowMs) {
      this.entries.set(key, { count: 1, resetAtMs: nowMs + this.windowMs });
      return { allowed: true, remaining: this.limit - 1 };
    }

    if (existing.count >= this.limit) {
      return {
        allowed: false,
        retryAfterSeconds: Math.max(
          1,
          Math.ceil((existing.resetAtMs - nowMs) / 1000),
        ),
      };
    }

    existing.count += 1;
    return { allowed: true, remaining: this.limit - existing.count };
  }
}

export function rateLimitedResponse(retryAfterSeconds: number): Response {
  return new Response(
    JSON.stringify({
      error: { code: "RATE_LIMITED", message: "Too many requests. Try again soon." },
    }),
    {
      status: 429,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Retry-After": String(retryAfterSeconds),
      },
    },
  );
}

