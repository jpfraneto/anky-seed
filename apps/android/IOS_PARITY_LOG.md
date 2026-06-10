# iOS Delta Parity Log

## 2026-06-10 Write Terminal Silence Continuation Fix

Baseline:

- Product-critical flow: the Write page seals the current `.anky` after 8 seconds of silence, stores it locally, then hands the user through Map into Reveal. If the artifact is still under 8 minutes, Reveal's `CONTINUE` action must return directly to Write with that writing loaded.
- iOS root flow uses `revealAfterWriting` as a pending Map-to-Reveal handoff and routes Reveal's continue action back through `beginContinuingWriting(from:)`.

Migrated Android changes:

- Android post-write completion now stores a pending reveal hash, navigates to Map first, then opens Reveal after the Map route is active, matching the iOS two-step handoff instead of firing Map and Reveal navigation back-to-back.
- Android `WriteViewModel.continueSession()` now reopens incomplete terminal-silence artifacts by trimming the terminal silence for the active draft, rendering the existing writing in the Write surface, freezing silence until the next glyph, and focusing the hidden input.
- Continued fragments now replace the previous fragment artifact/index entry when saved again, matching iOS' `continuedArtifactToReplace` intent and avoiding duplicate fragment rows on Map.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.write.WriteViewModelTest.terminalSilenceFragmentContinuesInWriteAndReplacesOldFragment` passed.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.write.WriteViewModelTest --tests inc.anky.android.privacy.SourceInvariantTest.postWriteCompletionRoutesThroughMapIntoRevealLikeIos --tests inc.anky.android.privacy.SourceInvariantTest.shortSessionTryAgainRoutesThroughRootRetryWritingLikeIos` passed.
- `./gradlew :app:testDebugUnitTest :app:assembleDebug` passed.

Known follow-up:

- Device/emulator QA should still manually verify the visible Write -> Map -> Reveal transition after an 8-second silence and the Reveal `CONTINUE` button returning to the loaded Write page.

## 2026-06-10 You Credits Sheet Footer Parity Pass

Baseline:

- Source of truth: current dirty iOS `Features/Credits/AnkyReflectionCreditsSheet.swift`, where the shared reflection credits sheet uses the shorter `Your private space to be witnessed.` subtitle, a native refresh symbol, and a second footer line explaining the long-press copy / external AI fallback.
- Android target: keep the You-owned credits modal aligned with the shared iOS credits sheet, not only the Reveal-owned sheet.

Migrated Android changes:

- Replaced the You credits sheet text refresh affordance with `Icons.Filled.Refresh` and the same `Refresh reflection credits` accessibility copy used by the current credit sheet strings.
- Added the shared `credits_sheet_prompt_copy_fallback` footer line to the You credits modal, matching the current iOS no-payment guidance.
- Tightened source parity coverage so the You credits modal keeps the current footer and icon refresh treatment.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.youHomeRowsMatchCurrentIosPromptAndLegalShape` passed.
- `./gradlew :app:testDebugUnitTest :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- This pass was verified by source invariant and build checks. Manual side-by-side You credits sheet screenshot QA remains pending.

## 2026-06-08 Reveal Credit Sheet Icon Parity Pass

Baseline:

- Source of truth: current dirty iOS `Features/Credits/AnkyReflectionCreditsSheet.swift`, where the sheet uses native symbol imagery for refresh and ornamental credit-sheet marks.
- Android target: remove text-glyph refresh/star stand-ins from the visible Reveal reflection credits sheet and use native Compose icon components.

Migrated Android changes:

- Replaced the Reveal credit sheet refresh glyph with `Icons.Filled.Refresh`.
- Replaced the footer star text glyphs with `Icons.Filled.AutoAwesome`, matching the icon-component treatment already used by the You credit sheet.
- Source parity coverage now asserts the Reveal credit sheet keeps native icons and does not render the old `↻` / `✦` text glyphs.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.revealCreditPurchaseSheetUsesCurrentIosCreditsSurface` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- This pass was verified by source invariant and build checks. Manual side-by-side sheet screenshot QA remains pending.

## 2026-06-08 You Credits Sheet Flow Parity Pass

Baseline:

- Source of truth: current dirty iOS `Features/You/YouView.swift` and `Features/Credits/AnkyReflectionCreditsSheet.swift`, where the You `Credits` row calls `openCreditsSheet()` and presents `.ankyReflectionCreditsSheet(...)`.
- Android target: make the main You Credits row open the same reflection-credits sheet surface instead of navigating to a full detail page.

Migrated Android changes:

- Added a You-owned `ModalBottomSheet` for reflection credits, backed directly by `YouState`.
- Reused the current iOS credit sheet copy and artwork: `Anky reflection credits`, `Your space to be seen, held, and mirrored.`, `credits_thread_background`, `available credits`, `best value`, and `Writing is free. One credit = one reflection.`
- The You Credits row now clears the companion prompt, opens the sheet, and refreshes credits, matching iOS' `openCreditsSheet()` behavior.
- Kept the existing direct `YouPage.Credits` route for native deep links / Reveal handoff while making the main row sheet-first like iOS.
- Source parity coverage now asserts the iOS credits sheet presenter and Android `ModalBottomSheet` / `YouReflectionCreditsSheet` path.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.youHomeRowsMatchCurrentIosPromptAndLegalShape` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- This pass was verified by source invariant and build checks. Live purchase/balance QA still needs configured RevenueCat and Google Play products.

## 2026-06-08 You Inline Title Parity Pass

Baseline:

