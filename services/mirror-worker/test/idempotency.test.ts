import { describe, expect, test } from "bun:test";
import { MemoryIdempotencyStore } from "../../mirror/src/idempotency/store";

describe("Worker idempotency contract", () => {
  test("uses processing, succeeded, and failed states without content", async () => {
    const store = new MemoryIdempotencyStore();
    const first = await store.begin({ key: "k", addressHash: "addrhash", ankyHash: "ankyhash", now: 1 });
    const duplicate = await store.begin({ key: "k", addressHash: "addrhash", ankyHash: "ankyhash", now: 2 });
    await store.markFailed("k", 3);
    const retry = await store.begin({ key: "k", addressHash: "addrhash", ankyHash: "ankyhash", now: 4 });
    await store.markSucceeded("k", 5);
    const completedDuplicate = await store.begin({ key: "k", addressHash: "addrhash", ankyHash: "ankyhash", now: 6 });

    expect(first.acquired).toBe(true);
    expect(duplicate.acquired).toBe(false);
    expect(retry.acquired).toBe(true);
    expect(completedDuplicate.acquired).toBe(false);
    expect(completedDuplicate.record).toMatchObject({ status: "succeeded", addressHash: "addrhash", ankyHash: "ankyhash" });
    expect(JSON.stringify(completedDuplicate.record)).not.toContain("writing");
    expect(JSON.stringify(completedDuplicate.record)).not.toContain("reflection");
  });
});
