# ANKY_MIRROR_DISTILLATION.md

## One-Line `/goal`

Run this from the root of the `anky-seed` monorepo after placing this file at the repo root:

```text
/goal Using ANKY_MIRROR_DISTILLATION.md as the source of truth, consolidate the current Anky mirror runtime into one auditable storytelling-quality TypeScript source file while preserving the current local code behavior exactly: POST /anky, GET /health, Base EOA/EIP-712 identity if present, duplicate protection, provider router/ZDR gating, credit semantics, privacy covenant, production guards, tests, and deployment behavior; update stale docs/context without regressing to older Ed25519/Solana assumptions.
```

---

# Anky Mirror One-File Consolidation Context

You are working in the root of the Anky monorepo.

Repo: `https://github.com/jpfraneto/anky-seed`

This repository contains the current implementation of Anky: native apps, protocol code, and the mirror server.

The purpose of this task is to simplify the mirror server into the clearest possible expression of what Anky currently is.

This is not a rewrite into a future architecture.

This is a consolidation of the current working system into a durable v1 implementation.

The final code should feel like opening the first smart contract of Anky: functional, narrow, readable, and spiritually precise.

---

## Mission

Transform the current Anky mirror server implementation into the simplest durable version of itself:

- one app-facing endpoint: `POST /anky`
- one operational health endpoint: `GET /health`
- one auditable TypeScript source file containing the mirror runtime/product logic
- no loss of security
- no loss of privacy
- no behavior regressions
- no stale architecture restored from old docs

The purpose is not to make the code clever.

The purpose is to make the mirror obvious.

Anky’s server is not a platform.

Anky’s server is not memory.

Anky’s server is a narrow mirror.

It receives one complete `.anky` artifact, verifies that the writer asked to be witnessed, reflects it once, returns the reflection, and forgets.

---

## Very Important Source-of-Truth Rule

Before editing, inspect the current local working tree.

The current code and tests are the source of truth.

Some docs may still describe older architecture, especially older Ed25519/base58/Solana-style identity. Do not blindly preserve stale docs if the current code has moved to Base EOA / EIP-712.

If local code currently uses:

- `X-Anky-Identity-Version: anky.base.eoa.v1`
- `X-Anky-Account: 0xChecksumAddress`
- `X-Anky-Signature-Type: eip712`
- `X-Anky-Signature: 0x...`
- `X-Anky-Request-Time: <epoch_ms>`
- `X-Anky-Client: ios | android | other`
- optional `X-Anky-App-Version`
- optional `X-Anky-Trial-Proof`

then preserve that model exactly.

Do not regress the code back to:

- `X-Anky-Public-Key`
- Solana public key identity
- Ed25519/base58 request signatures
- public-key-based RevenueCat identity

unless the current local code and tests truly still use that older model.

If docs disagree with current code/tests, update the docs.

Current implementation wins over old narrative.

Tests win over assumptions.

---

## Current Architecture Facts To Preserve If Present

Preserve the latest local architecture if it exists in the working tree.

These details come from the latest implementation status and must be confirmed against the local code before editing:

- Active identity is the EIP-55 checksum address only.
- RevenueCat App User ID is the same EIP-55 checksum address.
- EIP-712 uses `chainId=8453` in the domain if that is how current code works.
- Duplicate protection key is `sha256(address + ":" + ankyHash)`.
- Duplicate states are `new`, `processing`, `succeeded`, and `failed`.
- Cloudflare Worker path uses Durable Objects for duplicate protection if present.
- Railway may have a temporary in-memory fallback if that is documented/current.
- Provider router exists with OpenRouter, Bankr placeholder, Poiesis/Hermes placeholder, and safe fallback.
- If `ANKY_REQUIRE_ZDR=true`, unconfirmed providers must be skipped.
- Credits are spent only according to the current tested contract. If current tests say credits are spent only after real provider success, preserve that. Do not change to older spend-then-refund behavior unless tests already require it.
- Diagnostics must stay sanitized: request/account hash/hash/client/status/provider/duration/error/timestamps only.
- Logs must never contain raw writing, reconstructed writing, prompt text, reflection text, signature, trial proof, seed phrase, private key, or unsafe raw identity material.
- Identity backup remains local-first only: iOS iCloud Keychain path, Android encrypted export/import path, no server identity storage, no login.
- Wallet funding / Base USDC / Veil.cash remains docs/interfaces only unless already safely implemented. Do not ship unsafe wallet funding UI or production flow.

