# TECHNICAL_LAW.md

# Anky Technical Law

## 0. The Principle

Technical simplicity is product integrity.

The system should be as small as the ritual.

The app is local-first.

The server is stateless wherever possible.

The protocol is the sacred layer.

The implementation is disposable.

---

## 1. Architecture

The new Anky system has four layers:

```txt
apps/ios
apps/android
services/mirror
packages/protocol

The iOS and Android apps are native clients.

Do not use React Native.

Do not share UI code.

Share only:

product law
protocol law
API contract
test vectors
mirror contract

The official clients should feel native to their platforms.

The product should remain identical.

2. Canonical State

The canonical state of a writing session is the exact .anky file.

The app may derive:

reconstructed text
duration
hash
preview
title
reflection
local map status

But the source of truth is the .anky.

Do not invent another source of truth.

3. Local-First Law

The device stores:

active draft
completed .anky files
local session index
local reflection results
local identity
local settings

The server does not store:

raw .anky
reconstructed writing
private reflection content
journal archive
user memory
writing analytics

The server may temporarily hold writing in memory during a reflection request.

Then it forgets.

4. Identity Law

Each official app generates a local Solana-compatible identity.

The identity is derived from a locally stored seed phrase.

The public key is the writer identifier.

The private key never leaves the device.

The public key may be used as:

RevenueCat App User ID
mirror request identity
credit account key
free-credit grant target

The server does not issue identity.

No /register.

No /session.

No login ceremony.

The writer appears to the server only when asking Anky to mirror a .anky.

5. Request Authentication

The mirror endpoint must verify that the requester controls the public key.

Use signature authentication.

The client sends:

X-Anky-Public-Key
X-Anky-Signature
X-Anky-Request-Time
X-Anky-Client

The client signs a canonical message:

ANKY_POST_V1
method:POST
path:/anky
request_time:<epoch_ms>
body_sha256:<sha256_of_exact_body_bytes>

The server computes body_sha256 from the exact received body bytes.

The server reconstructs the canonical message.

The server verifies the signature against the public key.

If verification fails, reject the request.

6. Mirror Endpoint Law

There is one app-facing endpoint:

POST /anky

Do not create:

/register
/session
/me
/v1/reflections
/register-payment
/submit
/seal
/proof

The body of POST /anky is the exact .anky text/bytes.

Do not wrap it in JSON.

Do not ask the client to send the hash.

Do not ask the client to send the timestamp.

Do not ask the client to send the duration.

Do not ask the client to send reflection mode.

The server derives all of this from the .anky.

7. Server Flow

For POST /anky, the server must:

Read the exact raw request body bytes.
Compute SHA-256 hash.
Decode UTF-8.
Parse .anky.
Validate protocol.
Derive start timestamp.
Derive duration.
Reject invalid sessions.
Reject reflection for sessions under 8 minutes.
Verify request signature.
Use public key as credit identity.
Check/spend 1 credit.
Reconstruct writing.
Prepend the Anky witness prompt.
Send to the model provider using privacy-compatible routing.
Parse model output.
Return reflection JSON.
Forget raw .anky.
Forget reconstructed writing.
8. Credit Law

RevenueCat is the credit ledger.

The Anky backend should not maintain an independent credit database unless absolutely necessary.

Purchases happen in the native app through RevenueCat.

The backend spends credits when POST /anky succeeds.

The backend should use an idempotency key derived from:

publicKey + ankyHash

This prevents double spending when the client retries the same reflection request.

Free credits are manually granted by JP during the early phase.

Automatic free credits are forbidden in v0 because they create infinite-wallet abuse.

9. Database Law

The ideal mirror server has no durable application database.

Acceptable durable state:

environment variables
provider API keys
deployment metadata

Acceptable optional ephemeral state:

rate limits
replay protection
short-lived idempotency locks
abuse counters

Forbidden durable state:

raw .anky
reconstructed writing
private reflections
full journal history
AI training corpus
hidden user memory

If a database is introduced, it must be justified in writing.

The default answer is no database.

10. Privacy-Compatible Model Routing

The model provider must be configured so that writing is not retained for training or logging.

The server should prefer zero-retention or no-data-collection routing.

If the provider cannot satisfy the privacy covenant, it cannot be used for Anky reflections.

The privacy law outranks model quality.

11. Native App Law
iOS

Use SwiftUI.

The app opens directly into Write.

The keyboard appears immediately.

The app captures .anky locally.

The app stores active drafts locally.

The app saves completed .anky files locally by hash.

The app reconstructs writing locally.

The app stores reflections locally.

The app signs mirror requests locally.

Android

Use Kotlin.

Follow the same product law.

Follow the same protocol law.

Follow the same mirror contract.

Do not drift from iOS behavior.

12. Complexity Rules

Before adding a feature, ask:

Does this protect the ritual?
Does this preserve the protocol?
Does this strengthen privacy?
Does this increase ankys written?
Does this make the app more boring in the right way?

If not, do not add it.

13. Forbidden Complexity in v0

Do not implement:

Solana sealing
NFTs
Looms
SP1 proofs
Privy
Helius indexer
cloud sync
server archive
AI memory
social feed
chat threads
multi-reflection modes
analytics over writing content
automatic free credits
React Native bridge
shared cross-platform UI framework

The ritual is the product.
```
