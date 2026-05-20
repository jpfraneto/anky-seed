import { createApp } from "../../mirror/src";
import { loadEnv } from "../../mirror/src/env";
import type { IdempotencyBeginResult, IdempotencyRecord, IdempotencyStore, IdempotencyStatus } from "../../mirror/src/idempotency/store";

type WorkerEnv = Record<string, unknown> & {
  ANKY_IDEMPOTENCY: DurableObjectNamespace;
};

export class AnkyIdempotencyObject implements DurableObject {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const key = decodeURIComponent(url.pathname.slice(1));
    if (!key) return json({ error: "MISSING_KEY" }, 400);

    if (request.method === "POST" && url.searchParams.get("op") === "begin") {
      const input = await request.json() as { addressHash: string; ankyHash: string; now?: number };
      const existing = await this.state.storage.get<IdempotencyRecord>("record");
      if (existing?.status === "processing" || existing?.status === "succeeded") {
        return json({ acquired: false, record: existing } satisfies IdempotencyBeginResult);
      }
      const record: IdempotencyRecord = {
        key,
        status: "processing",
        addressHash: input.addressHash,
        ankyHash: input.ankyHash,
        updatedAt: input.now ?? Date.now(),
      };
      await this.state.storage.put("record", record);
      return json({ acquired: true, record } satisfies IdempotencyBeginResult);
    }

    if (request.method === "POST" && url.searchParams.get("op") === "status") {
      const input = await request.json() as { status: IdempotencyStatus; now?: number };
      const existing = await this.state.storage.get<IdempotencyRecord>("record");
      if (existing) {
        await this.state.storage.put("record", { ...existing, status: input.status, updatedAt: input.now ?? Date.now() });
      }
      return json({ ok: true });
    }

    return json({ error: "NOT_FOUND" }, 404);
  }
}

class DurableObjectIdempotencyStore implements IdempotencyStore {
  constructor(private readonly binding: DurableObjectNamespace) {}

  async begin(input: { key: string; addressHash: string; ankyHash: string; now?: number }): Promise<IdempotencyBeginResult> {
    const response = await this.stub(input.key).fetch(urlFor(input.key, "begin"), {
      method: "POST",
      body: JSON.stringify({ addressHash: input.addressHash, ankyHash: input.ankyHash, now: input.now }),
    });
    return response.json();
  }

  async markSucceeded(key: string, now?: number): Promise<void> {
    await this.mark(key, "succeeded", now);
  }

  async markFailed(key: string, now?: number): Promise<void> {
    await this.mark(key, "failed", now);
  }

  private async mark(key: string, status: IdempotencyStatus, now?: number): Promise<void> {
    await this.stub(key).fetch(urlFor(key, "status"), {
      method: "POST",
      body: JSON.stringify({ status, now }),
    });
  }

  private stub(key: string): DurableObjectStub {
    return this.binding.get(this.binding.idFromName(key));
  }
}

export default {
  async fetch(request: Request, env: WorkerEnv): Promise<Response> {
    const mirrorEnv = loadEnv(workerEnvToProcessEnv(env));
    return createApp({
      env: mirrorEnv,
      ankyRouteDeps: {
        idempotencyStore: new DurableObjectIdempotencyStore(env.ANKY_IDEMPOTENCY),
      },
    }).fetch(request);
  },
};

function workerEnvToProcessEnv(env: WorkerEnv): NodeJS.ProcessEnv {
  const output: NodeJS.ProcessEnv = {};
  for (const [key, value] of Object.entries(env)) {
    if (typeof value === "string") output[key] = value;
  }
  return output;
}

function urlFor(key: string, op: "begin" | "status"): string {
  return `https://idempotency/${encodeURIComponent(key)}?op=${op}`;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