---

## Product Law

The `.anky` file is the session.

The writer owns the writing.

The device is the archive.

The server is not memory.

The mirror server may transiently hold:

- raw `.anky` bytes
- reconstructed text
- model prompt
- model response

Only in memory.

Only during one request.

Only after explicit user action.

The mirror server must not persist:

- raw `.anky`
- reconstructed writing
- prompts containing writing
- private reflections
- writing-derived embeddings
- writing-derived summaries
- hidden user memory
- analytics over writing content

If a feature requires silently storing private writing, do not build it.

If a feature requires turning writing into analytics content, do not build it.

If a simplification weakens privacy, do not simplify it.

The protections are not extra implementation details.

The protections are the soul of the project.

---

## Security Is Part Of The Ritual

This endpoint is the covenant surface of Anky.

Security is not an enterprise decoration.

Security is part of the product meaning.

If the server leaks writing, accepts forged requests, stores private reflections, accepts malformed `.anky` files, bypasses production protections, or logs private material, the implementation has not merely failed technically.

It has broken the ritual.

The endpoint should be boring to attack, narrow in surface area, fail-closed by default, and incapable of leaking the writer’s private artifact even during errors.

The implementation must fail closed:

- reject ambiguous requests
- reject missing required headers
- reject unsupported identity versions
- reject unsupported signature types
- reject invalid EIP-55 account values if using Base EOA identity
- reject unsafe content types
- reject oversized request bodies before expensive work
- reject stale timestamps
- reject invalid signatures
- reject replay/duplicate requests according to current duplicate-protection semantics
- reject invalid `.anky` files
- reject incomplete rituals
- reject unsafe production configuration
- skip providers that do not satisfy required privacy/ZDR configuration
- never log raw writing, prompt text, reflection text, signatures, tokens, seed phrases, private keys, or unsafe raw account identifiers

Do not weaken tests to make the consolidation pass.

The one-file architecture is allowed only if it makes the covenant easier to audit.

---

## Desired Code Shape

The mirror should become one source scroll.

Prefer consolidating product/runtime logic into one file such as:

- `services/mirror/src/index.ts`

or, if platform bootstraps require it:

- one core product logic file
- only tiny platform-specific entrypoints with no product logic

The endpoint should remain simple:

```ts
app.post("/anky", async (c) => {
  return handleAnkyReflection(c, runtime)
})
```

The one file should still be organized into small named functions.

One file does not mean one giant function.

One file does not mean tangled code.

One file does not mean no boundaries.

One file means the reader can open one source file and understand the mirror in one sitting.

Use sections like:

```ts
// -----------------------------------------------------------------------------
// Imports
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// The Covenant
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Configuration
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Runtime Construction
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// HTTP App
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// POST /anky
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Identity + Signature Verification
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// .anky Protocol Validation
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Duplicate Protection
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Credits + Trials
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Provider Router
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Privacy-Safe Diagnostics
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Errors
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Server Entrypoint
// -----------------------------------------------------------------------------
```

At the top of the file, include a short comment that encodes the essence:

```ts
/**
 * ANKY MIRROR
 *
 * This server is not memory.
 * This server is not a journal.
 * This server is not a user database.
 *
 * It receives one complete .anky artifact,
 * verifies that the writer asked to be witnessed,
 * reflects once,
 * returns the reflection,
 * and forgets.
 */
```

Keep comments meaningful, not decorative.

The storytelling should clarify the architecture and covenant.

The comments should make the safety model easier to understand.

The comments should not hide complexity.

---

## API Contract To Preserve

Preserve current local API behavior exactly.

The request body must remain the exact `.anky` bytes/text.

No JSON writing body.

Do not introduce:

- `/register`
- `/session`
- `/me`
- `/v1/reflections`
- cloud journal endpoints
- login endpoints
- server-side wallet-link endpoints
- server-side identity backup
- writing analytics endpoints

`GET /health` may remain as infrastructure.

If there are webhooks, worker bindings, or deployment-specific internals already present, preserve them only if they do not weaken the law that `POST /anky` is the only app-facing mirror endpoint.

