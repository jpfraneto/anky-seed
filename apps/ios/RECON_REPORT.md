## 1. Overview

### Project, targets, and toolchain

- The build container is `Anky.xcodeproj`; there is no independent `.xcworkspace`. Xcode's implicit self-workspace is `Anky.xcodeproj/project.xcworkspace/contents.xcworkspacedata:1-7`.
- The project has seven native targets: `Anky`, `AnkyWriteBeforeScrollShieldAction`, `AnkyWriteBeforeScrollShieldConfiguration`, `AnkyWriteBeforeScrollMonitor`, `AnkyGlanceWidgets`, `AnkyClip`, and `AnkyTests` (`Anky.xcodeproj/project.pbxproj:1016-1160,1228-1236`).
- `Anky` embeds all three Screen Time extensions, the widget extension, and the App Clip (`Anky.xcodeproj/project.pbxproj:1020-1044`).
- The shared `Anky` scheme launches `Anky.app` with `Anky/Anky.storekit`; a separate shared `AnkyClip` scheme exists (`Anky.xcodeproj/xcshareddata/xcschemes/Anky.xcscheme:59-82`; `Anky.xcodeproj/xcshareddata/xcschemes/AnkyClip.xcscheme:1-82`).
- Minimum deployment is iOS 16.0 for every target except `AnkyGlanceWidgets`, which is iOS 16.1 (`Anky.xcodeproj/project.pbxproj:1775-1849,1853-1988,1991-2137`).
- Every Xcode target declares Swift 5.0; the portable package uses Swift tools 5.9 and declares iOS 16/macOS 14 (`Anky.xcodeproj/project.pbxproj:1802-1809,1841-1848,1853-2137`; `Package.swift:1-10`).
- Main app identity is bundle `com.jpfraneto.Anky`, marketing version `2.0.0`, build `56` (`Anky.xcodeproj/project.pbxproj:1775-1851`).

### Dependencies

- Direct Xcode SPM dependency `RevenueCat` allows `5.x` from `5.0.0` and resolves to `5.73.0`; it owns StoreKit purchases, offerings, customer info, and entitlement checks (`Anky.xcodeproj/project.pbxproj:2216-2245`; `Anky.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:22-29`; `Anky/Purchases/EntitlementStore.swift:124-185,232-343`).
- Direct Xcode/SPM dependency `web3swift` allows `3.3.x` from `3.3.2` and resolves to `3.3.2`; it derives the BIP39/HD Base EOA, addresses, and secp256k1 signatures (`Anky.xcodeproj/project.pbxproj:2225-2245`; `Package.swift:15-29`; `Anky/Core/Identity/WriterIdentity.swift:50-107`).
- Transitive `BigInt 5.4.1` and `CryptoSwift 1.10.0` support EIP-712 integer encoding, hashes, BIP39/checksum work, and hex/signature utilities (`Anky.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:4-20`; `Anky/Core/Mirror/AnkyPostSigner.swift:1-74`; `Anky/Core/Identity/WriterIdentity.swift:1-4,90-107`).
- Transitive `secp256k1.swift 0.10.0` underlies web3swift's EOA operations (`Anky.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:31-38`; `Anky/Core/Identity/WriterIdentity.swift:61-70,90-106`).
- `Package.swift` exposes portable `AnkyProtocol` and `AnkyCore` libraries, but the app itself is the Xcode target and also links RevenueCat directly (`Package.swift:11-49`; `Anky.xcodeproj/project.pbxproj:1037-1041`).

### Architecture actually in use

- The UI is native SwiftUI, with a SwiftUI `@main` app and an `AppRoot` view (`Anky/AnkyApp.swift:5-13`; `Anky/AppRoot.swift:559-575`).
- State management is ad-hoc MVVM: feature-local `ObservableObject` view models, `@StateObject`, `@Published`, callbacks, singleton/default-constructed stores, and manual task ownership; there is no TCA-style reducer/store or formal dependency container (`Anky/Features/Write/WriteViewModel.swift:11-54,98-188`; `Anky/Features/Geshtu/GeshtuWorldView.swift:19-50`).
- The live surface is not the large legacy `NavigationStack` router. `geshtuWorldEnabled = true` hardwires `GeshtuWorldView`, whose `GeshtuState.Phase` enum is the active navigation/state machine (`Anky/AppRoot.swift:559-580`; `Anky/Features/Geshtu/GeshtuState.swift:18-70`).
- The repository still compiles a second, legacy tab/sheet/`NavigationStack` architecture below `legacyBody`, creating two competing composition roots (`Anky/AppRoot.swift:575-766,901-1143`).
- Persistence is handwritten files/JSON/defaults/Keychain rather than SwiftData or Core Data (`Anky/Core/Storage/LocalAnkyArchive.swift:32-56`; `Anky/Core/Storage/SessionIndexStore.swift:187-235`; `Anky/Core/Identity/KeychainClient.swift:4-63`).

### Folder map, two levels deep

- `.build/` — generated SwiftPM checkouts, artifacts, indexes, repositories, and architecture build products; not source (`Package.swift:1-49`).
- `.wrangler/` — local Cloudflare Wrangler cache/state; no iOS runtime code (`.wrangler/cache/`; `.wrangler/state/`).
- `Anky.xcodeproj/` — Xcode project, implicit workspace, shared schemes, package lock, and user data (`Anky.xcodeproj/project.pbxproj`; `Anky.xcodeproj/project.xcworkspace/`; `Anky.xcodeproj/xcshareddata/`; `Anky.xcodeproj/xcuserdata/`).
- `Anky/` — main application module and bundled resources (`Anky/AnkyApp.swift`; `Anky/AppRoot.swift`).
- `Anky/Assets.xcassets/` — app icons, product art, animation frames, painting/share assets, and Geshtu Anchor raster (`Anky/Assets.xcassets/GeshtuAnchor.imageset/Contents.json:1-14`).
- `Anky/Core/` — protocol, identity, storage, Mirror client, level, clipboard, and Write Before Scroll infrastructure (`Anky/Core/Protocol/AnkyWriter.swift`; `Anky/Core/Identity/WriterIdentity.swift`; `Anky/Core/Storage/LocalAnkyArchive.swift`).
- `Anky/Features/` — SwiftUI feature surfaces: Geshtu, Write, Reveal, onboarding, painting/journey, settings, You, map, and Screen Time debug/setup (`Anky/Features/Geshtu/GeshtuWorldView.swift`; `Anky/Features/Write/WriteView.swift`).
- `Anky/Fonts/` — bundled Fraunces font faces registered at runtime (`Anky/Support/AnkyLazure.swift:456-561`).
- `Anky/JourneyKingdoms/` — bundled authored journey-position data and kingdom art consumed by Journey (`Anky/Features/Painting/Journey/JourneyTilePositions.swift:6-82`).
- `Anky/Purchases/` — RevenueCat configuration, entitlement state, product policy, and legacy paywall (`Anky/Purchases/AnkyPurchasesConfig.swift`; `Anky/Purchases/EntitlementStore.swift`; `Anky/Purchases/PaywallView.swift`).
- `Anky/StarterPainting/` — bundled level-one painting assets used by painting reveal (`Anky/Core/Level/PaintingAssetStore.swift:139-163`).
- `Anky/Support/` — lazure theme, typography, shared controls, haptics, sprite/image utilities, and privacy manifest (`Anky/Support/AnkyLazure.swift`; `Anky/Support/AnkyTheme.swift`; `Anky/PrivacyInfo.xcprivacy`).
- `Anky/Tests/` — Xcode/unit fixtures for protocol, storage, subscriptions, Clip handoff, and share sanitization (`Package.swift:36-48`; `Anky/Tests/ClipSessionHandoffTests.swift`; `Anky/Tests/QuoteSanitizerTests.swift`).
- `Anky/{de,en,es,fr,hi,zh-Hans}.lproj/` — localized strings plus localized privacy/support copy (`Anky/en.lproj/Localizable.strings`; `Anky/en.lproj/PrivacyPolicy.md`).
- `AnkyClip/` — App Clip target, its small writing UI/controller, entitlements, plist, and asset catalog (`AnkyClip/AnkyClipApp.swift`; `AnkyClip/ClipSessionController.swift`; `AnkyClip/Assets.xcassets/`).
- `AnkyGlanceWidgets/` — WidgetKit and Live Activity extension, widget deep links, plist, and shared App Group entitlement (`AnkyGlanceWidgets/PaintingWidget.swift`; `AnkyGlanceWidgets/Info.plist:23-27`; `AnkyGlanceWidgets/AnkyGlanceWidgets.entitlements:4-9`).
- `AnkyWriteBeforeScrollMonitor/` — `DeviceActivityMonitor` extension for scheduling/relocking shields (`AnkyWriteBeforeScrollMonitor/Info.plist:23-29`).
- `AnkyWriteBeforeScrollShieldAction/` — Managed Settings shield-action extension (`AnkyWriteBeforeScrollShieldAction/Info.plist:23-29`).
- `AnkyWriteBeforeScrollShieldConfiguration/` — Managed Settings UI shield-configuration extension (`AnkyWriteBeforeScrollShieldConfiguration/Info.plist:23-29`).
- `Assets/` — non-target source/reference art grouped under sprites, app-flow images, icons, journey, onboarding, and visual prompts (`Assets/AnkySprites/`; `Assets/anky-app-flow-images/`; `Assets/app-icons/`; `Assets/journey-images/`; `Assets/onboarding/`; `Assets/visual-prompts/`).
- `JP_TUTORIAL/` — repository tutorial/reference material, not an Xcode target (`JP_TUTORIAL/`).
- `anky-onboarding-pack/` — onboarding source pack with `assets/` and `reference/`, separate from the compiled asset catalog (`anky-onboarding-pack/assets/`; `anky-onboarding-pack/reference/`).
- `build/` — generated archives, DerivedData, simulator/device products, and verification builds; not source (`build/DerivedData/`; `build/Anky.xcarchive/`).
- `docs/` — product/spec documents, including `docs/specs/`; several Axis/Geshtu statements are stale (`docs/specs/`; `DEVIATIONS.md:99-127`; `QA-HANDOFF.md:94-111`).
- `references/` — design/reference material outside the target (`references/`).
- `screenshots/` — captured product/QA images (`screenshots/`).
- `scripts/` — repository maintenance/build/asset scripts (`scripts/`).

