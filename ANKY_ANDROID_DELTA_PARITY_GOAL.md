# ANKY Android iOS Delta Parity Goal

## Purpose

This file is the controlling brief for a **delta parity pass** from the canonical SwiftUI iOS app into the native Android app.

This is **not** a full Android rewrite and **not** another broad photocopy pass. The previous Android parity baseline is already in place. The goal now is to migrate only the latest iOS changes that are missing or stale on Android.

## Current Baseline

The previous full Android parity baseline was identified by audit as:

```text
736e743 Bring Android app to iOS parity
```

The latest iOS deltas identified by audit are:

```text
6d30d32 Implement device-bound trial credits
52f6aab Polish reveal privacy copy
```

Treat `apps/ios` as the canonical implementation, but preserve the existing Android architecture and style that came from the previous parity pass.

## High-Level Instruction

Implement the **safe iOS-to-Android delta parity changes** identified by the latest audit, while explicitly excluding Android device-bound trial proof for now.

Android should continue to feel like the same Anky vessel as iOS. Do not redesign. Do not make generic Material substitutes when the Swift app has a specific product language.

## Non-Negotiable Invariants

Do not change or weaken any of these:

1. `.anky` protocol semantics.
2. Local-first writing.
3. Exact mirror request body semantics: raw `.anky` bytes, not JSON.
4. Ed25519/signing behavior.
5. Local archive/storage behavior.
6. Privacy posture: no raw writing logs, no raw `.anky` logs, no recovery phrase/private key/seed logs.
7. RevenueCat secret handling: public SDK keys only in app; secret keys stay server-side.
8. No backend requests during writing, archive browsing, copy, export, app open, or local reminder changes.
9. No fake credits, no client-issued free grants, no public-key-only trial grant.
10. Do not send `X-Anky-Trial-Proof` from Android unless backed by a trustworthy Android proof implementation.

## Explicitly Out of Scope

Do **not** implement Android device-bound trial proof in this goal.

The iOS app uses DeviceCheck for device-bound trial proof. Android needs a separate trust design, probably involving Play Integrity and/or device recall, with server-side verification. That is not a simple UI parity change.

For now:

- Android trial proof remains intentionally disabled.
- Android must not send `X-Anky-Trial-Proof`.
- Android must not add public-key-only free credits.
- Android must not client-self-issue trial credits.
- Document this as an intentional platform divergence.

A separate design goal should handle Android trial proof later.

## Canonical iOS Sources To Read

Start by reading the relevant Swift files before changing Android:

```text
apps/ios/Anky/Features/Reveal/RevealView.swift
apps/ios/Anky/Features/Reveal/RevealViewModel.swift
apps/ios/Anky/Core/Mirror/DeviceCheckTrialProofProvider.swift
apps/ios/Anky/Core/Mirror/MirrorClient.swift
apps/ios/Anky/Core/Credits/RevenueCatCreditsClient.swift
```

Also search current iOS for these strings / symbols:

```text
AskReflectionFloatingButton
FloatingCopyButton
SavedReflectionPanel
creditsRemaining
8 free reflections included
copy writing
copy reflection
delete forever?
didTapReflectionPrompt
invalidateCreditBalanceCache
X-Anky-Trial-Proof
X-Anky-App-Version
```

## Android Areas Likely Requiring Updates

Inspect and modify only where needed:

```text
apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealScreen.kt
apps/android/app/src/main/java/inc/anky/android/feature/reveal/RevealViewModel.kt
apps/android/app/src/main/java/inc/anky/android/core/mirror/MirrorClient.kt
apps/android/app/src/main/java/inc/anky/android/core/credits/RevenueCatCreditsClient.kt
apps/android/app/src/test/java/.../MirrorClientTest.kt
apps/android/app/src/test/java/.../RevealViewModelTest.kt
apps/android/IOS_PARITY_MAP.md
apps/android/IOS_PARITY_LOG.md
apps/android/ANDROID_DEVICE_QA.md
```

If file names differ, locate the equivalent Android files by searching.

## Implementation Scope

### 1. Reveal Ask Anky CTA parity

Port the current iOS Reveal CTA behavior into Android.

Requirements:

- Use the bottom floating Ask Anky prompt/button pattern from SwiftUI.
- Remove or replace stale inline Android CTA patterns if they conflict with iOS.
- Match iOS copy and visual hierarchy.
- Include the iOS badge/copy where appropriate, especially:

