# Codex Prompt: Fix Companion Positioning

## Repo Context
Repo: ~/anky-seed
iOS App: SwiftUI (apps/ios/Anky/)

## Current Behavior
The AnkyPresenceOverlay (Support/AnkyPresenceOverlay.swift) is a draggable floating companion character. Its position is stored in UserDefaults (ankyPresenceX, ankyPresenceY). It animates when `dockedToDialogue` changes (line 69). When a dialogue appears, it moves to the left side near the dialogue panel (dialoguePoint at line 205-209).

In AppRoot.swift:69-76, the overlay is configured with:
- dockedToDialogue: shouldShowWriteDialogue (changes when dialogue appears/disappears)
- onTap: presenceTapHandler

This causes the companion to move/animate every time a message appears.

## Desired Behavior
- Companion is STATIC, fixed position
- Right side of screen, 50% from the top (vertically centered)
- No animation on message arrival
- No docking behavior
- Keep tap handler and long-press menu

## Tasks

1. **Simplify AnkyPresenceOverlay:**
   - Remove `dockedToDialogue` parameter entirely
   - Remove `dialoguePoint()` function (line 205-209)
   - Change `defaultPoint()` (line 198-203) to return:
     ```swift
     CGPoint(
       x: containerSize.width - presenceSize / 2 - 20,  // right side with 20pt margin
       y: containerSize.height / 2                       // 50% from top
     )
     ```
   - Remove the animation on `dockedToDialogue` (line 69)
   - Remove the `onChange(of: keyboardHeight)` repositioning (line 124-132) — keep keyboard avoidance if needed but don't reposition to dialogue

2. **Update AppRoot.swift:**
   - Remove `dockedToDialogue: shouldShowWriteDialogue` from AnkyPresenceOverlay init (line 73)
   - The overlay should stay fixed regardless of dialogue state

3. **Keep:**
   - Tap handler (onTap) — still needed for presenceTapHandler
   - Long-press menu — still needed for show/hide/change motion
   - Breathing animation — subtle scale pulse is fine
   - Golden glow and sigil transform — these are visual states, not position changes

## Files to Modify
- apps/ios/Anky/Support/AnkyPresenceOverlay.swift
- apps/ios/Anky/AppRoot.swift

## Testing
- Open app, verify companion appears on right side at 50% height
- Trigger dialogue messages, verify companion does NOT move
- Verify tap still works
- Verify long-press menu still works