## 2. Session lifecycle (most important section)

### Start and active writing

- Launch enters `AnkyApp → AppRoot → GeshtuWorldView` because the Geshtu flag is hardcoded true (`Anky/AnkyApp.swift:5-13`; `Anky/AppRoot.swift:559-573`).
- `GeshtuWorldView` owns `GeshtuState`, `WriteViewModel`, `VigilController`, and `GeshtuReflectionCoordinator` (`Anky/Features/Geshtu/GeshtuWorldView.swift:19-50`).
- `GeshtuState.phase` initially equals `.writing`; `GeshtuWorldView.onAppear` explicitly calls `enterWritingPhase()` because `onChange` will not observe that initial value (`Anky/Features/Geshtu/GeshtuState.swift:21-59`; `Anky/Features/Geshtu/GeshtuWorldView.swift:264-274,331-341`).
- On first launch, an onboarding animatic/name entry covers the already-mounted writing page and focuses it only after dismissal; the protocol session itself starts on the first accepted `Character`, which writes the epoch line (`Anky/Features/Geshtu/GeshtuWorldView.swift:71-74,169-181,527-540`; `Anky/Core/Protocol/AnkyWriter.swift:47-63`).
- Subsequent sessions start when `LandingStrataView.approachSentinel` invokes `axis.openWriting()`, transitioning the phase to `.writing` (`Anky/Features/Geshtu/LandingStrataView.swift:223-257`; `Anky/Features/Geshtu/GeshtuState.swift:181-188`).
- The writing phase mounts `WriteView(viewModel:axisMode:onCompleted:)`; its completion callback is `axis.channelDidClose(session:)` (`Anky/Features/Geshtu/GeshtuWorldView.swift:521-542`).
- `WriteView` wraps private `ForwardOnlyTextView`; native text enters `WriteViewModel.accept`, allowed autocorrection enters `replaceForwardTail`, and invalid input is rejected/nudged (`Anky/Features/Write/WriteView.swift:61-110,989-1055`).
- `WriteView.onAppear` loads preferences, binds completion, focuses, and catches up silence; foreground catch-up repeats and backgrounding saves the active draft (`Anky/Features/Write/WriteView.swift:303-325`).
- Each accepted insertion enters `WritingSessionEngine`, updates reconstructed glyphs/text, persists a draft, starts the 16 ms ticker, and reschedules closing (`Anky/Features/Write/WriteViewModel.swift:224-255`).
- The engine rejects CR/newline and time-distributes multi-character autocorrection/predictive insertions; suffix replacement is the only mutable protocol primitive (`Anky/Core/WriteBeforeScroll/WritingSessionEngine.swift:74-129,147-170`; `Anky/Core/Protocol/AnkyWriter.swift:65-107`).

### Sentinel and end detection

- “8-second sentinel” is not a universal eight-second delay: default is 8,000 ms, settings allow 3,000–30,000 ms, first Geshtu rehearsal overrides closing to 4,000 ms, and App Clip stays fixed at 8,000 ms (`Anky/Core/Protocol/AnkyDuration.swift:3-30`; `Anky/Core/Storage/WritingPreferencesStore.swift:49-112`; `Anky/Features/Geshtu/GeshtuWorldView.swift:331-339`; `AnkyClip/ClipSessionController.swift:19-31`).
- Accepted input schedules a `Task.sleep` for the remaining silence, then calls `closeOrFreezeAfterSilence()` (`Anky/Features/Write/WriteViewModel.swift:585-589,653-663`).
- Independently, the 16 ms display ticker compares wall-clock silence against `terminalSilenceMs` and closes when it crosses the threshold (`Anky/Features/Write/WriteViewModel.swift:1064-1103`).
- Foreground return catches up elapsed wall-clock silence in `closeIfSilenceElapsed()` (`Anky/Features/Write/WriteViewModel.swift:571-583`).
- `closeOrFreezeAfterSilence()` calls `sealAndSave()` when completion is bound; otherwise it freezes until `bindCompletion` arrives (`Anky/Features/Write/WriteViewModel.swift:172-177,1135-1141`).
- Eight minutes is only the “complete” classification/haptic threshold: crossing 480,000 accumulated event milliseconds does not end writing; silence still does (`Anky/Core/Protocol/AnkyDuration.swift:3-5,42-54`; `Anky/Features/Write/WriteViewModel.swift:1105-1117`).
- `sealAndSave()` validates and locally persists, credits level/WBS state, detaches `/level/sessions` sync, publishes `completedArtifact`, freezes input, and invokes the completion callback (`Anky/Features/Write/WriteViewModel.swift:678-746,1143-1160`).

### Exact completed-session shape

- Raw `.anky` first line is `<epochMilliseconds> <one Character>`; each later event is `<deltaMilliseconds> <one Character>` (`Anky/Core/Protocol/AnkyWriter.swift:28-30,47-63`).
- A literal space is encoded as `SPACE`; CR/newline is forbidden; lines are joined with `\n` and have no guaranteed trailing newline (`Anky/Core/Protocol/AnkyWriter.swift:47-63,122-128`).
- A bare positive integer line is terminal stillness; canonical serialized sentinel is `8000`. A representative artifact is `1784690000123 H`, `91 e`, `104 l`, `63 SPACE`, then `8000` on separate lines (`Anky/Core/Protocol/AnkyParser.swift:18-43`; `Anky/Core/Protocol/AnkyWriter.swift:109-120`).
- Parsed wrapper is `ParsedAnky(startEpochMs: Int64, events: [AnkyEvent], terminalSilenceMs: Int64?)`; each `AnkyEvent` is `(deltaMs: Int64, character: Character)`, with first event delta normalized to zero (`Anky/Core/Protocol/AnkyLine.swift:3-23`; `Anky/Core/Protocol/AnkyParser.swift:18-43`).
- `WritingSessionSnapshot` carries protocol/reconstructed text, elapsed/last-accepted milliseconds, and started/closed flags around the live engine (`Anky/Core/WriteBeforeScroll/WritingSessionEngine.swift:6-71`).
- Persisted wrapper `SavedAnky` carries local URL, SHA-256 hash, exact protocol text, reconstructed text, duration, completion flag, creation date, and rejected-input stats (`Anky/Core/Storage/LocalAnkyArchive.swift:6-25`).
- Reconstructed text concatenates event characters; duration sums event deltas and excludes terminal silence; `isComplete` means duration ≥480,000 ms (`Anky/Core/Protocol/AnkyReconstructor.swift:3-6`; `Anky/Core/Protocol/AnkyDuration.swift:42-54`).
- `createdAt` comes from the first epoch line and hash is SHA-256 over exact UTF-8 artifact bytes (`Anky/Core/Storage/LocalAnkyArchive.swift:49-56,332-348`; `../../protocol/SPEC.md:53-57`).

### Sentinel serialization contradiction

- `AnkyWriter.closeWithTerminalSilence()` appends fixed canonical `8000`, but main-app `sealAndSave()` never calls it and persists `sessionEngine.protocolText` directly (`Anky/Core/Protocol/AnkyWriter.swift:109-120`; `Anky/Features/Write/WriteViewModel.swift:678-703`).
- `AnkyValidator` permits a missing terminal marker, so a normal Geshtu session seals successfully without the declared sentinel (`Anky/Core/Protocol/AnkyValidator.swift:17-46`; `Anky/Features/Write/WriteViewModel.swift:686-703`).
- Before reflection, `terminalizedArtifactForReflection()` appends the currently stored inactivity preference, saves a newly hashed artifact, deletes the old artifact/index row, and inserts the replacement (`Anky/Features/Reveal/RevealViewModel.swift:463-490`).
- Swift accepts any positive terminal integer, but the backend TypeScript parser accepts only 1,000–8,000; configured thresholds 8,001–30,000 become malformed server input (`Anky/Core/Protocol/AnkyDuration.swift:32-40`; `../../protocol/implementations/typescript/src/parse.ts:12-14,43-54`).
- First-run closing uses the in-memory 4,000 override, while terminalization reloads stored preferences and normally appends `8000`; serialized silence therefore need not equal observed silence (`Anky/Features/Geshtu/GeshtuWorldView.swift:331-339`; `Anky/Features/Reveal/RevealViewModel.swift:475-477`).
- `GeshtuState.pendingSession` retains the deleted pre-terminalization hash; the reflection canvas excludes history by that stale hash while the archive holds the new hash, likely duplicating the current writing in its own background strata (`Anky/Features/Geshtu/GeshtuState.swift:56-60`; `Anky/Features/Geshtu/ReflectionDescentView.swift:155-161`).
- App Clip differs: it calls `engine.closeWithTerminalSilence()` and writes canonical `8000` before handoff (`AnkyClip/ClipSessionController.swift:111-132`).

