# iOS Delta Parity Log

## 2026-05-27 Delta Pass

Baseline:

- Source of truth: current dirty iOS worktree in `apps/ios/Anky`.
- Android delta target: port the new Write portal/nudge, Reveal chat invitation/copy behavior, You prompt-driven home, and mirror intent header.

Migrated Android changes:

- Mirror requests now send `X-Anky-Intent: reflection` by default and can send `X-Anky-Intent: nudge` for the new in-writing Anky nudge path.
- Write now tracks per-glyph settling color, renders the smaller bottom-right portal-style ritual ring, keeps the latest glyph red-to-white through silence, and lets tapping Anky during an unfinished session request a one-line nudge from the mirror.
- Write nudge copy matches the iOS shape: `anky is listening to this .anky for one line.`, one-line heading stripping, credit/incomplete-specific errors, and a transient six-second prompt.
- Write rejected-input handling now matches the current iOS nudge: rejected deletion/replacement/paste surfaces `that doesn't work here. just keep writing without agenda.` transiently and uses Android haptics from the input surface.
- Reveal now uses the bottom Anky conversation invitation instead of the old inline/floating mirror controls, including reflection-status progress copy while the mirror request is running.
- Reveal writing is tap-to-copy with a clipboard burst, saved reflection display removes a duplicated leading markdown heading matching the reflection title, and inline `*emphasis*` markdown is rendered.
- Reveal saved-reflection tap-copy was removed on Android because the current iOS view only wires tap-copy on reconstructed writing; a source parity guard now keeps Android from reintroducing an `Anky mirror` clipboard path without an iOS surface change.
- You home now follows the prompt-driven iOS update: no subtitle/avatar on the first screen, prompt rows for identity/privacy/data/credits/support/developer, no disclosure chevrons, and a bottom Anky conversation panel with up to two contextual actions.
- You backup prompt behavior now matches the current iOS shape: You home prepares the backup on entry, `export backup` appears only after a backup file exists, `restore backup` is always available, and the earlier Android-only `prepare backup` chat action is gone.
- Shared Android companion prompt UI now supports up to two chat actions with primary/secondary styling like the updated Swift `AnkyChatAction`.
- The presence overlay can delegate taps to Write before toggling hide/show, matching the new iOS Anky-tap nudge behavior.

Validation run in this pass:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.mirror.MirrorClientTest --tests inc.anky.android.privacy.SourceInvariantTest --tests inc.anky.android.feature.reveal.RevealViewModelTest` passed.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.write.WriteViewModelTest` passed with focused nudge coverage for immediate listening copy, `X-Anky-Intent: nudge` request intent, one-line heading stripping, six-second prompt clearing, and iOS rejected-input copy clearing.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest --tests inc.anky.android.feature.reveal.RevealViewModelTest` passed after aligning Reveal copy behavior to the current iOS writing-only tap surface.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest --tests inc.anky.android.mirror.MirrorClientTest` passed after tightening the explicit Write nudge test seam.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest --tests inc.anky.android.feature.you.YouViewModelStateTest` passed with `BUILD SUCCESSFUL in 2s` after aligning the You export prompt actions to current iOS.
- `./gradlew :app:test :app:assembleDebug :app:lintDebug` passed with `BUILD SUCCESSFUL in 9s` after the Write nudge test seam, immediate-listening prompt update, rejected-input copy alignment, and Reveal writing-only copy alignment.
- `./gradlew :app:test :app:assembleDebug :app:lintDebug :app:printReleaseSigningStatus` passed with `BUILD SUCCESSFUL in 10s`; release identity is `app.anky.mobile`, debug identity is `app.anky.mobile.debug`, version is `0.1.0` / `2026052002`, and `releaseSigningConfigured=false`.
- `xcodebuild -project ios/Anky.xcodeproj -scheme Anky -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' -derivedDataPath /tmp/anky-ios-parity-dd build` passed with `BUILD SUCCEEDED`.
- `git diff --check -- android` passed.
- Fresh Android 30 emulator screenshots were captured from the current debug APK:
  - `qa-screenshots/android-emulator-20260527-write-idle.png`
  - `qa-screenshots/android-emulator-20260527-write-active.png`
  - `qa-screenshots/android-emulator-20260527-map-current-seeded.png`
  - `qa-screenshots/android-emulator-20260527-map-day-current-seeded.png`
  - `qa-screenshots/android-emulator-20260527-reveal-saved-reflection.png`
  - `qa-screenshots/android-emulator-20260527-you-main.png`
- The seeded Reveal run used a same-day complete `.anky` plus local reflection sidecar and verified the updated saved-reflection hierarchy: duplicated leading title heading removed, inline emphasis rendered, quote and bullets rendered, and `7 reflections left` shown.

Privacy/protocol notes:

- Write now has an explicit, user-triggered mirror path only for tapping Anky during an unfinished session. The source invariant was updated to allow only that nudge path and still reject direct OkHttp/RevenueCat/purchase clients in Write.
- Android still does not send `X-Anky-Trial-Proof`.
- No asset migration was required for this delta; the iOS changes reused existing migrated sprites/icons/backgrounds.

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
