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

The root `.env.example` is the only committed environment template for this repo. Keep the real root `.env` local/uncommitted and set production values through Railway variables; the mirror service should not carry a separate subfolder env file.

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
- `REVENUECAT_CREDIT_CODE`, defaults to `CRD`.
- `ANKY_AUTO_TRIAL_ENABLED=false`, safe default.
- `ANKY_TRIAL_CREDITS=8`.
- `ANKY_IOS_TRIAL_ENABLED=false`, safe default.
- `ANKY_IOS_DEVICECHECK_REQUIRED=true`, safe default.
- `APPLE_DEVICECHECK_TEAM_ID`, required only when iOS automatic trials are enabled and DeviceCheck is required.
- `APPLE_DEVICECHECK_KEY_ID`, required only when iOS automatic trials are enabled and DeviceCheck is required.
- `APPLE_DEVICECHECK_PRIVATE_KEY`, required only when iOS automatic trials are enabled and DeviceCheck is required.
- `APPLE_DEVICECHECK_ENV=production`, or `development` for sandbox testing.
- `ANKY_ANDROID_TRIAL_ENABLED=false`; keep disabled until Play Integrity/device recall is implemented.
- `ANKY_ANDROID_PLAY_INTEGRITY_REQUIRED=true`.

Production startup fails loudly if dev bypass/mock is enabled, OpenRouter config is missing, RevenueCat config is missing, OpenRouter privacy confirmation is not set, iOS trials require DeviceCheck but Apple credentials are missing, or Android trials are enabled before Play Integrity/device recall exists. `ANKY_MIRROR_DISABLED=true` is the documented emergency mode that allows health checks without model/credit configuration; it does not make `POST /anky` useful.

OpenRouter privacy note: the adapter does not log prompts or responses. The exact no-data-collection routing flag must be verified against the current OpenRouter account/API configuration before setting `OPENROUTER_PRIVACY_CONFIRMED=true`.

RevenueCat note: RevenueCat is the credit ledger with public key as customer identity. Reflection spend, trial grant, and refund all use server-derived idempotency keys and safe references that never include writing, prompts, reflections, private keys, seed phrases, or raw DeviceCheck tokens. The adapter is isolated and does not create a custom credit database.

Automatic iOS trial ordering is fail-closed and database-free:

1. Validate the signed `POST /anky` request and complete `.anky`.
2. Read RevenueCat balance.
3. If balance is zero or unknown and iOS trial is enabled, query DeviceCheck bit 0.
4. If bit 0 is unclaimed, mark bit 0 claimed.
5. Grant `ANKY_TRIAL_CREDITS` in RevenueCat.
6. Spend one reflection credit.
7. Only then call the model.

If DeviceCheck marking succeeds but RevenueCat grant fails, the device may need support/manual credit help. The server does not create a local trial database to paper over that edge case.

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
railway variables set REVENUECAT_CREDIT_CODE=CRD
railway variables set ANKY_AUTO_TRIAL_ENABLED=false
railway variables set ANKY_IOS_TRIAL_ENABLED=false
railway variables set ANKY_ANDROID_TRIAL_ENABLED=false
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

## Manual QA

iOS real-device automatic trial QA:

1. Configure RevenueCat env: `REVENUECAT_SECRET_KEY`, `REVENUECAT_PROJECT_ID`, `REVENUECAT_CREDIT_CODE=CRD`.
2. Configure trial env: `ANKY_AUTO_TRIAL_ENABLED=true`, `ANKY_IOS_TRIAL_ENABLED=true`, `ANKY_IOS_DEVICECHECK_REQUIRED=true`, Apple DeviceCheck credentials, and `APPLE_DEVICECHECK_ENV`.
3. Fresh install on a real iPhone and confirm the app has a local public key.
4. Complete a valid 8-minute `.anky`, tap `Ask Anky`, and confirm the request has the exact `text/plain` body, existing signature headers, `X-Anky-Client: ios`, `X-Anky-App-Version`, and `X-Anky-Trial-Proof`.
5. Confirm the backend validates signature and `.anky`, sees zero balance, verifies DeviceCheck unclaimed, marks bit 0 claimed, grants `+8 CRD`, spends `-1 CRD`, calls the model, returns a reflection, and reports `creditsRemaining: 7`.
6. Confirm the app stores the reflection locally and no writing, prompt, reflection, or raw DeviceCheck token appears in logs.
7. Reinstall or create a new local key on the same device and confirm there is no second automatic trial grant.

Failure QA: force model failure after spend and confirm the server attempts a `+1 CRD` refund while keeping the DeviceCheck trial claim closed.

Android QA: confirm paid RevenueCat credits still work, automatic trials remain disabled, and Android never receives public-key-only automatic grants.

Current deployment:

```txt
https://mirror-production-a23c.up.railway.app
```

This Railway service is currently deployed with `ANKY_MIRROR_DISABLED=false`, `OPENROUTER_PRIVACY_CONFIRMED=true`, and `REVENUECAT_CREDIT_CODE=CRD`. `/health` is live. `POST /anky` is enabled, but it requires a valid signed app request and a RevenueCat credit balance.

Verify current non-secret Railway state without printing API keys:

```sh
railway run --service mirror --environment production -- sh -c 'printf "ANKY_MIRROR_DISABLED=%s\nOPENROUTER_PRIVACY_CONFIRMED=%s\nREVENUECAT_CREDIT_CODE=%s\n" "$ANKY_MIRROR_DISABLED" "$OPENROUTER_PRIVACY_CONFIRMED" "$REVENUECAT_CREDIT_CODE"'
```
