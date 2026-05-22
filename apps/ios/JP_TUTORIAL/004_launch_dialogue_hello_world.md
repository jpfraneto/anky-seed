# Launch Dialogue Hello World

This lesson explains the first app-load Anky dialogue.

## Mental model

The launch dialogue is the smallest proof that app communication can come from Anky instead of generic UI chrome. When the app opens to Write, the existing floating Anky moves into a speaker position and says `write 8 minutes`.

The message is intentionally simple. It is the "hello world" for the dialogue system.

## Files involved

- `Anky/AppRoot.swift` decides when the launch conversation appears and tracks which message is visible.
- `Anky/Support/AnkyPresenceOverlay.swift` temporarily docks the existing Anky companion near the dialogue box.
- `Anky/Support/AnkyWitnessView.swift` owns the shared dialogue box, conversation navigation, and vector ornaments.

## SwiftUI concepts

`AppRoot` stores `showsLaunchDialogue` and `launchDialogueIndex` as local view state. The dialogue appears only when:

- the Write tab is selected
- the app is unlocked
- writing has not started
- today is not already sealed

The launch conversation has four messages. Tapping the dialogue advances, the top-left arrow goes back, the top-right cross closes it, and the small squares show progress.

When writing starts, `onChange(of: writeViewModel.hasStarted)` hides the launch dialogue so it does not compete with the ritual.

## Decoration model

The dialogue decorations are drawn with SwiftUI `Canvas` paths. This works like SVG-style vector drawing inside the app: the corner brackets, thread lines, and small diamonds scale with the dialogue box size instead of using fixed bitmap art.

## Try this yourself

Launch the app fresh. Before typing, confirm Anky moves to the lower-left speaker spot and says `write 8 minutes`. Tap the box to move through the four messages, then type one character and confirm the dialogue disappears.
