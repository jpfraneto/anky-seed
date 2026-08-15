# Android Geshtu migration

## Runtime truth

Android now launches the same experience grammar as the current iOS app:

```text
WORLD
  strata ↔ opened day ↔ seed
     │
  fixed Anchor
     │
DEVICE
  writing → stillness → crossroads
                         ├─ keep writing
                         ├─ get Anky's reflection
                         └─ settle locally
```

`AnkyApp.kt` keeps the former navigation shell as a temporary rollback path,
but `GeshtuWorldEnabled` makes the Geshtu composition root canonical.

## The genome

`core/continuity/GeshtuContinuity.kt` is the first explicit TOHSENO-shaped
boundary in the mobile app. It is a pure reducer: no Compose, Android,
storage, network, purchase, or Anky protocol dependency. It owns only the
continuity law:

- writing closes into a pending artifact;
- an actual artifact must stand before it can be offered;
- a sealed artifact may continue as the same session;
- sending ends writing and enters finite reflection;
- settling clears transient state but never deletes the local artifact;
- the Anchor is the invitation between the world and the device.

The existing Android `.anky` writer, content-addressed archive, Base identity,
EIP-712 mirror client, reflection store, RevenueCat entitlement, gate runtime,
and settings surfaces remain adapters around that reducer.

## Migrated in this pass

- Geshtu WORLD/DEVICE composition instead of tabs.
- Fixed bottom Anchor drawn natively in Compose.
- Living archive strata with age recession and in-place opened entries.
- Writing device with parchment register, minimal countdown, and no legacy
  ritual rings.
- Stillness handoff into the three-way crossroads.
- Continue the same sealed session, including complete sessions.
- Explicit reflection request: no writing leaves the device before the
  reflection choice.
- Reflection descent with streaming, retry, and local settling.
- Paid reflection boundary with the portable prompt copied before the gate.
- Seed/settings surface using the existing account, recovery, export, privacy,
  reminder, and subscription implementation.
- Current first-principles name threshold instead of the deprecated 13-screen
  Android onboarding wrapper.
- Live wiring for writing preferences, the gate session, unlock application,
  level credit, and level sync.
- Pure reducer coverage for the primary continuity transitions.

## Deliberately not pretended complete

The newest uncommitted iOS work also contains platform-specific outward
surfaces that Android does not yet implement:

- the nine-frame first-launch animatic;
- selfie bubble plus screen recording/end-card stitching;
- paragraph-level share-card selection;
- late offering gravity animation for an old unreflected day;
- edit/ship/profile/web-login surfaces added by the outwards pivot;
- Android equivalents for App Clip, widgets, and iOS Screen Time extensions.

Those are adapters and product surfaces, not missing continuity law. They
should be ported on top of this root without adding tabs or a second router.

## Verification

```bash
cd apps/android
./gradlew :app:compileDebugKotlin
./gradlew :app:testDebugUnitTest \
  --tests 'inc.anky.android.continuity.GeshtuContinuityTest' \
  --tests 'inc.anky.android.write.WriteViewModelTest'
./gradlew :app:assembleDebug
```

The repository's broad `SourceInvariantTest` still contains several
string-matching assertions for the former white-on-black/tab/reveal shell and
other already-diverged iOS surfaces. Those assertions must be rewritten as
behavioral composition tests before the entire suite can be treated as a
Geshtu parity signal.
