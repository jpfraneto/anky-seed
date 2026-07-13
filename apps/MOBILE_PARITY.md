# iOS → Android Parity (Write Before You Scroll)

Mission: bring `/android` to full parity with `/ios` — every feature, flow, screen, and design detail, translated idiomatically to Kotlin/Compose.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done **and verified** (build + code inspection; check off only with evidence).

**Baseline (2026-07-07):** Android `assembleDebug` passes. Android is frozen at the June "8-minute journaling + credits" era. iOS is the WBS gate app (v1.2.4(50)).

---

## Platform decisions (Android-idiomatic equivalents)

| iOS mechanism | Android decision | Rationale |
|---|---|---|
| FamilyControls/ManagedSettings shield + DeviceActivity relock | **UsageStats foreground-app watcher (foreground service) + full-screen shield Activity + AlarmManager relock** | No per-app shield API. UsageStats polling (~800ms) + overlay/trampoline Activity is the standard blocker pattern; fewer Play-policy risks than AccessibilityService. Permissions: `PACKAGE_USAGE_STATS` (special access) + `POST_NOTIFICATIONS`; shield rendered as an exported-false full-screen activity launched over the blocked app (needs `SYSTEM_ALERT_WINDOW` **not** required when using a launched Activity from a foreground service w/ while-in-use; we use `Settings.canDrawOverlays` fallback if OEM blocks background activity starts). |
| App Group (`group.com.jpfraneto.Anky`) | Plain SharedPreferences/files — Android is single-process | No extensions on Android; the shield lives in the same process. |
| WidgetKit PaintingWidget | Glance `AppWidget` | |
| Live Activity (trial) | **Skip** (no equivalent); trial reminder notification kept | Ongoing notification for a trial countdown would read as spam; iOS keeps it. Revisit if JP wants. |
| Metal `paintingRevealMask` layerEffect | Bitmap composite renderer (port of iOS `FallbackRevealRenderer`), rendered off-main → `Image` | minSdk 26 < AGSL 33; iOS already ships a pixel-defined fallback — one code path, deterministic. |
| Display-P3 pigments | Compose `Color(..., ColorSpaces.DisplayP3)` | Compose supports wide gamut; falls back gracefully. |
| MeshGradient LazureWall (iOS18) + radial fallback | Radial-wash implementation (port the iOS fallback path) | Deterministic, cheap, identical on all API levels. |
| Keychain + iCloud keychain identity backup | Android Keystore AES/GCM (existing) — **no cross-device keychain equivalent**; recovery phrase import remains the restore path | Existing WriterIdentityStore pattern kept. |
| iCloud encrypted data backup | Existing local `AndroidEncryptedBackupStore` (same envelope format) | Cross-device cloud sync deferred (needs Drive API decision — flagged to JP). |
| StoreKit-via-RevenueCat (`pro` entitlement) | RevenueCat Android SDK, same entitlement `pro`, offering `default`, products `anky.yearly`/`anky.monthly` (Play products must exist — **operator task**) | |
| SFSpeechRecognizer (check-in talk) | Not ported — CheckIn flow is legacy/off the live iOS path | Confirmed: iOS live home is PaintingHomeView. |
| App-icon quick action | `ShortcutManager` dynamic shortcut → `anky://painting` deep link | |
| requestReview after first seal | Play In-App Review API | |

**Deliberately NOT ported** (legacy/dead on iOS): GateHomeView (replaced by PaintingHomeView), CheckIn flow (`.checkIn` unreachable), HomeDailyChamberView dead code, TokenPage/$ANKY onramp (deleted on iOS), credits economy (deleted on iOS — see WS4), `X-Anky-Trial-Proof` (deleted).

---

## WS1 — Core protocol & storage parity (foundation)

