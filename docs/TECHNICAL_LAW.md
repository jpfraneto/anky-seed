# Anky Technical Law

Technical simplicity is product integrity. The app is local-first, the server is stateless wherever possible, and the `.anky` protocol is the canonical layer.

## Architecture

The system has four layers:

```txt
apps/ios
apps/android
services/mirror
protocol
```

iOS and Android are native clients. Do not use React Native. Do not share UI code. Share protocol law, API contract, test vectors, and mirror contract.

## Canonical State

The canonical state of a writing session is the exact `.anky` file.

The app may derive reconstructed text, duration, hash, preview, title, reflection, and local map status. The source of truth remains the `.anky` artifact.

## Local-First Law

The device stores active drafts, completed `.anky` files, local indexes, local reflections, local identity, and settings.

The server must not persist raw `.anky`, reconstructed writing, prompts containing writing, reflections, AI memory, embeddings, journal history, or writing analytics.

The server may temporarily hold writing in memory during a reflection request. Then it forgets.

## Identity Law

Each official app generates or recovers a local Base EOA identity.

Current identity:

```txt
identityVersion: anky.base.eoa.v1
accountKind: eoa
chain: Base
productionChainId: 8453
testChainId: 84532
account: 0xChecksumAddress
recovery: bip39-english-12-word
derivationPath: m/44'/60'/0'/0/0
curve: secp256k1
signing: eip712
```

The 12-word recovery phrase controls the Anky Base account and never leaves the device. The server does not issue identity.

No `/register`. No `/session`. No login ceremony.

The checksum address is the writer identifier, RevenueCat App User ID, mirror request identity, credit account key, and free-credit grant target when official-app/device proof is valid.

Legacy identity material may be retained locally for manual support migration, but new `POST /anky` requests must use `anky.base.eoa.v1`.

## Request Authentication

The mirror endpoint must verify that the requester controls the Base account.

Required headers:

```txt
X-Anky-Identity-Version
X-Anky-Account
X-Anky-Signature-Type
X-Anky-Signature
X-Anky-Request-Time
X-Anky-Client
```

`X-Anky-Signature-Type` must be `eip712`.

The server computes SHA-256 from the exact received body bytes and verifies an EIP-712 `AnkyMirrorRequest` typed-data signature. If verification fails, reject before credit checks or model calls.

## Mirror Endpoint Law

There is one app-facing endpoint:

```txt
POST /anky
```

Do not create `/register`, `/session`, `/me`, `/wallet`, `/identity`, `/login`, `/profile`, `/submit`, `/seal`, `/proof`, or `/v1/reflections`.

The body of `POST /anky` is exact `.anky` bytes. Do not wrap it in JSON. Do not ask the client to send trusted hash, timestamp, duration, reconstructed text, or reflection mode.

## Server Flow

For `POST /anky`, the server must:

1. Read exact raw request body bytes.
2. Compute SHA-256 hash.
3. Verify Base EIP-712 request identity.
4. Decode UTF-8.
5. Parse `.anky`.
6. Validate protocol and complete 8-minute duration.
7. Use the checksum address as credit identity.
8. Preflight credit eligibility without spending.
9. Reconstruct writing in memory.
10. Build the transient Anky storyteller prompt.
11. Send to the provider router using ZDR-compatible routing.
12. Parse model output.
13. Spend 1 credit only if a real provider succeeded.
14. Return reflection JSON.
15. Forget raw `.anky`, prompt, and reconstructed writing.

## Credit Law

RevenueCat is the credit ledger. The backend should not maintain an independent credit database.

Purchases happen in the native app through RevenueCat. The backend spends credits when `POST /anky` succeeds.

Idempotency is derived from:

```txt
address + ankyHash
```

Official mobile clients may receive one automatic trial grant of 8 credits. The trial grant is not a registration flow. It happens lazily inside `POST /anky`, only when a writer asks for reflection on a complete `.anky`.

Trial grants require proof that the request came from an official app/device path. A public address alone must not grant credits.

## Database Law

The ideal mirror server has no durable application database.

Acceptable durable state: environment variables, provider API keys, deployment metadata.

Acceptable ephemeral state: rate limits, replay protection, short-lived idempotency locks, abuse counters.

Forbidden durable state: raw `.anky`, reconstructed writing, private reflections, full journal history, AI training corpus, hidden user memory.

## Native App Law

iOS uses SwiftUI. Android uses Kotlin. Both open directly into Write, capture `.anky` locally, reconstruct locally, store reflections locally, and sign mirror requests locally.

Do not drift from the shared protocol fixtures.

## Forbidden Complexity

Do not implement smart wallets, Coinbase Smart Wallet, Privy, WalletConnect, MetaMask integration, ERC-4337 UserOperations, on-chain `.anky` storage, on-chain reflections, NFTs, cloud sync, server archive, AI memory, social feed, chat threads, multi-reflection modes, analytics over writing content, automatic free credits without device-bound abuse protection, React Native, or shared cross-platform UI.

No Solana.
