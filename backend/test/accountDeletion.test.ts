import { beforeEach, describe, expect, test } from "bun:test";
import { signAnkyMirrorRequest } from "@anky/protocol";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  ankyWorld,
  clearReplayMemoryForTests,
  createApp,
  createSafeLogger,
} from "../server";
import { openLevelDb } from "../level/db";
import { paintingAccountDir } from "../painting/config";

const identityFixtureMnemonic =
  "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

beforeEach(() => {
  clearReplayMemoryForTests();
});

async function signedEmptyHeaders(): Promise<Record<string, string>> {
  const body = new Uint8Array();
  const requestTime = String(Date.now());
  const signed = await signAnkyMirrorRequest({
    mnemonic: identityFixtureMnemonic,
    chainId: 8453,
    body,
    requestTime,
    client: "other",
  });
  return {
    "X-Anky-Identity-Version": signed.identity.identityVersion,
    "X-Anky-Account": signed.identity.accountId,
    "X-Anky-Signature-Type": "eip712",
    "X-Anky-Signature": signed.signature,
    "X-Anky-Request-Time": requestTime,
    "X-Anky-Client": "other",
  };
}

async function fixtureAccountId(): Promise<string> {
  const signed = await signAnkyMirrorRequest({
    mnemonic: identityFixtureMnemonic,
    chainId: 8453,
    body: new Uint8Array(),
    requestTime: "0",
    client: "other",
  });
  return signed.identity.accountId;
}

function accountHash(account: string): string {
  return createHash("sha256").update(account).digest("hex").slice(0, 16);
}

describe("DELETE /account", () => {
  test("deletes every account-scoped table and is idempotent", async () => {
    const db = openLevelDb(":memory:");
    const dataDir = mkdtempSync(join(tmpdir(), "anky-account-delete-"));
    const account = await fixtureAccountId();
    const paintingDirectory = paintingAccountDir(dataDir, account);
    mkdirSync(join(paintingDirectory, "9"), { recursive: true });
    writeFileSync(join(paintingDirectory, "9", "final.png"), "personalized");
    expect(existsSync(paintingDirectory)).toBe(true);

    const app = createApp({
      env: ankyWorld({ dataDir }),
      logger: createSafeLogger({ log() {} }),
      levelDb: db,
    });
    const hash = accountHash(account);
    const now = Date.now();

    db.prepare(
      `INSERT INTO subscription_state (
        account, app_user_id, entitlement_id, product_id, store, period_type,
        expires_at_ms, is_active, environment, last_event_at_ms, updated_at_ms
      ) VALUES (?1, ?1, 'pro', 'anky.annual', 'APP_STORE', 'NORMAL', ?2, 1, 'PRODUCTION', ?3, ?3)`,
    ).run(account, now + 1_000_000, now);
    db.prepare(
      `INSERT INTO session_ledger (account, session_hash, seconds, sealed_at_ms, reported_at_ms)
       VALUES (?1, ?2, 480, ?3, ?3)`,
    ).run(account, "a".repeat(64), now);
    db.prepare(
      `INSERT INTO level_state (account, level, phase, title, scene, threshold_seconds, updated_at_ms)
       VALUES (?1, 2, 'generated', 'title', 'scene', 960, ?2)`,
    ).run(account, now);
    db.prepare(
      `INSERT INTO painting_meta (account, level, title, palette_json, created_at_ms)
       VALUES (?1, 2, 'title', '[]', ?2)`,
    ).run(account, now);
    db.prepare(
      `INSERT INTO generation_log (account, level, provider, kind, ok, cost_usd, detail, created_at_ms)
       VALUES (?1, 2, 'poiesis', 'final', 1, 0.1, 'ok', ?2)`,
    ).run(account, now);
    db.prepare(
      `INSERT INTO funnel_events (account_hash, event, origin, created_at_ms)
       VALUES (?1, 'paywall_shown', 'reflection', ?2)`,
    ).run(hash, now);
    db.prepare(
      `INSERT INTO request_idempotency (key, account, intent, artifact_hash, status, updated_at_ms)
       VALUES ('k', ?1, 'reflection', ?2, 'succeeded', ?3)`,
    ).run(account, "b".repeat(64), now);
    db.prepare(
      `INSERT INTO account_daily_quota (route, account, day_utc, count, updated_at_ms)
       VALUES ('anky', ?1, '2026-07-09', 1, ?2)`,
    ).run(account, now);

    const first = await app.request("/account", {
      method: "DELETE",
      headers: await signedEmptyHeaders(),
    });
    expect(first.status).toBe(200);
    const firstJson = await first.json();
    expect(firstJson.deleted).toBe(true);
    expect(firstJson.counts).toEqual({
      subscription_state: 1,
      session_ledger: 1,
      level_state: 1,
      painting_meta: 1,
      generation_log: 1,
      funnel_events: 1,
      request_idempotency: 1,
      account_daily_quota: 1,
      painting_assets: 1,
    });
    expect(existsSync(paintingDirectory)).toBe(false);

    for (const table of [
      "subscription_state",
      "session_ledger",
      "level_state",
      "painting_meta",
      "generation_log",
      "request_idempotency",
      "account_daily_quota",
    ]) {
      const row = db.prepare(`SELECT COUNT(*) AS count FROM ${table} WHERE account = ?1`).get(account) as { count: number };
      expect(row.count).toBe(0);
    }
    const funnel = db.prepare("SELECT COUNT(*) AS count FROM funnel_events WHERE account_hash = ?1").get(hash) as { count: number };
    expect(funnel.count).toBe(0);

    const second = await app.request("/account", {
      method: "DELETE",
      headers: await signedEmptyHeaders(),
    });
    expect(second.status).toBe(200);
    const secondJson = await second.json();
    expect(Object.values(secondJson.counts)).toEqual(Array(9).fill(0));
    rmSync(dataDir, { recursive: true, force: true });
  });
});
