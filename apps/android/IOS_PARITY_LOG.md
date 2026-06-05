# iOS Delta Parity Log

## 2026-06-03 Inline Reveal / Write Input Parity Pass

Baseline:

- Source of truth: current dirty iOS worktree in `apps/ios/Anky`.
- Android target: remove the Android-only Reveal bottom conversation/sheet as the primary reflection flow, tighten Write input mutation handling, preserve mirror/storage/identity contracts, and keep Android trial proof disabled.

Migrated Android changes:

- Reveal now renders saved reflections, streaming reflection text, and mirror errors inline below the reconstructed writing and privacy divider.
- Reveal now uses an iOS-style bottom gold action with `LOADING`, `READ REFLECTION`, `REFLECT THIS ANKY`, and `WRITE 8 MINUTES` states.
- Reveal copy is section-aware: `copy writing` copies reconstructed writing, `copy reflection` copies reflection title plus body, and copied feedback is tracked separately.
- Reveal delete confirmation now matches the iOS tone exactly: `Delete forever?`, `Delete`, `Cancel`, and `This permanently deletes this writing session. This cannot be undone.`
- Saved reflections render returned `creditsRemaining` as a truthful local remaining-reflections line when present.
- `RevealViewModel` invalidates the narrow Android `CreditsClient` credit cache only when a mirror response includes non-null `creditsRemaining`.
- Hidden Write input now rejects multi-glyph mutations at the input layer. Explicit `.anky` import remains available through the paste/import affordance, but pasted/autocorrected writing text is not accepted into the live ritual.

Preserved Android behavior:

- `.anky` remains the canonical local artifact and mirror request body.
- Ask Anky still sends exact UTF-8 `.anky` bytes as `text/plain; charset=utf-8`.
- Base EOA / EIP-712 identity signing and `X-Anky-App-Version` behavior are unchanged.
- Android still does not send `X-Anky-Trial-Proof`.
- Local archive, reflection sidecar, pending request, session index, Map refresh, You identity, RevenueCat public-key-only client setup, reminders, and export/import systems remain native Android.

Validation run:

- `./gradlew :app:compileDebugKotlin` passed.
- Focused `./gradlew :app:testDebugUnitTest --tests inc.anky.android.feature.reveal.RevealViewModelTest --tests inc.anky.android.mirror.MirrorClientTest --tests inc.anky.android.write.WriteViewModelTest --tests inc.anky.android.privacy.SourceInvariantTest` passed.
- Full `./gradlew testDebugUnitTest` passed.
- `./gradlew assembleDebug` passed.
- `adb devices` could not be run because `adb` is not available on this PATH, so `connectedDebugAndroidTest` was not run.
- Safety search confirmed Android source still does not send `X-Anky-Trial-Proof`; direct logging remains isolated to `SafeLog`; no server secrets or fake trial-credit grants were added.

Intentional divergence:

- Android device-bound trial proof remains out of scope until Play Integrity/device recall is designed and verified server-side.

## 2026-06-01 Reflection Flow Parity Pass

Baseline:

- Source of truth: current dirty iOS worktree in `apps/ios/Anky`.
- Android target: align the current write-to-reflection flow, local archive shape, streaming mirror behavior, reflection tags, tag navigation, and pending reflection request handling.

Migrated Android changes:

