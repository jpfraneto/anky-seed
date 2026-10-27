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

AI is subscriber-only. Reflections, nudges (`POST /anky`), and `POST /conversation`
require an active RevenueCat `pro` entitlement; anything else receives
`402 ENTITLEMENT_REQUIRED` before a prompt is built or a provider is called (a
real HTTP 402 on the `text/event-stream` path too). There is no free inference
lane. Level progression and paintings do not require a subscription.

Successful reflections are `text/plain; charset=utf-8` markdown. Error responses are JSON.

Only private integration keys are read from the host:

```txt
OPENROUTER_API_KEY
REVENUECAT_SECRET_KEY
REVENUECAT_WEBHOOK_AUTH
```

## Walking Meditation backend changes

New routes (contracts in [ROUTE_AUTH_TABLE.md](ROUTE_AUTH_TABLE.md)):

- `POST /access/status {start}` — server-authoritative seven-day free access.
  The ledger (`free_access_ledger`) stores only SHA-256(lowercased account) and
  the start time. **It survives `DELETE /account`** (anti-abuse; otherwise
  deleting the account resets the free week). Disclose this in the privacy
  policy.
- `GET /live/capabilities`, `POST /live/start`, `POST /live/stop`,
  `POST /live/report`, `POST /debug/live/:liveId/end` — livestreaming through
  Cloudflare Stream Live Inputs, available only when configured. Going live
  needs `pro` or active free access. Three distinct-IP reports end a broadcast.
- AI (`/anky`, `/conversation`) now returns `402 ENTITLEMENT_REQUIRED` for
  accounts without `pro`.

New env vars:

```txt
CLOUDFLARE_STREAM_ACCOUNT_ID       # Cloudflare account id
CLOUDFLARE_STREAM_API_TOKEN        # API token with Stream:Edit
CLOUDFLARE_STREAM_CUSTOMER_CODE    # the CODE in customer-CODE.cloudflarestream.com
CLOUDFLARE_STREAM_RECORDING_MODE   # optional: "off" (default) or "automatic"
```

Live is offered (`/live/capabilities` → `available: true`) only when the first
three are set. With recording `off` nothing is recorded, but Cloudflare
documents live HLS/DASH (iframe) playback as a property of `automatic` mode, so
RTMPS broadcasts may not play in the iframe viewer with `off`. WHIP-ingested
broadcasts are watched over WHEP (`whepPlaybackUrl`), never HLS. If you need
the iframe viewer for RTMPS, set `automatic`: the backend then sets
`deleteRecordingAfterDays: 30` (Cloudflare's minimum) as a backstop and deletes
the input's recordings when the broadcast ends.

Deployment steps (human):

1. In Cloudflare: enable Stream on the account, create an API token scoped to
   Stream:Edit, and note the customer subdomain code (Stream dashboard).
2. On Railway (`anky-essential`): set the three `CLOUDFLARE_STREAM_*` vars (and
   optionally `CLOUDFLARE_STREAM_RECORDING_MODE`). The schema migration
   `20261027_free_access_ledger_and_live` runs on boot.
3. Deploy. Check `GET /live/capabilities` returns `{"available": true}`.
4. Verify one real end-to-end broadcast (start → ingest from the app → watch
   `viewerUrl`/`whepPlaybackUrl` → stop → confirm the input is gone in the
   Cloudflare dashboard) before calling livestreaming ready.
5. Ship the iOS build that handles 402 on AI routes **together with or before**
   this deploy: older clients that expected the free reflection lane will see
   `402 ENTITLEMENT_REQUIRED` for non-subscribers.
6. Update the privacy policy: free-access ledger retention after deletion; live
   report reasons and per-broadcast IP hashes; Cloudflare as live processor.
