# Railway Mirror Deployment

The mirror service is deployable as a Docker-backed Railway service from `services/mirror/Dockerfile`.

## Local Safety Check

```sh
cd services/mirror
bun test
ANKY_DEV_BYPASS_CREDITS=true ANKY_DEV_MOCK_MIRROR=true bun run dev
curl http://127.0.0.1:3000/health
```

## Production Variables

Set these in Railway:

```sh
ANKY_ENV=production
NODE_ENV=production
OPENROUTER_API_KEY=<secret>
OPENROUTER_MODEL=<model>
OPENROUTER_PRIVACY_CONFIRMED=true
REVENUECAT_SECRET_KEY=<secret>
REVENUECAT_PROJECT_ID=<project>
ANKY_DEV_BYPASS_CREDITS=false
ANKY_DEV_MOCK_MIRROR=false
```

Optional:

```sh
ANKY_MAX_BODY_BYTES=1048576
OPENROUTER_TIMEOUT_MS=45000
REQUEST_TIME_TOLERANCE_MS=300000
```

## Deploy

This workspace has the Railway CLI installed, but no project is linked. Use:

```sh
railway login
railway link
railway variables set ANKY_ENV=production NODE_ENV=production
railway variables set OPENROUTER_API_KEY=... OPENROUTER_MODEL=... OPENROUTER_PRIVACY_CONFIRMED=true
railway variables set REVENUECAT_SECRET_KEY=... REVENUECAT_PROJECT_ID=...
railway variables set ANKY_DEV_BYPASS_CREDITS=false ANKY_DEV_MOCK_MIRROR=false
railway up
railway domain
```

Verify:

```sh
curl https://<railway-domain>/health
```

Current deployed domain:

```txt
https://mirror-production-a23c.up.railway.app
```

Current status: health-checkable production deployment, with `ANKY_MIRROR_DISABLED=true` because OpenRouter and RevenueCat variables are still placeholders. Turn that off only after real secrets are set.

## v0 Replay Scope

Replay and duplicate-in-progress protection are in memory. This is acceptable for one Railway instance in v0. Do not add Redis or a database unless the deployment moves to multiple instances and replay protection must survive process restarts.
