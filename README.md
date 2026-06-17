# ANKY

ANKY is a tiny writing protocol: write for 8 minutes, produce one `.anky` file, ask the mirror once, keep everything local.

The server is not memory. The server is not a journal. The server receives one complete `.anky`, verifies the writer, reflects, returns JSON, and forgets.

## Create A Client

Read [backend/server.ts](backend/server.ts). That file is the protocol in motion.

The client loop is deliberately small:

1. Render a textarea.
2. Capture every text delta as `.anky` lines.
3. End the session when the sum of accepted writing deltas reaches `480000` ms, or when product UX closes a fragment after silence.
   - Completion is based only on accumulated writing deltas.
   - A legacy terminal `8000` line may be parsed for compatibility, but it does not count toward completion and current clients should not append it to active saves.
4. Connect an Ethereum wallet, embedded wallet, or local signer with viem.
5. Sign the EIP-712 `AnkyMirrorRequest` over the exact `.anky` bytes.
6. `POST /anky` with `Content-Type: text/plain; charset=utf-8`.
7. If the server returns `402`, construct an x402 payment from `PAYMENT-REQUIRED` and retry with `PAYMENT-SIGNATURE`.

The public endpoint is:

```txt
https://mirror-production-a23c.up.railway.app/anky
```

The request body is the `.anky` file. There is no JSON wrapper.

## Shape

```txt
anky/
  apps/       clients
  backend/    one Bun/Hono server in server.ts
  docs/       protocol and product law
```

`protocol/` remains as shared fixtures and TypeScript protocol helpers used by the backend and tests.

## Backend

```sh
cd backend
bun install
bun test
bun run typecheck
bun run dev
```

The only app-facing route is:

```txt
POST /anky
```

Health checks use:

```txt
GET /health
```

Public values live at the top of [backend/server.ts](backend/server.ts). The running system has one state: production. The only host-provided values are private keys for model, credit, and Apple DeviceCheck integrations.

## Docs

- [API Contract](docs/API_CONTRACT.md)
- [Product Law](docs/PRODUCT_LAW.md)
- [Technical Law](docs/TECHNICAL_LAW.md)
- [Privacy Covenant](docs/PRIVACY_COVENANT.md)
- [Base Identity Law](docs/BASE_IDENTITY_LAW.md)