- Local `.anky` archive now saves hash-named files and can still read the legacy canonical `dotAnky.anky`.
- Android mirror client accepts streamed SSE reflection responses with progress, reflection chunks, final markdown, tags, hash, and credits.
- Reflection tags are persisted in `LocalReflection`, session summaries, backup export/import JSON, and the local session index.
- Write completion now freezes the completed writing and shows the Anky conversation prompt instead of auto-navigating away.
- The post-write prompt offers `reflect (1 credit)` and routes to Reveal with reflection startup.
- The writing ring now follows the current iOS 8-section ring: thicker passed sections and an inner counter-clockwise terminal-silence countdown after 3 seconds.
- Reveal now keeps the writing as the main surface and uses the Anky conversation prompt for `reflect this anky` / `read reflection`.
- Reflection progress and saved reflections render in a bottom sheet, with optional live text reveal during streaming.
- Reveal now refreshes reflection credits on entry through the existing Android `CreditsClient`, updates local balance state, and wires `open reflection credits` to You.
- `open reflection credits` now opens the Android credits detail directly through `you/credits`, with the You tab selected and back returning to the prior screen.
- Android Anky conversation actions now match the Swift action shape more closely: up to four actions, optional subtitle/badge text, a small `anky` header, and a thinking indicator.
- The You credits prompt now mirrors Swift by showing the live credit balance subtitle, refreshing credits when the credits row is opened, and rendering the first three credit packages directly as Anky chat actions with price subtitles and the `recommended` badge.
- The You privacy and support prompts now mirror Swift: privacy opens `https://anky.app/privacy`, support is labeled `support / feedback`, and both the prompt and credits page open a `mailto:support@anky.app` URL with the account id in the body.
- Reveal now puts `open credits` inside the Anky conversation actions instead of rendering a separate loose text link below the prompt.
- The post-write Android prompt now mirrors Swift's two-action shape: `reflect (1 credit)` starts the streamed Reveal flow, while `not now` consumes the completed hash and lands on Map.
- Android now shows the Swift-shaped launch writing bubble on the Write screen before the first character: the living `.anky` message or `ankys today: N`, the `write 8 minutes` / `write again` action, and the three ritual steps.
- Tapping the floating Anky on Android now mirrors Swift's contextual guide behavior across Write, Map, and You: it cycles the same `you are here...` companion notes instead of falling through to hide/show behavior.
- Android Write import failure copy now matches Swift: unreadable pasted `.anky` text shows `i couldn't find a readable .anky in that.` and open failures show `i couldn't open that .anky yet.`
- Android Reveal companion copy now matches Swift in the streaming and saved-reflection states: streaming uses `i am staying with this .anky.` plus `i am reading slowly. not looking for a summary.`, and saved reflections say `this anky has a reflection.`
- Tags are labeled, tappable, and open a local tag sessions screen backed by `SessionIndexStore.sessionsWithTag`.
- Android now has a local `ReflectionRequestStore` for pending reflection request persistence, clear-on-success/delete, and iOS-style pending retry/watcher behavior.
- The iOS `tellmewhoyouare` asset was migrated and used by the Android app-lock failure surface.
- Android app lock now mirrors the current iOS lock recovery fallback: after two failed biometric attempts, the `tellmewhoyouare` surface accepts a normalized 12-word recovery phrase, unlocks after a successful local identity import, and refreshes the You identity state.
- Floating Anky drag now breaks out of the Android home-following mode as soon as drag begins, matching Swift's direct `DragGesture(minimumDistance: 3)` behavior instead of snapping back during the gesture.
- Floating Anky's long-press menu copy now mirrors Swift: `anky stays beside the writing`, `Keep Anky here`, `Hide/Show Anky`, `Change motion`, and `Cancel`; the Android-only `Move Anky home` row was removed.
- Android Write errors now mirror Swift's recent-prompt recall behavior: transient invalid-input errors fade quickly, remain briefly recallable, and tapping Anky on the Write screen replays the recent prompt before generic companion notes.
- Android now preloads reflection credits from the app root like Swift and shows the current `N credit(s)` badge on the post-write `reflect (1 credit)` action when a balance is available.
- Android's launch Write action now mirrors Swift's `openWritingPortal()` path by issuing a fresh hidden-input focus request and haptic tick when `write 8 minutes` / `write again` is tapped.
- Android short-session `write again` now routes through the root retry-writing path like Swift: it clears pending completed state, returns to Write, and opens/focuses the writing portal instead of only popping Reveal.
- Android Reveal deletion now mirrors Swift's explicit `onDeleted` callback path: deleted sessions clear the pending completed writing state, refresh the shared local Map index, re-derive an open Map day from refreshed state, and then pop the Reveal route.
- Android reflection streaming progress now mirrors Swift's monotonic thread progress formula instead of resetting with a modulo, and live reflection reveal is one-way (`reveal live`) instead of a hide/show toggle.
- Android tag-session lists now refresh on lifecycle resume, matching Swift's `.onAppear` reload so returning from a child Reveal after deletion does not leave stale tagged rows.
- Android tag-session lists now use the same violet bloom texture treatment as Reveal, matching Swift's `RevealBackgroundTexture()` instead of only drawing guide lines.
- Android tag-session title layout now mirrors Swift by rendering the tag name inside the scroll content at 30sp with matching horizontal/bottom/top spacing instead of as a 26sp top-bar title.
- Android tag-session rows now mirror Swift's medium monospaced metadata and smaller 13dp chevron treatment.
- Android's idle reflection bottom sheet now mirrors Swift by showing the credit prompt message and an enabled/disabled `reflect this anky` action instead of a dead `the reflection is not here yet` placeholder.
- Android saved reflections in the bottom sheet now mirror Swift's `reflection.displayBody` rendering and no longer reinsert an Android-only title heading before the reflection body.
- Android's reflection bottom sheet now allows the partial/medium sheet state like Swift's `[.medium, .large]` detents and scrolls its content so long saved or streaming reflections are not clipped.
- Android markdown reflection rendering now treats Swift-style horizontal rules (`---`, `***`, `___`, em dash, and short repeated rule markers) as separators instead of body text.
- Android tag-session rows now use the platform localized medium-date/short-time formatter like Swift's abbreviated-date/shortened-time style, instead of the previous Android-only slash format and forced lowercase.
- Android's reflection bottom sheet now separates states like Swift: saved reflections open directly into the reflection body with the small scroll glyph, streaming uses `the mirror is forming`, and only the idle credit prompt keeps the generic `mirror` heading.
- Android's Reveal auto-start reflection route now mirrors Swift's `didAutoStartReflection` branch: the sheet starts closed, opens once on appear when there is no saved reflection, and credit-state changes or failed attempts do not silently re-trigger the reflection request loop.
- Android Map day session rows now expose Swift-shaped accessibility labels with reflected title, preview, time, duration, word count, `anky`, and `reflected` metadata instead of leaving that row context only in visible text.
- Android Map day session row dividers now mirror Swift's bottom overlay treatment instead of participating in the title/preview vertical spacing.
- Android Map day-detail lists now use Swift's separate horizontal/top/bottom padding, including the larger 72dp bottom breathing room.
- Android Map empty day detail now uses regular serif body typography like Swift's Georgia 20 empty state instead of the semibold heading style.
- Android Map day-detail date chrome now uses a compact 17sp semibold inline-title treatment against the 0.96 ink bar, closer to Swift's inline navigation title instead of an Android-only large gold heading.
- Android Map trail empty text and day nodes now mirror Swift's quieter treatment more closely: empty trail copy uses regular serif body typography, and non-today trail nodes keep the black/textured fill with region color reserved for the stroke instead of tint-filling the circle.
- Android Map's current-day jump control now mirrors Swift's 48dp circular material-style hit target and button-level accessibility label instead of relying on an Android-only dark IconButton background.
- Android Map's vertical trail line now scrolls with the day nodes and runs from first node center to last node center like Swift's `StraightTimeline`, instead of being drawn as a fixed viewport-height line behind the list.
- Android Map trail day nodes now expose Swift-shaped accessibility labels of `{date}, {trail activity summary}`, including `Today`, `No writing`, `Showed up`, and `No complete anky` states.
- Android Map's current-day progress ring and day-completion marker now expose the same accessibility labels as Swift: `UTC day progress` and `showed up`.
- Android You now starts with no active Anky conversation prompt like Swift's optional `activePrompt`; the bottom prompt opens only after a prompt selection or a status/error system message.
- Android Write now exposes the ritual clock with Swift's `Writing time {clock}` accessibility label after the 8-minute mark.
- Android Write now mirrors Swift's hidden dev-paste affordance: regular tap still imports a pasted `.anky`, while a five-second hold on the paste icon imports a built-in complete `.anky` fixture for testing.
- Android Reveal's delete control now mirrors Swift's accessible label and red danger treatment: the header button is `Delete writing session`, while destructive confirmation copy remains separate.
- Android You now ports Swift's hidden title-tap Anky Experience: tapping `you` opens a full-screen 88-minute forward-only writing surface with portal ring, elapsed-time accessibility label, companion copy prompt, and copy actions for the live `.anky` stream or reconstructed writing.
- Android now treats the You Anky Experience like Swift's full-screen cover at the root shell level: while it is open, the Android tab bar and floating Anky presence are suppressed so the experience is not framed by app chrome.
- Android You Anky Experience now hides Android system bars while open and restores them on dispose, matching Swift's `persistentSystemOverlays(.hidden)` behavior.
- Android You support prompt copy now mirrors Swift: `send support or feedback by email. include only what you choose to write.`
- Android You local identity copy now mirrors Swift's Base account / recovery phrase language, including the recovery reveal/copy actions and failure copy; Android keeps its platform secure-storage implementation.
- Android You identity backup now mirrors Swift's action shape: the prompt and Account page `back up identity` controls run a biometric-gated secure-storage backup path instead of revealing the recovery phrase.
- Android You reset-identity confirmation now mirrors Swift's warning that reset creates a new Base account, credits are tied to the current account, and the recovery phrase should be saved first.
- Android You local identity load failure copy now mirrors Swift's `Could not load the local Base identity.`
- Android You privacy policy keeps Swift's local-first structure while its source links now point to the Android archive, protocol, identity, mirror, backup, and You model implementation files instead of copied iOS paths.
- Android You recovery-import validation copy now mirrors Swift's `Recovery phrase must be 12 words.` and `Recovery phrase contains an unrecognized word.` instead of the older Android `Recovery key...` wording.
- Android active drafts now mirror Swift's storage split: the live draft is saved under `ActiveDrafts/dotAnky.anky`, while the legacy `Ankys/dotAnky.anky` path is only loaded/cleared when it is still an open draft.
- Android single `.anky` import now mirrors Swift's forgiving paste/import path: it tries normalized raw text, fenced code blocks, and extracted protocol runs, handles `SPACE` placeholders/trailing whitespace, and only saves complete imported sessions.
- Android now refreshes the root reflection-credit badge again when a completed writing is waiting on the post-write `reflect (1 credit)` prompt, closing the gap with Swift's shared `YouViewModel.creditBalance` badge source.
- Android imported `.anky` artifacts now enter the same post-write companion decision flow as Swift's `completion?(saved)` path instead of jumping directly to Reveal.
- Android post-write `not now` now mirrors Swift's `revealAfterWriting` handoff: it switches through Map and opens the artifact's normal Reveal screen without auto-starting reflection.
- Android Map refresh now mirrors Swift's resilience path by falling back to the existing local session index if archive rebuild fails, instead of blanking the map.
- Android tag pills and tag-session titles now preserve the stored tag display text like Swift instead of lowercasing it at render time.
- Android saved-reflection sheets now match current Swift by keeping the saved credit balance in local storage/state but no longer rendering an Android-only `N reflections left` line, and tag pills now use a single horizontal capsule rail like Swift.
- Android Reveal now mirrors Swift's left-edge horizontal back swipe using the same practical thresholds: a narrow 32dp edge region, rightward movement over 80dp, and vertical drift under 60dp.
- Android Map day detail now owns the same map-background texture plus 0.76 ink overlay as Swift's `MapDayBackground`, instead of relying only on the parent Map backdrop with a flat overlay.
- Android streaming reflection live reveal now mirrors Swift by labeling the revealed live markdown as `writing reflection · N characters`.
- Android streaming reflection progress now uses a Swift-like custom dark/gold thread bar instead of the generic Material linear progress control.
- Android reflection bottom-sheet actions now use Swift-like icon+text rows for `reveal live` and `reflect this anky`.
- Android reflection bottom sheets now own the Reveal ink texture/background like Swift's `ReflectionBottomSheet`, instead of rendering a flat ink sheet.
- Android reflection tag rails now render the full stored tag list like Swift's `ForEach(tags)` instead of silently truncating to eight display pills.
- Android reflection tag rail typography now mirrors Swift more closely: monospaced muted `tags` label with letter spacing and monospaced medium tag pills.
- Android reflection bottom-sheet content spacing now follows Swift's saved/streaming/idle padding differences, and streamed markdown keeps the streaming sheet state even if the ask flag has already flipped.