### What happens today when a session ends

1. Silence reaches its threshold and `sealAndSave()` writes `.anky` plus input stats/index, credits level/WBS state, and begins metadata sync (`Anky/Features/Write/WriteViewModel.swift:678-740`).
2. `completion?(persisted)` reaches `WriteView`'s bound closure and calls `axis.channelDidClose(session:)`; that stores `pendingSession` and sets phase `.channelClosed` (`Anky/Features/Geshtu/GeshtuWorldView.swift:527-540`; `Anky/Features/Geshtu/GeshtuState.swift:190-197`).
3. Phase observation immediately calls `reflection.begin(for:)`; this is the exact seam where editing/resolution must replace immediate reflection upload (`Anky/Features/Geshtu/GeshtuWorldView.swift:283-307`).

```swift
// Anky/Features/Geshtu/GeshtuWorldView.swift:283-311
.onChange(of: axis.phase) { newPhase in
    switch newPhase {
    case .writing:
        enterWritingPhase()
    case .reflection:
        reflection.commit()
        if !rehearsalDone {
            rehearsalDone = true
            writeViewModel.terminalSilenceOverrideMs = nil
        }
    case .channelClosed:
        if let session = axis.pendingSession {
            reflection.begin(for: session)
        }
    case .landing:
        reflection.discard()
    default:
        break
    }
}
```

4. `GeshtuReflectionCoordinator.begin` constructs `RevealViewModel`, labels the surface `axis`, sets only response persistence false, and immediately starts `askAnkyForSealedSession()` (`Anky/Features/Geshtu/ReflectionDescentView.swift:21-51`).
5. The user sees the closed channel/Anchor after upload has begun. Holding is allowed for verified Pro or an unused device-local first vigil; otherwise the hold raises the paywall (`Anky/Features/Geshtu/GeshtuWorldView.swift:29-42,80-82`; `Anky/Features/Geshtu/AnchorView.swift:129-149`).
6. A permitted press arms for 0.16 s and charges at roughly 62.5 Hz; completion moves `.vigil → .descent` (`Anky/Features/Geshtu/VigilController.swift:22-50,60-135`; `Anky/Features/Geshtu/GeshtuState.swift:199-230`).
7. Descent waits at least 0.9 s and at most 30 s for the response, animates for 2.6 s, then enters `.reflection` (`Anky/Features/Geshtu/VigilView.swift:132-195`; `Anky/Features/Geshtu/GeshtuWorldView.swift:587-599`).
8. `.reflection` calls `reflection.commit()`: it persists a held response or allows the in-flight response to persist when it arrives (`Anky/Features/Geshtu/GeshtuWorldView.swift:287-300`; `Anky/Features/Geshtu/ReflectionDescentView.swift:53-57`; `Anky/Features/Reveal/RevealViewModel.swift:217-225,385-400`).
9. `AxisReflectionCanvas` shows the writing and then retry/error, listening spiral, streamed markdown, or final reflection; paragraphs are tappable and inline markdown is rendered as attributed SwiftUI `Text` (`Anky/Features/Geshtu/ReflectionDescentView.swift:75-172,184-245`; `Anky/Features/Geshtu/GeshtuVoices.swift:150-277`).

### Reflection generation

- Reflection is server-side, not on-device. `RevealViewModel` terminalizes/re-hashes, loads/creates the local identity, then supplies exact raw `.anky` UTF-8 bytes to `MirrorClient` (`Anky/Features/Reveal/RevealViewModel.swift:272-355`).
- The client signs those bytes and performs `POST <base>/anky` as `text/plain`, requesting Server-Sent Events and adding intent/app-version/surface headers (`Anky/Core/Mirror/MirrorClient.swift:121-147`).

```swift
// Anky/Core/Mirror/MirrorClient.swift:128-145
let signed = try AnkyPostSigner.sign(body: bytes, identity: identity)
var request = URLRequest(url: baseURL.appendingPathComponent("anky"))
request.httpMethod = "POST"
request.httpBody = bytes
request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
request.setValue(signed.identityVersion, forHTTPHeaderField: "X-Anky-Identity-Version")
request.setValue(signed.accountId, forHTTPHeaderField: "X-Anky-Account")
request.setValue(signed.signatureType, forHTTPHeaderField: "X-Anky-Signature-Type")
request.setValue(signed.signature, forHTTPHeaderField: "X-Anky-Signature")
request.setValue(signed.requestTime, forHTTPHeaderField: "X-Anky-Request-Time")
request.setValue(signed.client, forHTTPHeaderField: "X-Anky-Client")
request.setValue(intent.rawValue, forHTTPHeaderField: "X-Anky-Intent")
```

- SSE events are `update`, `reflection_chunk`, `reflection`, and `error`; final payload contains hash/title/reflection/tags (`Anky/Core/Mirror/MirrorClient.swift:44-118,193-208`).
- Active prompt is backend constant `PROMPT_AXIS`: 4–6 short plain-text lines, writer's language, second person, no advice/questions/diagnosis/markdown; reconstructed writing is appended after `---` (`../../backend/reflection.ts:196-221,242-283`).
- `../../backend/prompts/reflect-current.md` and iOS `AnkyReflectionPrompt` are older long-form prompts, not the live Axis prompt; the “exact prompt” clipboard comment is false for this surface (`../../backend/prompts/reflect-current.md:1-15`; `Anky/Core/Mirror/MirrorEligibility.swift:20-43`; `Anky/Features/Geshtu/GeshtuWorldView.swift:318-329`).
- Default OpenRouter models are `google/gemini-2.5-flash-lite` for `<88 s` and `88–480 s` tiers (60/250 max tokens) and `anthropic/claude-sonnet-4.6` at `≥480 s`; Bankr/Poiesis default to Sonnet but host environment variables can override (`../../backend/server.ts:228-264,740-767,1437-1495`; `../../protocol/implementations/typescript/src/session.ts:4-35`).
- Provider order is Bankr → OpenRouter → Poiesis → safe local fallback; source alone cannot establish the deployed provider/model because availability and environment variables select it (`../../backend/server.ts:244-264,1306-1349,1720-1737`).
- OpenRouter is called with `data_collection: deny` and `zdr: true` (`../../backend/server.ts:1359-1401`).
- The backend reads, hashes, authenticates, validates, and reserves idempotency before entitlement gating; only an entitled request is reconstructed and sent to an inference provider (`../../backend/server.ts:2049-2263`).
- Reality contradicts the apparent vigil privacy contract: `persistsReflection = false` delays only local response storage. Exact writing bytes are transmitted at `.channelClosed`, before hold/paywall/edit approval; cancellation may occur after the server has read them (`Anky/Features/Geshtu/ReflectionDescentView.swift:35-70`; `Anky/Features/Geshtu/GeshtuWorldView.swift:301-307`; `../../backend/server.ts:2092-2149`).
- The local “first free vigil” has no server exemption: an ordinary non-entitled account receives HTTP 402 even on its first device-local vigil (`Anky/Features/Geshtu/GeshtuWorldView.swift:29-42,80-82`; `../../backend/server.ts:2198-2208`).

### App Clip lifecycle

- App Clip uses the shared engine, an in-memory session, 16 ms ticker, fixed 8,000 ms threshold, canonical sentinel, and App Group handoff; it has no identity or network reflection (`AnkyClip/ClipSessionController.swift:5-31,50-132`; `AnkyClip/AnkyClipApp.swift:3-25`).
- Main-app launch validates, archives, indexes, and clears a pending Clip session (`Anky/Core/Storage/ClipSessionImporter.swift:37-66`; `Anky/AnkyApp.swift:16-34`).

## 3. Persistence & data models

### Storage technology and session/writing models

