# Feature 03: Companion Positioning

## Problem
The Anky companion character moves/animates every time a message appears. The user wants it fixed: right side of screen, 50% from the top, no movement.

## Root Cause
`AnkyPresenceOverlay` (Support/AnkyPresenceOverlay.swift) has two movement triggers:

1. **Docking to dialogue** — `dockedToDialogue` parameter causes the overlay to reposition near the dialogue panel (left side) when messages appear. Animation on line 69.

2. **Draggable** — The overlay is fully draggable with `@AppStorage` persistence (ankyPresenceX, ankyPresenceY). User can move it anywhere.

In `AppRoot.swift:69-76`, the overlay is configured with `dockedToDialogue: shouldShowWriteDialogue` which toggles whenever a dialogue appears/disappears.

## Solution

### AnkyPresenceOverlay.swift Changes

1. **Remove `dockedToDialogue` parameter** — delete from init, delete from body logic
2. **Remove `dialoguePoint()` function** (line 205-209)
3. **Simplify `resolvedPoint()`** (line 177-189) — always return `defaultPoint()`
4. **Fix `defaultPoint()`** (line 198-203) to return right side, 50% height:
```swift
private func defaultPoint(in containerSize: CGSize, presenceSize: CGFloat) -> CGPoint {
    return CGPoint(
        x: containerSize.width - presenceSize / 2 - 20,  // right side, 20pt margin
        y: containerSize.height / 2                       // 50% from top
    )
}
```
5. **Remove the `dockedToDialogue` animation** (line 69)
6. **Remove the `onChange(of: keyboardHeight)` repositioning** (line 124-132)
7. **Keep:** tap handler, long-press menu, breathing animation, golden glow, sigil transform

### AppRoot.swift Changes

Remove `dockedToDialogue: shouldShowWriteDialogue` from `AnkyPresenceOverlay` init (line 73).

## Files to Modify
1. `apps/ios/Anky/Support/AnkyPresenceOverlay.swift`
2. `apps/ios/Anky/AppRoot.swift`

## Testing
- Open app, verify companion appears on right side at 50% height
- Trigger dialogue messages, verify companion stays still
- Verify tap still works
- Verify long-press menu still works (show/hide/change motion)
- Verify breathing animation still works
