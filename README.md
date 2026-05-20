# ANKY

ANKY is a ritual protocol for 8 minutes of uninterrupted presence.

The canonical artifact is a `.anky` file. The writer owns the writing. ANKY does not store the writing. The server is not memory. The server is a mirror.

## Product Law

The constitutional source of truth lives in:

- `docs/PRODUCT_LAW.md`
- `docs/TECHNICAL_LAW.md`
- `docs/API_CONTRACT.md`
- `docs/BASE_IDENTITY_LAW.md`
- `docs/FUTURE_SMART_ACCOUNTS.md`
- `docs/CODEX_MIGRATION_NOTES.md`
- `docs/PRIVACY_COVENANT.md`

The important constraints for this foundation:

- The `.anky` file is the session.
- Reconstructed text is only a view of `.anky`.
- The device stores `.anky` files and reflections locally.
- The mirror server receives `.anky` only when the writer explicitly asks for reflection.
- The mirror server processes writing transiently and forgets.
- There is one app-facing endpoint: `POST /anky`.
- Anky identity is Base-native: local EOA now, ERC-1271-compatible interface later.
- No cloud journal, feed, chat, social graph, smart wallet product, wallet UI, on-chain writing, AI memory, or server-side writing archive.

## Repository Structure

```txt
anky/
  docs/                 product, technical, API, and privacy law
  protocol/             .anky spec, fixtures, TypeScript implementation, tests
  services/mirror/      Bun + Hono mirror service
  apps/ios/             native SwiftUI app
  apps/android/         native Kotlin app placeholder
  scripts/              local utility scripts
  infra/                deployment notes and future infrastructure
  .github/              future CI
```

## Mirror Service

```sh
cd services/mirror
bun install
bun run dev
```

Or from the repository root:

```sh
make mirror-dev
```

The mirror exposes:

- `GET /health`
- `POST /anky`

`POST /anky` accepts `Content-Type: text/plain; charset=utf-8`. The request body is the exact `.anky` text/bytes. It does not accept JSON writing bodies.

The mirror runtime/product logic is consolidated in `services/mirror/src/index.ts`; tests and the Worker import that same surface.

Signature verification is EIP-712 over a Base account identity. Current requests use `X-Anky-Identity-Version: anky.base.eoa.v1`, `X-Anky-Account: 0xChecksumAddress`, `X-Anky-Signature-Type: eip712`, and an EVM signature over the server-derived `.anky` body hash. The Base chain ID remains in env and EIP-712 domain data.

The service listens on `process.env.PORT` and `0.0.0.0` for Railway. It has a production guard: when `ANKY_ENV=production` or `NODE_ENV=production`, dev credit bypass and mock mirror are forbidden, OpenRouter and RevenueCat configuration are required, and startup fails loudly if the mirror is unsafe.

The root `.env.example` is the only committed environment template. Keep the real root `.env` local/uncommitted and set production values through Railway variables; do not create per-subfolder env files.

For local iOS testing with a mock reflection:

```sh
cd services/mirror
ANKY_DEV_BYPASS_CREDITS=true ANKY_DEV_MOCK_MIRROR=true bun run dev
```

Then set the app's `You -> Mirror base URL` to `http://127.0.0.1:3000` for the iOS simulator, `http://10.0.2.2:3000` for the Android emulator, or use the deployed HTTPS mirror / an HTTPS tunnel for physical devices.

Current Railway mirror URL:

```txt
https://mirror-production-a23c.up.railway.app
```

Current status: `/health` is live on Railway. The production `mirror` service is configured with `ANKY_MIRROR_DISABLED=false`, `OPENROUTER_PRIVACY_CONFIRMED=true`, and `REVENUECAT_CREDIT_CODE=CRD`; `POST /anky` is enabled, but it requires a valid signed app request and a RevenueCat credit balance.

Verify current non-secret Railway state without printing secrets:

```sh
railway run --service mirror --environment production -- sh -c 'printf "ANKY_MIRROR_DISABLED=%s\nOPENROUTER_PRIVACY_CONFIRMED=%s\nREVENUECAT_CREDIT_CODE=%s\n" "$ANKY_MIRROR_DISABLED" "$OPENROUTER_PRIVACY_CONFIRMED" "$REVENUECAT_CREDIT_CODE"'
```

Railway deployment notes:

```sh
railway login
railway link
railway variables set ANKY_ENV=production NODE_ENV=production
railway variables set OPENROUTER_API_KEY=... OPENROUTER_MODEL=... OPENROUTER_PRIVACY_CONFIRMED=true
railway variables set REVENUECAT_SECRET_KEY=... REVENUECAT_PROJECT_ID=... REVENUECAT_CREDIT_CODE=CRD
railway variables set ANKY_AUTO_TRIAL_ENABLED=false ANKY_IOS_TRIAL_ENABLED=false ANKY_ANDROID_TRIAL_ENABLED=false
railway variables set ANKY_MIRROR_DISABLED=false ANKY_DEV_BYPASS_CREDITS=false ANKY_DEV_MOCK_MIRROR=false
railway up
railway domain
curl https://<railway-domain>/health
```

See `services/mirror/README.md` and `infra/railway/mirror.md`.

## iOS App

The native iOS v0 loop is implemented:

- Write captures local `.anky` files.
- Write now opens as a full-screen keyboard-first ritual surface with Ankyverse progress rings and local haptics.
- Reveal reconstructs locally as a reading/stats screen and can request a mirror for complete ankys.
- Ask Anky signs `POST /anky` and sends the exact `.anky` bytes.
- Reflections are stored locally by hash.
- Map shows the local trail grouped by day with complete/fragment/reflection state.
- You exposes the Anky address/Base account, recovery phrase reveal/copy after local auth, Face ID app lock, reminders, export, support/manual-credit contact, `$ANKY` CA copy, privacy, and DEBUG mirror tools.

See `apps/ios/README.md` for build, test, storage, and privacy details.

## Protocol Tests

```sh
cd protocol/implementations/typescript
bun install
bun test
```

Or from the repository root:

```sh
make protocol-test
```

## Inspect A Local `.anky`

```sh
make inspect FILE=protocol/fixtures/valid-complete.anky
```

This reads from disk, prints derived facts, and never uploads writing.

## Intentionally Not Implemented

- React Native or Expo
- Cloud journal storage
- Databases
- `/register`, `/session`, `/me`, `/v1/reflections`, or any product endpoint besides `POST /anky`
- Server-side persistence of raw `.anky`, reconstructed writing, prompts, or reflections
- Smart wallets, Coinbase Smart Wallet, Privy, WalletConnect, ERC-4337, on-chain `.anky` storage, on-chain reflections, NFTs, social feed, chat, cloud sync, or AI memory
- Android automatic trial credits before Play Integrity/device recall