- No SwiftData/Core Data store exists; sources use direct files, Codable JSON, standard/App Group `UserDefaults`, Keychain, caches, and optional iCloud ubiquity files (`Anky/Core/Storage/LocalAnkyArchive.swift:32-56`; `Anky/Core/Storage/SessionIndexStore.swift:187-235`; `Anky/Core/Identity/KeychainClient.swift:4-63`; `Anky/Core/Storage/ICloudBackupStore.swift:36-109`).
- `SavedAnky` and `WritingInputStats` are the local artifact wrapper and rejected-backspace/enter counters (`Anky/Core/Storage/LocalAnkyArchive.swift:6-25`).
- Raw artifacts are `Documents/Ankys/<sha256>.anky`; optional stats sidecars are `<sha256>.input-stats.json` (`Anky/Core/Storage/LocalAnkyArchive.swift:32-56,166-180`).
- `SessionSummary` stores hash/date/local URL, duration/completion, preview/word counts, rejected-input counts, and reflection metadata (`Anky/Core/Storage/SessionIndexStore.swift:14-107`).
- `SessionDay` is a derived grouping with sessions, complete/fragment/reflection counts, today flag, and `AnkyversePosition` (`Anky/Core/Storage/SessionIndexStore.swift:125-185,292-369`).
- The session index is an ISO-8601 JSON array at `Application Support/Anky/session-index.json` and can rebuild from artifact/reflection files (`Anky/Core/Storage/SessionIndexStore.swift:187-235,372-386`).
- `ActiveDraftRecovery` wraps protocol text/date/duration/word count; current draft is `Documents/ActiveDrafts/dotAnky.anky`, with corrupt drafts quarantined (`Anky/Core/Storage/ActiveDraftStore.swift:6-33,47-101`).
- `LocalReflection` stores hash/title/reflection/tags/date as `Application Support/Anky/reflections/<hash>.json` (`Anky/Core/Storage/ReflectionStore.swift:3-68,112-131`).
- `ReflectionRequestStore` keeps pending hashes/timestamps for 15 minutes in standard defaults key `anky.pendingReflectionRequests` (`Anky/Core/Storage/ReflectionRequestStore.swift:3-50`).
- `WritingPreferences` is JSON in standard defaults key `anky.writingPreferences.v1`, including the 3–30 s threshold, autocorrection, appearance, and related writing settings (`Anky/Core/Storage/WritingPreferencesStore.swift:49-142`).
- `SavedRawCheckIn` is separate legacy write/talk/image text stored as `.txt` plus JSON under `Documents/RawCheckIns`; it is not a `.anky` post model (`Anky/Core/Storage/RawCheckInStore.swift:6-97`).
- App Clip `Meta`/`PendingSession` live as `clip-session.txt` and `clip-session-meta.json` in `group.com.jpfraneto.Anky.handoff` (`Anky/Core/Storage/ClipSessionHandoff.swift:3-67`).

### Identity, level, streak, and sojourn models

- `writerName` and onboarding anchor sentence are standard-defaults strings (`anky.writerName`, `anky.wbs.anchorSentence`), deliberately outside App Group storage; neither is a server username/profile (`Anky/Core/WriteBeforeScroll/WritingAnchorStore.swift:3-29`).
- Optional avatar is only `Documents/avatar.jpg`, explicitly not uploaded/App-Grouped (`Anky/Core/Storage/AvatarStore.swift:7-38`).
- `WriterIdentity` is in-memory EOA/private-key state rederived from a Keychain-backed recovery phrase (`Anky/Core/Identity/WriterIdentity.swift:18-47`; `Anky/Core/Identity/WriterIdentityStore.swift:3-49`).
- Geshtu phase, pending/opened session, re-offer, and paragraph selection are memory-only; only `anky.axisRehearsalDone` and `anky.axisFirstVigilUsed` persist via `@AppStorage` (`Anky/Features/Geshtu/GeshtuState.swift:18-83`; `Anky/Features/Geshtu/GeshtuWorldView.swift:29-42`).
- `LevelPaintingPhase`, `LevelUnreportedSession(hash,seconds,sealedAtMs)`, and `LevelProgressSnapshot` track lifetime seconds, strokes, unreported metadata, level painting phases, ceremonies, and funnel migration (`Anky/Core/Level/LevelProgressStore.swift:6-65`).
- Level state is `Application Support/Anky/level-progress.json`; sealing credits it synchronously and queues only hash/seconds/time for server reconciliation (`Anky/Core/Level/LevelProgressStore.swift:67-100,180-219,355-378`).
- `AnkyversePosition(dayIndex,cycleDay,region,dayInRegion)` is derived over a repeating 96-day calendar, not persisted (`Anky/Core/Storage/AnkyverseCalendar.swift:3-30`).
- `JourneyAnchor` derives origin from the earliest complete session; `JourneySojourn` defines eight kingdoms ×12 days with bundled authored positions (`Anky/Core/Storage/JourneyAnchor.swift:3-21`; `Anky/Features/Painting/Journey/JourneyTilePositions.swift:6-82`).
- `JourneyState` derives written/missed days, minutes, count, and current streak from complete `SessionSummary` rows; only celebrated-day count persists as `anky.journey.celebratedDayCount.v2` (`Anky/Features/Painting/Journey/JourneyTilePositions.swift:192-274`).
- Map streak requires writing today, while Journey treats today or yesterday as current; streak semantics disagree (`Anky/Features/Map/MapViewModel.swift:36-49,68-88`; `Anky/Features/Painting/Journey/JourneyTilePositions.swift:214-264`).
- `SignalSnapshot` derives local streak/gate state from session dates plus WBS state, not raw writing (`Anky/Core/WriteBeforeScroll/SignalState.swift:3-104`).
- `EightDayGateProgress` stores permanent completion days/dates in `anky.wbs.eightDayGateProgress.v1`; day 5/6 hooks remain incomplete (`Anky/Core/WriteBeforeScroll/EightDayGateStore.swift:6-119`).
- WBS models include `UnlockTier`/`UnlockGrant`, `UnlockState`, `QuickPassState`, `DailyTargetState`, and screen-time selection/grant/shield state, stored through the shared App Group/defaults (`Anky/Core/WriteBeforeScroll/UnlockPolicy.swift:6-143`; `Anky/Core/WriteBeforeScroll/UnlockStateStore.swift:3-70`; `Anky/Core/WriteBeforeScroll/QuickPassStore.swift:3-59`; `Anky/Core/WriteBeforeScroll/DailyTargetStore.swift:3-115`; `Anky/Core/WriteBeforeScroll/WriteBeforeScrollScreenTimeStateStore.swift:3-122`).

### Sync truth

- Optional private iCloud backup is user-controlled: settings/date use standard defaults and encrypted envelope is `<ubiquity>/Documents/Anky/anky-private-backup.v1` (`Anky/Core/Storage/ICloudBackupStore.swift:36-109,176-194`).
- Backup ZIP includes raw `.anky` and reflection JSON, encrypted AES-GCM with an HKDF-SHA256 key derived from the recovery phrase (`Anky/Core/Storage/ICloudBackupStore.swift:146-205`; `Anky/Core/Storage/BackupImporter.swift:227-272`).
- Data is not all local: active Geshtu sends exact writing to `/anky`; every seal syncs hash/seconds/time; legacy painting can send reconstructed chapter text; subscription/funnel state syncs; opt-in iCloud uploads encrypted writing/reflections (`Anky/Features/Reveal/RevealViewModel.swift:326-355`; `Anky/Features/Write/WriteViewModel.swift:703-713`; `Anky/Core/Level/LevelPaintingCoordinator.swift:212-239`; `Anky/Core/Storage/ICloudBackupStore.swift:85-109`).
- Backend SQLite has no raw-writing/reflection columns but retains account-scoped session hashes/times, level/painting/subscription/events/idempotency/quota state; reflection logs retain safe metadata (`../../backend/level/db.ts:64-185`; `../../backend/server.ts:2314-2353`).
- There is no server publication/post/profile content store today (`../../backend/level/db.ts:64-185`; `../../backend/server.ts:406-486`; `../../backend/ROUTE_AUTH_TABLE.md:8-19`).

## 4. Identity

