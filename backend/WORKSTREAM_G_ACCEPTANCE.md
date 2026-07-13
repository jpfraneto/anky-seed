# Workstream G Acceptance Demonstrations

These are the production HTTP checks for the hardening pass. Set:

```sh
export BASE_URL="http://127.0.0.1:8080"
export WEBHOOK_SECRET="local-revenuecat-secret"
export ADMIN_KEY="local-admin-key"
```

For signed routes, create fresh EIP-712 headers over the exact body for every request. `scripts/sign-curl-headers.ts` uses `signAnkyMirrorRequest` from `@anky/protocol`; reusing a signature intentionally fails replay protection.

## 1. Burst Rate Limit Returns 429

`/level/prepare` has a per-account burst limit of 4 per 10 minutes and an IP burst limit of 20 per minute. Use a level-9 entitled account with a recent session and fresh signed headers per request:

```sh
BODY='{"level":9,"text":"'"$(printf 'w%.0s' {1..200})"'"}'
for i in 1 2 3 4 5; do
  HEADERS="$(bun scripts/sign-curl-headers.ts --text "$BODY" --content-type application/json)"
  eval "curl -i -sS -X POST '$BASE_URL/level/prepare' $HEADERS --data-binary '$BODY' | sed -n '1,8p'"
done
```

Expected: first allowed requests return `202`/`200`/idempotent status depending on level state; the burst-exceeding request returns `HTTP/1.1 429` with `Retry-After`.

## 2. Daily Quota Returns 429

The prepare daily quota is durable in `account_daily_quota` under route `level_prepare`. Seed or naturally consume 6 same-day prepare attempts, then request one more:

```sh
sqlite3 "$ANKY_DATA_DIR/anky.sqlite" \
  "INSERT INTO account_daily_quota(route, account, day_utc, count, updated_at_ms)
   VALUES('level_prepare', '$ACCOUNT', strftime('%Y-%m-%d','now'), 6, unixepoch()*1000)
   ON CONFLICT(route, account, day_utc) DO UPDATE SET count=6;"

BODY='{"level":9,"text":"'"$(printf 'w%.0s' {1..200})"'"}'
HEADERS="$(bun scripts/sign-curl-headers.ts --text "$BODY" --content-type application/json)"
eval "curl -i -sS -X POST '$BASE_URL/level/prepare' $HEADERS --data-binary '$BODY' | sed -n '1,10p'"
```

Expected: `HTTP/1.1 429`, JSON error `RATE_LIMITED`, and `Retry-After` near seconds until UTC midnight.

## 3. Oversized Body Rejected Before Memory Spike

Every body-reading route uses `readLimitedBody`, which checks `Content-Length` and the streamed byte count before appending each chunk.

```sh
python3 - <<'PY' > /tmp/too-large.anky
print("9" * 1100000)
PY
curl -i -sS -X POST "$BASE_URL/anky" \
  -H "Content-Type: text/plain; charset=utf-8" \
  -H "X-Anky-Signature: placeholder" \
  -H "X-Anky-Request-Time: $(date +%s000)" \
  --data-binary @/tmp/too-large.anky | sed -n '1,10p'
```

Expected: `HTTP/1.1 413` and `BODY_TOO_LARGE`. With a large `Content-Length`, rejection occurs before reading the full body; without it, the stream is cancelled as soon as the byte cap is exceeded.

## 4. Duplicate `(account, hash, intent)` Short-Circuits Before Provider Call

`/anky` persists idempotency in `request_idempotency` keyed by account + terminal artifact hash + intent. Send a valid entitled reflection once, then send the exact same terminalized `.anky` from the same account with a fresh signature:

```sh
BODY_FILE=../protocol/fixtures/valid-complete.anky
HEADERS="$(bun scripts/sign-curl-headers.ts --file "$BODY_FILE" --content-type 'text/plain; charset=utf-8')"
eval "curl -i -sS -X POST '$BASE_URL/anky' $HEADERS --data-binary '@$BODY_FILE' | sed -n '1,12p'"

HEADERS="$(bun scripts/sign-curl-headers.ts --file "$BODY_FILE" --content-type 'text/plain; charset=utf-8')"
eval "curl -i -sS -X POST '$BASE_URL/anky' $HEADERS --data-binary '@$BODY_FILE' | sed -n '1,12p'"
```

Expected: duplicate succeeds by retry path or returns duplicate-in-progress before a provider call. Verify no new provider log/cost row appears for the second call.

`/level/prepare` persists idempotency in `request_idempotency` using account + `level_prepare` + level. A repeated prepare for the same level returns status with `idempotency: "processing"` or `"succeeded"` before `runPaintingPipeline` can start again.

## 5. Webhook Wrong/Missing Secret Rejected Before Body Parsing

```sh
python3 - <<'PY' > /tmp/huge-webhook.json
print('{"event":{"id":"x","type":"INITIAL_PURCHASE"},"padding":"' + ("x" * 2000000) + '"}')
PY

curl -i -sS -X POST "$BASE_URL/webhooks/revenuecat" \
  --data-binary @/tmp/huge-webhook.json | sed -n '1,10p'

curl -i -sS -X POST "$BASE_URL/webhooks/revenuecat" \
  -H "Authorization: wrong" \
  --data-binary @/tmp/huge-webhook.json | sed -n '1,10p'
```

Expected: `401 INVALID_WEBHOOK_AUTH` without needing valid JSON and before body parsing. If `REVENUECAT_WEBHOOK_AUTH` is unset, expected response is `503 WEBHOOK_AUTH_UNCONFIGURED`.

## 6. Restart Preserves Durable Idempotency And Daily Quota

After step 2 or 4, restart the server process and inspect SQLite:

```sh
sqlite3 "$ANKY_DATA_DIR/anky.sqlite" \
  "SELECT route, account, day_utc, count FROM account_daily_quota WHERE route IN ('anky','level_prepare');"
sqlite3 "$ANKY_DATA_DIR/anky.sqlite" \
  "SELECT account, intent, artifact_hash, status FROM request_idempotency ORDER BY updated_at_ms DESC LIMIT 10;"
```

Repeat the same duplicate request and one over-quota request. Expected: same duplicate short-circuit and `429` daily quota after restart, because both controls are SQLite-backed.

## 7. `/debug/*` Returns 404 On Missing/Wrong/Unconfigured Token

```sh
curl -i -sS "$BASE_URL/debug/generations" | sed -n '1,10p'
curl -i -sS "$BASE_URL/debug/generations" -H "Authorization: Bearer wrong" | sed -n '1,10p'
```

Expected: `HTTP/1.1 404` with `{"error":"NOT_FOUND"}`. With `ANKY_ADMIN_KEY` unset, even a bearer value returns the same 404.