Validation run in this pass:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.storage.StorageTest --tests inc.anky.android.feature.reveal.RevealViewModelTest` passed after pending-request storage and Reveal wiring.
- `./gradlew :app:testDebugUnitTest` passed.
- `./gradlew :app:assembleDebug` passed.
- `git diff --check` passed.
- After the direct credits-route fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed again.
- After the Anky conversation/action parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed again.
- After the You privacy/support prompt parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the post-write `not now` parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the launch writing prompt parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the contextual floating-Anky tap parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the Write import failure-copy parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the Reveal companion-copy parity fix, `./gradlew :app:testDebugUnitTest` passed.
- After the app-lock recovery fallback parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the floating-Anky drag fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the floating-Anky menu-copy parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Write recent-prompt replay parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the post-write credit-badge parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the launch Write focus parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the short-session `write again` retry-flow parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Reveal deletion callback/map-refresh parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the streaming progress parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag-session resume refresh parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag-session Reveal texture parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag-session title layout parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag-session row metadata/chevron parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the idle reflection bottom-sheet parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the saved-reflection display-body parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection sheet detent/scroll parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the markdown horizontal-rule parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag-session date-format parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection sheet saved/streaming heading parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Reveal auto-start one-shot parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map session-row accessibility parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map session-row divider overlay parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map day-detail list padding parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map empty day detail typography parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map trail-day accessibility parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map progress/marker accessibility parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You initial conversation prompt parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Write timer accessibility parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Write hidden dev-paste parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Reveal delete-control accessibility/style parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You Anky Experience parity port, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You Anky Experience root-shell parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You Anky Experience system-bars parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You support prompt-copy parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You Base account / recovery phrase copy parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You identity backup action parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest --tests inc.anky.android.feature.you.YouViewModelStateTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You reset-identity warning parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the You Base identity failure-copy parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Android privacy source-link parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the recovery phrase validation-copy parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the active-draft storage parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the single `.anky` import-candidate parity fix, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the post-write credit-badge refresh parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the imported `.anky` post-write flow parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the post-write `not now` Map-to-Reveal handoff parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map refresh fallback parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the tag display-text parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the saved-reflection credit-line and horizontal tag-rail parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Reveal edge back-swipe parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map day-detail background parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the streaming reflection live-reveal label parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the streaming reflection thread-progress bar parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection bottom-sheet icon action parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection bottom-sheet texture parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection tag full-list rendering parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection tag typography parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the reflection bottom-sheet spacing/streaming-state parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map trail empty-state and node-texture parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map current-day button parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map scrolling timeline parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.
- After the Map day-detail inline-title parity fix, `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug`, and `git diff --check` passed.

Privacy/protocol notes:

- Android still does not send `X-Anky-Trial-Proof`.
- The raw `.anky` upload path remains only behind explicit reflection/nudge user actions.
- No server-side storage, auth, credit issuance, or identity semantics were changed in Android.

## 2026-05-27 Delta Pass

Baseline:

- Source of truth: current dirty iOS worktree in `apps/ios/Anky`.
- Android delta target: port the new Write portal/nudge, Reveal chat invitation/copy behavior, You prompt-driven home, and mirror intent header.

Migrated Android changes:

- Mirror requests now send `X-Anky-Intent: reflection` by default and can send `X-Anky-Intent: nudge` for the new in-writing Anky nudge path.
- Write now tracks per-glyph settling color, renders the smaller bottom-right portal-style ritual ring, keeps the latest glyph red-to-white through silence, and lets tapping Anky during an unfinished session request a one-line nudge from the mirror.
- Write nudge copy matches the iOS shape: `anky is listening to this .anky for one line.`, one-line heading stripping, credit/incomplete-specific errors, and a transient six-second prompt.
- Write rejected-input handling now matches the current iOS nudge: rejected deletion/replacement/paste surfaces `that doesn't work here. just keep writing without agenda.` transiently and uses Android haptics from the input surface.
- Reveal now uses the bottom Anky conversation invitation instead of the old inline/floating mirror controls, including reflection-status progress copy while the mirror request is running.
- Reveal writing is tap-to-copy with a clipboard burst, saved reflection display removes a duplicated leading markdown heading matching the reflection title, and inline `*emphasis*` markdown is rendered.
- Reveal saved-reflection tap-copy was removed on Android because the current iOS view only wires tap-copy on reconstructed writing; a source parity guard now keeps Android from reintroducing an `Anky mirror` clipboard path without an iOS surface change.
- You home now follows the prompt-driven iOS update: no subtitle/avatar on the first screen, prompt rows for identity/privacy/data/credits/support/developer, no disclosure chevrons, and a bottom Anky conversation panel with up to two contextual actions.
- You backup prompt behavior now matches the current iOS shape: You home prepares the backup on entry, `export backup` appears only after a backup file exists, `restore backup` is always available, and the earlier Android-only `prepare backup` chat action is gone.
- Shared Android companion prompt UI now supports up to two chat actions with primary/secondary styling like the updated Swift `AnkyChatAction`.
- The presence overlay can delegate taps to Write before toggling hide/show, matching the new iOS Anky-tap nudge behavior.

