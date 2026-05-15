# ANKY Android Codex Goal

_Last reviewed: 2026-05-15_

## One-line `/goal`

```text
/goal Build the native Android version of Anky in apps/android by using the current SwiftUI iOS app as the behavioral reference, while obeying the repo's product law, protocol law, privacy covenant, and mirror API contract. Do not port React Native. Do not invent a new product. Implement the smallest true Anky loop: Write locally -> Reveal locally -> optionally Ask Anky with exact signed .anky bytes -> save reflection locally -> show local Map/You surfaces.
```

## The task

Create a production-ready native Android app that does everything the current `apps/ios` app does at the product/behavior level.

The Android app must be native Kotlin. It should use the current state of the art Android stack, but stay boring and simple: Jetpack Compose, Kotlin coroutines/Flow, ViewModel-based state holders, a small repository/data layer, internal app-specific file storage, DataStore for small settings, Android biometric APIs, Android Keystore-backed protection for sensitive local material, and RevenueCat Android SDK for purchases/credit state.

The goal is parity with the iOS app, not a redesign.

## Core principle

The Android app is not a second interpretation of Anky.

It is the same ritual implemented on another native platform.

When in doubt, obey this hierarchy:

1. `docs/PRODUCT_LAW.md`
2. `docs/TECHNICAL_LAW.md`
3. `docs/API_CONTRACT.md`
4. `docs/PRIVACY_COVENANT.md`
5. `protocol/SPEC.md`
6. `protocol/fixtures/**`
7. Current iOS behavior in `apps/ios/Anky/**`
8. Current iOS tests in `apps/ios/Anky/Tests/**`
9. Current mirror behavior in `services/mirror/**`
10. Android platform best practices

Do not let Android convenience override the `.anky` protocol, the privacy model, or the mirror contract.

## Read first

Before writing code, inspect these files and directories:

```text
README.md
docs/PRODUCT_LAW.md
docs/TECHNICAL_LAW.md
docs/API_CONTRACT.md
docs/PRIVACY_COVENANT.md
docs/CODEX_MIGRATION_NOTES.md
protocol/SPEC.md
protocol/fixtures/**
protocol/implementations/typescript/**
services/mirror/src/**
services/mirror/test/**
apps/ios/README.md
apps/ios/Anky/AppRoot.swift
apps/ios/Anky/Features/Write/**
apps/ios/Anky/Features/Reveal/**
apps/ios/Anky/Features/Map/**
apps/ios/Anky/Features/You/**
apps/ios/Anky/Core/Protocol/**
apps/ios/Anky/Core/Identity/**
apps/ios/Anky/Core/Mirror/**
apps/ios/Anky/Core/Storage/**
apps/ios/Anky/Tests/**
apps/android/README.md
```

## Non-negotiables

- No React Native.
- No Expo.
- No Flutter.
- No shared UI layer with iOS.
- No server-side journal.
- No cloud sync.
- No analytics over writing content.
- No raw writing logs.
- No JSON wrapper around `.anky` body.
- No alternate canonical session format.
- No backend calls during writing.
- No backend calls on app open.
- The server receives writing only when the user explicitly taps Ask Anky on a complete Anky.
- Raw `.anky`, reconstructed text, prompts, and reflections must never be logged.
- RevenueCat secret keys must never be in the Android app.
- Private identity material must never leave the device.
- The public key is the writer identifier and should be used as the RevenueCat App User ID.
- Fragments are valid local writings but are not eligible for Ask Anky.
- A complete Anky is at least 480000ms of ritual time and must follow the protocol rules.

## Android stack

Use a simple native Android project under `apps/android`.

Recommended stack:

- Kotlin
- Gradle Kotlin DSL
- Android Gradle Plugin
- Jetpack Compose
- Material 3 only where it does not disturb the ritual minimalism
- AndroidX Lifecycle ViewModel
- `StateFlow` / `Flow`
- `collectAsStateWithLifecycle`
- Kotlin coroutines
- OkHttp or Ktor client for the mirror request
- DataStore Preferences for simple settings
- App-specific internal storage for `.anky`, reflection, index, and draft files
- Android BiometricPrompt for app lock and phrase reveal gates
- Android Keystore for encrypting/protecting sensitive local identity material
- RevenueCat Android SDK for purchases/customer info
- JUnit for JVM tests
- MockWebServer or equivalent for HTTP contract tests
- Compose UI tests for critical writing/reveal flows

