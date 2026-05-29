# Codex Prompt: Fix Section Separators

## Repo Context
Repo: ~/anky-seed
Backend: backend/server.ts
iOS: apps/ios/Anky/Features/Reveal/RevealView.swift

## Current Behavior
The LLM generates markdown with "---" horizontal rule separators between sections. The SelectableReflectionText markdown renderer (RevealView.swift:938-996) renders these. The "---" lines appear as em-dash "—" separators which look out of place.

Looking at the markdown renderer (attributedLine at line 955-996), there is NO explicit handling of "---" horizontal rules. They likely pass through as regular text lines, rendering as plain "—" or "---".

## Tasks

1. **Backend — reduce horizontal rules in LLM output:**
   - In buildStorytellerPrompt() (server.ts:2078), add: "Do not use horizontal rule separators (---). Use extra paragraph spacing between sections instead."

2. **iOS — handle remaining horizontal rules gracefully:**
   - In SelectableReflectionText.attributedLine() (RevealView.swift:955-996), add detection for "---" or "—" lines:
   ```swift
   // Before heading check, add:
   if trimmed == "---" || trimmed == "---" || trimmed.allSatisfy({ $0 == "-" || $0 == "\u{2014}" }) {
       let paragraph = NSMutableParagraphStyle()
       paragraph.lineSpacing = 0
       paragraph.paragraphSpacingBefore = 16  // spacing before divider
       paragraph.paragraphSpacingAfter = 16    // spacing after divider
       let divider = NSAttributedString(
           string: "",
           attributes: [.paragraphStyle: paragraph]
       )
       return divider
   }
   ```
   - This renders horizontal rules as blank space (spacing) instead of visible dashes
   - Or render as a subtle colored line if preferred

## Files to Modify
- backend/server.ts (buildStorytellerPrompt — add instruction)
- apps/ios/Anky/Features/Reveal/RevealView.swift (attributedLine — add HR handling)

## Testing
- Generate reflection with multiple sections
- Verify no visible "—" or "---" appears
- Verify sections are separated by clean spacing
