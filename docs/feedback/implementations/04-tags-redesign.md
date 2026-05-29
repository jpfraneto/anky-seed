# Feature 04: Tags Redesign

## Problem
Tags are displayed "ugly" at the bottom of the reflection, embedded as inline markdown text. They should be at the TOP as styled clickable pills that navigate to sessions with the same tag.

## Root Cause
The LLM prompt (server.ts:2078) says: "If you include tags, write them as markdown text." Tags are rendered as regular text by the markdown parser in `SelectableReflectionText`. No structured data, no navigation capability.

## Solution

### Backend — Structured Tag Output (server.ts)

Modify `buildStorytellerPrompt()` to instruct the LLM to output tags as a JSON block at the top:

```
Before the markdown document, output exactly one line of JSON:
{"tags": ["theme1", "theme2", "theme3"]}

Rules for tags:
- 3 to 5 tags maximum
- Each tag is 1-3 words describing an emotional theme or topic
- Use lowercase, no special characters
- Examples: "fear of letting go", "work identity", "parenting guilt", "creative block"
```

Then modify `parseMirrorResponse()` to extract the JSON tags line:

```typescript
export function parseMirrorResponse(raw: string): MirrorResponse {
  const lines = raw.trim().split('\n');
  let tags: string[] = [];
  let markdownStart = 0;
  
  // Check first line for JSON tags
  const firstLine = lines[0]?.trim();
  if (firstLine.startsWith('{') && firstLine.includes('"tags"')) {
    try {
      const parsed = JSON.parse(firstLine);
      tags = parsed.tags || [];
    } catch {}
    markdownStart = 1;
  }
  
  const reflection = lines.slice(markdownStart).join('\n').trim();
  // ... rest of function ...
  
  return { title, reflection, tags };
}
```

Update the SSE `reflection` event to include tags.

### iOS — Data Model

#### LocalReflection (ReflectionStore.swift)
Add `tags: [String]` field to the struct.

#### MirrorResponsePayload (MirrorClient.swift)
Add `tags: [String]` field.

### iOS — UI

#### ReflectionScrollPage (RevealView.swift:581-613)
Add tag pills at the top of the scroll view, above the reflection text:

```swift
// Inside ScrollView, before SelectableReflectionText:
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 8) {
        ForEach(reflection.tags, id: \.self) { tag in
            NavigationLink(destination: TagSessionsListView(tag: tag)) {
                Text(tag)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(RevealPalette.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.2), in: Capsule())
                    .overlay(Capsule().stroke(RevealPalette.gold.opacity(0.3), lineWidth: 1))
            }
        }
    }
    .padding(.horizontal, 22)
    .padding(.top, 8)
}
```

#### TagSessionsListView (new file)
A list view that shows all sessions matching a tag:
- Fetch from SessionIndexStore
- Display: date, session title, word count
- Tapping navigates to RevealView for that session
- Back button to return

#### SessionIndexStore
Add tag indexing: `sessionsWithTag(_ tag: String) -> [SavedAnky]`

### iOS — ViewModel

Update `RevealViewModel.askAnky()` to extract and save tags from the response.

## Files to Modify
1. `backend/server.ts` — modify prompt + parseMirrorResponse + SSE event
2. `apps/ios/Anky/Core/Storage/ReflectionStore.swift` — add tags field
3. `apps/ios/Anky/Core/Storage/SessionIndexStore.swift` — add tag indexing
4. `apps/ios/Anky/Core/Mirror/MirrorClient.swift` — add tags to payload
5. `apps/ios/Anky/Features/Reveal/RevealViewModel.swift` — save tags
6. `apps/ios/Anky/Features/Reveal/RevealView.swift` — tag pills in ReflectionScrollPage
7. NEW: `apps/ios/Anky/Features/Reveal/TagSessionsListView.swift`

## Testing
- Generate reflection, verify tags appear as pills at top
- Tap a tag, verify navigation to filtered session list
- Verify sessions shown actually have that tag
- Test with reflection that has no tags (show nothing, no crash)