- Source of truth: current dirty iOS `Features/You/YouView.swift`, which uses `.navigationTitle("You")` with `.navigationBarTitleDisplayMode(.inline)` and a trailing destructive-toggle toolbar item.
- Android target: restore compact native-style You screen title chrome without bringing back the stale large tappable `you` title from the older home layout.

Migrated Android changes:

- Added a compact centered `You` title at the top of Android `YouHome`.
- Moved the main row panel below the compact title area.
- Kept the red exclamation toggle in the top-right position, matching iOS' title-plus-trailing-toolbar composition.
- Updated source parity coverage to assert iOS inline navigation title and Android compact top title.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.youHomeRowsMatchCurrentIosPromptAndLegalShape` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- This pass was verified by source invariant and build checks. Manual screenshot QA should confirm top spacing and title weight against iOS.

## 2026-06-08 You First-Screen Composition Parity Pass

Baseline:

- Source of truth: current dirty iOS `Features/You/YouView.swift` body. The live first screen renders the main `YouPanel` rows under the native navigation title; older `YouTitle`, `YouStatsPanel`, and `AnkyExperienceView` structs remain in the Swift file but are not mounted by the current body.
- Android target: remove stale visible Android-only You header/stats entry points from the live first screen while retaining existing native code paths that are not currently mounted.

Migrated Android changes:

- Removed the large tappable `you` title from Android `YouHome`.
- Removed the visible stats panel from Android `YouHome`, so the first screen now starts with the current Swift-shaped main row panel.
- Left the retained local history and Anky Experience implementations in source, matching Swift's retained-but-unmounted code shape.
- Updated source invariants to assert Android no longer mounts the stale visible title/stats call while preserving the retained implementations.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.youExperienceCodeIsRetainedButNotVisibleOnCurrentHome --tests inc.anky.android.privacy.SourceInvariantTest.youStatsOpenCurrentIosAllAnkysHistory --tests inc.anky.android.privacy.SourceInvariantTest.youHomeRowsMatchCurrentIosPromptAndLegalShape` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- This pass was verified by source invariant and build checks. Manual screenshot QA should confirm the resulting top spacing against iOS' native navigation title area.

## 2026-06-08 You Token Row Icon Parity Pass

Baseline:

- Source of truth: current dirty iOS `Features/You/YouView.swift`, where the `$ANKY on Base` menu row uses `you-icon-anky-token`, mapped to the native `dollarsign.circle` symbol.
- Android target: stop using the large `$ANKY` coin art as the small row icon while keeping the coin art on the token detail page.

Migrated Android changes:

- Added `you_icon_anky_token.xml`, a small gold token-circle vector for the You home row.
- Switched the `$ANKY on Base` `PromptRow` to `R.drawable.you_icon_anky_token`.
- Kept `you_ankycoin.png` on the `$ANKY` detail page, matching iOS' separation between row symbol and detail artwork.
- Updated source parity coverage so the You row shape requires the token-row icon and the detail page still uses the migrated coin image.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.youHomeRowsMatchCurrentIosPromptAndLegalShape` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- This pass was verified by source invariant and build checks. Manual visual QA should still confirm final icon weight/color against iOS.

## 2026-06-08 You Device Lock Toggle Reachability Pass

Baseline:

- Source of truth: current dirty iOS `Features/You/YouView.swift`, especially `shouldShowFaceIDControl`, `YouToggleRow`, and `setFaceID(_:)`.
- Android target: keep app-lock control reachable from the production You home like iOS, while using Android-native device credential / biometric confirmation.

Migrated Android changes:

- You home now shows a main-panel `Device lock` / biometric lock row when Android reports usable biometric or device credential authentication.
- The row uses the same visible status shape as iOS, showing `On` or `Off` beside the toggle state.
- Enabling the row now routes through root `DeviceBiometricGate.authenticate("Protect ANKY with your device lock.")`, marks the one-time device-lock prompt completed, and skips the immediate duplicate unlock prompt after a successful enable.
- Disabling the row turns off app lock directly through `UserSettingsStore`, matching iOS' direct-off behavior.
- The retained Account page app-lock switch now uses the same authenticated root callback if that route is opened later.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.youHomeDeviceLockToggleMatchesCurrentIosReachability` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- This pass was verified by source invariant and JVM/assembly checks. Real device QA still needs to exercise the actual Android system credential prompt.

## 2026-06-08 Delete Account and Data Parity Pass

Baseline:

- Source of truth: current dirty iOS `Features/You/YouView.swift` and `Features/You/YouViewModel.swift`, especially the `Delete Account and Data?` confirmation and `deleteAccountAndDataEverywhere()` destructive reset.
- Android target: add the missing Android-native account/data deletion path while keeping platform differences explicit: local device data, Android settings/reminders, secure identity, RevenueCat logout, and cached credit state.

Migrated Android changes:

