
================================================================================
ANKY FEEDBACK ANALYSIS — COMPLETE
Repo: ~/anky-seed | Hosted: Railway/Cloudflare
Generated: 2026-05-29
================================================================================

7 RAW FEEDBACK ITEMS:
1. The reflection from Anky takes forever
2. Don't move the companion each time a message comes. Fixed position: right side, 50% from top
3. When getting reflection, want sharper/more precise backend status wording. Text streaming???
4. Tags displayed ugly at bottom. Show at top, make clickable to navigate to same-tag sessions
5. Section separators "—" look weird, please fix
6. Wrote in English but reflection starts: "hola, gracias por ser quien eres. mis pensamientos:"
7. Messages from Anky when I press it are not contextual

================================================================================
CODE RECONNAISSANCE
================================================================================

REPO STRUCTURE:
  backend/server.ts           — Bun/TypeScript server (Railway), reflection pipeline
  apps/ios/Anky/              — SwiftUI iOS app
    Features/Reveal/          — Reflection view (RevealView.swift + RevealViewModel.swift)
    Features/Write/           — Writing view (WriteView.swift + WriteViewModel.swift)
    Features/Map/             — Session calendar/map
    Features/You/             — User profile/credits
    Support/                  — AnkyWitnessView, AnkyPresenceOverlay, AnkySpriteView
    Core/Mirror/              — MirrorClient (reflection API calls)
    Core/Storage/             — ReflectionStore, LocalAnkyArchive, SessionIndexStore

KEY FILES PER FEEDBACK ITEM:

Item 1 (Performance):
  - backend/server.ts:2180-2244  handleAnkyReflectionStream() — SSE streaming endpoint
  - backend/server.ts:2246+      handleAnkyReflection() — main handler, ~500 lines
  - apps/ios/Anky/Core/Mirror/MirrorClient.swift:10-59  askAnky() — HTTP POST, NOT streaming
  - apps/ios/Anky/Features/Reveal/RevealViewModel.swift:174-239  askAnky() — calls MirrorClient

Item 2 (Companion position):
  - apps/ios/Anky/Support/AnkyPresenceOverlay.swift — draggable companion, stored position
  - apps/ios/Anky/AppRoot.swift:69-76  AnkyPresenceOverlay usage
  - apps/ios/Anky/AppRoot.swift:261-268  presenceTapHandler (calls replayRecentPromptIfAvailable)

Item 3 (Loading states):
  - backend/server.ts:2188-2244  SSE stream with stage messages
  - apps/ios/Anky/Features/Reveal/RevealView.swift:482-500  MirrorProgressLine (3 rotating messages)
  - apps/ios/Anky/Core/Mirror/MirrorClient.swift — does NOT consume SSE stream

Item 4 (Tags):
  - backend/server.ts:2078  Prompt asks LLM: "If you include tags, write them as markdown text"
  - apps/ios/Anky/Features/Reveal/RevealView.swift:906-1107  SelectableReflectionText renders markdown
  - Tags are embedded in markdown reflection, not structured data
  - No tag-based navigation exists

Item 5 (Section separators):
  - backend/server.ts:2051-2086  buildStorytellerPrompt() — LLM generates markdown
  - apps/ios/Anky/Features/Reveal/RevealView.swift:938-996  Markdown renderer
  - "—" likely comes from LLM-generated markdown horizontal rules "---" rendered as "—"

Item 6 (Language mismatch):
  - backend/server.ts:2067  "Respond in the same language they wrote in."
  - backend/server.ts:2075-2076  "first paragraph must begin with the natural equivalent... of: hey, thanks for being who you are. my thoughts:"
  - LLM (anthropic/claude-sonnet-4.6 via OpenRouter) may default to Spanish
  - NO explicit language detection before LLM call

Item 7 (Non-contextual messages):
  - apps/ios/Anky/AppRoot.swift:261-268  presenceTapHandler -> writeViewModel.replayRecentPromptIfAvailable()
  - apps/ios/Anky/Support/AnkyWitnessView.swift:96-143  AnkyCompanionPromptState hardcoded messages
  - NO session content passed to Anky tap messages


================================================================================
SECTION 1: BUGS (3 items)
================================================================================

BUG-1: REFLECTION PERFORMANCE (HIGH)
  Feedback: "the reflection from anky takes forever"

  Root cause analysis:
  - MirrorClient.askAnky() (MirrorClient.swift:10-59) uses synchronous HTTP POST
    with Accept: text/markdown — waits for FULL response before returning
  - Backend supports SSE streaming (handleAnkyReflectionStream) but iOS client
    does NOT use the streaming endpoint — it uses the blocking /anky POST
  - Backend model: anthropic/claude-sonnet-4.6 via OpenRouter (server.ts:186)
  - Backend timeout: 45 seconds (server.ts:187)
  - iOS shows 3 rotating messages during wait (MirrorProgressLine) — no progress granularity

  Fix: Either (a) make iOS use the SSE streaming endpoint, or (b) add progress
  granular stages to the blocking call, or (c) both.

BUG-6: LANGUAGE MISMATCH (HIGH)
  Feedback: "I wrote in english but reflection starts: hola, gracias por ser quien eres"

  Root cause analysis:
  - buildStorytellerPrompt() (server.ts:2051) says "Respond in the same language they wrote in" (line 2067)
  - But there is NO language detection before the LLM call
  - The LLM (Claude Sonnet 4.6) is expected to autodetect, but may be failing
  - The prompt template line 2075-2076: "first paragraph must begin with the natural equivalent... of: hey, thanks for being who you are. my thoughts:" — this phrasing may confuse the LLM into Spanish
  - Server is hosted on Railway, may have locale defaults influencing LLM behavior

  Fix: Add explicit language detection (e.g., compactml or frlang) before building
  the prompt, then inject "Respond in ENGLISH" as explicit instruction.