- [x] `AnkyLevel` (core/protocol): level curve base 480s × ratio 1.62, maxLevel 120, per-step rounding — must match iOS `AnkyLevel.swift` and TS `level.ts` exactly; port `LevelTests` fixtures.
- [x] `AnkyWriter.replaceSuffix` (backspace-as-replace: keep prefix N−1, re-type last char; text never empty) + `WritingSessionEngine` equivalent (wraps writer, snapshot).
- [x] `WritingInputStats` (`<hash>.input-stats.json` beside archive files: backspace/enter counts) in `LocalAnkyArchive`; surfaced in SessionSummary.
- [x] `WritingPreferencesStore`: backspaceAllowed (default false), autocorrectEnabled (default true), 5 fonts (Quill=serif, Georgia, Round, Plain, Typewriter=monospace-ish serif → map to Android system families), 4 sizes. Key `anky.writingPreferences.v1`.
- [x] `RecoveryPhrase` checksum validation on import only (BIP39 SHA256 top-4-bits; stored phrases load unvalidated) — match iOS `RecoveryPhrase(text:validatingChecksum:)` semantics.
- [x] `AvatarStore` (selfie → `filesDir/avatar.jpg`).
- [x] `AnkyverseCalendar` check: 96-day/8-region positions (Android has mod-8 in SessionIndexStore — align).
- [x] `AppOpenStore.recordEarlierFirstOpenDate` parity check (exists).
- [x] Unit tests ported: LevelTests, writer replaceSuffix tests, preferences store tests.

## WS2 — Write Before Scroll gate engine + Android blocking runtime

Pure logic (port with tests — iOS files in `Core/WriteBeforeScroll/`):
- [x] `UnlockPolicy` + `WriteBeforeScrollUnlockLadder`: quick pass = completed sentence (ends `.`/`!`/`?`, ≥6-word threshold) → 15 min, 3/day; daily = target reached **and entitled** → until local midnight; free tier: quick passes + emergency only; ladder actions offer/applyQuickPassively/upgradeToDaily/offerFreeTargetMoment/withdraw; quick grants gate-exclusive (organic sessions never spend a pass); daily upgrade of active quick window. Port `UnlockLadderTests`.
- [x] `QuickPassStore` (3/day, midnight reset), `DailyTargetStore` (1–8 min slider, default 8; onboarding immediate, later edits apply next day), `UnlockStateStore`, `FreeTargetMomentLedger` (once/day, `anky.freeTargetMoment.lastShownDay`).
- [x] `WriteBeforeScrollGateSwitchStore` (explicit off-switch outranks all re-arm paths) + `WriteBeforeScrollShieldReconciler` (pure decision) — port `GateSwitchTests`.
- [x] `AdaptiveTargetPolicy` + offer store (2 missed days → halve-target offer) — port `AdaptiveTargetPolicyTests`.
- [x] `SignalCalculator`/`SignalState` (streak, signal% = 11×streak + 12 if wrote today), `EightDayGateStore`, `FirstGateStore`, `WritingAnchorStore` (name + anchor sentence) — port `SignalStateTests`.
- [x] `WriteBeforeScrollEventLogStore` (max 300, 44 event names) + session metric tracker (golden metric).

Android blocking runtime (new, platform-specific):
- [~] `BlockedAppSelectionStore` — user picks installed apps (replaces FamilyActivityPicker with a launcher-apps list UI, checkboxes, app icons via PackageManager).
- [~] Gate watcher foreground service: UsageStatsManager `queryEvents` poll of foreground package; when a blocked app is foregrounded while locked → launch Shield activity over it. Persistent low-priority notification (required for FGS).
- [~] Shield screen (Activity/full-screen Compose): dark door background, rotating headline (3, stable per day), "{App} is waiting behind the door.", primary "Write ⊙" → deep-link into writing surface with gate context; secondary "Emergency unlock" → EmergencyBreath; quick-pass line / exhausted copy. All copy from AnkyCopyRegistry.
- [~] Relock scheduling: AlarmManager exact-ish alarm at `unlockedUntil` → re-apply lock; reconcile on app foreground and on service tick (belt-and-braces, matches iOS reconciler philosophy).
- [~] Permissions flow: usage-access grant screen (Settings intent), notification permission, battery-optimization exemption prompt (OEM reality) — GateSetup step 1 equivalent.
- [~] `EmergencyBreathView` equivalent: 30s breath, gold ring, cancel on pause (no partial credit), grant daily-until-midnight without consuming a pass, `reportEmergencyUnlock`.
- [~] Gate events wired: shield_shown/action_tapped, unlock_granted, relock_*, quick_pass_used, daily_target_reached, session_overshoot, wbs_session_sealed, emergency_unlock_tapped…

## WS3 — Level & painting system