Avoid heavy frameworks unless there is a clear reason. A small manual dependency container is better than introducing a large DI framework for v0.

## Suggested project shape

Create or complete this structure:

```text
apps/android/
  README.md
  settings.gradle.kts
  build.gradle.kts
  gradle.properties
  app/
    build.gradle.kts
    src/main/AndroidManifest.xml
    src/main/java/inc/anky/android/
      AnkyApplication.kt
      MainActivity.kt
      app/
        AppContainer.kt
        AnkyNav.kt
        AnkyApp.kt
      core/
        protocol/
          AnkyLine.kt
          AnkyParser.kt
          AnkyWriter.kt
          AnkyReconstructor.kt
          AnkyHasher.kt
          AnkyValidator.kt
          AnkyDuration.kt
        identity/
          Base58.kt
          RecoveryPhrase.kt
          WriterIdentity.kt
          WriterIdentityStore.kt
          AnkyPostSigner.kt
          BiometricGate.kt
        storage/
          ActiveDraftStore.kt
          LocalAnkyArchive.kt
          ReflectionStore.kt
          SessionIndexStore.kt
          Exporter.kt
        mirror/
          MirrorClient.kt
          MirrorConfiguration.kt
          MirrorEligibility.kt
          MirrorModels.kt
        credits/
          RevenueCatCreditsClient.kt
        privacy/
          SafeLog.kt
          PrivacyMessages.kt
        notifications/
          DailyReminderScheduler.kt
      feature/
        write/
          WriteScreen.kt
          WriteViewModel.kt
          HiddenTextInput.kt
        reveal/
          RevealScreen.kt
          RevealViewModel.kt
        map/
          MapScreen.kt
          MapViewModel.kt
        you/
          YouScreen.kt
          YouViewModel.kt
    src/test/java/inc/anky/android/
      protocol/
      identity/
      mirror/
      storage/
      reveal/
      privacy/
    src/androidTest/java/inc/anky/android/
      write/
      reveal/
      map/
```

The exact package name can change, but keep it stable and intentional. Prefer `inc.anky.android` or the final intended application id.

## Product surfaces to implement

### 1. App root

The root app should expose exactly three main tabs:

1. Write
2. Map
3. You

Reveal can be a pushed/detail surface, not necessarily a tab.

On startup:

- Load or create local writer identity.
- Preload RevenueCat/customer credit state if configured.
- Honor app lock if enabled.
- Restore active draft if present.
- Open into the writing ritual quickly.

Do not add onboarding unless the current iOS app has equivalent behavior. Keep startup minimal.

### 2. Write

This is the sacred surface.

Behavioral requirements:

- Fullscreen ritual UI.
- Keyboard-first.
- No visible text field chrome.
- No feed.
- No prompts by default unless already present in the current iOS behavior.
- First accepted character starts the session.
- Each accepted character is appended to the `.anky` writer.
- Show only the latest accepted character/glyph/ritual focus, matching the spirit of the iOS view.
- Show 8-minute progress.
- Show 8-second silence/closing state.
- Save active draft locally as the user writes.
- Restore active draft on app relaunch.
- After 8000ms of silence, close the session, append the terminal silence according to protocol, hash exact bytes, save completed `.anky`, update local index, clear active draft, and navigate to Reveal.
- If the session is abandoned before valid close, preserve draft locally rather than losing writing.

Input restrictions:

- Accept forward-only character input.
- Block paste.
- Block deletion/backspace mutation.
- Block replacement.
- Block rich text.
- Block multi-character insertions unless Android IME composition forces a safe path that still produces exact accepted characters.
- Block newline unless iOS allows it. If unsure, match iOS: no newline.
- Do not allow the user to edit old writing.

Android IME warning:

Android keyboards can emit composing text, suggestions, replacements, and multi-character commits. This is a major risk area. Implement the input layer deliberately and test it. If needed, use a custom `BasicTextField`/hidden input pattern with strict event filtering. The result must preserve Anky's one-directional writing law.

