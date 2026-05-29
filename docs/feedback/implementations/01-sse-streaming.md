# Feature 01: SSE Streaming Reflections

## Problem
Reflection generation "takes forever" because the iOS app uses a blocking HTTP POST to `POST /anky` with `Accept: text/markdown`. The backend waits for the full LLM response before returning anything to the client. During this wait (up to 45s), the user sees 3 vague rotating messages.

## Root Cause
- **iOS side:** `MirrorClient.askAnky()` sends `Accept: text/markdown` — blocking request
- **Backend side:** SSE streaming endpoint already exists (`handleAnkyReflectionStream`) but iOS doesn't use it
- **Backend sends granular stages:** stream_open, request_received, dot_anky_read, hash_computed, identity_verified, protocol_validated, credit_checked, reflection_prepared, provider_started, provider_finished, credit_spent

## Architecture

### Backend (server.ts)
The SSE endpoint at `handleAnkyReflectionStream()` (line 2180) is production-ready. It:
1. Opens a `ReadableStream<Uint8Array>` 
2. Sends stage events via `send("update", {stage, message})`
3. Calls `handleAnkyReflection()` with a progress callback
4. Sends the final reflection via `send("reflection", {markdown, headers})`
5. Closes the stream

**No backend changes needed for this feature.** The streaming endpoint works.

### iOS Side (requires changes)

#### MirrorClient.swift — Rewrite askAnky() for SSE
Current: blocking `URLSession.data(for:)` call
New: streaming `URLSession.bytes(for:)` with SSE parsing

```
Current flow:
  MirrorClient.askAnky() -> HTTP POST -> wait ~30s -> full response

New flow:
  MirrorClient.askAnky(streaming:) -> HTTP POST with Accept: text/event-stream
    -> receives stage events progressively
    -> receives final reflection markdown
    -> returns MirrorResponsePayload
```

Key changes:
- Change Accept header to `text/event-stream`
- Use `URLSession.bytes(for:)` async sequence to read stream line by line
- Parse SSE format: `event: <name>\ndata: <json>\n\n`
- Call progress callback on each "update" event
- Return payload on "reflection" event
- Handle "error" event

#### RevealViewModel.swift — Add progress state
- Add `@Published var progressStage: String?` 
- Pass progress callback to MirrorClient
- Update UI as stages arrive

#### RevealView.swift — Replace MirrorProgressLine
Current: 3 vague rotating messages every 2.1s
New: Display actual backend stage messages

Stage → User-facing message mapping:
```
stream_open         -> "opening the mirror..."
request_received    -> "received your writing..."
dot_anky_read       -> "reading your .anky..."
hash_computed       -> "verifying the seal..."
identity_verified   -> "confirming your identity..."
protocol_validated  -> "validating the ritual..."
credit_checked      -> "checking reflection access..."
reflection_prepared -> "preparing the reflection..."
provider_started    -> "anky is writing..."
provider_finished   -> "bringing it back..."
credit_spent        -> "settling..."
```

## Files to Modify
1. `apps/ios/Anky/Core/Mirror/MirrorClient.swift` — add `askAnkyStreaming()` method
2. `apps/ios/Anky/Features/Reveal/RevealViewModel.swift` — add progress state, use streaming
3. `apps/ios/Anky/Features/Reveal/RevealView.swift` — replace MirrorProgressLine with stage display

## Testing
- Write session, tap "get reflection", verify stage messages appear progressively
- Verify final reflection arrives and displays correctly
- Test error case: server returns error event, app shows error message
- Measure perceived wait time improvement
