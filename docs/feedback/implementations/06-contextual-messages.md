# Feature 06: Contextual Anky Messages

## Problem
When the user taps the Anky companion, they get generic hardcoded messages that have nothing to do with what they're writing about. The messages feel disconnected.

## Root Cause
`AnkyCompanionPromptState` (AnkyWitnessView.swift:96-143) has 5 hardcoded messages based on UI state:
- `.importedReady` = "I found the rhythm inside this. Mirror it?"
- `.mirrorLoading` = "stay close. i'm listening for the shape underneath."
- `.mirrorReady` = "Something came back."
- `.notice` = "I am here."
- `.error` = "I could not find a .anky rhythm in that."

The current writing session content is NEVER analyzed to generate contextual responses.

## Solution: Lightweight Theme Detection (No LLM Needed)

### AnkyNudgeGenerator.swift (new file)

A simple theme detection + message generation system that works offline:

```swift
struct AnkyNudgeGenerator {
    static func generateNudge(from writing: String, timeWritten: TimeInterval, wordCount: Int) -> String {
        let theme = detectTheme(in: writing)
        let messages = themeMessages[theme] ?? defaultMessages
        // Use hash of writing prefix for stable message selection
        let index = stableIndex(from: writing, count: messages.count)
        return messages[index]
    }
    
    private func detectTheme(in text: String) -> String {
        let lower = text.lowercased()
        
        // Theme detection via keyword matching
        if matches(["fear", "scared", "anxious", "worried", "terrified", "panic", "afraid"], in: lower) {
            return "fear"
        }
        if matches(["love", "child", "family", "kid", "baby", "daughter", "son", "partner"], in: lower) {
            return "love"
        }
        if matches(["work", "code", "project", "build", "startup", "company", "product"], in: lower) {
            return "work"
        }
        if matches(["stuck", "can't", "don't know", "lost", "confused", "blocked"], in: lower) {
            return "stuck"
        }
        if matches(["angry", "frustrated", "tired", "exhausted", "drained", "burnt"], in: lower) {
            return "exhaustion"
        }
        if matches(["dream", "vision", "idea", "want", "hope", "wish", "imagine"], in: lower) {
            return "aspiration"
        }
        
        // Time-based fallbacks
        if timeWritten < 240 { // < 4 minutes
            return "early"
        }
        if wordCount < 50 {
            return "brief"
        }
        
        return "default"
    }
}
```

### Message Templates by Theme

```swift
private let themeMessages: [String: [String]] = [
    "fear": [
        "I see you circling something that keeps you awake at night. Keep writing — the shape will reveal itself.",
        "There's a fear here you've been carrying. You don't have to name it. Just let it breathe on the page.",
        "The thing you're afraid of is already in these words. I can see it. You just haven't looked yet.",
    ],
    "love": [
        "Something tender is surfacing here. Don't protect it — let it be messy.",
        "There's love in these words that doesn't know what to do with itself. That's okay.",
        "The way you write about this tells me everything. Keep going.",
    ],
    "work": [
        "Behind the work, there's a hunger. What is it really asking for?",
        "You're building something, but I'm hearing the person behind the builder.",
        "The code/product/project is a container. What's trying to break through it?",
    ],
    "stuck": [
        "The not-knowing is the doorway. Stay in it.",
        "You don't need to know where this is going. You just need to keep walking.",
        "Being stuck IS the writing. This IS the session.",
    ],
    "exhaustion": [
        "The exhaustion is data. What is it pointing toward?",
        "You're tired. That's valid. The 8 minutes will hold you.",
        "I hear the weight in these words. Let them carry it for a moment.",
    ],
    "aspiration": [
        "That want — follow it. It knows where it's going.",
        "There's a future self in these words. They're trying to reach you.",
        "The dream you're circling — it's already closer than you think.",
    ],
    "early": [
        "You're just getting started. The thread is forming.",
        "Give it a few more minutes. The real stuff is still coming.",
        "I'm here. The first words are always the hardest.",
    ],
    "brief": [
        "Every word counts. Keep them coming.",
        "The silence between words is part of the writing too.",
        "You don't need to fill the space. Just be honest in it.",
    ],
]

private let defaultMessages: [String] = [
    "I'm here. Keep going — the thread is forming.",
    "Something is trying to surface. Don't rush it.",
    "Every word you write changes what comes next.",
    "You're doing the work. I'm witnessing it.",
    "The writing knows where it's going. Trust it.",
]
```

### Integration

#### WriteViewModel Changes
- Add `replayRecentPromptIfAvailable()` to use `AnkyNudgeGenerator`
- Pass current draft text, time written, word count
- Cache the generated message per session (don't regenerate on rapid taps)
- Add debouncing: minimum 3 seconds between messages
- Cycle through messages per session (don't repeat same message)

#### AppRoot.swift Changes
- Update `presenceTapHandler` to call the new contextual message system

## Files to Modify
1. NEW: `apps/ios/Anky/Core/Mirror/AnkyNudgeGenerator.swift` — theme detection + messages
2. `apps/ios/Anky/Features/Write/WriteViewModel.swift` — integrate nudge system
3. `apps/ios/Anky/AppRoot.swift` — update presenceTapHandler

## Testing
- Write about different topics, tap Anky, verify messages reference the content
- Rapid tap, verify debouncing works (no spam)
- No network needed — all offline
- Write in Spanish, verify messages are in Spanish (add Spanish message set)