- `RecoveryPhrase` is 12 lowercase BIP39-English words; human import validates dictionary membership and checksum (`Anky/Core/Identity/RecoveryPhrase.swift:5-40`; `Anky/Core/Identity/BIP39WordList.swift:3-5`).
- Generation obtains 128 random bits with `SecRandomCopyBytes`, adds the first four SHA-256 checksum bits, and maps twelve 11-bit indexes into the bundled list (`Anky/Core/Identity/RecoveryPhrase.swift:42-99`).
- The phrase derives an app-owned Base EOA via BIP39 seed and path `m/44'/60'/0'/0/0`; production chain ID is 8453, test 84532, curve secp256k1, signing EIP-712 (`Anky/Core/Identity/WriterIdentity.swift:18-30,50-71`).
- `accountId` is the checksummed Ethereum address; the private key is held only in the derived `WriterIdentity` value and can sign/recover 32-byte digests (`Anky/Core/Identity/WriterIdentity.swift:28-47,83-107`).
- Keychain uses generic-password service `lat.memetics.anky`. Primary phrase accessibility is `AfterFirstUnlockThisDeviceOnly`; explicit synchronized backup uses `AfterFirstUnlock` plus `kSecAttrSynchronizable=true` (`Anky/Core/Identity/KeychainClient.swift:4-44,53-62`).
- Keychain accounts are legacy `writer-ed25519-v1`, primary `writer-base-eoa-recovery-phrase-v1`, iCloud backup `writer-base-eoa-recovery-phrase-icloud-backup-v1`, and pending/previous import safety items (`Anky/Core/Identity/WriterIdentityStore.swift:3-16`).
- First load adopts a synchronized phrase if present, otherwise generates/saves one and deletes the legacy raw key; import stages/verifies before switching and snapshots the outgoing phrase (`Anky/Core/Identity/WriterIdentityStore.swift:18-89`).
- iCloud Keychain phrase backup is explicit opt-in (`Anky/Core/Identity/WriterIdentityStore.swift:103-130`).
- Biometrics protect recovery UI operations, not the Keychain item itself: no biometric `SecAccessControl` ACL is attached, so the app can read it after first unlock (`Anky/Core/Identity/BiometricAuthClient.swift:4-42`; `Anky/Core/Identity/KeychainClient.swift:27-30`).
- Account UI reveals/imports/backs up after device authentication and can delete backend plus local data (`Anky/Features/You/YouViewModel.swift:84-100,135-228,330-360`).
- Identity is local/self-custodied but not “purely local”: signed requests create/use pseudonymous backend records keyed by EOA for levels, subscriptions, events, and deletion; there is no username/password/email session (`Anky/Core/Level/LevelSyncClient.swift:20-32,142-204,224-233`; `../../backend/level/db.ts:64-185`).
- `SignedAnkyPost` is request-signing metadata, not a social post or publication model (`Anky/Core/Mirror/AnkyPostSigner.swift:10-47`; `Anky/Core/Mirror/MirrorClient.swift:121-139`).
- Human name is device-local `anky.writerName`, default `You`; optional avatar is a device-local JPEG and neither is uploaded (`Anky/Core/WriteBeforeScroll/WritingAnchorStore.swift:3-40`; `Anky/Core/Storage/AvatarStore.swift:7-53`).
- The local EOA authenticates APIs and becomes RevenueCat `appUserID`; recovery-phrase import is the only key-import path, and there is no RPC, transaction UI, WalletConnect, or SIWE flow (`Anky/Core/Identity/WriterIdentityStore.swift:51-89`; `Anky/Core/Identity/WriterIdentity.swift:18-107`; `Anky/Purchases/AnkyPurchasesConfig.swift:42-92`).
- No Farcaster/FID/Warpcast linkage exists; only a Clip test fixture says `farcaster` and a future deployment note mentions such links (`Anky/Tests/ClipSessionHandoffTests.swift:37`; `APPCLIP.md:100-105`).

## 5. Networking & backend

### Configuration and authentication

- Main API default is `https://mirror-production-a23c.up.railway.app`; standard `UserDefaults["mirrorBaseURL"]` can override it. There is no typed staging environment (`Anky/Core/Mirror/MirrorConfiguration.swift:3-10`).
- Public static-painting base is hardcoded `https://anky-gallery.fairchat.workers.dev/gallery/paintings/defaults` (`Anky/Features/Painting/GalleryView.swift:162-197`).
- API auth is wallet EIP-712, not bearer/cookie. `AnkyPostSigner` hashes exact body bytes and signs domain `Anky`, version `1`, Base chain, request time, and client (`Anky/Core/Mirror/AnkyPostSigner.swift:21-74`).
- Headers are `X-Anky-Identity-Version`, `Account`, `Signature-Type`, `Signature`, `Request-Time`, `Client`, plus `/anky` intent/app-version/surface (`Anky/Core/Mirror/MirrorClient.swift:128-146`; `Anky/Core/Level/LevelSyncClient.swift:224-233`).
- The signed message always says method `POST`, path `/anky`, even for GET/DELETE/other routes; backend deliberately verifies the same compatibility message, so route/method are not cryptographically bound (`Anky/Core/Mirror/AnkyPostSigner.swift:63-71`; `../../backend/server.ts:539-570,940-982`).
- Backend checks clock freshness/replay before signature verification; no App Attest/device attestation appears (`../../backend/server.ts:2081-2126`; `Anky/Core/Mirror/AnkyPostSigner.swift:21-74`).

### Every endpoint called by iOS

- `POST /anky` — raw `.anky` `text/plain`, SSE reflection; client `MirrorClient`, active call site `RevealViewModel`, server route `../../backend/server.ts` (`Anky/Core/Mirror/MirrorClient.swift:6-31,121-147`; `Anky/Features/Reveal/RevealViewModel.swift:272-355`; `../../backend/server.ts:2013-2295`).
- `POST /level/sessions` — JSON hash/seconds/sealedAt only, active after each seal (`Anky/Core/Level/LevelSyncClient.swift:39-62,206-222`; `Anky/Features/Write/WriteViewModel.swift:703-713`; `../../backend/level/routes.ts:92-167`).
- `GET /level/status` — signed level/painting status, called by legacy painting coordinator (`Anky/Core/Level/LevelSyncClient.swift:64-77`; `Anky/Core/Level/LevelPaintingCoordinator.swift:244-256`; `../../backend/level/routes.ts:200-210`).
- `POST /level/prepare` — `{level,text}` where text is distilled reconstructed writing since level-up; legacy route only (`Anky/Core/Level/LevelSyncClient.swift:79-101`; `Anky/Core/Level/LevelPaintingCoordinator.swift:212-239`; `../../backend/painting/routes.ts:152-408`).
- `POST /level/ceremony-shown` — `{level}`, legacy ceremony acknowledgment (`Anky/Core/Level/LevelSyncClient.swift:103-115`; `Anky/Core/Level/LevelPaintingCoordinator.swift:128-140`; `../../backend/level/routes.ts:169-198`).
- `GET /level/assets/<level>/<file>` — signed fetch of `final.png`, `underdrawing.png`, `revealmap.png`, or `meta.json` (`Anky/Core/Level/LevelSyncClient.swift:117-128`; `Anky/Core/Level/PaintingAssetStore.swift:139-163`; `../../backend/painting/routes.ts:410-448`).
- `POST /events/emergency-unlock` — `{}`, called only from inactive legacy `AppRoot` (`Anky/Core/Level/LevelSyncClient.swift:130-140`; `Anky/AppRoot.swift:445-458`; `../../backend/events/routes.ts:76-96`).
- `POST /events/funnel` — fire-and-forget whitelisted event/origin metadata (`Anky/Core/Level/LevelSyncClient.swift:177-195,246-268`; `../../backend/events/routes.ts:98-144`).
- `POST /subscription/identify` — `{appUserId: EOA address}`, proving RevenueCat user belongs to signed wallet (`Anky/Core/Level/LevelSyncClient.swift:142-175`; `Anky/Purchases/EntitlementStore.swift:346-371`; `../../backend/subscription/routes.ts:123-173`).
- `DELETE /account` — signed empty body, invoked from account deletion (`Anky/Core/Level/LevelSyncClient.swift:197-204`; `Anky/Features/You/YouViewModel.swift:330-360`; `../../backend/account/routes.ts:54-98`).
- Unsigned gallery `GET .../level-<n>/underdrawing.webp` — cached under `Caches/StaticPaintings` (`Anky/Features/Painting/GalleryView.swift:164-197`).
- RevenueCat SDK makes its own network calls; there is no direct Apple subscription request in app `URLSession` clients (`Anky/Purchases/AnkyPurchasesConfig.swift:38-93`; `Anky/Purchases/EntitlementStore.swift:124-185`).
- `/subscription/sync` is deprecated with no iOS caller; `/webhooks/revenuecat` is server-to-server; `/health` is operational only (`../../backend/subscription/routes.ts:175-203`; `../../backend/server.ts:406-486`).
- `WriteViewModel.requestAnkyNudge()` can call `/anky` with nudge intent, but has no caller; visible nudges are local `showContextualNudge()` (`Anky/Features/Write/WriteViewModel.swift:591-650,1008-1019`).

### Service ownership

- The service is discernible in the same monorepo at `../../backend`: package `@anky/backend`, Bun + Hono + SQLite, shared `@anky/protocol`, `viem`, and `sharp` (`../../backend/package.json:1-33`; `../../backend/server.ts:31-81`).
- SQLite defaults to `/data/anky.sqlite` for a Railway volume; provider secrets/endpoints/models come from host environment (`../../backend/server.ts:520-532,698-767`).
- iOS README still points to nonexistent `services/mirror`, and monorepo README still claims `/anky` is the only app route; current server registers level, painting, subscription, event, and account routes (`README.md:70-73`; `../../README.md:42-64`; `../../backend/server.ts:406-486`).

## 6. RevenueCat & monetization

### Catalog and configuration

