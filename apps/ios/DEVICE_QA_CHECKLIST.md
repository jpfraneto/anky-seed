# Write Before You Scroll — Physical iPhone QA Checklist

FamilyControls, ManagedSettings shields, and DeviceActivity relock do **not**
work in the simulator. Everything below must be verified on a real iPhone.

## Prerequisites

- iPhone on iOS 17+ (16+ minimum per deployment target).
- Xcode signed in with a team that has the **Family Controls** capability
  approved (the `com.apple.developer.family-controls` entitlement exists on
  the app and all three extensions: ShieldAction, ShieldConfiguration,
  Monitor). Check the `.entitlements` files if shields silently fail.
- App Group `group.com.jpfraneto.Anky` present on the app and extensions.
- One "noisy" app installed on the device (e.g. X, Instagram, YouTube).
- Build a **DEBUG** build for QA: the WBS debug panel (top-left "WBS"
  capsule) only exists in DEBUG. Release builds hide it entirely — verify
  that too (step 26).

### Build & run

```
xcodebuild -project Anky.xcodeproj -scheme Anky \
  -destination 'platform=iOS,name=<your iPhone>' -configuration Debug
```

or run the `Anky` scheme from Xcode onto the device. If signing fails on the
extensions, fix all four targets' teams together.

### Inspecting WBS events during QA (DEBUG builds)

Tap the **WBS** capsule at the top-left of any non-sealing screen to expand
the debug panel. It shows authorization status, selection counts, tier,
shield state, and the **last 20 WBS events** (the ring buffer holds 300).
Key event names you should see during a healthy loop, in rough order:

`onboarding_target_set → screen_time_authorization_requested →
screen_time_authorization_granted → app_selection_saved → shield_applied →
shield_rendered → shield_primary_tapped → notification_scheduled →
notification_tapped → app_opened_with_pending_wbs_intent →
routed_to_wbs_from_shield → writing_started → sentence_unlock_available →
wbs_session_sealed → unlock_tapped → quick_pass_used → unlock_granted →
shield_cleared → relock_scheduled → relock_applied`

For the daily path: `daily_target_reached` replaces
`sentence_unlock_available`, and `session_overshoot` fires at seal when the
session ran past the target. When all three passes are spent, the shield
logs `quick_pass_exhausted_shown`. Editing the target in You logs
`target_changed`.

No event ever contains writing, reconstructed text, or the anchor sentence —
only names, counts, tiers, durations, and timestamps. If you see anything
else in the log, that is a privacy bug: stop and report it.

## A. First run

1. [ ] Fresh install (delete any previous build first).
2. [ ] Complete onboarding: 3 thesis screens, the daily-target slider
       (defaults to 8 minutes — try moving it and setting it back), then the
       personal screen. Enter a name and an anchor sentence
       (e.g. "I don't need to disappear right now.").
       Event: `onboarding_target_set` with the chosen value.
3. [ ] Gate setup sheet appears automatically. Tap **Allow Screen Time** and
       approve the system prompt. Status line should read `approved`
       (events: `screen_time_authorization_requested` → `..._granted`).
4. [ ] Tap **Choose apps** and select at least one app in Apple's picker.
       Status shows a non-zero count (event: `app_selection_saved`).
5. [ ] Tap **Turn on the gate**. Shield status reads `active`
       (event: `shield_applied`). Dismiss with **Done**.
6. [ ] Home (gate) screen shows "Your gate is on." with correct protected
       counts, "Day 1 of 8", and Signal 0%.

## B. Shield → notification → writing gate

7. [ ] Open a selected blocked app. Anky's dark shield appears
       ("Write before you scroll.") — event `shield_rendered`.
8. [ ] Tap the primary shield button (**Send notification**) —
       events `shield_primary_tapped`, `notification_scheduled`.
9. [ ] Shield copy switches to the "Tap the notification" state and honestly
       describes the notification path (no claim of direct open).
10. [ ] Tap the "Write before you scroll" notification — event
        `notification_tapped`.
11. [ ] Anky opens directly into the writing gate showing your anchor
        ("<name>, remember: “…” Write one true sentence to unlock."), or
        "Write one true thing before the feed gets in." if no anchor.
        Events: `app_opened_with_pending_wbs_intent`, `routed_to_wbs_from_shield`.

## C. Quick Passes and the Daily Unlock

12. [ ] Type an incomplete phrase (e.g. `hello`), stop 8 seconds; session
        seals (`wbs_session_sealed`); **no** Quick Pass offered. Pill read
        "finish a sentence · opens a 15-min pass" while typing.
13. [ ] New session; write `I am here.`; pill flips to "stop to unlock ·
        15 min"; after sealing a 15-minute Quick Pass is offered
        (`sentence_unlock_available`).
14. [ ] Apply the unlock (`unlock_tapped`, `quick_pass_used` with
        passNumber 1, `unlock_granted`, `shield_cleared`, `relock_scheduled`).
15. [ ] Blocked app opens (known apps get a web return URL) or you can return
        manually and use it.
16. [ ] While unlocked, all selected apps are shield-free; home shows
        "You wrote first. The gate is open." with the expiry time.
17. [ ] Wait for expiry. The shield re-applies automatically
        (`relock_applied` from the DeviceActivity monitor). If the monitor
        missed it, re-opening Anky must re-shield via reconcile
        (`shield_applied`). Verify one of the two happened.