- [x] `LevelProgressStore` (lifetime seconds of record; credits at seal, continued sessions credit delta; `freeBoundaryLevel=2`; `presentedProgress(entitled:)` clamps display only; unreported queue; owed ceremony from persisted lastCeremonyShownLevel; adoptServerTotalIfHigher) — port `LevelProgressStoreTests`.
- [x] `LevelPaintingCoordinator` state machine (accumulating→generationPending→generated→ceremonyPending→ceremonyShown; kill-safe ceremony replay; entitledForGating stored flag).
- [x] `PaintingAssetStore` (`filesDir/Paintings/<level>/{final,underdrawing,revealmap}.png + meta.json`; installs bundled StarterPainting as level 1; signed sequential downloads) — port `PaintingAssetStoreTests`.
- [x] `LevelSyncClient`: POST /level/sessions, GET /level/status, POST /level/prepare (distill corpus ≤60k chars), POST /level/ceremony-shown, GET /level/assets/{level}/{file}, POST /events/emergency-unlock, POST /events/funnel — all EIP-712 signed like /anky.
- [x] `LevelTriggerTuning` (p95-of-28-days pre-generation trigger, loading excerpts).
- [x] Reveal renderer: bitmap composite (underdrawing + final masked by revealmap at progress) — port iOS FallbackRevealRenderer semantics.
- [~] `PaintingHomeView` (THE home screen): 2-page pager (painting at presented progress / journey card), primary CTA by GatePhase (Write / Choose apps / Continue setup), quick-pass line, emergency link when shielded+locked, blocked-app icon row, History card (5 recent), stroke-beat animation (≤3s), boundary ceremony veil, journey paywall sheet. **2026-07-07 update:** wired `PaintingHomeDependencies` in `AppContainer` and made `painting` the Android start route; verified `testDebugUnitTest`, `assembleDebug`, `assembleRelease`. Remaining: real gate setup/settings/legal destinations and visual emulator QA.
- [~] `UnveilCeremonyView` with CeremonyTiming beats (finalStrokes 2.2 → heldBreath 1.8 → darkening 1.1 → title 0.8 → glimpse 8.0/1.2/1.8 → begin 0.9 → drain 3.4); "WELCOME TO LEVEL N"; `PaintingGenerationWaitView` with writing excerpts.
- [~] Journey map: 96 days, 8 stacked kingdom paintings, 4% seam overlap with alpha-fade band, positions from `journey_positions.json`, JourneyState from session index, celebration ledger; kingdom names never in UI.
- [~] `GalleryView` (grid of installed paintings).
- [x] Assets copied: StarterPainting (final/underdrawing/revealmap/meta), kingdom1–8.png, journey_positions.json.

## WS4 — Subscriptions (replaces credits economy)

- [~] **Delete credits economy**: ReflectionCreditCache, RevenueCatCreditsClient CRD/`Credits` offering, credit purchase sheets, free-credit WhatsApp flow, TokenPage/$ANKY onramp (`StripeOnrampClient`), x402 progress stages, credit strings. **2026-07-07 update:** shell-level `you/credits` route and Reveal → credits navigation removed and SourceInvariantTest now enforces subscription-era products/veil behavior; inert credits classes and YouViewModel stubs still remain.
- [x] RevenueCat Android: configure once at launch with appUserID = wallet address (fail closed; logIn on identity change), entitlement `pro`, offering `default`, products `anky.yearly` ($88/yr, 3-day trial) / `anky.monthly` ($11.99/mo).
- [x] `EntitlementStore` equivalent: customerInfo stream → isEntitled/activeProductID/periodType/expiration; `isEntitledForGating` QA flag; `lastKnownEntitledForGating` persisted; ensureConfigured retry; offerings/restore error lines.
- [~] `PaywallView`: contexts onboarding/lapsed/veil(origin) — one styling path; yearly+monthly selector; 3-node trial timeline; price formatting ($88 whole, $1.69/wk); restore/terms/privacy footer; hard gate in onboarding (non-skippable flag).
- [~] Veils: `VeiledFeature`/`ReflectionGhost` — reflection veil (free sessions skip LLM), journey veil, boundary ceremony veil at level 2; `PaywallPressureLedger` (once/rolling-week).
- [~] Free-target moment (option C): !entitled && target reached && !shown today → sealing-gate block with trial CTA + emergency link.
- [~] `POST /subscription/identify` after entitlement events; funnel events (paywall_shown, trial_started, subscribed, restored, lapsed, boundary_reached, veil_tapped, ceremony_1_shown). **2026-07-07 update:** `AppContainer.entitlementStore` now wires `RevenueCatSubscriptionGateway` to signed `LevelSyncClient.identifySubscription`/funnel backend; paywall-origin funnel coverage still incomplete.
- [~] Trial reminder notification at expiration−28h (honest, from RC periodType).
- [~] Reflection gating: entitled → mirror LLM reflection; free → 402 ENTITLEMENT_REQUIRED → veil (no credit prompts anywhere). **2026-07-07 update:** `AnkyApp` now feeds `EntitlementStore.isEntitledForGating` into `RevealViewModel` and `WriteViewModel`; reveal/paywall tap host wiring still needs the AppRoot shell pass.

