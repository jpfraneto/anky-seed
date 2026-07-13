// -----------------------------------------------------------------------------
// Level ledger — the one durable store besides RevenueCat.
//
// The covenant holds here too: this database never sees writing. It keeps
// artifact hashes, seconds, and the painting state machine — nothing else.
// -----------------------------------------------------------------------------

import { Database } from "bun:sqlite";
import { progressInLevel, type LevelProgress } from "@anky/protocol";

export const LEVEL_PHASES = [
  "accumulating",
  "generationPending",
  "generated",
  "ceremonyPending",
  "ceremonyShown",
] as const;

export type LevelPhase = (typeof LEVEL_PHASES)[number];

// A single session can never honestly exceed four hours of writing.
export const MAX_SESSION_SECONDS = 4 * 60 * 60;
export const MAX_SESSIONS_PER_REPORT = 2000;

export type ReportedSession = {
  hash: string;
  seconds: number;
  sealedAtMs: number;
};

export type SessionReportResult = {
  accepted: number;
  duplicate: number;
  rejected: number;
};

export type AccountDeletionCounts = Record<
  | "subscription_state"
  | "session_ledger"
  | "level_state"
  | "painting_meta"
  | "generation_log"
  | "funnel_events"
  | "request_idempotency"
  | "account_daily_quota",
  number
>;

export type LevelStatus = {
  totalSeconds: number;
  level: number;
  secondsIntoLevel: number;
  secondsRequired: number;
  percent: number;
  // The level being earned next; its painting pre-generates while accumulating.
  nextLevel: number;
  nextPaintingPhase: LevelPhase;
  nextPaintingTitle: string | null;
  nextPalette: string[] | null;
  // Lowest level whose painting is generated and owed its unveiling, if any.
  pendingCeremonyLevel: number | null;
};

