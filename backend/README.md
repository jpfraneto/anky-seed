# Backend

One file matters: [server.ts](server.ts).

It defines public protocol values at the top, exposes `GET /health` and `POST /anky`, verifies Base EIP-712 identity, asks the mirror provider, returns markdown text, and forgets the writing.

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

Subscription is required for reflection and painting generation. A non-entitled
account receives `402 ENTITLEMENT_REQUIRED`; the app opens the subscription
paywall and retries only after RevenueCat entitlement syncs.

Successful reflections are `text/plain; charset=utf-8` markdown. Error responses are JSON.

Only private integration keys are read from the host:

```txt
OPENROUTER_API_KEY
REVENUECAT_SECRET_KEY
REVENUECAT_WEBHOOK_AUTH
```
