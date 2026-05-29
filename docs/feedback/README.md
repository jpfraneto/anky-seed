# Feedback Analysis & Codex Prompts

Generated: 2026-05-29 from user feedback session on anky.app

## Quick Links

| # | Prompt | Status |
|---|--------|--------|
| 1 | [Performance & Language](codex-prompts/01-performance-and-language.md) | 🔴 BUG (HIGH) |
| 2 | [Companion Positioning](codex-prompts/02-companion-positioning.md) | 🟡 UX (MEDIUM) |
| 3 | [Loading States & Streaming](codex-prompts/03-loading-states-streaming.md) | 🟡 UX (MEDIUM) |
| 4 | [Tags Redesign](codex-prompts/04-tags-redesign.md) | 🟡 UX (MEDIUM) |
| 5 | [Section Separators](codex-prompts/05-section-separators.md) | 🟢 Visual (LOW) |
| 6 | [Contextual Anky Messages](codex-prompts/06-contextual-anky-messages.md) | 🟡 BUG (MEDIUM) |

## Raw Feedback (7 items)

1. The reflection from Anky takes forever
2. Don't move the companion each time a message comes. Fixed: right side, 50% from top
3. When getting reflection, want sharper/more precise backend status. Text streaming???
4. Tags displayed ugly at bottom. Show at top, make clickable for same-tag sessions
5. Section separators "—" look weird, fix
6. Wrote in English but reflection starts: "hola, gracias por ser quien eres. mis pensamientos:"
7. Messages from Anky when I press it are not contextual

## How to Use These Prompts

Each prompt in `codex-prompts/` is self-contained and ready to feed into Codex or any coding agent:

```bash
# Run Codex on a specific fix
cd /path/to/anky-seed
codex --yolo "$(cat docs/feedback/codex-prompts/01-performance-and-language.md)"
```

## Recommended Implementation Order

1. **#1 Performance & Language** — fixes the biggest user pain (slow reflection) AND the language bug. Unlocks SSE streaming which powers #3.
2. **#3 Loading States** — builds on #1's streaming to show precise progress
3. **#5 Section Separators** — quick visual polish, low risk
4. **#2 Companion Positioning** — simple SwiftUI change
5. **#6 Contextual Messages** — adds theme detection system
6. **#4 Tags Redesign** — requires backend + frontend coordination, do last

## SOUL.md Mismatches (Strategic)

These aren't bugs but identity misalignments between how the app works and what Anky is supposed to be:

- **"Reflection" vs Storytelling** — SOUL.md says Anky generates STORIES, not reflections
- **"Tags" vs Kingdoms** — SOUL.md uses 8 emotional kingdoms, not generic tags
- **"Companion" vs Narrator** — SOUL.md says Anky is the omniscient narrator, not a chat companion
- **Language inconsistency** — English-first identity but LLM defaults to Spanish
- **No context awareness** — SOUL.md says sessions accumulate lore, but messages are hardcoded

See [ANALYSIS.md](ANALYSIS.md) for full details.
