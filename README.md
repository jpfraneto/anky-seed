# ANKY

ANKY is a ritual protocol for 8 minutes of uninterrupted presence.

The canonical artifact is a `.anky` file. The writer owns the writing. ANKY does not store the writing. The server is not memory. The server is a mirror.

## Product Law

The constitutional source of truth lives in:

- `docs/PRODUCT_LAW.md`
- `docs/TECHNICAL_LAW.md`
- `docs/API_CONTRACT.md`
- `docs/CODEX_MIGRATION_NOTES.md`
- `docs/PRIVACY_COVENANT.md`

The important constraints for this foundation:

- The `.anky` file is the session.
- Reconstructed text is only a view of `.anky`.
- The device stores `.anky` files and reflections locally.
- The mirror server receives `.anky` only when the writer explicitly asks for reflection.
- The mirror server processes writing transiently and forgets.
- There is one app-facing endpoint: `POST /anky`.
- No cloud journal, feed, chat, social graph, Solana sealing, NFTs, AI memory, or server-side writing archive.

## Repository Structure

```txt
anky/
  docs/                 product, technical, API, and privacy law
  protocol/             .anky spec, fixtures, TypeScript implementation, tests
  services/mirror/      Bun + Hono mirror service
  apps/ios/             native SwiftUI app placeholder
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

Signature verification is implemented with Ed25519 using `@noble/curves` and Solana-style base58 public keys/signatures via `bs58`.

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
- Solana sealing, NFTs, Looms, proofs, Helius, Privy, social feed, chat, cloud sync, or AI memory
- Full iOS or Android app implementation
- Automatic free credits