```text
8 free reflections included
```

- Preserve Android-native accessibility and touch target behavior.
- Do not alter mirror request body/signature semantics.

### 2. Reveal copy UX parity

Port the iOS floating copy behavior.

Requirements:

- Support separate copy actions for:
  - writing text
  - reflection text
- Use iOS-equivalent labels:
  - `copy writing`
  - `copy reflection`
- Add copied state / short flash behavior comparable to iOS.
- Use Android-native haptics where appropriate.
- Do not log copied content.
- Do not copy `.anky` or writing unless the user explicitly taps the relevant copy action.

### 3. Saved reflection credits display

If a saved local reflection includes `creditsRemaining`, render the remaining-reflections line like iOS.

Requirements:

- Preserve `LocalReflection.creditsRemaining` persistence.
- Show remaining reflections/credits in the saved reflection panel when present.
- Do not invent or fetch credits just to render saved local state.
- Make singular/plural copy match iOS where possible.

### 4. Reveal delete affordance parity

Add the Reveal delete action and confirmation flow matching iOS.

Requirements:

- Match iOS tone/copy, including:

```text
delete forever?
```

when that is the canonical iOS copy.

- Delete only local archive/reflection state as iOS does.
- Do not delete server state.
- Do not make network calls.
- Use Android-native confirmation UI.
- Use haptic warning where appropriate.

### 5. Credit refresh after Ask Anky

When `Ask Anky` returns a response with non-null `creditsRemaining`, Android should invalidate or refresh local RevenueCat/credits state through a narrow interface.

Requirements:

- Add a focused method such as `invalidateCreditBalanceCache()` or equivalent if missing.
- Inject/call this from `RevealViewModel` only when response credits are present.
- Do not couple Reveal directly to broad RevenueCat internals.
- Add/update unit tests for this behavior.
- Preserve current behavior when RevenueCat is not configured.

### 6. Documentation updates

Update Android parity documentation.

Requirements:

- Update `apps/android/IOS_PARITY_MAP.md` so it does not claim stale Reveal parity.
- Update or create `apps/android/IOS_PARITY_LOG.md`.
- Document:
  - latest iOS delta baseline
  - migrated Android changes
  - skipped changes
  - explicit Android trial-proof divergence
  - validations run
- Update `ANDROID_DEVICE_QA.md` only if new Reveal QA steps are needed.

## Required Tests / Validation

Run these from `apps/android` when feasible:

```bash
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

If a connected device/emulator exists, also run:

```bash
./gradlew connectedDebugAndroidTest
```

Run targeted search checks from repo root:

```bash
rg -n "X-Anky-Trial-Proof|X-Anky-App-Version|creditsRemaining|8 free reflections included|copy writing|copy reflection|delete forever" apps/android apps/ios
git status --short
```

Expected outcomes:

- Tests pass or failures are explained precisely.
- Android still does not send `X-Anky-Trial-Proof`.
- Android still sends `X-Anky-App-Version` if already implemented.
- `creditsRemaining` is persisted and rendered where appropriate.
- Credit cache invalidation happens after Ask Anky responses with non-null `creditsRemaining`.
- Reveal CTA/copy/delete behavior now matches iOS deltas.

## Acceptance Criteria

This goal is complete when:

1. Android Reveal matches the latest iOS Reveal CTA behavior.
2. Android copy UX supports separate writing/reflection copy actions with copied-state feedback.
3. Saved reflection panels show remaining credits/reflections when available.
4. Reveal delete affordance and confirmation flow match iOS.
5. Ask Anky response handling refreshes/invalidates credit state when `creditsRemaining` is returned.
6. Android trial proof remains intentionally unimplemented and documented.
7. No privacy/protocol/storage/signing/backend invariants are changed.
8. Android tests/builds are run or blockers are explicitly documented.
9. `IOS_PARITY_MAP.md` / `IOS_PARITY_LOG.md` accurately reflect the current state.

## Completion Report Format

Finish with a concise report:

```text
Implemented:
- ...

Files changed:
- ...

Tests/validations run:
- ...

Remaining gaps:
- ...

Intentional platform divergences:
- Android device-bound trial proof remains disabled until Play Integrity/device recall design.

Privacy/protocol notes:
- No changes to .anky protocol, mirror body, signing, local-first storage, or logging.
```

## Reminder

Do not redesign Anky. Do not make Android generic. This is a disciplined delta sync from Swift to Android.