- RevenueCat SDK is `5.73.0` (`Anky.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:22-29`).
- Configuration is hardcoded: public Apple SDK key `appl_mvCsxolPWZmQjtULGLQhmOUhGMY`, entitlement `pro`, offering `default`, group `Anky`, products `anky.annual`, `anky.monthly`, `anky.weekly` (`Anky/Purchases/AnkyPurchasesConfig.swift:11-30`).
- The shipped SDK key is a RevenueCat public key, but there is no environment/xcconfig indirection (`Anky/Purchases/AnkyPurchasesConfig.swift:11-13`; `Anky.xcodeproj/project.pbxproj:1775-1849`).
- RevenueCat configures directly with EOA address as `appUserID`; identity change calls `Purchases.shared.logIn`, never an anonymous-ID migration (`Anky/Purchases/AnkyPurchasesConfig.swift:38-93`).
- All billing periods unlock the same app-wide `pro`; there is no product-specific feature branch (`Anky/Purchases/PurchaseConstants.swift:4-37`).
- `EntitlementStore` trusts only current `verifiedActive` for gating; cached state is display-only, watches `customerInfoStream`, loads exact `default` offering/products, and fails unless all three plans exist (`Anky/Purchases/EntitlementStore.swift:71-89,124-185`).
- Purchase/restore uses RevenueCat, requires active `pro`, then identifies the signed EOA to backend; foreground verification explicitly fetches current customer info (`Anky/Purchases/EntitlementStore.swift:232-343,346-371`).
- Trial copy appears only when RevenueCat confirms exact annual three-day eligibility (`Anky/Purchases/EntitlementStore.swift:202-230`; `Anky/Purchases/PurchaseConstants.swift:39-60`).
- Local StoreKit catalog is weekly $3.99, monthly $11.99, annual $88.90 with a three-day trial (`Anky/Anky.storekit:11-158`).
- Production catalog is uncertain: code says weekly still needs App Store Connect/RevenueCat setup, Info metadata and privacy policy list only monthly/annual, while runtime requires all three (`Anky/Purchases/AnkyPurchasesConfig.swift:23-30`; `Anky/Info.plist:12-25`; `Anky/en.lproj/PrivacyPolicy.md:92-100`; `Anky/Purchases/EntitlementStore.swift:145-185`).

### Paywalls and feature gates

- Legacy full `PaywallView` offers annual/monthly and includes benefits, renewal terms, trial, restore, redemption, Terms, Privacy, and onboarding-free continuation (`Anky/Purchases/PaywallView.swift:19-91,123-177,269-311,404-483,534-583`).
- Live Geshtu uses separate `GeshtuGateSheet` with weekly/monthly/yearly direct purchase but no restore, renewal disclosure, legal links, redemption, or trial treatment (`Anky/Features/Geshtu/GeshtuWorldView.swift:214-221,766-879`).
- Settings opens the older `PaywallSheet`, so one build exposes two divergent subscription surfaces and Settings cannot choose weekly (`Anky/Features/Settings/AnkySettingsView.swift:103-132`; `Anky/Purchases/PaywallView.swift:586-617`).
- Current Geshtu gates the Anchor vigil: verified Pro or unused first-vigil flag proceeds; otherwise the paywall sheet rises (`Anky/Features/Geshtu/GeshtuWorldView.swift:29-43,80-82`; `Anky/Features/Geshtu/AnchorView.swift:129-149`).

```swift
// Anky/Features/Geshtu/GeshtuWorldView.swift:80-82
private var vigilAllowed: Bool {
    entitlements.isEntitledForGating || !firstVigilUsed
}

// Anky/Features/Geshtu/AnchorView.swift:139-148
if axis.anchorSupportsVigil {
    if vigilAllowed {
        configureVigil()
        vigil.press(duration: effectiveVigilDuration)
    } else {
        AnkyHaptics.light()
        onNeedsPaywall()
    }
}
```

- Policy declares writing/local nudges/existing reflections/gate/Quick Pass/emergency/early paintings/delivered art/history/settings free; new reflection/server nudge/journey/automatic Daily Unlock/adaptive targets/post-level-8 paintings Pro (`Anky/Purchases/PurchaseConstants.swift:182-224`).
- Live behavior is narrower: writing is free, one local first vigil is free, later vigils require verified Pro; first-vigil credit is `@AppStorage` and reinstall-resettable pending explicit server TODO (`Anky/Features/Geshtu/GeshtuWorldView.swift:29-42,80-82,268-272`).
- Server has no first-vigil exception, so that “free” vigil does not yield a reflection for a normal unentitled account (`../../backend/server.ts:2198-2208`; `Anky/Features/Geshtu/GeshtuWorldView.swift:29-42`).
- Critical live-root defect: deterministic RevenueCat configure/start/foreground reconcile exists only on unreachable `legacyBody` modifiers (`Anky/AppRoot.swift:559-575,1020-1029,1057-1079`).
- Geshtu creates `EntitlementStore` but only `loadPackages()` from gate/settings lazily starts RevenueCat and does not call `reconcileOnForeground`; a returning subscriber may remain unverified and see the gate (`Anky/Features/Geshtu/GeshtuWorldView.swift:43,214-245,766-879`; `Anky/Purchases/EntitlementStore.swift:145-199,326-390`).

### Write Before Scrolling tiers

- Quick Pass is free, 15 minutes, three per local day, triggered by terminal punctuation or six words; Daily Unlock runs to local day-end only when `dailyUnlockEntitled` is true (`Anky/Core/WriteBeforeScroll/UnlockPolicy.swift:6-31,91-143`).
- Legacy root binds `WriteViewModel` passive grants to `WriteBeforeScrollSpikeViewModel.applyUnlock`, reconciles paid grants, bootstraps RevenueCat, and propagates verified Pro into `dailyUnlockEntitled` (`Anky/AppRoot.swift:983-1042,1119-1139`).
- Applying Quick Pass consumes a pass, clears shield, and schedules relock; paid Daily Unlock is revoked/recreated during entitlement reconciliation (`Anky/Features/WriteBeforeScrollDebug/WriteBeforeScrollSpikeViewModel.swift:179-224,261-307`).
- Live Geshtu creates separate write/Screen Time models but binds neither passive unlock callback nor entitlement propagation; computed Quick Pass/Daily Unlock therefore cannot clear the shield on this route (`Anky/Features/Geshtu/GeshtuWorldView.swift:19-50`; `Anky/Features/Write/WriteViewModel.swift:180-187,825-913`; contrast `Anky/AppRoot.swift:983-1004`).
- Reader-to-writer subscriptions are not represented: RevenueCat has one app-wide `pro` attached to the reader's own EOA and no writer target, creator offering, allocation/payout, or reader→writer relationship (`Anky/Purchases/AnkyPurchasesConfig.swift:15-30,42-92`; `Anky/Core/Level/LevelSyncClient.swift:142-175`).

## 7. Deep links & app surface

- Main app registers custom scheme `anky` under URL type `inc.anky.deeplink` (`Anky/Info.plist:34-44`).
- Neither main app nor App Clip declares Associated Domains; there is no universal-link entitlement for public profiles (`Anky/Anky.entitlements:4-24`; `AnkyClip/AnkyClip.entitlements:4-13`).
- Legacy parser accepts scheme `anky`; host `write` opens writing, every other host—including documented `painting`—falls to home (`Anky/AppRoot.swift:417-428`).
- Widget emits `anky://write` and `anky://painting`; Home quick action emits/parks `anky://painting` (`AnkyGlanceWidgets/PaintingWidget.swift:84-115`; `Anky/Core/Level/HomeQuickActionPublisher.swift:9-71`).
- `.onOpenURL`, quick-action notification, and pending-URL consumption are modifiers only on `legacyBody`; hardwired Geshtu never mounts them, so current root does not route its registered scheme/widget/quick-action links (`Anky/AppRoot.swift:559-575,952-962,1050-1052`).

```swift
// Anky/AppRoot.swift:565-573
private let geshtuWorldEnabled = true

var body: some View {
    if geshtuWorldEnabled {
        GeshtuWorldView()
    } else {
        legacyBody
    }
}

// Anky/AppRoot.swift:960-962 — attached inside legacyBody
.onOpenURL { url in
    handleDeepLink(url)
}
```

- Main app delegate handles quick actions/notification callbacks but not `openURLContexts` or universal-link continuation (`Anky/AnkyApp.swift:16-84`).
- App Clip observes browsing-web activity and URLs but reads only optional `?source=` attribution; path is ignored (`AnkyClip/AnkyClipApp.swift:17-26`; `AnkyClip/ClipSessionController.swift:40-48`).
- App Clip AASA is a manual server/operator TODO, and future parameters beyond `source` are documented as ignored (`APPCLIP.md:68-105`).
- Live navigation is eight-case `GeshtuState.Phase`, not `NavigationStack`; warm phases share one strata surface and vigil/descent/reflection replace it (`Anky/Features/Geshtu/GeshtuState.swift:18-52`; `Anky/Features/Geshtu/GeshtuWorldView.swift:521-625`).
- Entry opening expands in-place; paywall, Settings, gate setup, share preview, and recording completion are sheets (`Anky/Features/Geshtu/LandingStrataView.swift:570-575,604-670`; `Anky/Features/Geshtu/GeshtuWorldView.swift:214-245`).
- No current phase/destination can represent an external public profile; profiles need an app-level URL/universal-link router plus a new Geshtu destination model (`Anky/Features/Geshtu/GeshtuState.swift:21-52`; `Anky/AppRoot.swift:417-428,559-575`).

## 8. Design system