18. [ ] Use two more Quick Passes (passNumber 2, then 3). The shield subtitle
        counts down ("2 passes left today." → "1 pass left today."). After
        the third, the shield leads with "I've opened the door three times
        today. Write with me first" and logs `quick_pass_exhausted_shown`;
        the writing pill reads "write to your target · opens the day".
19. [ ] Write to your daily target (set it low in You for testing —
        remember edits apply tomorrow, so set it before QA day or reinstall).
        At the target the pill flips to "stop to unlock · rest of day"
        without interrupting the session (`daily_target_reached`); keep
        writing past it, seal → `session_overshoot` with target and actual;
        the unlock expires at local midnight. Passes reset at midnight too.

## D. Protocol & privacy

20. [ ] Export a sealed `.anky` (You → Data → export). The file ends with
        exactly one bare `8000` line — once, and only once.
21. [ ] Raw writing never enters the App Group: inspect the app group
        container (Xcode → Devices → download container) — only selection
        tokens, shield/unlock state, launch-bridge intents, and event logs.
        No `.anky` text, no anchor sentence, no name.
22. [ ] Active draft: start writing, go Home mid-session, tap **Write now**
        — the in-flight session is still there. Background/foreground
        mid-session — it survives. (Cross-launch restore after force-kill is
        NOT a feature: a killed unsealed session stays only as a crash
        artifact file. Expected.)
23. [ ] Sealed immutability: seal a short session; verify the archive offers
        no way to continue/edit it (read/reflect/export only).

## E. Reflection & 8-Day Gate

24. [ ] Request a reflection on a sealed session; it streams and saves.
        (Contract: exact `.anky` bytes as `text/plain`, no tier field —
        backend derives the tier.)
25. [ ] 8-Day Gate card: after the first applied unlock, Day 1 shows
        complete; select a second app → Day 2 completes; your first Daily
        Unlock → Day 3; writing past your target (any overshoot) → Day 7;
        opening an archive reveal → Day 4. Days 5 and 6 are scaffolded and
        stay incomplete.

## F. Release-build check

26. [ ] Build once with `-configuration Release` (or archive) and confirm
        the WBS debug capsule does **not** exist anywhere, and gate setup is
        still fully usable via onboarding, Home, and the You tab.

## Known failure modes

| Symptom | Likely cause | What to check |
|---|---|---|
| No shield on blocked app | Authorization not `.approved`, empty selection, or entitlement missing | Debug panel auth/selected rows; `.entitlements` on all targets |
| Shield button does nothing visible | Notification permission denied | `notification_permission_missing` event; iOS Settings → Anky → Notifications; shield copy switches to "Open Anky manually" |
| Notification never arrives | Focus/DND suppressing it, or 2s debounce | Check Focus modes; `notification_resend_tapped` with "debounced" message |
| Tapping notification opens Anky but not the writing gate | Pending intent expired (10 min) or already consumed | `pending_intent_consumed` / absence of `routed_to_wbs_from_shield` |
| Relock never fires | DeviceActivity minimum window (unlock < ~5s away is rejected) or monitor extension died | `relock_failed` vs `relock_scheduled`; reconcile-on-active should re-shield as backstop |
| "Go back to X" does nothing | App has no known return URL mapping | Only x/tiktok/instagram/youtube/reddit/facebook/threads/snapchat map to web URLs; others return to Anky home — expected |
| Direct open from shield | Not possible on current SDK | Always notification fallback; any copy claiming direct open is a bug |
| Emergency unlock leaves app blocked on relaunch | By design: it only dismisses the shield presentation once | `emergency_unlock_tapped` event |

## G. Phase-3 — the boundary (needs device + StoreKit sandbox)

QA setup: `EntitlementStore.ignoresEntitlementForQA = true` forces the free
tier everywhere; combine with the seeded past-boundary level state
(`level-progress.json` totalSeconds ≥ 1300, lastCeremonyShownLevel = 2).

27. [ ] Free seal (Quick Pass): pass granted, unlock line, seconds counted,
        strokes land — and where the reflection would appear, the veiled
        card ("anky read this…"). Airplane mode on: identical (zero LLM
        calls; no network entry to /anky in Console).
28. [ ] Free daily-target session: NO day unlock (quick pass only if one
        remains); adaptive-target offer never appears.
29. [ ] Archive reveal while free: veil in place of reflection; sessions
        that already have reflections still show them.
30. [ ] Boundary: bar holds at lvl 2 · 100%; tapping the painting opens the
        veiled canvas → paywall sheet; "not yet" returns quietly.
31. [ ] Purchase at the boundary (sandbox): pay → "anky is painting…" →
        ceremony plays. Verify `/subscription/sync` 200 in Console BEFORE
        `/level/prepare` fires (race order).
32. [ ] Trial expiry (sandbox clock): veils return in-session at next
        feature use, no crash, no lockout screen anywhere; gate/passes/
        emergency all still work.
33. [ ] Refund test (sandbox): future generation gated, delivered paintings
        and gallery untouched.
34. [ ] Widget at boundary: earned painting + spiral + "a new painting
        waits", tap lands on painting home. Quick action shows
        "a new painting is waiting — with anky+".
35. [ ] Live Activity: never starts within 7 days of ANY paywall_shown.
36. [ ] Operator: App Store Connect → App Store Server Notifications V2
        URL set to
        https://mirror-production-a23c.up.railway.app/appstore/notifications
