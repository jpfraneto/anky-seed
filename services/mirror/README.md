# ANKY Mirror

Bun + Hono service for the stateless ANKY mirror.

The only app-facing endpoint is `POST /anky`. It accepts the exact `.anky` UTF-8 bytes as `text/plain; charset=utf-8`, verifies the ANKY signature headers, derives the hash/duration/reconstructed text on the server, asks the mirror model, returns JSON, and forgets. It does not store raw `.anky`, reconstructed writing, prompts, or reflections.

## Run Locally

```sh
cd services/mirror
bun install
ANKY_DEV_BYPASS_CREDITS=true ANKY_DEV_MOCK_MIRROR=true bun run dev
```

Health check:

```sh
curl http://127.0.0.1:3000/health
```

Run tests:

```sh
cd services/mirror
bun test
```

## Test POST /anky In Dev Mode

Use the iOS app against:

- Simulator: `http://127.0.0.1:3000`
- iPhone: `http://<your-mac-lan-ip>:3000`

Then complete an 8-minute `.anky`, open Reveal, and tap `Ask Anky`. Dev mode requires both:

```sh
ANKY_DEV_BYPASS_CREDITS=true
ANKY_DEV_MOCK_MIRROR=true
```

The request body remains the exact `.anky` bytes. The dev flags only bypass credits and return a mock reflection.

## Environment

Common:

- `PORT`: Railway-provided port, defaults to `3000`.
- `HOST`: bind host, defaults to `0.0.0.0`.
- `ANKY_ENV`: set to `production` for production guard.
- `NODE_ENV`: production guard also runs when this is `production`.
- `ANKY_MAX_BODY_BYTES`: POST body limit, defaults to `1048576`.
- `REQUEST_TIME_TOLERANCE_MS`: signature freshness window, defaults to `300000`.

Development only:

- `ANKY_DEV_BYPASS_CREDITS=true`
- `ANKY_DEV_MOCK_MIRROR=true`

Production:

- `OPENROUTER_API_KEY`
- `OPENROUTER_MODEL`
- `OPENROUTER_TIMEOUT_MS`, optional, defaults to `45000`.
- `OPENROUTER_PRIVACY_CONFIRMED=true`
- `REVENUECAT_SECRET_KEY`
- `REVENUECAT_PROJECT_ID`

Production startup fails loudly if dev bypass/mock is enabled, OpenRouter config is missing, RevenueCat config is missing, or OpenRouter privacy confirmation is not set. `ANKY_MIRROR_DISABLED=true` is the documented emergency mode that allows health checks without model/credit configuration; it does not make `POST /anky` useful.

OpenRouter privacy note: the adapter does not log prompts or responses. The exact no-data-collection routing flag must be verified against the current OpenRouter account/API configuration before setting `OPENROUTER_PRIVACY_CONFIRMED=true`.

RevenueCat note: RevenueCat is intended to be the credit ledger with public key as customer identity and `publicKey + ankyHash` as the idempotency basis. The adapter is isolated and does not create a custom credit database. Until real spend wiring is completed, production requests without dev bypass will fail closed instead of silently granting credits.

## Railway

The Dockerfile binds the service to `0.0.0.0` and `process.env.PORT`. `GET /health` does not require secrets.

Railway CLI commands:

```sh
railway login
railway link
railway variables set ANKY_ENV=production
railway variables set NODE_ENV=production
railway variables set OPENROUTER_API_KEY=...
railway variables set OPENROUTER_MODEL=...
railway variables set OPENROUTER_PRIVACY_CONFIRMED=true
railway variables set REVENUECAT_SECRET_KEY=...
railway variables set REVENUECAT_PROJECT_ID=...
railway variables set ANKY_DEV_BYPASS_CREDITS=false
railway variables set ANKY_DEV_MOCK_MIRROR=false
railway up
railway domain
```

Verify:

```sh
curl https://<railway-domain>/health
```

Do not commit secrets. Do not enable dev bypass/mock in production.

Current deployment:

```txt
https://mirror-production-a23c.up.railway.app
```

This Railway service is currently deployed in `ANKY_MIRROR_DISABLED=true` mode because the configured OpenRouter and RevenueCat values are placeholders. `/health` is live. `POST /anky` remains fail-closed until real secrets are set and `ANKY_MIRROR_DISABLED=false`.
