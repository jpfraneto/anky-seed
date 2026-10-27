# Backend Route Auth Table

Generated from the final route registrations on 2026-07-09; Walking Meditation routes added 2026-10-27.

| Route | Auth | Body cap | Rate limits | Durable controls | Stored content |
| --- | --- | --- | --- | --- | --- |
| `GET /health` | Public | N/A | IP window | None | None |
| `POST /anky` | EIP-712 signed `.anky` bytes + active `pro` entitlement (reflection and nudge; else `402 ENTITLEMENT_REQUIRED` before lock/prompt/provider, as real HTTP 402 on the SSE path too) | Streaming `readLimitedBody` | IP burst, account burst, account daily quota | SQLite idempotency by account + terminal artifact hash + intent | Hash, seconds/metadata only; no writing |
| `POST /conversation` | EIP-712 signed JSON + active `pro` entitlement (else `402 ENTITLEMENT_REQUIRED` before quota/prompt/provider) | Streaming `readLimitedBody` | Expensive IP window, authenticated IP + account window, account daily quota | None | None |
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
| `POST /access/status` | EIP-712 signed JSON `{start}` | Streaming `readLimitedBody` | Authenticated IP + account window | `INSERT OR IGNORE` on `free_access_ledger` primary key: one row per account, start never moves | SHA-256(account) + free-access start time only |
| `GET /live/capabilities` | Public | N/A | Public IP window | None | None |
| `POST /live/start` | EIP-712 signed JSON + (`pro` entitlement OR active free access; else 402) | Streaming `readLimitedBody` | Authenticated IP + account window; one active broadcast per account (409) | In-process per-account start lock | Random live id, SHA-256(account), Cloudflare input uid, audience, timestamps; stream key never stored |
| `POST /live/stop` | EIP-712 signed JSON, owner only (404 otherwise) | Streaming `readLimitedBody` | Authenticated IP + account window | Idempotent end; Cloudflare input deleted before the row is marked ended | End timestamp + reason |
| `POST /live/report` | Public | 4 KiB `readLimitedBody` | Strict IP window (5 / 10 min) | One report per (broadcast, IP hash); 3 distinct IPs end the broadcast | Per-broadcast IP hash + reporter-written reason (≤ 500 chars) |
| `POST /debug/live/:liveId/end` | Bearer `ANKY_ADMIN_KEY` | N/A | Hidden by 404 on missing/wrong/unconfigured token | Idempotent end | End reason `admin` |
| `DELETE /account` | EIP-712 signed empty body | N/A | Authenticated IP + account window plus deletion account/IP window | Single SQLite transaction | Deletes all account-scoped rows and this account's live broadcasts/reports (active Cloudflare inputs are ended first). **Retains `free_access_ledger`** (SHA-256(account) + start time, no content) so deletion cannot reset the seven-day free access; disclose in the privacy policy |
| `GET /debug/*` | Bearer `ANKY_ADMIN_KEY` | N/A | Hidden by 404 on missing/wrong/unconfigured token | None | Operator summaries only |
| `POST /debug/distill` | Bearer `ANKY_ADMIN_KEY` | Streaming `readLimitedBody` after token check | Hidden by 404 on missing/wrong/unconfigured token | None | No storage; token counts may log |
| `POST /debug/seed-default-painting` | Bearer `ANKY_ADMIN_KEY` | Streaming `readLimitedBody` after token check | Hidden by 404 on missing/wrong/unconfigured token | In-memory detached seed run guard | Static default painting package |

There is no CORS middleware in the backend. Mobile clients do not need CORS; any future browser client must add an exact-origin allowlist instead of a wildcard.

Signed-route freshness is documented beside `rememberRequest` in `server.ts`: timestamp skew is bounded by `requestTimeToleranceMs`, the `(requestTime, signature)` pair is rejected on replay within that window, and signatures bind the exact body hash, account, request time, and client.