## WS5 — Lazure design system

- [x] Pigment palette (Display-P3 exact values from AnkyLazure.swift: ankyPaper .965/.937/.894, ankyInk .239/.216/.310, ankyGold .878/.694/.427, ankyViolet, ankyApricot, ankySage, ankyRose, ankyMadder, ankyUmber, ankySlate, ankyGoldLight, ankyInkSoft, ankyPaperDeep). No pure white/black anywhere. Hairline 0.5dp ink@0.08 edges; violet shadows.
- [x] `AnkyBreath` 8s clock; `LazureWall` breathing background (radial-wash port; moods dawn/dusk/kingdom(color)); `PaperGrain` deterministic speckle.
- [x] `VeilCard`, `LazureDivider`, `ThreadButtonStyle` (gold gradient capsule + breathing glow), `WashButtonStyle`, `AnkySunGlyph` (drawn spiral sun).
- [x] Typography: serif titles/prose (Android `FontFamily.Serif`), sans labels; writing-font choices mapped.
- [~] Retheme ALL existing screens from dark-cosmic to lazure (Write stays dark-chamber where iOS does — check iOS WriteView: writing surface has its own treatment).
- [x] `LevelTheme` palette-driven tint from painting meta swatches.
- [ ] Theme.Anky window colors updated (paper, not #080713) where appropriate.

## WS6 — Onboarding (13 screens) + gate setup

- [~] Screens 1–5 pre-dawn (aubergine): problem / solution / mechanism / phone-hours bracket (`anky.dailyPhoneHours`) / visceral math (wakingYears = round(hours×40/16), timed beats).
- [~] Screens 6–9 dawn: meet Anky (wave sprite) / name + optional selfie (AvatarStore, front camera) / target slider 1–8 (DailyTargetStore.setInitialTarget) / 8-day journey story.
- [~] Screen 10: paywall (hard gate, skip-if-entitled). Screen 11: notifications permission + trial-reminder sync. Screen 12: GateSetup sheet. Screen 13: DayOneThresholdOverlay over live writing surface; `onboardingCompleted` only fires on its dismissal; `anky.onboardingLastScreen` abandonment marker.
- [~] GateSetup 4 steps: authorize (usage-access grant) → chooseApps (installed-app picker) → turnOn → done (+ "turn the gate off" link w/ confirmation).
- [~] Review prompt: In-App Review once after first sealed session (skip if bounced straight back).
- [~] Replace old 3-image onboarding entirely.

## WS7 — Write/Seal/Reveal flow updates

- [~] WriteView parity: preferences-driven font/size, backspace honored when enabled (replaceSuffix), autocorrect toggle honored (IME flags), rejected-input top-bar copy from registry, minute haptics kept, gate-context entry (from shield → seal returns to "{app}").
- [~] Unlock ladder integration in WriteViewModel: record progress per keystroke → offer / passive quick apply / daily upgrade / free-target moment; `sealIfLeftInMotion` on background; overshoot event; level credit at seal (`creditSealedSession` + flushUnreported).
- [~] `PostSessionSealingView` (3-phase seal → mirror → gate): min 3s seal beat; hashLine "Sealed · ABCD…WXYZ"; free sessions show reflection veil instead of LLM; contextual gate button; free-target-moment block; dedupe streamed reflection opening.
- [~] Nudges: local `AnkyNudgeGenerator` (EN/ES themed) for free users; mirror `intent: nudge` for entitled.
- [~] Reveal updates: remove credit CTA states; veil for unentitled; review prompt after first reflection; keep tags/copy/delete/continue.
- [~] Archive: plain searchable list (search over cached lowercase reconstructedText; never "Fragment" labels or counts) — match iOS ArchiveChamberView.
- [~] Sealed sessions immutable (continue guards !isClosed) — verify Android matches.

## WS8 — You tab, Settings, navigation shell

- [~] AppRoot-equivalent shell: PaintingHome as THE home; manual surface flow (home → write → sealing); overlay stack (ceremony, emergency breath, adaptive offer, onboarding, day-one threshold); no bottom tab bar (iOS hides it — mirror the iOS nav topology: home / You / archive reachable from chrome). **2026-07-07 update:** Android now starts at `painting` and hides the bottom bar there; home routes to write/archive/You. Still open: post-write shell still jumps to Reveal, overlay stack is partial, old Map tab still exists off-home, settings/gate setup are placeholder-routed to You.
- [~] YouView rework: stats, recovery phrase (biometric), import phrase (staged w/ rollback + checksum), encrypted backup, export/import, delete-account-everywhere, support email, version; remove Credits/Token pages.
- [~] `AnkySettingsView`: writing preferences (font/size/backspace/autocorrect), app lock, gate setup entry, mirror URL override, privacy/terms sheets, backup; routed from You + gear on home.
- [~] Legal docs: subscription-reality privacy/terms text in all 6 locales (port from iOS).
- [~] Founder chat link https://t.me/ankytheapp.
- [x] Deep links: `anky://write`, `anky://painting` intent-filters → nav routing; dynamic shortcut "Open painting" — implemented in `AndroidManifest.xml`, `MainActivity`, and `AnkyApp`; verified 2026-07-07 by `testDebugUnitTest`, `assembleDebug`, `assembleRelease`.

## WS9 — Widget, notifications, copy, localization

- [ ] Glance painting widget: current painting at presented progress + boundary line; taps → anky://write / anky://painting; snapshot contract (render composite to file on seal/foreground like GlanceSyncCoordinator).
- [ ] Notifications: daily reminder (existing) kept; trial-ending reminder (WS4); shield "open Anky" not needed (same process) — emergency-door notification path where applicable.
- [ ] `AnkyCopyRegistry` port: ALL registry strings (gate headlines ×3, exhausted, footer, pass line, quick-pass unlock, top-bar, ceremony, emergency, off-switch, free-target moment, veils, widget/boundary/adaptive/paywall-sheet copy).
- [ ] Localization: every new string × 6 locales (en/es/fr/de/hi/zh-rCN); update LocalizationResourceTest counts; remove dead credit strings.
- [ ] App version plumbing (X-Anky-App-Version = Android versionName(code)).

## WS10 — Cleanup, tests, release readiness

- [ ] Remove dead code: credits, TokenPage, onramp, mascot flows that iOS dropped (keep AnkyPresenceOverlay — iOS still has it), old MapScreen trail if replaced by archive+journey (verify iOS: archive = ArchiveChamberView; map trail → journey map).
- [x] SourceInvariantTest updated for new modules (no hardcoded URLs/secrets) — verified 2026-07-07 by `./gradlew testDebugUnitTest` (591 tests).
- [x] All unit tests green (`testDebugUnitTest`) — verified 2026-07-07: `BUILD SUCCESSFUL`, 591 tests.
- [x] `assembleDebug` + `assembleRelease` green — verified 2026-07-07 after painting-home/deep-link shell wiring: both commands returned `BUILD SUCCESSFUL` (`assembleRelease` in 12s incremental).
- [ ] QA flags default-safe (paywall non-skippable, no QA entitlement bypass).
- [ ] Fresh reviewer agent audit vs /ios + this file.

---

## Operator tasks (JP — cannot be done from this machine)

- [ ] Play Console: create `anky.yearly` ($88/yr, 3-day free trial) + `anky.monthly` ($11.99/mo) subscriptions; attach to RevenueCat `default` offering (Android app in RC project, Play credentials).
- [ ] RevenueCat: add Android app to project, set `ANKY_REVENUECAT_ANDROID_PUBLIC_KEY` in local.properties/CI to the **Play** public key.
- [ ] Decide: cross-device encrypted backup destination on Android (Drive API?) — currently local-file only.
- [ ] Review the UsageStats-based blocking approach (vs AccessibilityService) before Play submission; Play requires a special-access declaration for `PACKAGE_USAGE_STATS`.
