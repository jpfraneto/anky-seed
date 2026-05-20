# Backend

One file matters: [server.ts](server.ts).

It defines public protocol values at the top, exposes `GET /health` and `POST /anky`, verifies Base EIP-712 identity, accepts x402 payment when credits are absent, asks the mirror provider, returns markdown text, and forgets the writing.

```sh
bun install
bun test
bun run typecheck
bun run dev
```

`POST /anky` accepts exact `.anky` UTF-8 bytes:

```txt
Content-Type: text/plain; charset=utf-8
X-Anky-Identity-Version: anky.base.eoa.v1
X-Anky-Account: 0xChecksumAddress
X-Anky-Signature-Type: eip712
X-Anky-Signature: 0x...
X-Anky-Request-Time: <epoch_ms>
X-Anky-Client: ios | android | other
```

When a writer has no available credit, the endpoint stays open through x402:

1. Server returns `402` with `PAYMENT-REQUIRED`.
2. Client signs a payment payload.
3. Client retries with `PAYMENT-SIGNATURE`.
4. Server verifies the payment against the current provider quote, reflects, settles, and returns `PAYMENT-RESPONSE`.

Successful reflections are `text/plain; charset=utf-8` markdown. Error responses are JSON.

Only private integration keys are read from the host:

```txt
OPENROUTER_API_KEY
REVENUECAT_SECRET_KEY
REVENUECAT_PROJECT_ID
APPLE_DEVICECHECK_TEAM_ID
APPLE_DEVICECHECK_KEY_ID
APPLE_DEVICECHECK_PRIVATE_KEY
```