### 3. Reveal

Reveal should read local `.anky` bytes and reconstruct the view from the canonical file.

Requirements:

- Show the reconstructed writing as a view, not as canonical state.
- Show basic session stats: duration, hash, complete/fragment status.
- Allow copy reconstructed text.
- Allow copy exact `.anky` bytes/text.
- Show privacy reminder.
- If fragment: copy-only; no Ask Anky.
- If complete and no saved reflection: show Ask Anky.
- If complete and saved reflection exists: show title/reflection from local store.
- Ask Anky sends exact `.anky` bytes to mirror, with correct headers/signature.
- Save returned reflection locally by hash.
- Never send writing automatically.

### 4. Map

Map is local archive navigation.

Requirements:

- Read local `.anky` archive/index.
- Group sessions by day.
- Show complete vs fragment.
- Show local reflection/title state when available.
- Let the user open a session in Reveal.
- Do not fetch remote content.
- Do not imply cloud backup.

The Map can be visually simple at first. Functional correctness matters more than visual polish.

### 5. You

You should expose local identity, privacy, credits, exports, and settings.

Required behaviors:

- Show public key.
- Copy public key.
- Recovery phrase reveal/copy must require biometric/local auth.
- App lock setting using biometric/local auth.
- Daily reminder setting using Android notification APIs.
- Mirror base URL setting.
- Local export/share of `.anky` archive and/or selected session.
- WhatsApp/free-credit helper message if iOS has it; never include writing content in this message.
- `$ANKY`/link surfaces if currently present in iOS.
- Privacy explanation.
- Credit balance / RevenueCat purchase surface if configured.
- Debug mirror tools only in debug builds.

## `.anky` protocol implementation

Implement the protocol natively in Kotlin.

Do not import the TypeScript implementation into Android runtime. You may use it as a reference.

Rules:

- `.anky` is the canonical state.
- UTF-8 bytes are canonical.
- LF line endings only.
- Do not normalize Unicode.
- Do not trim whitespace.
- Do not convert spaces.
- Do not JSON-wrap sessions.
- Do not reconstruct and then hash.
- Hash exact `.anky` bytes.
- Reconstructed text is only a view.

Implement and test:

- Parser
- Validator
- Writer
- Reconstructor
- Duration calculation
- SHA-256 exact-byte hash
- Complete vs fragment classification
- Fixture validation against `protocol/fixtures/**`

## Mirror API contract

The Android mirror client must match the backend contract exactly.

Endpoint:

```text
POST /anky
Content-Type: text/plain; charset=utf-8
```

Body:

```text
exact .anky bytes
```

Required headers:

```text
X-Anky-Public-Key: <base58 public key>
X-Anky-Signature: <base58 Ed25519 signature>
X-Anky-Request-Time: <epoch ms>
X-Anky-Client: android
```

Canonical signing message:

```text
ANKY_POST_V1
method:POST
path:/anky
request_time:<epoch_ms>
body_sha256:<sha256_hex>
```

Important:

- Confirm exact newline behavior by inspecting the current iOS signer and mirror tests.
- Server derives hash/duration/reconstructed text. Client metadata is not trusted.
- The client must send the exact `.anky` file bytes as the body.
- The body hash in the signature must be SHA-256 of those exact bytes.
- Do not retry in a way that double-spends credits unless backend idempotency is respected.
- Parse mirror errors into clear UI states.
- Do not log raw request body, reconstructed text, prompt, or reflection.

Expected success shape:

```json
{
  "hash": "...",
  "title": "...",
  "reflection": "...",
  "creditsRemaining": 0
}
```

Use the actual backend types/tests as the source of truth if this shape has changed.

## Identity/signing

The Android identity must be compatible with the backend verifier and with the iOS conceptual model.

Requirements:

- Generate or import a local recovery phrase.
- Derive a deterministic Ed25519 signing identity.
- Encode public key as base58.
- Sign the canonical mirror message.
- Store private material locally only.
- Protect private material using Android Keystore-backed encryption or an equivalent platform-secure design.
- Recovery phrase reveal/copy requires biometric/local auth.
- Public key becomes the RevenueCat App User ID.

