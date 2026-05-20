# Anky As Storyteller

Anky is a local-first writer archive. The `.anky` file on the device is the canonical artifact.

The mirror is a transient storyteller. It receives exact `.anky` bytes at `POST /anky`, verifies a per-request Base EIP-712 signature, reconstructs the writing in memory, builds a storyteller prompt, asks a confirmed private provider, returns a reflection, and forgets the writing.

No server memory:

- no raw `.anky` storage;
- no reconstructed writing storage;
- no prompt storage;
- no reflection storage;
- no embeddings;
- no login/session/profile.

Provider routing lives inside the one-file mirror runtime, `backend/server.ts`. Providers declare zero-data-retention, content logging, and training status. The default fallback is no-charge and does not call a model.

Storyteller entrypoint:

- mirror runtime, prompt, provider router, route/core, identity verifier, x402, credit ledger, diagnostics: `backend/server.ts`
- protocol: `protocol/implementations/typescript/src/identity.ts`
- iOS request path: `apps/ios/Anky/Core/Mirror/AnkyPostSigner.swift`, `apps/ios/Anky/Core/Mirror/MirrorClient.swift`
- Android request path: `apps/android/app/src/main/java/inc/anky/android/core/identity/AnkyPostSigner.kt`, `apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt`