export function openLevelDb(path: string): Database {
  const db = new Database(path, { create: true });
  db.exec("PRAGMA journal_mode = WAL;");
  migrateSubscriptionStateToRevenueCat(db);
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version TEXT PRIMARY KEY,
      applied_at_ms INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS session_ledger (
      account TEXT NOT NULL,
      session_hash TEXT NOT NULL,
      seconds INTEGER NOT NULL,
      sealed_at_ms INTEGER NOT NULL,
      reported_at_ms INTEGER NOT NULL,
      PRIMARY KEY (account, session_hash)
    );
    CREATE INDEX IF NOT EXISTS idx_session_ledger_account
      ON session_ledger (account);

    CREATE TABLE IF NOT EXISTS level_state (
      account TEXT NOT NULL,
      level INTEGER NOT NULL,
      phase TEXT NOT NULL DEFAULT 'accumulating',
      title TEXT,
      scene TEXT,
      threshold_seconds INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      PRIMARY KEY (account, level)
    );

    CREATE TABLE IF NOT EXISTS painting_meta (
      account TEXT NOT NULL,
      level INTEGER NOT NULL,
      title TEXT NOT NULL,
      palette_json TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      PRIMARY KEY (account, level)
    );

    CREATE TABLE IF NOT EXISTS generation_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      account TEXT NOT NULL,
      level INTEGER NOT NULL,
      provider TEXT NOT NULL,
      kind TEXT NOT NULL,
      ok INTEGER NOT NULL,
      cost_usd REAL,
      detail TEXT,
      created_at_ms INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS subscription_state (
      account TEXT PRIMARY KEY,
      app_user_id TEXT NOT NULL,
      entitlement_id TEXT NOT NULL,
      product_id TEXT,
      store TEXT,
      period_type TEXT,
      -- NULLABLE on purpose: lifetime / open-ended promotional grants are
      -- entitled with no expiration.
      expires_at_ms INTEGER,
      is_active INTEGER NOT NULL DEFAULT 0,
      environment TEXT,
      last_event_at_ms INTEGER NOT NULL DEFAULT 0,
      updated_at_ms INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS revenuecat_events (
      event_id TEXT PRIMARY KEY,
      event_type TEXT NOT NULL,
      received_at_ms INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS funnel_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      account_hash TEXT NOT NULL,
      event TEXT NOT NULL,
      origin TEXT,
      created_at_ms INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_funnel_events_created
      ON funnel_events (created_at_ms);
  `);
  runSchemaMigrations(db);
  return db;
}

const SCHEMA_MIGRATIONS: Array<{ version: string; sql: string }> = [
  {
    version: "20260709_session_ledger_account_sealed_at",
    sql: `
      CREATE INDEX IF NOT EXISTS idx_session_ledger_account_sealed_at
        ON session_ledger (account, sealed_at_ms);
    `,
  },
  {
    version: "20260709_request_idempotency_and_daily_quota",
    sql: `
      CREATE TABLE IF NOT EXISTS request_idempotency (
        key TEXT PRIMARY KEY,
        account TEXT NOT NULL,
        intent TEXT NOT NULL,
        artifact_hash TEXT NOT NULL,
        status TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_request_idempotency_account
        ON request_idempotency (account, updated_at_ms);

      CREATE TABLE IF NOT EXISTS account_daily_quota (
        route TEXT NOT NULL,
        account TEXT NOT NULL,
        day_utc TEXT NOT NULL,
        count INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        PRIMARY KEY (route, account, day_utc)
      );
    `,
  },
];

function runSchemaMigrations(db: Database): void {
  const applied = new Set(
    (db
      .prepare("SELECT version FROM schema_migrations")
      .all() as { version: string }[]).map((row) => row.version),
  );
  const migrate = db.transaction((migration: { version: string; sql: string }) => {
    db.exec(migration.sql);
    db.prepare(
      "INSERT INTO schema_migrations (version, applied_at_ms) VALUES (?1, ?2)",
    ).run(migration.version, Date.now());
  });
  for (const migration of SCHEMA_MIGRATIONS) {
    if (!applied.has(migration.version)) migrate(migration);
  }
}

/**
 * One-time schema migration (2026-07): subscription_state used to hold
 * Apple-JWS-derived columns (original_transaction_id, app_account_token,
 * signed_at_ms). RevenueCat webhooks are entitlement truth now and the
 * table is RevenueCat-shaped. Old rows are not carried over on purpose:
 * state rebuilds from webhooks, /subscription/identify, and the live REST
 * fallback within one app foreground.
 */
function migrateSubscriptionStateToRevenueCat(db: Database): void {
  const columns = db
    .prepare("PRAGMA table_info(subscription_state)")
    .all() as { name: string }[];
  if (columns.some((column) => column.name === "original_transaction_id")) {
    db.exec("DROP INDEX IF EXISTS idx_subscription_original_txn;");
    db.exec("DROP TABLE subscription_state;");
  }
}

const SESSION_HASH_PATTERN = /^[0-9a-f]{64}$/;
// Nothing was sealed before Anky existed; nothing is sealed in the far future.
const MIN_SEALED_AT_MS = Date.UTC(2024, 0, 1);

export function isReportableSession(
  session: ReportedSession,
  nowMs: number,
  toleranceMs: number,
): boolean {
  if (!SESSION_HASH_PATTERN.test(session.hash)) return false;
  if (!Number.isSafeInteger(session.seconds)) return false;
  if (session.seconds < 1 || session.seconds > MAX_SESSION_SECONDS) return false;
  if (!Number.isSafeInteger(session.sealedAtMs)) return false;
  if (session.sealedAtMs < MIN_SEALED_AT_MS) return false;
  if (session.sealedAtMs > nowMs + toleranceMs) return false;
  return true;
}

export function recordSessions(
  db: Database,
  account: string,
  sessions: ReportedSession[],
  nowMs: number,
  toleranceMs: number,
): SessionReportResult {
  const insert = db.prepare(
    `INSERT OR IGNORE INTO session_ledger
       (account, session_hash, seconds, sealed_at_ms, reported_at_ms)
     VALUES (?1, ?2, ?3, ?4, ?5)`,
  );
  let accepted = 0;
  let duplicate = 0;
  let rejected = 0;
  const report = db.transaction(() => {
    for (const session of sessions) {
      if (!isReportableSession(session, nowMs, toleranceMs)) {
        rejected += 1;
        continue;
      }
      const result = insert.run(
        account,
        session.hash,
        session.seconds,
        session.sealedAtMs,
        nowMs,
      );
      if (result.changes > 0) accepted += 1;
      else duplicate += 1;
    }
  });
  report();
  return { accepted, duplicate, rejected };
}

export function totalSecondsFor(db: Database, account: string): number {
  const row = db
    .prepare(
      "SELECT COALESCE(SUM(seconds), 0) AS total FROM session_ledger WHERE account = ?1",
    )
    .get(account) as { total: number };
  return row.total;
}

export function sessionCountSince(
  db: Database,
  account: string,
  sinceSealedAtMs: number,
): number {
  const row = db
    .prepare(
      "SELECT COUNT(*) AS n FROM session_ledger WHERE account = ?1 AND sealed_at_ms >= ?2",
    )
    .get(account, sinceSealedAtMs) as { n: number };
  return row.n;
}

type LevelStateRow = {
  phase: string;
  title: string | null;
  scene: string | null;
  threshold_seconds: number;
};

export function getLevelState(
  db: Database,
  account: string,
  level: number,
): { phase: LevelPhase; title: string | null; scene: string | null } | null {
  const row = db
    .prepare(
      "SELECT phase, title, scene, threshold_seconds FROM level_state WHERE account = ?1 AND level = ?2",
    )
    .get(account, level) as LevelStateRow | null;
  if (!row) return null;
  const phase = LEVEL_PHASES.includes(row.phase as LevelPhase)
    ? (row.phase as LevelPhase)
    : "accumulating";
  return { phase, title: row.title, scene: row.scene };
}

export function setLevelPhase(
  db: Database,
  account: string,
  level: number,
  phase: LevelPhase,
  nowMs: number,
  extras: { title?: string; scene?: string; thresholdSeconds?: number } = {},
): void {
  db.prepare(
    `INSERT INTO level_state (account, level, phase, title, scene, threshold_seconds, updated_at_ms)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
     ON CONFLICT (account, level) DO UPDATE SET
       phase = excluded.phase,
       title = COALESCE(excluded.title, level_state.title),
       scene = COALESCE(excluded.scene, level_state.scene),
       updated_at_ms = excluded.updated_at_ms`,
  ).run(
    account,
    level,
    phase,
    extras.title ?? null,
    extras.scene ?? null,
    extras.thresholdSeconds ?? 0,
    nowMs,
  );
}

export function getPaintingMeta(
  db: Database,
  account: string,
  level: number,
): { title: string; palette: string[] } | null {
  const row = db
    .prepare(
      "SELECT title, palette_json FROM painting_meta WHERE account = ?1 AND level = ?2",
    )
    .get(account, level) as { title: string; palette_json: string } | null;
  if (!row) return null;
  let palette: string[] = [];
  try {
    const parsed = JSON.parse(row.palette_json);
    if (Array.isArray(parsed)) palette = parsed.filter((p) => typeof p === "string");
  } catch {
    palette = [];
  }
  return { title: row.title, palette };
}

/**
 * Server backstop for the state machine: a level-state row tracks the painting
 * that celebrates *reaching* its level. Once the ledger reaches or passes that
 * level, any already-generated painting is owed its unveiling.
 */
export function markOwedCeremonies(
  db: Database,
  account: string,
  reachedLevel: number,
  nowMs: number,
): void {
  db.prepare(
    `UPDATE level_state SET phase = 'ceremonyPending', updated_at_ms = ?3
     WHERE account = ?1 AND level <= ?2 AND phase = 'generated'`,
  ).run(account, reachedLevel, nowMs);
}

export function levelStatusFor(db: Database, account: string): LevelStatus {
  const totalSeconds = totalSecondsFor(db, account);
  const progress: LevelProgress = progressInLevel(totalSeconds);
  const nextLevel = progress.level + 1;
  const nextState = getLevelState(db, account, nextLevel);
  const nextMeta = getPaintingMeta(db, account, nextLevel);
  const owed = db
    .prepare(
      `SELECT level FROM level_state
       WHERE account = ?1 AND level <= ?2 AND phase = 'ceremonyPending'
       ORDER BY level ASC LIMIT 1`,
    )
    .get(account, progress.level) as { level: number } | null;
  return {
    totalSeconds,
    level: progress.level,
    secondsIntoLevel: progress.secondsIntoLevel,
    secondsRequired: progress.secondsRequired,
    percent: progress.percent,
    nextLevel,
    nextPaintingPhase: nextState?.phase ?? "accumulating",
    nextPaintingTitle: nextMeta?.title ?? nextState?.title ?? null,
    nextPalette: nextMeta?.palette ?? null,
    pendingCeremonyLevel: owed?.level ?? null,
  };
}

export function logGeneration(
  db: Database,
  entry: {
    account: string;
    level: number;
    provider: string;
    kind: string;
    ok: boolean;
    costUsd?: number;
    detail?: string;
    nowMs: number;
  },
): void {
  db.prepare(
    `INSERT INTO generation_log (account, level, provider, kind, ok, cost_usd, detail, created_at_ms)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
  ).run(
    entry.account,
    entry.level,
    entry.provider,
    entry.kind,
    entry.ok ? 1 : 0,
    entry.costUsd ?? null,
    entry.detail ?? null,
    entry.nowMs,
  );
}

export type DailyQuotaResult =
  | { allowed: true; remaining: number }
  | { allowed: false; retryAfterSeconds: number };

export function consumeAccountDailyQuota(
  db: Database,
  input: { route: string; account: string; limit: number; nowMs: number },
): DailyQuotaResult {
  const dayUtc = new Date(input.nowMs).toISOString().slice(0, 10);
  const retryAfterSeconds = Math.max(
    1,
    Math.ceil(
      (Date.parse(`${dayUtc}T00:00:00.000Z`) + 24 * 60 * 60 * 1000 - input.nowMs) /
        1000,
    ),
  );
  const current = db
    .prepare(
      `SELECT count FROM account_daily_quota
       WHERE route = ?1 AND account = ?2 AND day_utc = ?3`,
    )
    .get(input.route, input.account, dayUtc) as { count: number } | null;
  if (current && current.count >= input.limit) {
    return { allowed: false, retryAfterSeconds };
  }
  db.prepare(
    `INSERT INTO account_daily_quota (route, account, day_utc, count, updated_at_ms)
     VALUES (?1, ?2, ?3, 1, ?4)
     ON CONFLICT(route, account, day_utc) DO UPDATE SET
       count = account_daily_quota.count + 1,
       updated_at_ms = excluded.updated_at_ms`,
  ).run(input.route, input.account, dayUtc, input.nowMs);
  return { allowed: true, remaining: Math.max(0, input.limit - ((current?.count ?? 0) + 1)) };
}

export function beginRequestIdempotency(
  db: Database,
  input: {
    key: string;
    account: string;
    intent: string;
    artifactHash: string;
    nowMs: number;
  },
): { acquired: true } | { acquired: false; status: string } {
  const existing = db
    .prepare("SELECT status FROM request_idempotency WHERE key = ?1")
    .get(input.key) as { status: string } | null;
  if (existing?.status === "processing" || existing?.status === "succeeded") {
    return { acquired: false, status: existing.status };
  }
  db.prepare(
    `INSERT INTO request_idempotency
       (key, account, intent, artifact_hash, status, updated_at_ms)
     VALUES (?1, ?2, ?3, ?4, 'processing', ?5)
     ON CONFLICT(key) DO UPDATE SET
       status = 'processing',
       updated_at_ms = excluded.updated_at_ms`,
  ).run(input.key, input.account, input.intent, input.artifactHash, input.nowMs);
  return { acquired: true };
}

export function markRequestIdempotency(
  db: Database,
  key: string,
  status: "succeeded" | "failed",
  nowMs: number,
): void {
  db.prepare(
    `UPDATE request_idempotency
     SET status = ?2, updated_at_ms = ?3
     WHERE key = ?1`,
  ).run(key, status, nowMs);
}

export function deleteAccountScopedRows(
  db: Database,
  account: string,
  accountHash: string,
): AccountDeletionCounts {
  const emptyCounts: AccountDeletionCounts = {
    subscription_state: 0,
    session_ledger: 0,
    level_state: 0,
    painting_meta: 0,
    generation_log: 0,
    funnel_events: 0,
    request_idempotency: 0,
    account_daily_quota: 0,
  };
  const tx = db.transaction(() => {
    const counts = { ...emptyCounts };
    counts.subscription_state = db
      .prepare("DELETE FROM subscription_state WHERE account = ?1")
      .run(account).changes;
    counts.session_ledger = db
      .prepare("DELETE FROM session_ledger WHERE account = ?1")
      .run(account).changes;
    counts.level_state = db
      .prepare("DELETE FROM level_state WHERE account = ?1")
      .run(account).changes;
    counts.painting_meta = db
      .prepare("DELETE FROM painting_meta WHERE account = ?1")
      .run(account).changes;
    counts.generation_log = db
      .prepare("DELETE FROM generation_log WHERE account = ?1")
      .run(account).changes;
    counts.funnel_events = db
      .prepare("DELETE FROM funnel_events WHERE account_hash = ?1")
      .run(accountHash).changes;
    counts.request_idempotency = db
      .prepare("DELETE FROM request_idempotency WHERE account = ?1")
      .run(account).changes;
    counts.account_daily_quota = db
      .prepare("DELETE FROM account_daily_quota WHERE account = ?1")
      .run(account).changes;
    return counts;
  });
  return tx();
}
