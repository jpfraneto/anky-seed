# WIRING — WS3 core level & painting system (`inc.anky.android.core.level`)

Everything below is built and unit-tested but NOT wired into `AppContainer`/UI yet
(WS3 core owns no existing files). A later pass (or the WS3 UI half) should do this.

## Construction (AppContainer)

```kotlin
val levelProgressStore = LevelProgressStore(context)            // filesDir/Anky/level-progress.json
val paintingAssetStore = PaintingAssetStore(context)            // filesDir/Paintings/<level>/...
val levelSyncClient = LevelSyncClient(baseUrl = MirrorConfiguration().baseUrl) // reuse the shared OkHttpClient if one exists
val ankyFunnel = AnkyFunnel(levelSyncClient, { writerIdentityStore.loadOrCreate() }, appScope)

val levelPaintingCoordinator = LevelPaintingCoordinator(
    progressStore = levelProgressStore,
    assetStore = paintingAssetStore,
    syncClient = levelSyncClient,
    funnel = ankyFunnel,
    identityProvider = { runCatching { writerIdentityStore.loadOrCreate() }.getOrNull() },
    sessionStats = {
        sessionIndexStore.load().map {
            LevelSessionStat(hash = it.hash, createdAtMs = it.createdAt.toEpochMilli(), durationMs = it.durationMs)
        }
    },
    chapterArtifacts = {
        localAnkyArchive.list().map {
            LevelChapterArtifact(createdAtMs = it.createdAt.toEpochMilli(), reconstructedText = it.reconstructedText)
        }
    },
    scope = appScope,
)
```

## Hooks needed in existing code

1. **Seal path** (wherever a session is sealed / WriteViewModel completion):
   `levelProgressStore.creditSealedSession(hash, durationMs, replacedDurationMs)` —
   synchronously, before any UI transition; pass `replacedDurationMs` for continued
   sessions (only the delta is credited). Then `levelPaintingCoordinator.handleSealCompleted()`.
2. **App foreground / launch** (AnkyApp / MainActivity onStart):
   `levelPaintingCoordinator.refreshOnForeground()` — flushes the unreported queue,
   reconciles `GET /level/status`, prefetches generated packages.
3. **Entitlement changes** (WS4 subscription store): keep
   `levelPaintingCoordinator.entitledForGating` fresh (defaults false / fails closed),
   and call `handleEntitlementConfirmed()` after a server-confirmed purchase/restore.
4. **One-time backfill** (first run of the level system):
   `levelProgressStore.backfillIfNeeded(sessionIndexStore.load().map { ... })` — guarded
   internally by `didBackfill`.
5. **Starter painting** (first composition of the painting home):
   `paintingAssetStore.installStarterIfNeeded { path -> runCatching { context.assets.open(path).use { it.readBytes() } }.getOrNull() }`
   (assets live at `assets/starterpainting/`).
6. **Ceremony UI** (WS3 UI half): gate on
   `presentableCeremonyLevel(unhurried = ...)`; poll `waitForCeremonyPackage(level)`
   while showing the generation-wait view (`paintingGenerationExcerpts()` for its
   excerpts); call `markCeremonyShown(level)` when the unveiling finishes.
7. **Widget snapshot** (post-seal / ceremony / foreground — Android port of iOS
   GlanceSyncCoordinator, to be written with the widget workstream): render
   `FallbackRevealRenderer().render(pkg, presentedProgress.percent)`, then
   `GlanceSharedState.write(context.filesDir, snapshot, pngBytes)` (`filesDir/Widget/`).
8. **Emergency unlock analytics** (WS2 gate): `levelSyncClient.reportEmergencyUnlock(identity)`.
9. **Subscription identify** (WS4): `levelSyncClient.identifySubscription(identity)` after
   RevenueCat logIn; funnel events via `ankyFunnel.report(AnkyFunnel.Subscribed, origin)` etc.
10. **Journey card** (WS3 UI half): `JourneyState.derive(sessions, nowMs, zone)` with
    `JourneySessionInput` adapted from SessionIndexStore;
    `JourneyPositions.parse(assets json at journeykingdoms/journey_positions.json)`;
    celebration ledger `JourneyCelebrationLedger(sharedPreferences)` (key
    `anky.journey.celebratedDayCount.v2`). Kingdom images: `assets/journeykingdoms/kingdom1..8.png`.

## Test-invariant note (do not lose)

`SourceInvariantTest.networkAndPurchaseClientsStayInExplicitPaths` allowlists the
tokens `OkHttpClient` / `Request.Builder` / `newCall(` to `core/mirror/MirrorClient.kt`
only. The whole SourceInvariantTest class currently fails to run because it still
resolves the pre-move `apps/android/...` paths; whoever repoints it to
`apps/android/...` must also add
`.../core/level/LevelSyncClient.kt` to that allowlist (it is a network client by
design, signed with the same EIP-712 plumbing as MirrorClient).

## Contract notes

- Signing parity: like iOS, every `/level/*`, `/events/*`, `/subscription/*` request is
  signed with typed data carrying `method: "POST", path: "/anky"` (the signer's fixed
  message); only bodyHash/requestTime/account vary. `SignedLevelRequests` wraps the
  existing `AnkyPostSigner` without modifying it.
- Asset downloads are sequential on purpose (same-millisecond signature replay protection).