- You Account now exposes a red danger-zone `DELETE ACCOUNT AND DATA` action with the iOS confirmation title/buttons and Android-native device-only warning copy.
- You home now mirrors iOS' hidden destructive-entry pattern: a red exclamation control toggles the `DELETE ACCOUNT AND DATA` row without adding an always-visible account row to the main panel.
- `YouViewModel.deleteAccountAndDataEverywhere()` clears local `.anky` files, reflections, pending reflection requests, the session index, active draft, first-open state, settings/reminders, local identity, RevenueCat session/package cache, and per-account reflection credit cache.
- Successful deletion resets You state to an empty local identity/credits/stats surface and keeps the success message visible: `Account and data deleted from this device.`
- Root cleanup now clears the active Write state, refreshes Map, and removes the root credit badge without immediately recreating the You view model.
- `WriteViewModel.resetAfterAccountDeletion()` cancels pending close/nudge/error work, clears the active draft, and prevents a pending writing session from archiving after the account delete.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.feature.you.YouViewModelStateTest --tests inc.anky.android.write.WriteViewModelTest --tests inc.anky.android.privacy.SourceInvariantTest.youDeleteAccountAndDataMatchesCurrentIosDestructiveFlow` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- This pass was verified by JVM tests and source invariants. Device-level QA should still exercise the destructive flow with real Android credentials and a configured RevenueCat session.

## 2026-06-08 You Local History Parity Pass

Baseline:

- Source of truth: current dirty iOS `Features/You/YouView.swift` and `Features/You/YouViewModel.swift`, especially `YouAllAnkysHistoryView`, `YouRoute.allAnkys`, and the tappable stats panel.
- Android target: add the missing native You history surface so the stats panel can open all local complete `.anky` sessions like iOS.

Migrated Android changes:

- `YouState` now exposes `completeAnkySessions`, derived from the same rebuilt local `SessionIndexStore` data that powers Map.
- The You stats panel is now tappable and exposes the iOS accessibility label `Open all ankys`.
- Added a native Compose `YouHistoryPage` using the Map background texture, dark ink overlay, 87% responsive content width, `N anky/ankys` title, iOS-style empty `0 ankys` state, and `WRITE 8 MINUTES` CTA.
- History rows render local complete sessions with reflection title/fallback title, medium-date/short-time metadata, word count, divider, chevron, and tap-through to the existing Reveal route by hash.
- Empty history CTA routes through the existing root retry-writing path so it returns to Write and opens the writing portal.

Validation run:

- `./gradlew :app:compileDebugKotlin` passed.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.feature.you.YouViewModelStateTest --tests inc.anky.android.privacy.SourceInvariantTest.youStatsOpenCurrentIosAllAnkysHistory` passed.

Known follow-up:

- This pass was verified by source invariants/JVM tests. It still needs visual QA against iOS' `YouAllAnkysHistoryView`.

## 2026-06-08 Reflection Credit Cache Parity Pass

Baseline:

- Source of truth: current dirty iOS `Core/Mirror/MirrorEligibility.swift`, `Features/Reveal/RevealViewModel.swift`, and `Features/You/YouViewModel.swift`.
- Android target: mirror iOS' per-account `ReflectionCreditCache` behavior so Reveal and You can show the last known credit balance immediately, preserve free-reflection claimed state, and keep balances current after mirror, refresh, purchase, and restore paths.

Migrated Android changes:

- Added `ReflectionCreditCache` with a `SharedPreferencesReflectionCreditCache` implementation using the same `anky.hasClaimedFreeReflections.<accountId>` and `anky.reflectionCreditBalance.<accountId>` key shapes as iOS, with fallback to Android's previous global free-claim preference.
- `AppContainer` now owns the shared credit cache and injects it into Reveal and You.
- Reveal now seeds `creditBalance` from the per-account cache, reads/marks the cached free-reflection claim through the same cache, stores non-null mirror `creditsRemaining`, and writes refreshed/purchased balances back to the cache.
- You now seeds its credits state from the same per-account cache and writes refresh, purchase, and restore balances back under the configured account id.
- You credits now mirrors iOS' unspent-gift gate: the page shows the device gift caption/detail, package rows are locked, conversation purchase actions are suppressed, and direct purchase attempts return `Use this device's first two reflections before buying more credits.` until the free-reflection claim has been marked.
- You now rereads local identity, cached credit balance, cached free-claim state, and local stats on screen entry like Swift's `viewModel.refresh()` on appear.
- Source parity coverage asserts iOS and Android both keep per-account credit/free-claim cache reads, write-backs, and unspent-gift purchase gating wired through Reveal and You.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.feature.reveal.RevealViewModelTest --tests inc.anky.android.feature.you.YouViewModelStateTest --tests inc.anky.android.privacy.SourceInvariantTest.reflectionCreditBalanceCacheMirrorsIosPerAccountPersistence` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- This was verified with JVM tests and source invariants. Live RevenueCat / Google Play credit balance and purchase behavior still needs configured-device QA.

## 2026-06-08 Reveal Credits Sheet Parity Pass

Baseline:

- Source of truth: current dirty iOS `Features/Credits/AnkyReflectionCreditsSheet.swift` and its Reveal presenter.
- Android target: align the active Reveal credit-purchase sheet with the current iOS credit surface instead of leaving the newly migrated credits background asset unused.

Migrated Android changes:

- Reveal credit purchase sheet now uses the iOS title and subtitle: `Anky reflection credits` and `Your space to be seen, held, and mirrored.`
- The available-credit card now uses the migrated `credits_thread_background` image with the same `available credits` framing.
- Credit package rows now use the larger iOS-style row treatment, sparkle icon, serif title/price scale, and `best value` badge for the 11-reflection pack.
- Footer copy now matches iOS: `Writing is free. One credit = one reflection.`
- Source parity coverage asserts the active Android Reveal sheet stays aligned with the iOS credits sheet copy, badge, and image asset.

Validation run:

