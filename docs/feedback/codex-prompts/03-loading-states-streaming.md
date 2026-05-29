
# Codex Prompt: Improve Reflection Loading States with Text Streaming

## Context
While the reflection is being generated, the user sees vague loading indicators. They want sharper, more precise status updates and ideally text streaming.

## Desired Behavior
1. **Status messages** that precisely describe what's happening:
   - "Reading your words..." (receiving input)
   - "Finding patterns in your writing..." (analyzing)
   - "Weaving your reflection..." (generating output)
   - "Almost there..." (finalizing)

2. **Text streaming** — tokens should appear progressively as the LLM generates them, not all at once at the end. This makes the wait feel shorter and more engaging.

## Tasks

1. **Backend streaming:**
   - If not already implemented, add SSE (Server-Sent Events) streaming from the Rust/Axum backend
   - Stream LLM tokens as they come from llama.cpp on port 8080
   - Each chunk should be a partial token, not waiting for full completion

2. **Frontend streaming display:**
   - Consume SSE stream and append tokens to the reflection text in real-time
   - Add subtle typewriter/streaming animation effect
   - Show cursor or indicator at the end of streaming text

3. **Status phase indicators:**
   - Before streaming starts: show phase-specific status text
   - During streaming: show "Weaving your reflection..." with progressive text
   - After streaming: smooth transition to complete reflection

4. **Error handling:**
   - If streaming fails, gracefully fall back to loading spinner with status text
   - Show retry option if connection drops

## Files to check
- Backend: reflection handler for streaming support
- Frontend: reflection display component
- LLM client: check if llama.cpp supports streaming responses

## Testing
- Trigger reflection generation, verify status messages appear in sequence
- Verify text appears progressively (streaming), not all at once
- Test network interruption and recovery