Validation run in this pass:

- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.mirror.MirrorClientTest --tests inc.anky.android.privacy.SourceInvariantTest --tests inc.anky.android.feature.reveal.RevealViewModelTest` passed.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.write.WriteViewModelTest` passed with focused nudge coverage for immediate listening copy, `X-Anky-Intent: nudge` request intent, one-line heading stripping, six-second prompt clearing, and iOS rejected-input copy clearing.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest --tests inc.anky.android.feature.reveal.RevealViewModelTest` passed after aligning Reveal copy behavior to the current iOS writing-only tap surface.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest --tests inc.anky.android.mirror.MirrorClientTest` passed after tightening the explicit Write nudge test seam.
- `./gradlew :app:testDebugUnitTest --tests inc.anky.android.privacy.SourceInvariantTest --tests inc.anky.android.feature.you.YouViewModelStateTest` passed with `BUILD SUCCESSFUL in 2s` after aligning the You export prompt actions to current iOS.
- `./gradlew :app:test :app:assembleDebug :app:lintDebug` passed with `BUILD SUCCESSFUL in 9s` after the Write nudge test seam, immediate-listening prompt update, rejected-input copy alignment, and Reveal writing-only copy alignment.
- `./gradlew :app:test :app:assembleDebug :app:lintDebug :app:printReleaseSigningStatus` passed with `BUILD SUCCESSFUL in 10s`; release identity is `app.anky.mobile`, debug identity is `app.anky.mobile.debug`, version is `0.1.0` / `2026052002`, and `releaseSigningConfigured=false`.
- `xcodebuild -project ios/Anky.xcodeproj -scheme Anky -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' -derivedDataPath /tmp/anky-ios-parity-dd build` passed with `BUILD SUCCEEDED`.
- `git diff --check -- android` passed.
- Fresh Android 30 emulator screenshots were captured from the current debug APK:
  - `qa-screenshots/android-emulator-20260527-write-idle.png`
  - `qa-screenshots/android-emulator-20260527-write-active.png`
  - `qa-screenshots/android-emulator-20260527-map-current-seeded.png`
  - `qa-screenshots/android-emulator-20260527-map-day-current-seeded.png`
  - `qa-screenshots/android-emulator-20260527-reveal-saved-reflection.png`
  - `qa-screenshots/android-emulator-20260527-you-main.png`