- `./gradlew :app:compileDebugKotlin` passed.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.revealCreditPurchaseSheetUsesCurrentIosCreditsSurface` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.

Known follow-up:

- This was not live-purchase tested. RevenueCat / Google Play purchase validation still requires configured Android products and a device/test account.

## 2026-06-08 Device Lock Activation Prompt Parity Pass

Baseline:

- Source of truth: current dirty iOS `AppRoot.presentFaceIDActivationPromptIfNeeded()` and `AnkyLocalization` device-lock copy.
- Android target: add the missing native Android prompt that offers device-lock app protection after the user has at least one complete `.anky`.

Migrated Android changes:

- Android settings now persist `deviceLockPromptCompleted`, mirroring iOS' one-time privacy onboarding completion flag.
- Android root now checks for an existing complete local session, available device credential/biometric support, app lock disabled, and prompt not completed before showing an activation dialog.
- Dialog copy matches current iOS in Android-native terms: `Activate Device Lock` and `Protect your Anky with your device lock. Your writing is local, and this keeps access private on this phone.`
- Confirming the dialog authenticates with `Protect ANKY with your device lock.`, enables Android app lock on success, and skips the immediate follow-up unlock prompt. Dismissing or choosing `not now` marks the prompt completed like iOS.

Validation run:

- `./gradlew :app:compileDebugKotlin` passed.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.appLockActivationPromptAfterFirstCompleteMatchesCurrentIos` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.

Known follow-up:

- This pass was verified by source invariants and JVM/assembly checks. A real device should still exercise the actual Android system credential prompt before release.

## 2026-06-08 First Launch Onboarding Parity Pass

Baseline:

- Source of truth: current dirty iOS worktree in `apps/ios/Anky`, especially `Features/Onboarding/OnboardingView.swift` and `AppRoot.shouldShowOnboarding`.
- Android target: move the newly migrated onboarding art from asset-only parity into a real native Android first-launch surface that follows the current iOS three-page flow.

Migrated Android changes:

- Added a native Compose `AnkyOnboardingScreen` with the same three full-screen onboarding images, copy lines, CTA labels, dot indicator, dark image overlay, and gold/purple CTA treatment.
- Android root now shows onboarding on the unlocked Write tab before the normal launch bubble, suppressing root tab/presence chrome underneath it like iOS.
- The final `Write 8 minutes` CTA hides onboarding, dismisses the launch prompt, navigates to Write, and opens the Write portal.
- Source parity coverage now asserts the iOS and Android onboarding pages, CTAs, image resources, and root gating remain aligned.

Validation run:

- `./gradlew :app:compileDebugKotlin` passed.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.firstLaunchOnboardingMatchesCurrentIosPages` passed.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- `adb devices` showed no attached devices, so no fresh onboarding screenshot was captured in this pass.

## 2026-06-08 Source Invariant / Protocol Duration Parity Pass

Baseline:

- Source of truth: current dirty iOS worktree in `apps/ios/Anky` plus shared TypeScript protocol sources in `protocol/implementations/typescript`.
- Android target: clear stale source-invariant drift left after the You passes and align Android protocol duration/completion semantics with current Swift/TypeScript behavior.

Migrated Android changes:

- Android `.anky` duration now matches Swift and TypeScript: `durationMs` is writing duration only, and terminal silence does not make a fragment complete.
- Added `AnkyDuration.writingDurationMs()` and changed `isComplete` to use `writingDurationMs >= 480000`.
- Updated complete test/dev fixtures from `472000 + 8000 terminal silence` to `480000 writing duration` where the fixture is meant to be complete.
- Android You identity copy now uses current Swift-shaped Base account / recovery phrase language while keeping Android secure-storage wording.
- You privacy prompt actions now match the current Swift empty-action shape, and support prompt action copy now uses `Open email`.
- Map day-detail rows now use the current Swift responsive content width, current session accessibility metadata shape, and no visible empty-state `no writing saved` copy.
- Source invariants were refreshed for current Swift Write launch steps, hidden dev paste source shape, tag-session title typography, Map session rows, You privacy/support prompt actions, You identity copy, You export actions, You legal rows, and image asset coverage.

Validation run:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest` passed.
- Focused protocol/mirror/write/reveal tests passed after the duration semantics update.
- Full `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- This pass did not run fresh emulator or real-device visual QA. Remaining full-goal gaps are still manual side-by-side iOS comparison and live RevenueCat/Google Play purchase QA.

## 2026-06-08 You Readable Export Parity Pass

Baseline:

- Source of truth: current dirty iOS worktree in `apps/ios/Anky`, especially `BackupExporter.exportFormattedWritings()`, `YouViewModel.prepareFormattedWritingExport()`, and the current You Data prompt actions.
- Android target: add the missing readable writing export path and align the Android You Data prompt with Swift's current `Back up now` / `Export writings` shape while keeping Android restore/ZIP backup native.

Migrated Android changes:

- Android storage now exports readable writings as `anky-writings-YYYY-MM-DD.md`.
- The formatted export content mirrors iOS: each saved writing renders as `ISO8601-createdAt:reconstructedText`, with entries separated by blank lines.
- `YouState` now tracks `formattedWritingExportFile` separately from the ZIP backup file.
- Android You Data prompt now exposes `Back up now` and `Export writings`, matching the current Swift conversation actions.
- Android You Data detail now shows readable export first, with `No writing to export yet` when empty, then keeps Android-native backup ZIP and restore controls in a separate panel.
- Android share handling now supports `text/markdown` for readable writing exports in addition to ZIP backup sharing.

Validation run:

- `./gradlew :app:compileDebugKotlin` passed.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.youExportPromptMatchesCurrentIosReadableExportActions --tests inc.anky.android.storage.StorageTest.formattedWritingExportMatchesIosReadableWritingShape --tests inc.anky.android.feature.you.YouViewModelStateTest` passed.
- `./gradlew :app:assembleDebug` passed.

Known follow-up:

- Full `SourceInvariantTest` is still failing on six independent drift checks: current iOS changes around Write launch copy, hidden dev paste copy, Map session row source assertions, tag-session title typography assertions, You privacy/support prompt shape, and You identity copy. Those remain next-pass targets.