Critical caution:

Do not assume Android Keystore supports the exact Ed25519 behavior needed across target devices. Prove identity/signature compatibility with tests against the backend verifier and iOS-compatible vectors. If direct Keystore Ed25519 is not viable, use a well-reviewed Ed25519 implementation for signing and protect the seed/private material using Keystore-backed encryption.

## Local storage map

Mirror the iOS storage semantics using Android app-specific internal storage.

Suggested mapping:

```text
Active draft:
  filesDir/Anky/active-draft.anky

Completed .anky sessions:
  filesDir/Ankys/<sha256>.anky

Reflections:
  filesDir/Anky/reflections/<sha256>.json

Session index:
  filesDir/Anky/session-index.json

Settings:
  DataStore Preferences

Identity:
  Keystore-protected encrypted local file / DataStore entry
```

Rules:

- User writing should stay local by default.
- Use internal app-specific storage for canonical files.
- Export/share should be explicit user action.
- Do not require broad storage permissions.
- Consider Android backup rules intentionally. Sensitive identity material should not be backed up accidentally.
- Do not store raw writing in logs, crash breadcrumbs, analytics, or debug output.

## RevenueCat / credits

Implement Android RevenueCat support carefully.

Requirements:

- Use the Android public SDK key, not the iOS public key unless RevenueCat project configuration explicitly says otherwise.
- Never include RevenueCat secret key in the app.
- Log in/configure RevenueCat with the writer public key as App User ID.
- Fetch customer info/virtual currency state if supported by the current SDK/project setup.
- Display credit balance if available.
- Show purchase packages from the configured Android offering.
- Do not hard-code iOS App Store product IDs as Android products.
- If Google Play / RevenueCat Android products are not configured yet, implement the interface with clear disabled states and TODO notes, but do not fake successful purchases.
- Backend remains responsible for spending credits before calling the model.

Known iOS product IDs in the current context:

```text
inc.dev.anky.credits.22
inc.dev.anky.credits.88_bonus_11
inc.dev.anky.credits.333_bonus_88
```

These are references only. Android/Google Play product IDs may need separate configuration.

## Privacy requirements

The Android app must preserve the privacy posture of the repo.

Never log:

- Raw `.anky` body
- Reconstructed writing
- User prompt
- Mirror prompt
- Model response if it contains private reflection content
- Recovery phrase
- Private key / seed
- Signature secret material

Allowed logs:

- App lifecycle events without content
- Hashes
- Public key prefix/suffix if needed
- Duration
- Complete/fragment status
- HTTP status codes
- Safe error codes

Create a `SafeLog` helper and route all logs through it. In release builds, keep logging minimal.

## Tests required before declaring done

Add Android tests that mirror the iOS test coverage.

### JVM/unit tests

Required:

- Protocol parser accepts valid fixtures.
- Protocol parser rejects invalid fixtures.
- Reconstructor output matches expected fixtures.
- Duration calculation matches fixture expectations.
- Writer emits expected `.anky` lines for deterministic clock input.
- SHA-256 hash is over exact UTF-8 bytes.
- Complete vs fragment classification is correct.
- Mirror eligibility rejects fragments and invalid files.
- Canonical signing message matches iOS/backend expectations.
- Ed25519 signature verifies with backend-compatible verifier.
- Base58 public key/signature encoding is compatible.
- Mirror client sends exact request body bytes.
- Mirror client sends required headers.
- Mirror client handles insufficient credits, invalid signature, incomplete Anky, and server disabled errors.
- Active draft save/restore works.
- Completed archive save/read/list works.
- Reflection save/read by hash works.
- Session index updates correctly.
- Recovery phrase/private key never appears in safe log output.

### Android instrumentation / Compose tests

Required where feasible:

- App opens to Write.
- Write input gains focus.
- Accepted character appears as current ritual focus.
- Backspace/delete does not mutate previous `.anky` content.
- Paste/multi-character replacement is blocked or safely decomposed according to the protocol.
- 8000ms silence closes a session when using injectable clock/test scheduler.
- Reveal shows copy-only state for fragments.
- Reveal shows Ask Anky only for complete sessions.
- Map lists local saved sessions.
- You shows public key and gates recovery phrase behind auth, using a fake biometric gate in tests.

