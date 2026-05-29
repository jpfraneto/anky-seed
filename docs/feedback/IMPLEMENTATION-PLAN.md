# Master Implementation Plan — Anky Feedback Fixes

## Overview
This document is the implementation guide for fixing 7 user feedback items from anky.app. Each feature has its own detailed spec in `implementations/`. This master plan defines the execution order, dependencies, and integration points.

## Execution Order

### Phase 1: Backend (server.ts) — Do First
These changes affect the API and must be deployed before iOS changes work.

1. **Feature 02: Language Detection** (`implementations/02-language-detection.md`)
   - Add `detectLanguage()` function to server.ts
   - Modify `buildStorytellerPrompt()` to inject explicit language
   - Fix greeting template ambiguity
   - **Impact:** Fixes the "hola" bug immediately

2. **Feature 05: Section Separators** (`implementations/05-section-separators.md`)
   - Add instruction to `buildStorytellerPrompt()` to avoid horizontal rules
   - **Impact:** Quick fix, no iOS changes needed for backend part

3. **Feature 04: Tags (Backend)** (`implementations/04-tags-redesign.md`)
   - Modify LLM prompt to output JSON tags block
   - Modify `parseMirrorResponse()` to extract tags
   - Update SSE reflection event to include tags
   - **Impact:** Enables structured tag data for iOS

### Phase 2: iOS Core — Streaming Foundation
This is the biggest change and unlocks the best UX improvement.

4. **Feature 01: SSE Streaming** (`implementations/01-sse-streaming.md`)
   - Rewrite `MirrorClient.askAnky()` to use SSE streaming
   - Add progress state to `RevealViewModel`
   - Replace `MirrorProgressLine` with stage-aware display
   - **Impact:** Fixes "takes forever" + enables real-time progress

### Phase 3: iOS UI Polish
These are independent visual changes that can be done in parallel.

5. **Feature 03: Companion Positioning** (`implementations/03-companion-positioning.md`)
   - Remove docking behavior from `AnkyPresenceOverlay`
   - Fix position to right side, 50% height
   - **Impact:** Simple visual fix, low risk

6. **Feature 04: Tags (iOS)** (`implementations/04-tags-redesign.md`)
   - Add tags field to data models
   - Build tag pills UI in `ReflectionScrollPage`
   - Create `TagSessionsListView` for navigation
   - Add tag indexing to `SessionIndexStore`
   - **Impact:** Requires Phase 1 backend tags to be deployed

7. **Feature 06: Contextual Messages** (`implementations/06-contextual-messages.md`)
   - Create `AnkyNudgeGenerator` with theme detection
   - Integrate into `WriteViewModel`
   - Update `presenceTapHandler` in `AppRoot`
   - **Impact:** Completely offline, no backend dependency

## File Change Summary

### backend/server.ts
- Add `detectLanguage()` function
- Modify `buildStorytellerPrompt()` (language injection + separator instruction + tags instruction)
- Modify `parseMirrorResponse()` (extract JSON tags)
- Update SSE reflection event (include tags)

### apps/ios/Anky/Core/Mirror/MirrorClient.swift
- Rewrite `askAnky()` to support SSE streaming with `URLSession.bytes(for:)`
- Add `tags` to `MirrorResponsePayload`

### apps/ios/Anky/Core/Storage/ReflectionStore.swift
- Add `tags: [String]` to `LocalReflection`

### apps/ios/Anky/Core/Storage/SessionIndexStore.swift
- Add tag indexing methods

### apps/ios/Anky/Features/Reveal/RevealViewModel.swift
- Add `@Published var progressStage: String?`
- Use streaming `askAnky()` method
- Save tags from response

### apps/ios/Anky/Features/Reveal/RevealView.swift
- Replace `MirrorProgressLine` with stage-aware display
- Add tag pills to `ReflectionScrollPage`
- Handle horizontal rules in `attributedLine()`

### apps/ios/Anky/Features/Write/WriteViewModel.swift
- Integrate `AnkyNudgeGenerator` for contextual messages

### apps/ios/Anky/Support/AnkyPresenceOverlay.swift
- Remove `dockedToDialogue` parameter and logic
- Fix `defaultPoint()` to right/50%
- Remove dialogue animation

### apps/ios/Anky/AppRoot.swift
- Remove `dockedToDialogue` from `AnkyPresenceOverlay` init
- Update `presenceTapHandler` for contextual messages

### NEW FILES
- `apps/ios/Anky/Core/Mirror/AnkyNudgeGenerator.swift`
- `apps/ios/Anky/Features/Reveal/TagSessionsListView.swift`

## Dependencies Graph

```
Phase 1 (Backend)
  02-language ─────────────────────────┐
  05-separators (backend part) ────────┤
  04-tags (backend part) ──────────────┘
                                        │
Phase 2 (iOS Core)                      │
  01-streaming ─────────────────────────┼── All Phase 3 depend on backend
                                        │
Phase 3 (iOS UI)                        │
  03-companion  ← independent           │
  04-tags (iOS) ← needs Phase 1 tags    │
  06-messages   ← independent           │
```

## Testing Strategy

After all changes:
1. Write a session in English → verify English reflection with progressive loading
2. Write a session in Spanish → verify Spanish reflection
3. Tap Anky during writing → verify contextual message
4. Open reflection → verify tags at top, no em-dash separators
5. Tap a tag → verify navigation to filtered sessions
6. Verify Anky companion stays fixed on right side