## 2026-06-08 You Legal / Asset Parity Pass

Baseline:

- Source of truth: current dirty iOS worktree in `apps/ios/Anky`, especially the current `Features/You/YouView.swift` home panel and in-app legal sheets.
- Android target: move the Android You home closer to the current Swift row order/copy while preserving native Android export, credit purchase, support email, and local token-copy behavior.

Migrated Android changes:

- Android You home now uses the current iOS-facing first panel shape: `Data`, `Credits`, `Support / Feedback`, `Privacy Policy`, `Terms & Conditions`, and `$ANKY on Base`.
- Support and terms rows now use distinct native Android vector icons migrated from the iOS SVG concepts instead of reusing the credits icon.
- Tapping `$ANKY on Base` now copies the Base contract address directly from the You home row and shows a temporary `Copied to clipboard` subtitle, matching the Swift row behavior.
- Android now includes a native Terms page with the current iOS legal structure, adapted only where Android must refer to Google Play instead of Apple's App Store.
- Newly present iOS raster representatives for onboarding and credits/reflections artwork were migrated into Android drawable resources for asset parity coverage.
- The iOS asset coverage invariant now accepts Android vector drawables for iOS SVG image sets and parent-prefixed names for numeric iOS filenames such as `onboarding/1.png`.

Validation run:

- `./gradlew :app:compileDebugKotlin` passed.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.youHomeRowsMatchCurrentIosPromptAndLegalShape` passed.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest.iosImageAssetsHaveAndroidDrawableResources --tests inc.anky.android.privacy.SourceInvariantTest.youHomeRowsMatchCurrentIosPromptAndLegalShape` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check -- android` passed.

Known follow-up:

- The full `SourceInvariantTest` suite currently fails on older assertions that no longer match the current dirty iOS source for Write launch prompts, tag session refresh, Map session accessibility, You export/privacy/support/identity copy, and related drift. Those failures are now useful next-pass parity targets rather than regressions from this You legal/asset pass.

## 2026-06-03 Inline Reveal / Write Input Parity Pass

Baseline:

- Source of truth: current dirty iOS worktree in `apps/ios/Anky`.
- Android target: remove the Android-only Reveal bottom conversation/sheet as the primary reflection flow, tighten Write input mutation handling, preserve mirror/storage/identity contracts, and keep Android trial proof disabled.

Migrated Android changes:

- Reveal now renders saved reflections, streaming reflection text, and mirror errors inline below the reconstructed writing and privacy divider.
- Reveal now uses an iOS-style bottom gold action with `LOADING`, `READ REFLECTION`, `REFLECT THIS ANKY`, and `WRITE 8 MINUTES` states.
- Reveal copy is section-aware: `copy writing` copies reconstructed writing, `copy reflection` copies reflection title plus body, and copied feedback is tracked separately.
- Reveal delete confirmation now matches the iOS tone exactly: `Delete forever?`, `Delete`, `Cancel`, and `This permanently deletes this writing session. This cannot be undone.`
- Saved reflections render returned `creditsRemaining` as a truthful local remaining-reflections line when present.
- `RevealViewModel` invalidates the narrow Android `CreditsClient` credit cache only when a mirror response includes non-null `creditsRemaining`.
- Hidden Write input now rejects multi-glyph mutations at the input layer. Explicit `.anky` import remains available through the paste/import affordance, but pasted/autocorrected writing text is not accepted into the live ritual.

Preserved Android behavior:

- `.anky` remains the canonical local artifact and mirror request body.
- Ask Anky still sends exact UTF-8 `.anky` bytes as `text/plain; charset=utf-8`.
- Base EOA / EIP-712 identity signing and `X-Anky-App-Version` behavior are unchanged.
- Android still does not send `X-Anky-Trial-Proof`.
- Local archive, reflection sidecar, pending request, session index, Map refresh, You identity, RevenueCat public-key-only client setup, reminders, and export/import systems remain native Android.

Validation run:

- `./gradlew :app:compileDebugKotlin` passed.
- Focused `./gradlew :app:testDebugUnitTest --tests inc.anky.android.feature.reveal.RevealViewModelTest --tests inc.anky.android.mirror.MirrorClientTest --tests inc.anky.android.write.WriteViewModelTest --tests inc.anky.android.privacy.SourceInvariantTest` passed.
- Full `./gradlew testDebugUnitTest` passed.
- `./gradlew assembleDebug` passed.
- `adb devices` could not be run because `adb` is not available on this PATH, so `connectedDebugAndroidTest` was not run.
- Safety search confirmed Android source still does not send `X-Anky-Trial-Proof`; direct logging remains isolated to `SafeLog`; no server secrets or fake trial-credit grants were added.

Intentional divergence:

- Android device-bound trial proof remains out of scope until Play Integrity/device recall is designed and verified server-side.

## 2026-06-01 Reflection Flow Parity Pass

Baseline:

- Source of truth: current dirty iOS worktree in `apps/ios/Anky`.
- Android target: align the current write-to-reflection flow, local archive shape, streaming mirror behavior, reflection tags, tag navigation, and pending reflection request handling.

Migrated Android changes:

- Local `.anky` archive now saves hash-named files and can still read the legacy canonical `dotAnky.anky`.
- Android mirror client accepts streamed SSE reflection responses with progress, reflection chunks, final markdown, tags, hash, and credits.
- Reflection tags are persisted in `LocalReflection`, session summaries, backup export/import JSON, and the local session index.
- Write completion now freezes the completed writing and shows the Anky conversation prompt instead of auto-navigating away.
- The post-write prompt offers `reflect (1 credit)` and routes to Reveal with reflection startup.
- The writing ring now follows the current iOS 8-section ring: thicker passed sections and an inner counter-clockwise terminal-silence countdown after 3 seconds.
- Reveal now keeps the writing as the main surface and uses the Anky conversation prompt for `reflect this anky` / `read reflection`.
- Reflection progress and saved reflections render in a bottom sheet, with optional live text reveal during streaming.
- Reveal now refreshes reflection credits on entry through the existing Android `CreditsClient`, updates local balance state, and wires `open reflection credits` to You.
- `open reflection credits` now opens the Android credits detail directly through `you/credits`, with the You tab selected and back returning to the prior screen.
- Android Anky conversation actions now match the Swift action shape more closely: up to four actions, optional subtitle/badge text, a small `anky` header, and a thinking indicator.
- The You credits prompt now mirrors Swift by showing the live credit balance subtitle, refreshing credits when the credits row is opened, and rendering the first three credit packages directly as Anky chat actions with price subtitles and the `recommended` badge.
- The You privacy and support prompts now mirror Swift: privacy opens `https://anky.app/privacy`, support is labeled `support / feedback`, and both the prompt and credits page open a `mailto:support@anky.app` URL with the account id in the body.
- Reveal now puts `open credits` inside the Anky conversation actions instead of rendering a separate loose text link below the prompt.
- The post-write Android prompt now mirrors Swift's two-action shape: `reflect (1 credit)` starts the streamed Reveal flow, while `not now` consumes the completed hash and lands on Map.
- Android now shows the Swift-shaped launch writing bubble on the Write screen before the first character: the living `.anky` message or `ankys today: N`, the `write 8 minutes` / `write again` action, and the three ritual steps.
- Tapping the floating Anky on Android now mirrors Swift's contextual guide behavior across Write, Map, and You: it cycles the same `you are here...` companion notes instead of falling through to hide/show behavior.
- Android Write import failure copy now matches Swift: unreadable pasted `.anky` text shows `i couldn't find a readable .anky in that.` and open failures show `i couldn't open that .anky yet.`
- Android Reveal companion copy now matches Swift in the streaming and saved-reflection states: streaming uses `i am staying with this .anky.` plus `i am reading slowly. not looking for a summary.`, and saved reflections say `this anky has a reflection.`
- Tags are labeled, tappable, and open a local tag sessions screen backed by `SessionIndexStore.sessionsWithTag`.
- Android now has a local `ReflectionRequestStore` for pending reflection request persistence, clear-on-success/delete, and iOS-style pending retry/watcher behavior.
- The iOS `tellmewhoyouare` asset was migrated and used by the Android app-lock failure surface.
- Android app lock now mirrors the current iOS lock recovery fallback: after two failed biometric attempts, the `tellmewhoyouare` surface accepts a normalized 12-word recovery phrase, unlocks after a successful local identity import, and refreshes the You identity state.
- Floating Anky drag now breaks out of the Android home-following mode as soon as drag begins, matching Swift's direct `DragGesture(minimumDistance: 3)` behavior instead of snapping back during the gesture.
- Floating Anky's long-press menu copy now mirrors Swift: `anky stays beside the writing`, `Keep Anky here`, `Hide/Show Anky`, `Change motion`, and `Cancel`; the Android-only `Move Anky home` row was removed.
- Android Write errors now mirror Swift's recent-prompt recall behavior: transient invalid-input errors fade quickly, remain briefly recallable, and tapping Anky on the Write screen replays the recent prompt before generic companion notes.
- Android now preloads reflection credits from the app root like Swift and shows the current `N credit(s)` badge on the post-write `reflect (1 credit)` action when a balance is available.
- Android's launch Write action now mirrors Swift's `openWritingPortal()` path by issuing a fresh hidden-input focus request and haptic tick when `write 8 minutes` / `write again` is tapped.
- Android short-session `write again` now routes through the root retry-writing path like Swift: it clears pending completed state, returns to Write, and opens/focuses the writing portal instead of only popping Reveal.
- Android Reveal deletion now mirrors Swift's explicit `onDeleted` callback path: deleted sessions clear the pending completed writing state, refresh the shared local Map index, re-derive an open Map day from refreshed state, and then pop the Reveal route.
- Android reflection streaming progress now mirrors Swift's monotonic thread progress formula instead of resetting with a modulo, and live reflection reveal is one-way (`reveal live`) instead of a hide/show toggle.
- Android tag-session lists now refresh on lifecycle resume, matching Swift's `.onAppear` reload so returning from a child Reveal after deletion does not leave stale tagged rows.
- Android tag-session lists now use the same violet bloom texture treatment as Reveal, matching Swift's `RevealBackgroundTexture()` instead of only drawing guide lines.
- Android tag-session title layout now mirrors Swift by rendering the tag name inside the scroll content at 30sp with matching horizontal/bottom/top spacing instead of as a 26sp top-bar title.
- Android tag-session rows now mirror Swift's medium monospaced metadata and smaller 13dp chevron treatment.
- Android's idle reflection bottom sheet now mirrors Swift by showing the credit prompt message and an enabled/disabled `reflect this anky` action instead of a dead `the reflection is not here yet` placeholder.
- Android saved reflections in the bottom sheet now mirror Swift's `reflection.displayBody` rendering and no longer reinsert an Android-only title heading before the reflection body.
- Android's reflection bottom sheet now allows the partial/medium sheet state like Swift's `[.medium, .large]` detents and scrolls its content so long saved or streaming reflections are not clipped.
- Android markdown reflection rendering now treats Swift-style horizontal rules (`---`, `***`, `___`, em dash, and short repeated rule markers) as separators instead of body text.
- Android tag-session rows now use the platform localized medium-date/short-time formatter like Swift's abbreviated-date/shortened-time style, instead of the previous Android-only slash format and forced lowercase.
- Android's reflection bottom sheet now separates states like Swift: saved reflections open directly into the reflection body with the small scroll glyph, streaming uses `the mirror is forming`, and only the idle credit prompt keeps the generic `mirror` heading.
- Android's Reveal auto-start reflection route now mirrors Swift's `didAutoStartReflection` branch: the sheet starts closed, opens once on appear when there is no saved reflection, and credit-state changes or failed attempts do not silently re-trigger the reflection request loop.
- Android Map day session rows now expose Swift-shaped accessibility labels with reflected title, preview, time, duration, word count, `anky`, and `reflected` metadata instead of leaving that row context only in visible text.
- Android Map day session row dividers now mirror Swift's bottom overlay treatment instead of participating in the title/preview vertical spacing.
- Android Map day-detail lists now use Swift's separate horizontal/top/bottom padding, including the larger 72dp bottom breathing room.
- Android Map empty day detail now uses regular serif body typography like Swift's Georgia 20 empty state instead of the semibold heading style.
- Android Map day-detail date chrome now uses a compact 17sp semibold inline-title treatment against the 0.96 ink bar, closer to Swift's inline navigation title instead of an Android-only large gold heading.
- Android Map trail empty text and day nodes now mirror Swift's quieter treatment more closely: empty trail copy uses regular serif body typography, and non-today trail nodes keep the black/textured fill with region color reserved for the stroke instead of tint-filling the circle.
- Android Map's current-day jump control now mirrors Swift's 48dp circular material-style hit target and button-level accessibility label instead of relying on an Android-only dark IconButton background.
- Android Map's vertical trail line now scrolls with the day nodes and runs from first node center to last node center like Swift's `StraightTimeline`, instead of being drawn as a fixed viewport-height line behind the list.
- Android Map trail day nodes now expose Swift-shaped accessibility labels of `{date}, {trail activity summary}`, including `Today`, `No writing`, `Showed up`, and `No complete anky` states.
- Android Map's current-day progress ring and day-completion marker now expose the same accessibility labels as Swift: `UTC day progress` and `showed up`.
- Android You now starts with no active Anky conversation prompt like Swift's optional `activePrompt`; the bottom prompt opens only after a prompt selection or a status/error system message.
- Android Write now exposes the ritual clock with Swift's `Writing time {clock}` accessibility label after the 8-minute mark.
- Android Write now mirrors Swift's hidden dev-paste affordance: regular tap still imports a pasted `.anky`, while a five-second hold on the paste icon imports a built-in complete `.anky` fixture for testing.
- Android Reveal's delete control now mirrors Swift's accessible label and red danger treatment: the header button is `Delete writing session`, while destructive confirmation copy remains separate.
- Android You now ports Swift's hidden title-tap Anky Experience: tapping `you` opens a full-screen 88-minute forward-only writing surface with portal ring, elapsed-time accessibility label, companion copy prompt, and copy actions for the live `.anky` stream or reconstructed writing.
- Android now treats the You Anky Experience like Swift's full-screen cover at the root shell level: while it is open, the Android tab bar and floating Anky presence are suppressed so the experience is not framed by app chrome.
- Android You Anky Experience now hides Android system bars while open and restores them on dispose, matching Swift's `persistentSystemOverlays(.hidden)` behavior.
- Android You support prompt copy now mirrors Swift: `send support or feedback by email. include only what you choose to write.`
- Android You local identity copy now mirrors Swift's Base account / recovery phrase language, including the recovery reveal/copy actions and failure copy; Android keeps its platform secure-storage implementation.
- Android You identity backup now mirrors Swift's action shape: the prompt and Account page `back up identity` controls run a biometric-gated secure-storage backup path instead of revealing the recovery phrase.
- Android You reset-identity confirmation now mirrors Swift's warning that reset creates a new Base account, credits are tied to the current account, and the recovery phrase should be saved first.
- Android You local identity load failure copy now mirrors Swift's `Could not load the local Base identity.`
- Android You privacy policy keeps Swift's local-first structure while its source links now point to the Android archive, protocol, identity, mirror, backup, and You model implementation files instead of copied iOS paths.
- Android You recovery-import validation copy now mirrors Swift's `Recovery phrase must be 12 words.` and `Recovery phrase contains an unrecognized word.` instead of the older Android `Recovery key...` wording.
- Android active drafts now mirror Swift's storage split: the live draft is saved under `ActiveDrafts/dotAnky.anky`, while the legacy `Ankys/dotAnky.anky` path is only loaded/cleared when it is still an open draft.
- Android single `.anky` import now mirrors Swift's forgiving paste/import path: it tries normalized raw text, fenced code blocks, and extracted protocol runs, handles `SPACE` placeholders/trailing whitespace, and only saves complete imported sessions.
- Android now refreshes the root reflection-credit badge again when a completed writing is waiting on the post-write `reflect (1 credit)` prompt, closing the gap with Swift's shared `YouViewModel.creditBalance` badge source.
- Android imported `.anky` artifacts now enter the same post-write companion decision flow as Swift's `completion?(saved)` path instead of jumping directly to Reveal.
- Android post-write `not now` now mirrors Swift's `revealAfterWriting` handoff: it switches through Map and opens the artifact's normal Reveal screen without auto-starting reflection.
- Android Map refresh now mirrors Swift's resilience path by falling back to the existing local session index if archive rebuild fails, instead of blanking the map.
- Android tag pills and tag-session titles now preserve the stored tag display text like Swift instead of lowercasing it at render time.
- Android saved-reflection sheets now match current Swift by keeping the saved credit balance in local storage/state but no longer rendering an Android-only `N reflections left` line, and tag pills now use a single horizontal capsule rail like Swift.
- Android Reveal now mirrors Swift's left-edge horizontal back swipe using the same practical thresholds: a narrow 32dp edge region, rightward movement over 80dp, and vertical drift under 60dp.
- Android Map day detail now owns the same map-background texture plus 0.76 ink overlay as Swift's `MapDayBackground`, instead of relying only on the parent Map backdrop with a flat overlay.
- Android streaming reflection live reveal now mirrors Swift by labeling the revealed live markdown as `writing reflection · N characters`.
- Android streaming reflection progress now uses a Swift-like custom dark/gold thread bar instead of the generic Material linear progress control.
- Android reflection bottom-sheet actions now use Swift-like icon+text rows for `reveal live` and `reflect this anky`.
- Android reflection bottom sheets now own the Reveal ink texture/background like Swift's `ReflectionBottomSheet`, instead of rendering a flat ink sheet.
- Android reflection tag rails now render the full stored tag list like Swift's `ForEach(tags)` instead of silently truncating to eight display pills.
- Android reflection tag rail typography now mirrors Swift more closely: monospaced muted `tags` label with letter spacing and monospaced medium tag pills.
- Android reflection bottom-sheet content spacing now follows Swift's saved/streaming/idle padding differences, and streamed markdown keeps the streaming sheet state even if the ask flag has already flipped.