- The seeded Reveal run used a same-day complete `.anky` plus local reflection sidecar and verified the then-current saved-reflection hierarchy: duplicated leading title heading removed, inline emphasis rendered, quote and bullets rendered. A later parity pass removed the Android-only saved-reflection credit line to match current Swift.

Privacy/protocol notes:

- Write now has an explicit, user-triggered mirror path only for tapping Anky during an unfinished session. The source invariant was updated to allow only that nudge path and still reject direct OkHttp/RevenueCat/purchase clients in Write.
- Android still does not send `X-Anky-Trial-Proof`.
- No asset migration was required for this delta; the iOS changes reused existing migrated sprites/icons/backgrounds.

## 2026-05-16 Delta Pass

Baseline:

- Previous Android parity baseline: `736e743 Bring Android app to iOS parity`
- iOS deltas synced: `6d30d32 Implement device-bound trial credits`, `52f6aab Polish reveal privacy copy`
- Controlling brief: `ANKY_ANDROID_DELTA_PARITY_GOAL.md`

Migrated Android changes:

- Reveal now uses the iOS-style bottom floating `ask anky` prompt that scrolls the user to the inline Ask Anky action.
- Reveal Ask Anky inline action uses `1 free reflection included`.
- Reveal copy is section-aware with `copy writing` / `copy reflection` and short copied-state feedback.
- Saved reflections preserve local `creditsRemaining` for state/export parity, while the current saved-reflection sheet keeps that balance out of the rendered body like Swift.
- Reveal has a local delete affordance and Android-native confirmation using `delete forever?`.
- `RevealViewModel` deletes only local `.anky`, local reflection, and local session-index state.
- `RevealViewModel` invalidates credit balance cache through a narrow `CreditsClient.invalidateCreditBalanceCache()` hook when Ask Anky returns non-null `creditsRemaining`.
- Unit coverage was added for credit-cache invalidation, null-credit no-op behavior, and local Reveal deletion.

