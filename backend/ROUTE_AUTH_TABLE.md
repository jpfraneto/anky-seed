# Backend Route Auth Table

Generated from the final route registrations on 2026-07-09.

| Route | Auth | Body cap | Rate limits | Durable controls | Stored content |
| --- | --- | --- | --- | --- | --- |
| `GET /health` | Public | N/A | IP window | None | None |
| `POST /anky` | EIP-712 signed `.anky` bytes | Streaming `readLimitedBody` | IP burst, account burst, account daily quota | SQLite idempotency by account + terminal artifact hash + intent | Hash, seconds/metadata only; no writing |
| `POST /level/sessions` | EIP-712 signed JSON | Streaming `readLimitedBody` | Authenticated IP + account window | SQLite ledger idempotency by account + session hash | Hash, seconds, sealed timestamp |
| `GET /level/status` | EIP-712 signed empty body | N/A | Authenticated IP + account window | None | None |
| `POST /level/ceremony-shown` | EIP-712 signed JSON | Streaming `readLimitedBody` | Authenticated IP + account window | Idempotent phase advance | Level phase only |
| `POST /level/prepare` | EIP-712 signed JSON | Streaming `readLimitedBody` | Authenticated IP + account window, prepare IP burst, prepare account burst, prepare account daily quota | SQLite idempotency by account + `level_prepare` + level | Distilled painting metadata and generated assets only; raw text is transient |
| `GET /level/assets/:level/:file` | EIP-712 signed empty body | N/A | Authenticated IP + account window | Owner check for writer-specific paintings | Serves generated asset bytes |
| `POST /events/emergency-unlock` | EIP-712 signed JSON | Streaming `readLimitedBody` | Authenticated IP + account window | None | Hashed account + event metadata |
| `POST /events/funnel` | EIP-712 signed JSON | Streaming `readLimitedBody` | Authenticated IP + account window | None | Hashed account + whitelisted event/origin |
| `POST /subscription/identify` | EIP-712 signed JSON | Streaming `readLimitedBody` | Authenticated IP + account window | RevenueCat refresh | Subscription state only |
| `POST /subscription/sync` | EIP-712 signed JSON | Streaming `readLimitedBody` | Authenticated IP + account window | Deprecated shim, no receipt storage | Subscription response metadata only |
| `POST /webhooks/revenuecat` | Shared `Authorization` secret | Streaming `readLimitedBody` after secret check | IP window after secret check | RevenueCat event-id idempotency | Subscription state and webhook id/type |
| `DELETE /account` | EIP-712 signed empty body | N/A | Authenticated IP + account window plus deletion account/IP window | Single SQLite transaction | Deletes all account-scoped rows |
| `GET /debug/*` | Bearer `ANKY_ADMIN_KEY` | N/A | Hidden by 404 on missing/wrong/unconfigured token | None | Operator summaries only |
| `POST /debug/distill` | Bearer `ANKY_ADMIN_KEY` | Streaming `readLimitedBody` after token check | Hidden by 404 on missing/wrong/unconfigured token | None | No storage; token counts may log |
| `POST /debug/seed-default-painting` | Bearer `ANKY_ADMIN_KEY` | Streaming `readLimitedBody` after token check | Hidden by 404 on missing/wrong/unconfigured token | In-memory detached seed run guard | Static default painting package |

There is no CORS middleware in the backend. Mobile clients do not need CORS; any future browser client must add an exact-origin allowlist instead of a wildcard.

Signed-route freshness is documented beside `rememberRequest` in `server.ts`: timestamp skew is bounded by `requestTimeToleranceMs`, the `(requestTime, signature)` pair is rejected on replay within that window, and signatures bind the exact body hash, account, request time, and client.
