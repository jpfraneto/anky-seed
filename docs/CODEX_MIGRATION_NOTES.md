# CODEX_MIGRATION_NOTES.md

# Codex Migration Notes

## 0. Purpose

This document exists to prevent the new Anky from recreating the old complexity.

The goal is not to port the existing app.

The goal is to rebuild the smallest true Anky from product law.

---

## 1. Current Core Flow

The existing app already discovered the core flow:

```txt
open app
→ write
→ silence closes session
→ reveal reconstructed writing
→ if under 8 minutes: copy only
→ if 8+ minutes: ask Anky for reflection + copy
→ back goes to map
→ bottom navigation: write | map | you

This is the product.

Everything else must justify itself.

2. Keep

Keep the concepts that directly serve the product law:

.anky protocol
parser
hash
reconstruction
local draft persistence
local completed file persistence
local session index
Write screen
Reveal screen
Map screen
You/settings screen
local identity
seed phrase
accountId
RevenueCat credits
one mirror endpoint
3. Drop From v0

Drop the old complexity:

React Native
Expo dependency
Privy
on-chain writing storage
Looms
NFTs
SP1 proof
Helius indexer
thread chat
processing tickets
carpet/full archive processing
server-side writing archive
cloud journal assumptions
old payment verification paths
old checkout paths
proof status UI
seal status UI
wallet flows not needed for local identity
any flow that exists because of a previous architecture, not the current product law
4. New Repository Shape
anky/
  apps/
    ios/
    android/
  services/
    mirror/
  packages/
    protocol/
  docs/
    PRODUCT_LAW.md
    TECHNICAL_LAW.md
    API_CONTRACT.md
    PRIVACY_COVENANT.md
    CODEX_MIGRATION_NOTES.md
apps/ios

Native SwiftUI app.

apps/android

Native Kotlin app.

services/mirror

Bun + Hono mirror service.

Contains POST /anky.

packages/protocol

Shared protocol specification, fixtures, and tests.

This package should not become a giant shared app layer.

5. Migration Strategy

Do not migrate file-by-file.

Instead:

Freeze product law.
Freeze API contract.
Freeze protocol tests.
Scaffold mirror service.
Scaffold iOS app.
Scaffold Android app.
Reimplement only the core flow.
Compare behavior against protocol fixtures.
Ship smallest native version.
Reintroduce nothing unless required.

The old repo is reference material, not the foundation.

6. First Build Target

The first successful build is not feature-complete.

The first successful build proves:

iOS app can:
- generate local identity
- capture .anky
- save .anky locally
- reconstruct writing
- show Reveal
- copy text
- sign POST /anky
- receive reflection
- store reflection locally

mirror service can:
- receive exact .anky body
- hash body
- parse .anky
- reject invalid/incomplete sessions
- verify signature
- spend/check credit placeholder
- call mirror placeholder
- return reflection JSON
- avoid storing writing

Android can follow the same law after iOS proves the minimal loop, unless parallel work is desired.

7. Mirror Service Skeleton

The mirror service should start tiny:

services/mirror/
  src/
    index.ts
    anky/
      parse.ts
      reconstruct.ts
      hash.ts
      validate.ts
    auth/
      verifySignature.ts
      canonicalMessage.ts
    credits/
      revenuecat.ts
    mirror/
      witnessPrompt.ts
      openrouter.ts
    privacy/
      safeLogger.ts
  test/
    protocol.test.ts
    signature.test.ts
    endpoint.test.ts

The server must never log raw writing.

Use a safe logger from the beginning.

8. Protocol Package

The protocol package should contain:

packages/protocol/
  README.md
  fixtures/
    valid-complete.anky
    valid-fragment.anky
    invalid-empty.anky
    invalid-malformed.anky
  src/
    parse.ts
    reconstruct.ts
    hash.ts
    duration.ts
    validate.ts
  test/
    parse.test.ts
    reconstruct.test.ts
    duration.test.ts
    hash.test.ts

The protocol package should make it hard to accidentally reinterpret .anky.

9. UI Principle

The app should be boring.

The culture is alive.

Do not overdesign v0.

The Write screen should have almost nothing.

The Reveal screen should be clear.

The Map should make continuity visible.

The You page should contain only necessary settings and credit flows.

10. Copy

Fragments must be useful.

If a writer writes under 8 minutes, they should still be able to copy what they wrote.

Under-8-minute writing is not failure.

It is simply not eligible for the official mirror.

11. Reflection

Reflection is always the same core action.

Do not implement multiple reflection modes in v0.

No quick/deep/poetic/therapist modes.

One Anky mirror.

The prompt can evolve.

The product surface should not fragment.

12. Trial Credits

Do not grant credits on app install.

Do not grant credits during onboarding.

Do not grant credits by accountId alone.

Official mobile clients may receive one automatic 8-credit trial grant only when a valid complete `.anky` asks for reflection through `POST /anky`.

The grant must be device-bound, app-bound, platform-bound, and RevenueCat-backed.

If device-bound proof is unavailable, automatic grants stay disabled.

Fallback support may still use JP/manual credit help with accountId, platform, and app version only.

This protects the mirror budget without making the first reflection require a conversation.

13. Agent Compatibility

Do not hardcode assumptions that the writer is human.

Use writer.

Use client.

Use .anky.

Official mobile app language may be human-friendly.

Protocol and API language should remain substrate-neutral.

Good:

writer
client
artifact
thread
mirror

Avoid:

patient
user soul
human only
journal entry only
therapy session
14. Anti-Goals

The rebuild is not trying to prove:

on-chain sealing
decentralized identity
social virality
AI memory
full archive processing
multi-agent consciousness
perfect native architecture
perfect UI
complete settings
scalable enterprise backend

The rebuild is trying to prove:

Can a writer open Anky, write for 8 minutes, receive a private mirror, and want to return tomorrow?
15. Done Means

The first phase is done when:

product law exists
privacy covenant exists
API contract exists
mirror skeleton exists
protocol tests exist
iOS minimal loop exists or is clearly scaffolded
Android minimal loop exists or is clearly scaffolded
no writing is stored on server
POST /anky is the only app-facing mirror endpoint
no legacy proof/loom code enters v0
16. Warning

Complexity will try to return as cleverness.

Reject it.

The ritual is simple.

The protocol is sacred.

The server is a mirror.

The server forgets.
```