Skipped / intentional divergence:

- Android device-bound trial proof remains intentionally unimplemented.
- Android must not send `X-Anky-Trial-Proof` until a Play Integrity/device recall design exists with server-side verification.
- No fake credits, client-issued trial credits, or public-key-only trial grants were added.

Validation run in this pass:

- `./gradlew testDebugUnitTest --tests inc.anky.android.feature.reveal.RevealViewModelTest --tests inc.anky.android.mirror.MirrorClientTest`
- First attempt failed because Java was not on the default path.
- Re-run with `JAVA_HOME=/Users/kithkui/.local/share/mise/installs/java/corretto-17.0.19.10.1` but no `ANDROID_HOME` reached Gradle and stopped with `SDK location not found`.
- Final focused run with `JAVA_HOME=/Users/kithkui/.local/share/mise/installs/java/corretto-17.0.19.10.1 ANDROID_HOME=/opt/homebrew/share/android-commandlinetools` passed with `BUILD SUCCESSFUL in 10s`.
- Full `testDebugUnitTest` passed with `BUILD SUCCESSFUL in 1s`.
- `assembleDebug` passed with `BUILD SUCCESSFUL in 3s`.
- `adb devices` showed no attached devices, so `connectedDebugAndroidTest` was not run.
- `git diff --check -- apps/android` passed.
- Targeted parity search for `X-Anky-Trial-Proof|X-Anky-App-Version|creditsRemaining|8 free reflections included|copy writing|copy reflection|delete forever` was run from repo root.

Privacy/protocol notes:

- No `.anky` protocol, parser, writer, hash, signing, mirror body, or mirror signature semantics were changed.
- Android still sends raw `.anky` bytes to `POST /anky`.
- Android still sends `X-Anky-App-Version`.
- Android still must not send `X-Anky-Trial-Proof`.
- No logging of copied writing, reflection text, raw `.anky`, recovery phrase, private key, seed, or signature material was added.
