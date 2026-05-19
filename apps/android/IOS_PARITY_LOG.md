# iOS Delta Parity Log

## 2026-05-16 Delta Pass

Baseline:

- Previous Android parity baseline: `736e743 Bring Android app to iOS parity`
- iOS deltas synced: `6d30d32 Implement device-bound trial credits`, `52f6aab Polish reveal privacy copy`
- Controlling brief: `ANKY_ANDROID_DELTA_PARITY_GOAL.md`

Migrated Android changes:

- Reveal now uses the iOS-style bottom floating `ask anky` prompt that scrolls the user to the inline Ask Anky action.
- Reveal Ask Anky inline action uses `8 free reflections included`.
- Reveal copy is section-aware with `copy writing` / `copy reflection` and short copied-state feedback.
- Saved reflections render local `creditsRemaining` as `N reflection(s) left` when present.
- Reveal has a local delete affordance and Android-native confirmation using `delete forever?`.
- `RevealViewModel` deletes only local `.anky`, local reflection, and local session-index state.
- `RevealViewModel` invalidates credit balance cache through a narrow `CreditsClient.invalidateCreditBalanceCache()` hook when Ask Anky returns non-null `creditsRemaining`.
- Unit coverage was added for credit-cache invalidation, null-credit no-op behavior, and local Reveal deletion.

Skipped / intentional divergence:

- Android device-bound trial proof remains intentionally unimplemented.
- Android must not send `X-Anky-Trial-Proof` until a Play Integrity/device recall design exists with server-side verification.
- No fake credits, client-issued trial credits, or public-key-only trial grants were added.

Validation run in this pass:

- `./gradlew testDebugUnitTest --tests inc.anky.android.feature.reveal.RevealViewModelTest --tests inc.anky.android.mirror.MirrorClientTest`
- First attempt failed because Java was not on the default path.
- Re-run with `JAVA_HOME=/Users/kithkui/.local/share/mise/installs/java/corretto-17.0.19.10.1` but no `ANDROID_HOME` reached Gradle and stopped with `SDK location not found`.
- Final focused run with `JAVA_HOME=/Users/kithkui/.local/share/mise/installs/java/corretto-17.0.19.10.1 ANDROID_HOME=/opt/homebrew/share/android-commandlinetools` passed with `BUILD SUCCESSFUL in 10s`.
- Full `testDebugUnitTest` passed with `BUILD SUCCESSFUL in 1s`.
- `assembleDebug` passed with `BUILD SUCCESSFUL in 3s`.
- `adb devices` showed no attached devices, so `connectedDebugAndroidTest` was not run.
- `git diff --check -- apps/android` passed.
- Targeted parity search for `X-Anky-Trial-Proof|X-Anky-App-Version|creditsRemaining|8 free reflections included|copy writing|copy reflection|delete forever` was run from repo root.

Privacy/protocol notes:

- No `.anky` protocol, parser, writer, hash, signing, mirror body, or mirror signature semantics were changed.
- Android still sends raw `.anky` bytes to `POST /anky`.
- Android still sends `X-Anky-App-Version`.
- Android still must not send `X-Anky-Trial-Proof`.
- No logging of copied writing, reflection text, raw `.anky`, recovery phrase, private key, seed, or signature material was added.
