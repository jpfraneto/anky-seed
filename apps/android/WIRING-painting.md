# WIRING — WS3 painting surfaces (`inc.anky.android.feature.painting`)

The painting home, unveil ceremony, journey map, gallery, generation-wait
view, and glance-sync hook are built and self-contained. Nothing outside
`feature/painting/`, `res/values/strings_painting.xml`, and
`test/.../painting/` was touched. This doc is the integration contract for
the phase that wires them into `AnkyApp`/`AppContainer`.

## Files

| File | iOS source |
| --- | --- |
| `PaintingHomeView.kt` (`PaintingHomeDependencies`, `PaintingHomeSession`, home screen, boundary ceremony veil) | `PaintingHomeView.swift` (incl. `BoundaryCeremonyVeilView`) |
| `PaintingHomeLogic.kt` (`PaintingGatePhase`, `PaintingHomeLogic`, `StrokeBeat`, `PaintingFrameMath`) | `PaintingHomeView.phase`/stroke beat + `PaintingFrameMetrics.swift` |
| `PaintingView.kt` (`PaintingRevealAssets`, `PaintingRevealAssetCache`, `rememberPaintingRevealAssets`, `PaintingView`) | `PaintingView.swift` + `PaintingRevealModifier.swift` (fallback path; no Metal on Android) |
| `UnveilCeremonyView.kt` | `UnveilCeremonyView.swift` |
| `CeremonyTiming.kt` (`CeremonyTiming`, `CeremonyBeat`) | `CeremonyTiming.swift` |
| `PaintingGenerationWaitView.kt` | `PaintingGenerationWaitView` (in UnveilCeremonyView.swift) |
| `JourneyMapView.kt` (`JourneyKingdomAtlas`, `JourneyMapView`) | `JourneyMapView.swift` + `JourneyKingdomAtlas` |
| `JourneyMapMath.kt` (`JourneyMapGeometry`, `JourneyDayState`, `journeyDayState`, `JourneyImageSampling`) | `JourneyMapGeometry` (JourneyTilePositions.swift) |
| `GalleryView.kt` (`GalleryEntry`, `GalleryView`) | `GalleryView.swift` |
| `PaintingGlanceSync.kt` | `GlanceSyncCoordinator.swift` (render half) |

Strings: `res/values/strings_painting.xml` (`painting_*`, `journey_*`,
`ceremony_*`). Registry lines (gate pass line, emergency link, ceremony
title/line/Begin, "Anky is painting…", journey day label, veils) come from
`core/copy/AnkyCopyRegistry` and are NOT duplicated in resources.

Tests: `app/src/test/java/inc/anky/android/painting/` —
`CeremonyTimingTest` (beat table + stroke-beat clamps),
`JourneyMapMathTest` (seam/stack/point math, day states, downsampling),
`PaintingHomeLogicTest` (CTA by phase, quick-pass/emergency chrome, painting
progress, frame invariant). All pure JVM.

## Construction (AppContainer)

```kotlin
val paintingHomeDependencies = PaintingHomeDependencies(
    levelProgressStore = levelProgressStore,            // WS3 core
    paintingAssetStore = paintingAssetStore,            // WS3 core
    coordinator = levelPaintingCoordinator,             // WS3 core
    entitlementStore = entitlementStore,                // WS4
    quickPassStore = quickPassStore,                    // WS2 (gatePrefs)
    gateStateStore = gateStateStore,                    // WS2
    unlockStateStore = unlockStateStore,                // WS2
    funnel = ankyFunnel,                                // WS3 core
    celebrationLedger = JourneyCelebrationLedger(gatePrefs), // or its own prefs — key anky.journey.celebratedDayCount.v2
    loadAsset = { path -> runCatching { appContext.assets.open(path).use { it.readBytes() } }.getOrNull() },
    filesDir = appContext.filesDir,
    isGateAuthorized = { /* blocking runtime's live permission check (usage access / accessibility) */ },
    writerName = { writingAnchorStore.writerName },
    avatar = { /* AvatarStore bitmap, or { null } until an avatar exists */ },
    recentSessions = {
        sessionIndexStore.load().map {
            PaintingHomeSession(it.hash, it.createdAt.toEpochMilli(), it.preview, it.durationMs)
        }
    },
    journeySessions = {
        sessionIndexStore.load().map { JourneySessionInput(it.createdAt.toEpochMilli(), it.durationMs) }
    },
    backfillSessionStats = {
        sessionIndexStore.load().map {
            LevelSessionStat(it.hash, it.createdAt.toEpochMilli(), it.durationMs)
        }
    },
)
```

## Composable entry points