- Display-P3 pigments are centralized as `Color.ankyPaper`, paperDeep, ink, inkSoft, ore, glaze, umber, quoteInk, slate, violet, apricot, gold/goldLight, sage, rose, and madder (`Anky/Support/AnkyLazure.swift:24-71`).
- Older semantic names alias lazure pigments through `AnkyTheme`; haptic conveniences live beside them in `AnkyHaptics` (`Anky/Support/AnkyTheme.swift:4-39`).
- Shared eight-second ambient motion is `AnkyBreath`, a cosine `0→1→0` phase (`Anky/Support/AnkyLazure.swift:73-86`).
- `LazureWall` is procedural: `TimelineView` at up to 20 fps, iOS 18 drifting `MeshGradient`, iOS 16/17 radial-gradient layers, plus deterministic Canvas paper grain (`Anky/Support/AnkyLazure.swift:88-210`).
- `WatercolorVeilView` is procedural Canvas with four breathing radial washes; Lazure itself is not a raster background or shader (`Anky/Support/WatercolorVeilView.swift:3-76`; `Anky/Support/AnkyLazure.swift:88-210`).
- Reusable primitives include `VeilCard`, `LazureDivider`, `ThreadButtonStyle`, `PaperThreadButtonStyle`, and `WashButtonStyle` (`Anky/Support/AnkyLazure.swift:213-359`).
- There is no centralized spacing/radius scale; shared and feature views use literal padding/radii such as 20, 28, 15/28 (`Anky/Support/AnkyLazure.swift:219-252,270-359`).
- Fraunces TTF faces are runtime-registered via Core Text with system-serif fallback; launch invokes registration (`Anky/Support/AnkyLazure.swift:456-561`; `Anky/AnkyApp.swift:21-25`).
- Broad font tokens are `.ankyTitle`, `.ankyHeading`, `.ankyProse`, `.ankyLabel`, `.ankyCaption`, `.ankyAction`; writing separately persists five UIKit/SwiftUI typeface choices (`Anky/Support/AnkyLazure.swift:563-581,845-893`).
- Geshtu voice modifiers distinguish writer `ore` from Anky `glaze`; tappable variants provide paragraph-level soft-gold selection (`Anky/Features/Geshtu/GeshtuVoices.swift:26-227`).
- `GeshtuAnchor` is raster asset rendered with `Image`; share cards use raster watercolor/character assets and `ImageRenderer` exports fixed 1080×1920 bitmaps (`Anky/Features/Geshtu/AnchorView.swift:251-359`; `Anky/Assets.xcassets/GeshtuAnchor.imageset/Contents.json:1-14`; `Anky/Features/Reveal/ShareCardView.swift:30-46,114-145`; `Anky/Features/Reveal/ShareCardRenderer.swift:4-23`).
- Painting reveal is distinct from Lazure: iOS 17 uses a Metal wet-edge layer effect over underdrawing/final/reveal-map rasters; iOS 16 uses Core Image fallback (`Anky/Features/Painting/PaintingRevealModifier.swift:35-180`; `Anky/Features/Painting/PaintingReveal.metal:4-52`).
- Anchor uses one zero-distance drag for tap/hold/release, breath-driven timelines, Canvas sparks/wood grain, radial glows, springs/easing, and escalating haptics (`Anky/Features/Geshtu/AnchorView.swift:51-175,249-442`; `Anky/Features/Geshtu/VigilController.swift:22-168,183-255`; `Anky/Features/Geshtu/VigilView.swift:19-129`).
- Other character animation uses named raster-frame sequences with per-sequence FPS, an async frame loop, and a separate breathing scale in `AnkySpriteView` (`Anky/Support/AnkySpriteView.swift:3-77,79-134`).
- Inline-mark foundation exists at TextKit level: private `ForwardOnlyTextView` updates `UITextView.textStorage` with UTF-16 ranges and builds attributed text glyph-by-glyph (`Anky/Features/Write/WriteView.swift:989-1055,1180-1274`).
- It is not an editor: `WritingGlyph` has only character/silence progress, spellcheck is disabled, mid-document changes are rejected, and selection is forced to the end (`Anky/Features/Write/WriteViewModel.swift:6-9`; `Anky/Features/Write/WriteView.swift:1026-1033,1349-1402,1437-1500`).
- `SelectableWritingText` is static/non-editable and voice selection is paragraph-level; there is no correction/ambiguity/range-resolution model or existing inline-mark behavior (`Anky/Features/Reveal/RevealView.swift:1018-1065`; `Anky/Features/Geshtu/GeshtuVoices.swift:52-227`; `Anky/Features/Write/WriteViewModel.swift:6-9`).
- Reusable pieces for the editor are the TextKit attribute pass, pigments, selection blob, and typography; stable annotation ranges, replacement history, ambiguity state, and arbitrary editing must be new (`Anky/Features/Write/WriteView.swift:1180-1274`; `Anky/Features/Geshtu/GeshtuVoices.swift:88-227`).

## 9. Capabilities & config

- Main entitlements are Family Controls, CloudDocuments/ubiquity container `iCloud.com.jpfraneto.Anky`, and App Groups `group.com.jpfraneto.Anky` plus `.handoff` (`Anky/Anky.entitlements:4-24`).
- No Associated Domains, `aps-environment`, Sign in with Apple, CloudKit, or explicit keychain-access group is declared in the main entitlement file (`Anky/Anky.entitlements:4-24`).
- App Clip entitlement contains parent app identifier and only handoff App Group (`AnkyClip/AnkyClip.entitlements:4-13`).
- Widget has main App Group; all three WBS extensions have Family Controls plus main App Group (`AnkyGlanceWidgets/AnkyGlanceWidgets.entitlements:4-9`; `AnkyWriteBeforeScrollMonitor/AnkyWriteBeforeScrollMonitor.entitlements:4-11`; `AnkyWriteBeforeScrollShieldAction/AnkyWriteBeforeScrollShieldAction.entitlements:4-11`; `AnkyWriteBeforeScrollShieldConfiguration/AnkyWriteBeforeScrollShieldConfiguration.entitlements:4-11`).
- Xcode capability metadata enables App Groups, Family Controls, and In-App Purchase on the main target (`Anky.xcodeproj/project.pbxproj:1170-1183`).
- Main Info is generated plus `Anky/Info.plist`; source plist declares exempt encryption, RevenueCat mirror metadata, camera/microphone/photo-add copy, and `anky` scheme (`Anky/Info.plist:5-44`; `Anky.xcodeproj/project.pbxproj:1787-1809,1826-1848`).
- Build settings add healthcare/fitness category, Face ID, photo-read, speech recognition, Live Activities, scene/launch generation, indirect input, and orientations (`Anky.xcodeproj/project.pbxproj:1787-1810,1826-1849`).
- No `UIBackgroundModes` key or push entitlement exists; reflection instead requests a finite UIKit background task (`Anky/Info.plist:4-45`; `Anky/Anky.entitlements:4-24`; `Anky/Features/Reveal/RevealViewModel.swift:580-599`).
- App Clip explicitly requests neither ephemeral notifications nor location confirmation (`AnkyClip/Info.plist:4-12`).
- Extension points are WidgetKit, DeviceActivity monitor, ManagedSettings shield action, and ManagedSettingsUI shield configuration (`AnkyGlanceWidgets/Info.plist:23-27`; `AnkyWriteBeforeScrollMonitor/Info.plist:23-29`; `AnkyWriteBeforeScrollShieldAction/Info.plist:23-29`; `AnkyWriteBeforeScrollShieldConfiguration/Info.plist:23-29`).
- Privacy manifest says no tracking while declaring linked user ID/content/purchases and UserDefaults/file-timestamp access (`Anky/PrivacyInfo.xcprivacy:5-116`).
- There are no source-owned `.xcconfig` base configurations: team, bundles, versions, permissions, and URLs are in project/plists/Swift (`Anky.xcodeproj/project.pbxproj:1775-1849`; `Anky/Info.plist:5-44`; `Anky/Core/Mirror/MirrorConfiguration.swift:3-10`).
- Public RevenueCat key, Mirror production URL, and gallery URL are hardcoded; inference/backend secrets remain host environment variables (`Anky/Purchases/AnkyPurchasesConfig.swift:11-13`; `Anky/Core/Mirror/MirrorConfiguration.swift:3-10`; `Anky/Features/Painting/GalleryView.swift:162-197`; `../../backend/server.ts:698-767`).
- Geshtu development phase/duration forcing reads `AXIS_DEBUG_*` process environment variables; these are debug scaffolding, not deployment environments (`Anky/Features/Geshtu/GeshtuWorldView.swift:343-380`).

## 10. Half-built, deprecated, or adjacent

