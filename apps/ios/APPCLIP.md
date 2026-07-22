# Anky App Clip

One raw writing session, then the handoff. The clip (`AnkyClip` target, bundle id
`com.jpfraneto.Anky.Clip`) is the acquisition surface: a link opens directly onto a live
writing surface — no onboarding, no identity, no networking. The 8-second sentinel seals the
session, the frozen words stay on screen, the system `SKOverlay` offers the full app, and the
session is waiting in the archive on first launch of the full app.

## What's in the clip target

Shared sources compiled directly from the app tree (no framework — same pattern as the
shield/widget extensions; behavior can never drift because it is the same code):

- `Anky/Core/Protocol/` — `AnkyWriter`/`AnkyParser`/`AnkyReconstructor`/`AnkyValidator`/
  `AnkyHasher`/`AnkyDuration`/`AnkyLine` (canonical encoding, byte-for-byte)
- `Anky/Core/WriteBeforeScroll/WritingSessionEngine.swift` (+ `UnlockPolicy.swift`,
  `UnlockStateStore.swift`, `AppGroupStorage.swift` as compile-time dependencies; dead code at
  clip runtime)
- `Anky/Support/AnkyLazure.swift`, `AnkyLocalization.swift`, `WatercolorVeilView.swift`,
  `Anky/Core/Storage/WritingPreferencesStore.swift` (lazure design system + Fraunces)
- `Anky/Features/Write/WritingRhythmDisplay.swift` — `WritingRhythmColor` + `SilenceLifeBar`,
  extracted (moved, not copied) from `WriteView.swift` so the sentinel's ink→madder timing
  curve is one definition for app and clip
- `Anky/Core/Storage/ClipSessionHandoff.swift` — the handoff contract (both targets)
- `Anky/Fonts/` folder reference (Fraunces TTFs, ~536 KB)

Clip-only files in `AnkyClip/`: `AnkyClipApp.swift` (entry, Fraunces registration, URL
handling), `ClipSessionController.swift` (16 ms ticker + sentinel + seal + handoff write —
mirrors `WriteViewModel`'s ticker cadence exactly; the session lives in memory and is written
once at seal), `ClipWriteView.swift` (the single screen + forward-only UITextView),
`ClipShims.swift` (no-op `AnkyFunnel`, verbatim `AnkyHaptics` — their real homes drag
networking/app UI), Info.plist (`NSAppClip`), entitlements, app-icon asset catalog.

Deliberately NOT in the clip: identity/BIP39/keychain, wallet code, RevenueCat, MirrorClient
or any networking, FamilyControls, notifications, the 57 Anky character frames, Rive/Lottie,
Localizable.strings (English microcopy only — `AnkyLocalization` falls back to the key).
Zero permission prompts.

## Handoff contract

App Group: **`group.com.jpfraneto.Anky.handoff`** — dedicated, shared ONLY between the app
and the clip. Not `group.com.jpfraneto.Anky`: that one is shared with the Screen Time
shield/monitor/widget extensions and is documented as never carrying raw writing.

At session end the clip writes atomically into the group container:

| File | Content |
|---|---|
| `clip-session.txt` | The raw canonical `.anky` protocol string (epoch-ms first line, delta-ms lines, `SPACE` token, `8000` terminal sentinel) — exactly what `AnkyWriter` produced |
| `clip-session-meta.json` | `{"createdAt": <epoch-ms>, "clipVersion": "2.0.0", "source": <?source= param or absent>}` |

Full-app side: `ClipSessionImporter.claimPendingClipSession()` runs in
`AnkyAppDelegate.didFinishLaunching` (delegate, not a view — it must run under both the
legacy root and the Geshtu world). It validates, imports through the SAME path as a native
session (`LocalAnkyArchive.save` + `SessionIndexStore` upsert), then clears the container.
`createdAt` needs no special handling — the archive dates artifacts from the protocol's
first-line epoch. A malformed payload is cleared so it can't wedge future launches; a storage
failure leaves it for the next launch to retry. On success the
`anky.clipImport.pendingWelcome` UserDefaults flag is set; the legacy surface's companion
bubble consumes it once ("the words you wrote before installing anky are already here.",
localized ×6).

Tests: `Anky/Tests/ClipSessionHandoffTests.swift` (SwiftPM suite, `swift test`) — canonical
string round-trips byte-for-byte into normal session storage, claim-once semantics, malformed
payload cleared, missing container ignored. Also verified live in the simulator: seeded
container → app launch → container empty, artifact in `Documents/Ankys/` byte-identical.

## Invocation

Every invocation lands on the writing surface. URLs arrive via
`NSUserActivityTypeBrowsingWeb` (and `onOpenURL`); all parameters are ignored except
`?source=`, which is recorded into the sidecar JSON (`ClipSessionController.handleInvocation`)
— future attribution needs no redesign.

Local testing: the shared `AnkyClip` scheme sets `_XCAppClipURL=https://anky.app/clip?source=xcode`.

## Server TODO (AASA) — do not forget

`https://anky.app/.well-known/apple-app-site-association` must gain an `appclips` entry:

```json
{
  "appclips": {
    "apps": ["84V63LKV45.com.jpfraneto.Anky.Clip"]
  }
}
```

(servable as `application/json`, no redirect, alongside any existing `applinks` entries).

## App Store Connect — manual steps (operator)

1. App Groups: register `group.com.jpfraneto.Anky.handoff` in the developer portal and add it
   to BOTH the `com.jpfraneto.Anky` and `com.jpfraneto.Anky.Clip` identifiers (automatic
   signing usually does this on first device build, but verify).
2. The clip's App ID `com.jpfraneto.Anky.Clip` needs the App Clip (`On Demand Install
   Capable`) capability and Parent Application Identifier `com.jpfraneto.Anky` (Xcode
   automatic signing handles this; the entitlements file already declares
   `parent-application-identifiers`).
3. In App Store Connect, after uploading a build containing the clip: configure the
   **default App Clip experience** (header image 1800×1200, subtitle, action "Open") and
   **advanced App Clip experiences** for the invocation URLs (`https://anky.app/clip` and
   whatever Farcaster/Mirror will link).
4. Set up the domain(s) in Associated Domains only if we later adopt `appclips:anky.app` in
   entitlements for physical-world invocations (link-based invocation needs AASA only).

## Measured size

Release, arm64 device build (unsigned, unthinned): **3.9 MB total** —
binary 440 KB, Fraunces fonts 536 KB, Assets.car (app icon) 2.9 MB. App Thinning will strip
unused icon sizes further. Comfortably under the 15 MB uncompressed thinned budget for
instant-launch eligibility. Re-measure from an exported archive's App Thinning Size Report
before submission if the clip gains assets.

## Notes / deviations

- The written spec described "4-digit zero-padded delta-ms" and "literal newline characters
  for newlines" — the shipped protocol (`AnkyWriter`, canon) pads nothing, encodes spaces as
  the `SPACE` token, and rejects newline input entirely (the main app's Enter key is a
  rejected input). The clip shares `AnkyWriter`, so it matches the app byte-for-byte, which is
  the real contract.
- The clip disables autocorrect (`.no`): the app keeps autocorrect alive through a
  tail-replacement protocol (`replaceSuffix`) that demands the full `ForwardOnlyTextView`
  machinery; the clip's input stays boring — strict end-append only, deletions/edits/newlines
  rejected, same engine-side filtering.
- No retry surface: one session per invocation. Dismissing the overlay leaves the frozen
  session on screen.
