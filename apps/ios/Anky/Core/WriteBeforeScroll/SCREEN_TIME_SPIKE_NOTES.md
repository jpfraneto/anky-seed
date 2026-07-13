# Write Before You Scroll Screen Time Spike

This spike proves the narrow X loop only:

1. Open Anky.
2. Tap the temporary `WBS` debug control.
3. Tap `authorize` and approve Family Controls.
4. Tap `select X`, choose X manually in the Family Activity Picker, and dismiss the picker.
5. The selected token is saved in the App Group and the shield is reconciled immediately.
6. Open X. The custom shield should show `WRITE BEFORE YOU SCROLL`.
7. Tap the primary shield button. On SDKs that expose `ShieldActionResponse.openParentalControlsApp`, the intended bridge mode is direct open. On the current local SDK, the Swift interface does not expose that case, so the spike uses the notification fallback.
8. In notification fallback mode, tap the notification or manually open Anky. The app sees the pending launch intent and opens the writing surface.
9. Write:
   - first completed sentence with a period: unlocks for 15 minutes
   - 88 seconds of writing: unlocks for 30 minutes
   - full anky: unlocks until the end of the local day
10. On unlock, Anky clears the shield and starts a Device Activity interval. When the interval ends, the monitor extension reapplies the shield.

## Manual Real-Device Checklist

Run this on a physical iPhone. Simulator testing is not meaningful for Screen Time shielding.

1. Install and launch Anky.
2. Tap the temporary `WBS` debug control.
3. Tap `authorize` and approve Family Controls.
4. Tap `select X`, select X/Twitter manually in the Family Activity Picker, and dismiss the picker.
5. Confirm the debug panel shows selected app status `exists`.
6. Tap `force lock`.
7. Confirm the debug panel shows shield `active`, no unlock expiration, and no last error.
8. Open X.
9. Confirm the shield appears with `WRITE BEFORE YOU SCROLL`.
10. Tap the shield action.
11. Tap the notification or manually open Anky.
12. Confirm Anky opens directly into the writing surface and the event log includes `shield_rendered`, `shield_primary_tapped`, `bridge_mode_notification`, `notification_scheduled`, `app_opened_with_pending_wbs_intent`, `routed_to_wbs_from_shield`, and `pending_intent_consumed`.
13. Write one complete sentence ending with a period.
14. Confirm the debug panel shows sentence unlock available.
15. Type at least one more character after sentence unlock becomes available.
16. Confirm the debug panel golden metric says continued writing is true and shows characters/seconds after unlock availability.
17. Tap the debug unlock button.
18. Confirm the event log includes `unlock_tapped`, `unlock_granted`, and `relock_scheduled`.
19. Confirm X opens or is manually openable and unshielded.
20. Wait for the unlock expiration.
21. Confirm the debug panel shows shield `active` again and the event log includes `relock_applied`.

For faster iteration, `force unlock` writes a clear one-minute test expiration and `force lock` clears any expiration before reapplying the shield.

## Bridge QA

Direct-open mode, once building with an SDK that exposes `ShieldActionResponse.openParentalControlsApp`:

1. Open a blocked app.
2. Confirm the shield primary button says `Open Anky`.
3. Tap `Open Anky`.
4. Confirm Anky opens directly into the writing interface.
5. Confirm no notification appears.

Notification fallback mode:

1. Open a blocked app.
2. Confirm the shield primary button says `Send notification`.
3. Tap `Send notification`.
4. Confirm a local notification appears.
5. Confirm the shield copy changes to `Tap the notification`.
6. Tap the notification.
7. Confirm Anky lands immediately in the writing interface.
8. Reopen the blocked app and tap the primary button repeatedly.
9. Confirm notifications are not spammed faster than the two-second cooldown.

Notifications disabled:

1. Deny notifications for Anky.
2. Open a blocked app.
3. Tap the primary shield button.
4. Confirm the shield tells the user to open Anky manually and does not claim it can open Anky directly.

## Limits

- X cannot be hardcoded by bundle identifier through the Screen Time API. Family Activity selections are privacy-preserving opaque tokens, so the tester must select X manually.
- The local Xcode SDK exports an `openParentalControlsApp` binary symbol but does not expose `ShieldActionResponse.openParentalControlsApp` in the Swift interface. The bridge resolver therefore keeps notification fallback compiling and includes a compatibility TODO for enabling direct open once the SDK exposes the case.
- The notification workaround depends on notification permission and the user's Focus/notification settings.
- Device Activity relock behavior must be verified on an unlocked physical iPhone after selecting X. Simulator testing is not meaningful for this loop.
- Family Controls requires Apple approval for distribution entitlement use. Development signing may work locally while TestFlight/App Store distribution still needs explicit approval.
