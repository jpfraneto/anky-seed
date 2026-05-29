# Codex Prompt: Make Anky Messages Contextual

## Repo Context
Repo: ~/anky-seed
iOS: apps/ios/Anky/

## Current Behavior
When the user taps the Anky companion character during writing, they get a hardcoded message. The flow:

1. AppRoot.swift:261-268 — presenceTapHandler calls `writeViewModel.replayRecentPromptIfAvailable()`
2. AnkyCompanionPromptState (AnkyWitnessView.swift:96-143) has hardcoded messages by state:
   - .importedReady = "I found the rhythm inside this. Mirror it?"
   - .mirrorLoading = "stay close. i'm listening for the shape underneath."
   - .mirrorReady = "Something came back."
   - .notice = "I am here."
   - .error = "I could not find a .anky rhythm in that."

These messages are STATE-BASED, not CONTENT-BASED. The current writing session content is never passed to generate contextual responses.

## Desired Behavior
- Anky messages reference what the user is actually writing about
- Acknowledge themes, emotions, or patterns in the current session
- Feel like a narrator responding to the story, not a chatbot
- Match the user's language

## Tasks

### Option A: Lightweight (no LLM call, fast, always works)

1. **Add session-aware message generation to WriteViewModel:**
   - Analyze the current writing text for keywords/themes
   - Generate contextual messages based on detected content:
     - If writing contains words about fear/anxiety -> "I see you circling something that scares you. Keep writing."
     - If writing contains words about love/child/family -> "There's something tender here. Let it surface."
     - If writing is technical/work focused -> "Behind the code, there's a hunger. What is it?"
     - If writing is short/repetitive -> "You're holding back. The 8 minutes will take you further."
   - Use a simple keyword/phrase matching system (no LLM needed)
   - Cache the message so rapid taps don't regenerate

2. **Implement in replayRecentPromptIfAvailable():**
   - Read current draft text from ActiveDraftStore
   - Run through theme detection (simple word frequency + keyword lists)
   - Select appropriate message template
   - Fill in session-specific details (time written, word count)

3. **Add debouncing:**
   - Minimum 3 seconds between Anky messages
   - Cycle through 2-3 contextual messages per session (don't repeat)

### Option B: Full (LLM-powered, requires network)

1. **Add a lightweight "nudge" endpoint to backend:**
   - POST /anky/nudge with body: current writing text (first 500 chars)
   - Returns a 1-2 sentence contextual message
   - Use the same storyteller prompt but with system instruction: "Write one brief, evocative sentence that acknowledges what the writer is exploring. Be specific to their content. Match their language."
   - Keep response under 500ms

2. **Call from WriteViewModel with caching:**
   - Cache nudge response per session
   - Fall back to Option A messages if network unavailable

## Recommended: Start with Option A, add Option B later

## Files to Modify
- apps/ios/Anky/Features/Write/WriteViewModel.swift (add contextual message generation)
- apps/ios/Anky/Support/AnkyWitnessView.swift (update AnkyCompanionPromptState or replace with dynamic)
- apps/ios/Anky/AppRoot.swift (update presenceTapHandler if needed)
- NEW: apps/ios/Anky/Core/Mirror/AnkyNudgeGenerator.swift (theme detection + message templates)

## Message Templates (Option A)
Create a matrix of themes -> messages:

| Theme Keywords | Messages |
|---|---|
| fear, scared, anxious, worried | "I see you circling something that keeps you awake. Keep writing — the shape will reveal itself." |
| love, child, family, kid, baby | "There's something tender here. Let it surface without protecting it." |
| work, code, project, build | "Behind the work, there's a hunger. What is it really asking for?" |
| stuck, can't, don't know, lost | "The not-knowing is the doorway. Stay in it." |
| angry, frustrated, tired, exhausted | "The frustration is data. What is it pointing toward?" |
| dream, vision, idea, want | "That want — follow it. It knows where it's going." |
| default (no theme detected) | "I'm here. Keep going — the thread is forming." |

## Testing
- Write about different topics, tap Anky, verify messages reference the content
- Rapid tap, verify debouncing works
- No network, verify fallback messages work
- Write in Spanish, verify messages match language
