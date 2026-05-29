# Feature 05: Section Separators

## Problem
Between sections of the reflection, there are "—" (em-dash) separators that look weird and out of place.

## Root Cause
The LLM generates markdown with `---` horizontal rule separators between sections. The `SelectableReflectionText` markdown renderer (RevealView.swift:955-996) does NOT handle horizontal rules — they pass through as regular text lines, rendering as plain `---` or `—`.

## Solution

### Backend — Reduce Horizontal Rules (server.ts)

In `buildStorytellerPrompt()`, add instruction:
```
"Do not use horizontal rule separators (--- or ***). Separate sections with extra blank lines instead."
```

### iOS — Handle Remaining Rules (RevealView.swift)

In `attributedLine()` (line 955), add detection for horizontal rule lines before other checks:

```swift
// Detect horizontal rules: "---", "***", "___", or "—"
if trimmed == "---" || trimmed == "***" || trimmed == "___"
   || (trimmed.count <= 5 && trimmed.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" || $0 == "\u{2014}" }) {
    // Render as spacing instead of visible line
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 0
    paragraph.paragraphSpacingBefore = 12
    paragraph.paragraphSpacingAfter = 12
    return NSAttributedString(string: "", attributes: [.paragraphStyle: paragraph])
}
```

This converts horizontal rules into blank space (12pt padding before and after) instead of rendering visible dashes.

## Files to Modify
1. `backend/server.ts` — add instruction to buildStorytellerPrompt()
2. `apps/ios/Anky/Features/Reveal/RevealView.swift` — add HR detection in attributedLine()

## Testing
- Generate reflection with multiple sections
- Verify no visible "—" or "---" appears
- Verify sections are separated by clean spacing