---

## Request Contract To Preserve If Current Code Uses Base EOA

If the current local implementation uses Base EOA / EIP-712 identity, preserve this exact direction:

Required request headers:

```text
X-Anky-Identity-Version: anky.base.eoa.v1
X-Anky-Account: 0xChecksumAddress
X-Anky-Signature-Type: eip712
X-Anky-Signature: 0x...
X-Anky-Request-Time: <epoch_ms>
X-Anky-Client: ios | android | other
```

Optional request headers:

```text
X-Anky-App-Version: <optional>
X-Anky-Trial-Proof: <optional>
```

Identity law:

- The active identity is the EIP-55 checksum account address.
- The server must not store private keys.
- The server must not store seed phrases.
- The server must not provide server-side identity backup.
- The RevenueCat App User ID should follow the current implementation. If current code uses the EIP-55 checksum address, preserve it.

Signature law:

- Preserve the current EIP-712 domain and message structure.
- Preserve the current `chainId=8453` behavior if present.
- Reject unsupported signature types.
- Reject stale timestamps according to current tested tolerance.
- Reject invalid signatures.
- Preserve replay/duplicate semantics.

Do not silently change the signing payload.

Do not silently change request headers.

Do not silently change identity canonicalization.

---

## Duplicate Protection

Preserve current duplicate protection behavior.

If current code uses:

```text
sha256(address + ":" + ankyHash)
```

then preserve that exact semantic.

Preserve the current state machine if present:

```text
new
processing
succeeded
failed
```

The intent:

- repeated identical requests should not double-charge
- repeated identical requests should not produce uncontrolled duplicate provider calls
- in-flight duplicates should be handled deterministically
- failed attempts should follow the current tested retry behavior

If Cloudflare Durable Objects are the canonical production duplicate-protection path, preserve that.

If Railway currently uses a documented temporary in-memory fallback, preserve it only as transitional behavior and keep it clearly marked as such.

Do not replace Durable Objects with a weaker production mechanism.

Do not introduce a database unless the current architecture already requires it.

---

## Credits + Trials

Preserve current credit behavior exactly.

Do not assume old behavior.

If current tests say:

- credits are spent only after real provider success

then preserve that.

If current tests say:

- credits are reserved/spent before provider call and refunded on failure

then preserve that.

The rule is: current code/tests win.

Keep RevenueCat identity behavior aligned with current implementation.

Keep trial proof handling aligned with current implementation.

Do not log trial proofs.

Do not accept fake trial proofs in production.

Do not enable Android/iOS trial bypasses in production unless the current production guard explicitly permits them safely.

---

## Provider Router + Privacy / ZDR

Preserve the provider router if present.

Known provider slots may include:

- OpenRouter
- Bankr placeholder
- Poiesis/Hermes placeholder
- safe fallback

Preserve `ANKY_REQUIRE_ZDR=true` behavior if present.

If `ANKY_REQUIRE_ZDR=true`, skip providers that do not have confirmed privacy / zero-data-retention posture according to current code.

Do not silently route private writing to an unconfirmed provider.

Do not add new providers.

Do not make placeholder providers live.

Do not log provider prompts or responses.

Do not store provider prompts or responses.

---

## Privacy-Safe Diagnostics

Diagnostics may include only safe metadata, such as:

- request hash
- account hash
- `.anky` hash
- client
- status
- provider name
- duration
- coarse error code
- timestamps

Diagnostics must not include:

- raw writing
- reconstructed writing
- prompt text
- reflection text
- signature
- trial proof
- seed phrase
- private key
- raw DeviceCheck token
- raw Play Integrity token
- unsafe full account identifiers if current code hashes them

When unsure, hash or omit.

Privacy tests must remain strict.

Do not loosen privacy tests.

---

## Production Guards

Production must fail loudly on unsafe configuration.

Preserve current production startup guards.

Production should not allow:

- mock providers unless explicitly safe and current tests allow it
- bypassed credits
- fake trial proofs
- missing privacy confirmation
- unsafe ZDR provider behavior
- missing required provider config if reflection is enabled
- silent fallback to unsafe local behavior

If auth/secrets are missing locally during tests or deploy attempts, report them as environment blockers.

