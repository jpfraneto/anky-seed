# Codex Prompt: Fix Reflection Performance & Language

## Repo Context
Repo: ~/anky-seed (jpfraneto/anky-seed on GitHub, hosted on Railway/Cloudflare)
Backend: Bun/TypeScript (backend/server.ts)
iOS App: SwiftUI (apps/ios/Anky/)

## Bug 1: Reflection Takes Forever

### Root Cause
The iOS MirrorClient uses a BLOCKING HTTP POST to POST /anky (MirrorClient.swift:10-59) with `Accept: text/markdown`. It waits for the FULL response before returning. The backend already supports SSE streaming at the same endpoint when `Accept: text/event-stream` is sent (server.ts:277 checks for this header, then calls handleAnkyReflectionStream at line 2180).

The iOS app does NOT use the streaming endpoint. During the wait, it shows 3 rotating vague messages in MirrorProgressLine (RevealView.swift:482-500).

### Tasks

1. **Rewrite MirrorClient.askAnky() to use SSE streaming:**
   - Change Accept header from `text/markdown` to `text/event-stream`
   - Use URLSession.asyncBytes(for:) to read the SSE stream line by line
   - Parse SSE events: `event: update` (progress stages) and `event: reflection` (final markdown)
   - Add a callback/closure parameter for progress updates: `(String) -> Void`
   - The backend sends stages: stream_open, request_received, dot_anky_read, hash_computed, identity_verified, protocol_validated, duplicate_lock_acquired, credit_checked, reflection_prepared, provider_started, provider_finished, credit_spent

2. **Update RevealViewModel.askAnky() to handle streaming:**
   - Add @Published var progressMessage: String? to RevealViewModel
   - Pass progress callback to MirrorClient
   - Update UI progressively as stages arrive

3. **Replace MirrorProgressLine with stage-aware display:**
   - Map backend stages to user-friendly messages:
     - "stream_open" -> "opening the mirror..."
     - "identity_verified" -> "verifying your seal..."
     - "protocol_validated" -> "reading your .anky..."
     - "reflection_prepared" -> "preparing the reflection..."
     - "provider_started" -> "anky is writing..."
     - "provider_finished" -> "bringing it back..."
   - Show these as progressive text that updates, not cycling messages

## Bug 2: Language Mismatch ("hola" instead of English)

### Root Cause
buildStorytellerPrompt() (server.ts:2051-2086) says "Respond in the same language they wrote in" (line 2067) but there is NO language detection before the LLM call. The LLM (anthropic/claude-sonnet-4.6 via OpenRouter) is expected to autodetect but fails.

### Tasks

1. **Add language detection to buildStorytellerPrompt():**
   - Use a simple heuristic: count non-ASCII characters, check for common language markers
   - Or use `@cf工作者` language detection if available on Railway edge
   - Or use a compact library like `frlang` or `compact-lang-det` for Node/Bun
   - Detect: English, Spanish, Portuguese, French, German, Japanese as minimum

2. **Inject detected language explicitly into the prompt:**
   - After detecting language, add to prompt: "The user wrote in {DETECTED_LANGUAGE}. Respond in {DETECTED_LANGUAGE}."
   - Make this explicit and prominent in the system prompt

3. **Fix the greeting template (server.ts:2075-2076):**
   - Current: "After the H1, the first paragraph must begin with the natural equivalent, in the same language the user wrote in, of: hey, thanks for being who you are. my thoughts:"
   - This is ambiguous. Change to: "After the H1, begin with: 'hey, thanks for being who you are. my thoughts:' — keep this exact phrasing in {DETECTED_LANGUAGE}."

## Files to Modify
- apps/ios/Anky/Core/Mirror/MirrorClient.swift (rewrite askAnky for SSE)
- apps/ios/Anky/Features/Reveal/RevealViewModel.swift (add progress handling)
- apps/ios/Anky/Features/Reveal/RevealView.swift (replace MirrorProgressLine)
- backend/server.ts (add language detection to buildStorytellerPrompt)

## Testing
- Write session, tap "get reflection", verify progressive stage messages appear
- Measure total time, verify streaming reduces perceived wait
- Write in English, verify reflection is in English
- Write in Spanish, verify reflection is in Spanish