- Two app architectures coexist. `AppRoot` retains the roughly 3,000-line legacy router but hardwires Geshtu on; its nearby comment still says legacy is canonical/Geshtu gated off (`Anky/AppRoot.swift:559-575`).
- `DEVIATIONS.md` and `QA-HANDOFF.md` say `geshtuWorldEnabled=false`, directly contradicting source (`DEVIATIONS.md:99-127`; `QA-HANDOFF.md:28-31,94-111`; `Anky/AppRoot.swift:559-573`).
- The inactive legacy root still owns deep-link consumption, deterministic RevenueCat reconcile, passive Screen Time unlock plumbing, Face ID lock, Clip welcome, iCloud restore, painting ceremonies, tabs, and routers (`Anky/AppRoot.swift:575-1227`).
- Several Axis names intentionally remain for persisted compatibility: reflection surface `axis`, `WriteView(axisMode:)`, and `anky.axis*` keys (`Anky/Features/Geshtu/ReflectionDescentView.swift:37-50`; `Anky/Features/Write/WriteView.swift:24-53`; `Anky/Features/Geshtu/GeshtuWorldView.swift:29-42`; `DEVIATIONS.md:46-67`).
- Geshtu still contains “Phase 1 scaffold,” debug phase-forcing removal notes, and release fallback `the ear is listening` when no reflection VM exists (`Anky/Features/Geshtu/GeshtuWorldView.swift:10-13,556-623`; `Anky/Features/Geshtu/GeshtuState.swift:321-339`).
- First-free-vigil server reconciliation is explicit TODO and reinstall-resettable (`Anky/Features/Geshtu/GeshtuWorldView.swift:29-42`).
- Proposed 60-second mission did not land; daily target remains integer 1–8 minutes, default eight (`DEVIATIONS.md:80-95`; `Anky/Core/WriteBeforeScroll/DailyTargetStore.swift:3-21,45-47`).
- `FirstGateStore` has an unused future subscription-pitch hook (`Anky/Core/WriteBeforeScroll/FirstGateStore.swift:24-32`).
- Screen Time direct-open remains deferred; resolver always selects notification because SDK enum is unavailable (`Anky/Core/WriteBeforeScroll/WriteBeforeScrollLaunchBridgeModeResolver.swift:3-17`).
- Eight-day tracker labels day-5 morning protection and day-6 share incomplete; share-card code now exists but no tracker event marks it (`Anky/Core/WriteBeforeScroll/EightDayGateStore.swift:83-115`; `Anky/Features/Reveal/RevealView.swift:1956-1997`).
- Overlong share quotes clamp while passage-picker UI remains TODO (`Anky/Features/Reveal/QuoteSanitizer.swift:63-82`).
- Sharing is export-only via rendered image and `UIActivityViewController`, not publishing; Geshtu entry share invokes that same local sheet (`Anky/Features/Reveal/RevealView.swift:1956-2009`; `Anky/Features/Geshtu/LandingStrataView.swift:593-670`).
- Existing `YouView` explicitly describes a private/device-local profile; Geshtu onboarding collects only local name and the optional avatar belongs to legacy onboarding/Painting Home (`Anky/Features/You/YouView.swift:723-762`; `Anky/Features/Onboarding/OnboardingAnimaticView.swift:30-59`; `Anky/Core/Storage/AvatarStore.swift:7-53`; `Anky/AppRoot.swift:851-857`).
- No visibility, publication, feed, subscriber, follower, unique username, or public-profile model/route exists in iOS/backend surfaces (`Anky/Core/Mirror/AnkyPostSigner.swift:10-47`; `Anky/Features/Geshtu/GeshtuState.swift:18-83`; `../../backend/server.ts:406-486`; `../../backend/level/db.ts:64-185`).
- App Clip AASA/operator work remains TODO (`APPCLIP.md:68-105`).
- Backend `/subscription/sync` is deprecated and unused by iOS (`../../backend/subscription/routes.ts:175-201`; `Anky/Core/Level/LevelSyncClient.swift:142-175`).
- Privacy policy says writing is sent on explicit reflection request, but current Geshtu sends at channel close before the hold/paywall (`Anky/en.lproj/PrivacyPolicy.md:52-64`; `Anky/Features/Geshtu/GeshtuWorldView.swift:301-307`; `Anky/Features/Geshtu/ReflectionDescentView.swift:35-50`).
- Subscription UI/catalog/legal sources disagree: live gate has weekly/no trial/restore, old paywall has annual/monthly/trial/restore, metadata/legal text list monthly/annual (`Anky/Features/Geshtu/GeshtuWorldView.swift:766-879`; `Anky/Purchases/PaywallView.swift:19-22,269-311,404-483`; `Anky/Info.plist:15-25`; `Anky/en.lproj/PrivacyPolicy.md:92-100`).
- README describes the old three-tab explicit-request privacy and 1–8-second stillness, not live Geshtu and current 3–30-second preferences (`README.md:5-29,196-211`; `Anky/AppRoot.swift:559-573`; `Anky/Core/Storage/WritingPreferencesStore.swift:49-112`).

## 11. Risks & unknowns

1. **Editing versus immutable protocol identity:** `.anky` is content-addressed by exact timed bytes; editing reconstructed prose changes or severs event mapping and requires distinct raw/edited models plus hash/index/reflection/level migration semantics (`Anky/Core/Storage/LocalAnkyArchive.swift:49-56`; `Anky/Core/Storage/SessionIndexStore.swift:93-107`; `Anky/Core/Protocol/AnkyWriter.swift:65-107`).
2. **No annotation domain:** there is no correction, ambiguity, range, resolution, original-versus-edited, publication, or visibility model; current glyph only stores character/silence (`Anky/Features/Write/WriteViewModel.swift:6-9`; `Anky/Core/Storage/SessionIndexStore.swift:14-107`).
3. **Upload occurs before the intended seam:** reflection transmission begins at sentinel, before editing, explicit hold, and paywall; the chain must be reordered if only approved edited content may ship, and current behavior already contradicts explicit-request privacy copy (`Anky/Features/Geshtu/GeshtuWorldView.swift:301-307`; `Anky/Features/Geshtu/ReflectionDescentView.swift:35-50`; `Anky/Features/Geshtu/AnchorView.swift:139-148`; `Anky/en.lproj/PrivacyPolicy.md:52-64`).
4. **Protocol/hash defects preexist:** main sessions omit canonical sentinel, reflection later mutates/re-hashes, state retains old hash, and server rejects configured terminal values over eight seconds (`Anky/Features/Write/WriteViewModel.swift:678-703`; `Anky/Features/Reveal/RevealViewModel.swift:463-490`; `Anky/Features/Geshtu/ReflectionDescentView.swift:155-161`; `../../protocol/implementations/typescript/src/parse.ts:12-14,43-54`).
5. **Profiles require a new identity/service domain:** name/avatar/free-vigil state are device-local and can reset independently of the recovery-backed EOA; backend has no username uniqueness, lookup, profile metadata/avatar storage, or public-account lifecycle beyond signed deletion (`Anky/Core/WriteBeforeScroll/WritingAnchorStore.swift:3-40`; `Anky/Core/Storage/AvatarStore.swift:7-53`; `Anky/Features/Geshtu/GeshtuWorldView.swift:29-42`; `Anky/Core/Identity/WriterIdentityStore.swift:18-130`; `../../backend/account/routes.ts:54-98`).
6. **Visibility requires authorization infrastructure:** public/subscribers/private needs stable post IDs, ACL checks, mutations/deletion, pagination/cache, moderation/report/block, and account-deletion behavior absent from current signed request ledger (`Anky/Core/Mirror/AnkyPostSigner.swift:10-47`; `../../backend/ROUTE_AUTH_TABLE.md:8-19`; `../../backend/account/routes.ts:54-98`).
7. **Creator subscriptions do not fit current RevenueCat model:** one global `pro` entitlement cannot encode which writer is subscribed, proceeds/payout, creator eligibility, grace/refund/revocation, or subscriber ACL (`Anky/Purchases/AnkyPurchasesConfig.swift:15-30,42-92`; `Anky/Core/Level/LevelSyncClient.swift:142-175`).
8. **Live composition root strands required infrastructure:** Geshtu bypasses deep links, RevenueCat verification, WBS unlock callbacks, and other bootstrap work in `legacyBody`; stale docs contradict that root and Map/Journey also disagree on streak semantics (`Anky/AppRoot.swift:559-575,952-1143`; `Anky/Features/Geshtu/GeshtuWorldView.swift:19-50`; `DEVIATIONS.md:99-127`; `Anky/Features/Map/MapViewModel.swift:36-88`; `Anky/Features/Painting/Journey/JourneyTilePositions.swift:214-264`).
9. **Profile deep links have no platform or navigation entry:** no Associated Domains and no active scheme handler/router/destination exist (`Anky/Anky.entitlements:4-24`; `Anky/AppRoot.swift:559-575,952-962`; `Anky/Features/Geshtu/GeshtuState.swift:21-52`).
10. **Unknown from code/deployed state:** live Railway provider/model/env/log retention, inference-provider retention, App Store Connect products, RevenueCat offering/entitlement/webhook state, production Associated Domains capability/AASA, and moderation/financial agreements cannot be verified locally; source shows no raw-writing DB columns but cannot prove infrastructure retention (`../../backend/server.ts:698-767,1306-1495,2314-2353`; `../../backend/level/db.ts:64-185`; `Anky/Purchases/AnkyPurchasesConfig.swift:23-30`; `APPCLIP.md:68-105`).