### Suggested commands

From `apps/android`:

```bash
./gradlew test
./gradlew connectedDebugAndroidTest
./gradlew assembleDebug
```

From repo root, optionally add:

```bash
make android-test
make android-build
```

Do not break existing checks:

```bash
bun test
bun run typecheck
swift test --package-path apps/ios --scratch-path /tmp/anky-ios-swiftpm
```

Use the existing iOS build command from `apps/ios/README.md` when needed.

## Acceptance criteria

The goal is complete when:

- `apps/android` contains a real native Android project.
- Android app builds successfully.
- Android protocol implementation passes fixture tests.
- Android mirror signing passes backend-compatible tests.
- Android Write produces canonical `.anky` files locally.
- Android Reveal reconstructs from `.anky`, not from alternate state.
- Android Ask Anky sends exact signed `.anky` bytes and saves reflection locally.
- Android Map reads local archive and opens Reveal.
- Android You exposes local identity/settings/export/privacy/credits surfaces.
- No React Native/Expo/Flutter dependencies exist.
- No raw writing is logged.
- No server-side storage assumptions are introduced.
- No backend API contract changes are required.
- Existing iOS and mirror tests still pass.
- README for `apps/android` explains build/test/run setup and known gaps.

## Implementation order

Work in this order:

1. Inspect docs, iOS app, tests, protocol, and mirror.
2. Create minimal Gradle Android project.
3. Add Kotlin protocol implementation and fixture tests.
4. Add storage layer and tests.
5. Add identity/signing layer and backend-compatible tests.
6. Add mirror client and MockWebServer tests.
7. Add Write flow with injectable clock/scheduler.
8. Add Reveal flow.
9. Add Map flow.
10. Add You/settings/privacy/export flow.
11. Add RevenueCat integration or disabled placeholder if Android products are not configured.
12. Add instrumentation/Compose tests.
13. Update `apps/android/README.md`.
14. Add root Makefile helpers if useful.
15. Run all tests/builds and summarize remaining gaps honestly.

## Visual/design guidance

Do not overdesign.

The iOS app is the behavioral reference, but Android should feel native.

The ritual should feel:

- quiet
- focused
- fast
- local
- private
- direct

Avoid decorative complexity until parity is stable.

The writing screen should be the most protected surface. No extra buttons, no promotional content, no purchase prompts, no network state, no feed, no streak pressure.

## Known risk areas

### 1. Android text input

This is the biggest implementation risk. Android IMEs are complex. The Anky protocol requires strict accepted-character behavior. Write tests before trusting the UI.

### 2. Ed25519 compatibility

The backend expects Solana-style Ed25519 public keys/signatures encoded in base58. Prove compatibility with tests. Do not assume a platform API works until tested.

### 3. Exact bytes

Any newline normalization, Unicode normalization, trimming, or JSON wrapping breaks the contract.

### 4. RevenueCat Android setup

iOS product IDs are not necessarily Android product IDs. If Android Play products are not configured yet, keep the UI honest and disabled rather than faking credit purchases.

### 5. Privacy regressions

Android logs and crash tooling can leak text if careless. Add `SafeLog` early and use it everywhere.

### 6. Product drift

Do not add social, cloud, AI companion chat, onboarding funnels, streak systems, or Solana sealing in this goal. Those may exist later, but not in this Android parity build.

## Final response expected from Codex

When done, summarize:

- Files created/changed.
- What works.
- What is intentionally not implemented.
- Exact commands run and results.
- Known blockers/gaps.
- Whether any external configuration is still needed, especially RevenueCat Android products, Google Play setup, or mirror env configuration.

Do not claim production readiness if tests were not run.
Do not hide privacy or signing uncertainty.
Do not invent successful RevenueCat purchases without real configuration.

## North star

The Android app should prove that Anky is not an iOS app.

Anky is a protocol and a ritual.

The Android app is simply another native vessel for the same 8 minutes.