Do not change code to make missing production secrets pass silently.

---

## Native App Boundaries

This task is primarily about the mirror server.

Do not redesign iOS or Android in this pass unless needed to preserve compatibility with the current server contract.

If native app code is touched:

- preserve the write/reveal/map/you product law
- preserve local-first identity backup
- preserve local `.anky` archive
- preserve exact request headers expected by the server
- run relevant native tests if possible

Do not add login.

Do not add server identity storage.

Do not add server-side journal sync.

Do not add cloud memory.

---

## Documentation Requirements

Update stale documentation to match the current implementation.

Especially check:

- root `README.md`
- `services/mirror/README.md`
- `docs/API_CONTRACT.md`
- `docs/PRIVACY_COVENANT.md`
- any existing `ANKY_MIRROR_ONE_FILE_CONTEXT.md`
- deployment docs that mention mirror identity or signatures

If docs still describe Ed25519/base58/Solana public key identity but code now uses Base EOA/EIP-712, update the docs.

If docs describe old credit timing but current code/tests use newer credit semantics, update the docs.

If docs describe Railway as canonical but Worker/Durable Objects are now canonical, update the docs to explain the current reality.

Docs must describe reality.

Do not make docs aspirational unless clearly marked as future work.

---

## Testing Requirements

After refactor, run the relevant checks that exist in the repo.

Start by inspecting package scripts and existing CI/test commands.

At minimum, attempt the protocol and mirror checks if these paths/scripts exist:

```sh
cd protocol/implementations/typescript && bun test && bun run typecheck
cd ../../../services/mirror && bun test && bun run typecheck
```

If Worker tests/typecheck/dry-run commands exist, run them too.

If iOS or Android code is touched, run the existing unit checks for those surfaces if available.

Do not upload to App Store Connect.

Do not upload to Play Console.

Do not deploy Railway.

Do not deploy Cloudflare.

Do not require local secrets for this refactor.

If deployment commands fail because auth/secrets are missing, report that clearly and do not treat it as a code failure.

---

## What Not To Do

Do not:

- rewrite the whole repo
- redesign the apps
- add new product endpoints
- add a database
- add account login
- add server-side identity backup
- add cloud journal storage
- add analytics over writing contents
- introduce a new provider
- turn placeholder provider paths into production paths
- weaken privacy tests
- weaken signature verification
- weaken duplicate protection
- silence production guard failures
- deploy anything
- upload mobile builds
- commit secrets
- log private material
- preserve stale docs over current code

---

## Acceptance Criteria

The work is complete only if:

1. The mirror product/runtime logic is consolidated into one auditable TypeScript source file, or one core file plus tiny platform bootstraps if unavoidable.
2. `POST /anky` behavior is unchanged.
3. `GET /health` behavior is unchanged.
4. Current identity/signature model is preserved.
5. Current duplicate-protection semantics are preserved.
6. Current provider router/ZDR behavior is preserved.
7. Current credit/trial behavior is preserved.
8. Production guards still fail loudly on unsafe config.
9. Privacy-safe diagnostics remain safe.
10. Tests pass, or failures are clearly unrelated to code and caused by missing local auth/secrets.
11. No private material is logged.
12. No new product endpoints are added.
13. Docs are updated to match the actual implementation.
14. Final report lists changed files, tests run, and any blockers.

---

## Final Report Format

When finished, report:

```text
Status:
- Complete / partial / blocked

Changed files:
- ...

Final mirror file path:
- ...

Old runtime files:
- Deleted / reduced to thin bootstraps / intentionally kept, with reason

API contract:
- POST /anky:
- GET /health:

Identity model:
- ...

Duplicate protection:
- ...

Provider / ZDR behavior:
- ...

Credit / trial behavior:
- ...

Privacy / logging:
- ...

Production guards:
- ...

Commands run:
- ...

Results:
- ...

Blockers:
- ...

Intentional non-changes:
- ...

Notes for JP:
- ...
```

---

## Final Reminder

This refactor is allowed only if it makes Anky simpler to understand and harder to accidentally violate.

The goal is not to make a “god file.”

The goal is to make a source scroll.

A single file that says:

A person writes.

The device keeps the artifact.

The server witnesses only when invited.

The server forgets.

The person returns to their trail.
