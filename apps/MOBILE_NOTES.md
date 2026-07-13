# Porting notes — one lesson per line

- iOS's live home is PaintingHomeView; GateHomeView + CheckIn flow are legacy and NOT wired into AppRoot — do not port them.
- iOS deleted the entire credits economy (CRD/offering "Credits"/TokenPage/x402/Stripe onramp) on 2026-07-06; parity means deleting it on Android too, not migrating it.
- The level curve (base 480s × 1.62, per-step rounding) exists in three places (iOS AnkyLevel.swift, TS level.ts, now Kotlin) — any drift breaks server/client agreement; port the cross-tested fixtures.
- Android has no App Group problem: shield + app are one process, so all the iOS App-Group stores collapse to plain SharedPreferences/files.
- Android blocking = UsageStats poll in foreground service + full-screen shield Activity + AlarmManager relock; chosen over AccessibilityService for Play-policy safety. PACKAGE_USAGE_STATS needs a special-access declaration at Play review.
- Quick passes (3/day/15min) and emergency breath are free forever; Daily Unlock is subscription-gated; free tier level display clamps at level 2 (ledger keeps counting).
- Backspace-when-enabled is recorded as replaceSuffix (keep N−1, re-type last char) because the .anky protocol cannot represent deletions; text can never go empty.
- 8s cache: the "8" is load-bearing everywhere — 8-min ritual, 8s terminal silence, 8s breath cycle, 8 kingdoms, 96=8×12 journey days, 3 quick passes is the odd one out.
- Trial Live Activity has no Android equivalent worth shipping; skipped deliberately (trial reminder notification at expiry−28h is kept).
- Every new AnkyCopyRegistry string needs Localizable rows ×6 in the same change (iOS shipped an untranslated emergency link once; LocalizationResourceTest enforces parity on Android — update its counts).
- Reveal shader: minSdk 26 rules out AGSL; port iOS FallbackRevealRenderer (bitmap composite) as the single code path.
- Subscription wiring must happen in the shell/container, not lazily from Reveal/You: `EntitlementStore` is the gate truth, while old credits classes are temporary compile stubs until WS4 cleanup deletes them.
- Android's root route is now `painting`; Write is a child surface opened from the home CTA, so any new post-write/back behavior should return to PaintingHome, not the legacy Map tab.
- Public Android app links use host-only URIs (`anky://painting`, `anky://write`); MainActivity owns cold/warm intent state and AnkyApp consumes it for navigation.
