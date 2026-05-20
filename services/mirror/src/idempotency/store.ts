import { sha256Hex } from "@anky/protocol";

export type IdempotencyStatus = "new" | "processing" | "succeeded" | "failed";

export type IdempotencyRecord = {
  key: string;
  status: IdempotencyStatus;
  addressHash: string;
  ankyHash: string;
  updatedAt: number;
};

export type IdempotencyBeginResult =
  | { acquired: true; record: IdempotencyRecord }
  | { acquired: false; record: IdempotencyRecord };

export interface IdempotencyStore {
  begin(input: { key: string; addressHash: string; ankyHash: string; now?: number }): Promise<IdempotencyBeginResult>;
  markSucceeded(key: string, now?: number): Promise<void>;
  markFailed(key: string, now?: number): Promise<void>;
}

export async function mirrorIdempotencyKey(address: string, ankyHash: string): Promise<string> {
  return sha256Hex(`${address}:${ankyHash}`);
}

export class MemoryIdempotencyStore implements IdempotencyStore {
  private records = new Map<string, IdempotencyRecord>();

  async begin(input: { key: string; addressHash: string; ankyHash: string; now?: number }): Promise<IdempotencyBeginResult> {
    const now = input.now ?? Date.now();
    const existing = this.records.get(input.key);
    if (existing?.status === "processing" || existing?.status === "succeeded") {
      return { acquired: false, record: existing };
    }

    const record: IdempotencyRecord = {
      key: input.key,
      status: "processing",
      addressHash: input.addressHash,
      ankyHash: input.ankyHash,
      updatedAt: now,
    };
    this.records.set(input.key, record);
    return { acquired: true, record };
  }

  async markSucceeded(key: string, now = Date.now()): Promise<void> {
    this.update(key, "succeeded", now);
  }

  async markFailed(key: string, now = Date.now()): Promise<void> {
    this.update(key, "failed", now);
  }

  clearForTests(): void {
    this.records.clear();
  }

  private update(key: string, status: IdempotencyStatus, now: number): void {
    const existing = this.records.get(key);
    if (!existing) return;
    this.records.set(key, { ...existing, status, updatedAt: now });
  }
}

export const railwayMemoryIdempotencyStore = new MemoryIdempotencyStore();