BUG-7: NON-CONTEXTUAL ANKY MESSAGES (MEDIUM)
  Feedback: "Messages from Anky when I press it are not contextual"

  Root cause analysis:
  - AppRoot.swift:261-268: presenceTapHandler calls writeViewModel.replayRecentPromptIfAvailable()
  - AnkyCompanionPromptState (AnkyWitnessView.swift:96-143) has hardcoded messages:
    .importedReady = "I found the rhythm inside this. Mirror it?"
    .mirrorLoading = "stay close. i'm listening for the shape underneath."
    .mirrorReady = "Something came back."
    .notice = "I am here."
    .error = "I could not find a .anky rhythm in that."
  - These are STATE-BASED, not CONTENT-BASED. No session writing content is
    passed to generate contextual responses.

  Fix: Pass current session writing text to the LLM when generating Anky tap
  messages, or at minimum make messages reference session-specific data
  (word count, time written, detected themes).


================================================================================
SECTION 2: UX IMPROVEMENTS (4 items)
================================================================================

UX-2: COMPANION POSITIONING (MEDIUM)
  Current: AnkyPresenceOverlay is draggable, stored position in UserDefaults
  (ankyPresenceX, ankyPresenceY). It moves when dockedToDialogue changes
  (AnkyPresenceOverlay.swift:69 animation on dockedToDialogue).

  Desired: Static position, right side, 50% from top. No animation on message.

  Fix locations:
  - AnkyPresenceOverlay.swift:177-189 resolvedPoint() — simplify to fixed position
  - AnkyPresenceOverlay.swift:198-203 defaultPoint() — change to right/50%
  - Remove dockedToDialogue parameter and related animation (line 69)
  - Remove drag gesture or make it no-op

UX-3: LOADING STATE MESSAGING (MEDIUM)
  Current: MirrorProgressLine cycles 3 vague messages every 2.1 seconds:
    "carrying your writing to the mirror..."
    "listening for the shape underneath..."
    "bringing the reflection back..."

  Desired: Precise backend stage messaging + text streaming of reflection tokens.

  Fix locations:
  - MirrorClient.swift:10-59 — rewrite to use SSE streaming endpoint
  - RevealViewModel.swift:174-239 — handle streaming updates
  - RevealView.swift:482-500 — replace MirrorProgressLine with stage-aware display
  - Backend already sends stage events (server.ts stages: stream_open,
    request_received, dot_anky_read, hash_computed, identity_verified,
    protocol_validated, duplicate_lock_acquired, credit_checked,
    reflection_prepared, provider_started, provider_finished, etc.)

UX-4: TAGS REDESIGN (MEDIUM)
  Current: Tags embedded in markdown reflection text, rendered inline by
  SelectableReflectionText markdown parser. No structured data, no navigation.

  Desired: Tags at TOP of reflection, clickable, navigate to same-tag sessions.

  Fix locations:
  - backend/server.ts:2078 — modify LLM prompt to output tags as structured
    data (e.g., YAML front matter or JSON block at top of markdown)
  - apps/ios/Anky/Features/Reveal/RevealView.swift:581-613 ReflectionScrollPage
    — parse tags from reflection, display as clickable pills at top
  - apps/ios/Anky/Core/Storage/ReflectionStore.swift — store extracted tags
  - apps/ios/Anky/Core/Storage/SessionIndexStore.swift — index by tags
  - New view: TagSessionsListView for filtered session browsing

UX-5: SECTION SEPARATORS (LOW)
  Current: LLM generates markdown with "---" horizontal rules, rendered as "—"
  in SelectableReflectionText.

  Desired: Subtle styled divider or just spacing.

  Fix locations:
  - backend/server.ts:2078 — update LLM prompt to use "---" sparingly or not at all
  - apps/ios/Anky/Features/Reveal/RevealView.swift:938-996 — detect "---" lines
    and render as subtle styled divider instead of em-dash


================================================================================
SECTION 3: SOUL.md MISMATCHES (5 items)
================================================================================

MISMATCH-1: "REFLECTION" vs STORYTELLING
  SOUL.md: "Anky is a storytelling engine for exhausted parents."
  The UI labels output as "reflection" throughout. SOUL.md says the story IS
  the product, not a reflection. The entire value prop is parent writes -> kid gets story.
  Current framing is clinical/analytical.

MISMATCH-2: "TAGS" vs KINGDOMS
  SOUL.md organizes emotional territory into 8 kingdoms (Primordia=fear,
  Emblazion=passion, etc.). Generic "tags" feel like a productivity app.
  Should be kingdom/emotional territory labels.

MISMATCH-3: "COMPANION" vs NARRATOR
  SOUL.md: "I am not a chatbot. I am Anky — the narrator."
  The UI treats Anky as a draggable chat companion. SOUL.md identity is
  omniscient story narrator, blue-skinned with purple hair and golden eyes.

MISMATCH-4: LANGUAGE INCONSISTENCY
  SOUL.md voice is English-first, direct, practical. Spanish "hola" greeting
  from LLM is a basic execution failure.

MISMATCH-5: CONTEXT AWARENESS
  SOUL.md: "Characters repeat across sessions," "The 8 kingdoms accumulate
  canonical events." Hardcoded companion messages break continuity identity.


================================================================================
SECTION 4: CODEX IMPLEMENTATION PROMPTS
================================================================================

See /tmp/analysis/codex_prompts/ for 6 detailed prompts.
Below are the corrected versions with accurate file references.