Validation run in this pass:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.storage.StorageTest --tests inc.anky.android.feature.reveal.RevealViewModelTest` passed after pending-request storage and Reveal wiring.
- `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check` passed.
- After the direct credits-route fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed again.
- After the Anky conversation/action parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed again.
- After the You privacy/support prompt parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the post-write `not now` parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the launch writing prompt parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the contextual floating-Anky tap parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the Write import failure-copy parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the Reveal companion-copy parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the app-lock recovery fallback parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the floating-Anky drag fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the floating-Anky menu-copy parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Write recent-prompt replay parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the post-write credit-badge parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the launch Write focus parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the short-session `write again` retry-flow parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Reveal deletion callback/map-refresh parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the streaming progress parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag-session resume refresh parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag-session Reveal texture parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag-session title layout parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag-session row metadata/chevron parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the idle reflection bottom-sheet parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the saved-reflection display-body parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection sheet detent/scroll parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the markdown horizontal-rule parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag-session date-format parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection sheet saved/streaming heading parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Reveal auto-start one-shot parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map session-row accessibility parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map session-row divider overlay parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map day-detail list padding parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map empty day detail typography parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map trail-day accessibility parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map progress/marker accessibility parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You initial conversation prompt parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Write timer accessibility parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Write hidden dev-paste parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Reveal delete-control accessibility/style parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You Anky Experience parity port, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You Anky Experience root-shell parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You Anky Experience system-bars parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You support prompt-copy parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You Base account / recovery phrase copy parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You identity backup action parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest --tests inc.anky.android.feature.you.YouViewModelStateTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You reset-identity warning parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You Base identity failure-copy parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Android privacy source-link parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the recovery phrase validation-copy parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the active-draft storage parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the single `.anky` import-candidate parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the post-write credit-badge refresh parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the imported `.anky` post-write flow parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the post-write `not now` Map-to-Reveal handoff parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map refresh fallback parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag display-text parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the saved-reflection credit-line and horizontal tag-rail parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Reveal edge back-swipe parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map day-detail background parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the streaming reflection live-reveal label parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the streaming reflection thread-progress bar parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection bottom-sheet icon action parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection bottom-sheet texture parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection tag full-list rendering parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection tag typography parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection bottom-sheet spacing/streaming-state parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map trail empty-state and node-texture parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map current-day button parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map scrolling timeline parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map day-detail inline-title parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.

Privacy/protocol notes:

- Android still does not send `X-Anky-Trial-Proof`.
- The raw `.anky` upload path remains only behind explicit reflection/nudge user actions.
- No server-side storage, auth, credit issuance, or identity semantics were changed in Android.

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
- The seeded Reveal run used a same-day complete `.anky` plus local reflection sidecar and verified the then-current saved-reflection hierarchy: duplicated leading title heading removed, inline emphasis rendered, quote and bullets rendered. A later parity pass removed the Android-only saved-reflection credit line to match current Swift.

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
- Reveal Ask Anky inline action uses `2 free reflections included`.
- Reveal copy is section-aware with `copy writing` / `copy reflection` and short copied-state feedback.
- Saved reflections preserve local `creditsRemaining` for state/export parity, while the current saved-reflection sheet keeps that balance out of the rendered body like Swift.
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
- Targeted parity search for `X-Anky-Trial-Proof|X-Anky-App-Version|creditsRemaining|2 free reflections included|copy writing|copy reflection|delete forever` was run from repo root.

Privacy/protocol notes:

- No `.anky` protocol, parser, writer, hash, signing, mirror body, or mirror signature semantics were changed.
- Android still sends raw `.anky` bytes to `POST /anky`.
- Android still sends `X-Anky-App-Version`.
- Android still must not send `X-Anky-Trial-Proof`.
- No logging of copied writing, reflection text, raw `.anky`, recovery phrase, private key, seed, or signature material was added.