```kotlin
PaintingHomeView(
    dependencies = paintingHomeDependencies,
    onWrite = { nav to write },
    onChooseApps = { nav to app selection },      // gate phase NeedsSelection
    onContinueSetup = { nav to permission setup },// gate phase NeedsAuthorization (iOS folds both into onSetup)
    onOpenSettings = { ... },
    onOpenArchive = { ... },                      // History card tap
    onOpenYou = { ... },                          // header name/avatar tap
    onEmergencyBreath = { ... },                  // emergency link (shielded + locked only)
    blockedAppIcons = /* List<ImageBitmap> from PackageManager for the selected packages */,
    paywallSheet = { origin, onDismiss -> PaywallSheet(origin = origin, onDismiss = onDismiss) },
)

UnveilCeremonyView(level = level, coordinator = levelPaintingCoordinator, onFinished = { ... })

GalleryView(currentLevel, paintingAssetStore, levelProgressStore, onClose)   // also opened internally by home
JourneyMapView(side, positions, snapshot, loadAsset, celebrationLedger = ...) // page 2 of home's pager; standalone use optional
PaintingGenerationWaitView(excerpts)                                          // used internally by the ceremony
```

Integration notes:

1. **Ceremony gating** stays with the integrator: show `UnveilCeremonyView`
   when `coordinator.presentableCeremonyLevel(unhurried = true) != null`
   (app open / daily-unlock end — never mid-Quick-Pass). The view itself
   calls `markCeremonyShown(level)` on Begin; the caller only removes it in
   `onFinished`.
2. **paywallSheet slot** is invoked with the funnel origin (`"journey"` or
   `"ceremony"`). The home already reports `veil_tapped {origin}` before
   showing it; the sheet should report `paywall_shown {origin}` itself
   (iOS PaywallSheet behavior). Entitlement landing dissolves the boundary
   veil automatically (the home collects `entitlementStore.state`).
3. **Refresh cadence**: the home derives level/gate state on composition and
   whenever entitlement changes. If a resume-time refresh is wanted (iOS
   `onAppear` + `screenTime.state` observation), recompose the screen on
   ON_RESUME (nav re-entry already does this) — no extra API needed.
4. **Stroke beat**: `LevelProgressStore.consumePendingStrokeSeconds()` is
   consumed by the home the first time the painting is visible with assets;
   the seal path must NOT consume it (WIRING-level §1 credits only).
5. **GlanceSync**: after every progress change the home calls
   `PaintingGlanceSync.sync(filesDir, progressStore, assetStore, entitled)`
   (IO thread) which renders the composite and writes
   `GlanceSharedState` (`filesDir/Widget/`). The widget workstream reads it;
   seal/ceremony paths outside the home may call the same object.
6. **blockedAppIcons**: iOS renders FamilyControls `Label(token)`; Android
   has no token type — the integrator supplies launcher icons for the
   selected packages (order = selection order). Empty list hides the row.
7. `installStarterIfNeeded` and `backfillIfNeeded` are invoked inside the
   home (idempotent, guarded by the stores); calling them earlier at launch
   is also fine.

## Fidelity notes / approximations (vs. iOS)

- **Ceremony beats** are second-exact from `CeremonyTiming.swift`
  (2.2 / 1.8 / 1.1 / 0.8 / 8.0 / 1.2 / 1.8 / 0.9 / 3.4; stroke beat
  1.2–3.0s, `1.2 + pending/240`). Animations start from `LaunchedEffect`
  (post-insertion frame), the Compose equivalent of the iOS
  `DispatchQueue.main.async` kick.
- **Reveal rendering**: no AGSL/Metal — `PaintingRevealAssets` decodes each
  package once (LRU of 4, 1024px; gallery thumbs 512px) and blends with
  core `RevealRules` per progress bucket (100 buckets) off-main. During
  the 8s bloom this re-composites ~coarse frames instead of per-frame
  shader evaluation; the soft edge (gain 60) is identical.
- **Painting glow**: iOS uses two tinted `.shadow`s; Android draws two
  radial washes behind the frame (tinted shadows need API 28+ and can't
  animate). Alphas match (0.32/0.18 × strength).
- **Journey**: iOS currently ships the single baked 96-tile card;
  this port implements the stacked 8-kingdom scroll from
  `JourneyMapGeometry` per the WS3 spec — 4% seam overlap, the upper
  image's bottom band alpha-faded via `CompositingStrategy.Offscreen` +
  `BlendMode.DstIn` vertical gradient, 96 markers from
  `journey_positions.json`, auto-scroll centering the current stone,
  celebration bloom once per new day (`JourneyCelebrationLedger`).
  The current stone = max written index (iOS `latestWrittenIndex`).
- **Frame invariant**: `PaintingFrameMath` = `PaintingFrameMetrics`
  (inset 28, top 14%, max side 420, border 1.5, glow 42) in dp; the
  ceremony and home both place the frame through it, so it never moves.
- **History card / chrome**: `.ultraThinMaterial` replaced by the lazure
  translucent paper gradient (same approximation as `VeilCard`); the
  feather stat icon (iOS asset `you-icon-feather-stat`) is stood in by the
  spiral sun until the shared drawable lands.
- The journey pager page uses `AnkyCopyRegistry.veilJourney` under
  `VeiledFeature(surface = "journey")`; the boundary veil uses
  `veilCeremony` with the "not yet" dismiss underneath — copy verbatim.
