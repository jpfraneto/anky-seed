package inc.anky.android.core.subscription

/**
 * The complete map of what the `pro` entitlement gates, derived from every
 * `isEntitledForGating` / `lastKnownEntitledForGating` consultation in the
 * iOS app. Feature stores own their gating flags; this object is the shared
 * vocabulary (and the constants) so every gate consults the same truth.
 *
 * iOS gate inventory (file:line → what it decides → Android enforcement):
 *
 * 1. Reflection (LLM) — free sessions make ZERO LLM calls:
 *    - AppRoot.swift:1592 `reflectionVeiled` and :1629 (sealing flow asks the
 *      mirror only when entitled), RevealView.swift:128/284/321/467/526
 *      (veil card where the reflection would bloom; "SEE WHAT ANKY SAW" CTA
 *      opens the paywall sheet and reports `veil_tapped {reflection}`).
 *      → Android: RevealViewModel/PostSessionSealing equivalents must consult
 *        [freeSessionSkipsLlmReflection] before any mirror `askAnky` call.
 *    - WriteViewModel.swift:529 (server nudges are LLM calls; free sessions
 *      get the local fallback nudge) — uses persisted
 *      `EntitlementStore.lastKnownEntitledForGating` because WriteViewModel
 *      sits outside the store's object graph.
 *      → Android: WriteViewModel nudge path reads
 *        [EntitlementStore.lastKnownEntitledForGating].
 *
 * 2. Daily Unlock — the daily-target unlock belongs to the subscription:
 *    - AppRoot.swift:742/822 pushes `writeViewModel.dailyUnlockEntitled`;
 *      UnlockPolicy.swift:58-68/158-163 grants the daily tier only when
 *      `dailyUnlockEntitled`; the free-target moment (option C) fires when
 *      `!entitled && targetReached && no unlock grant` (AppRoot.swift:240).
 *      Quick Passes and the emergency breath stay free for everyone.
 *      → Android: the WBS unlock policy takes the same boolean, fed from
 *        `EntitlementStore.isEntitledForGating` on start/foreground/change.
 *
 * 3. Level/painting boundary — free tier presents level 2 serenely complete:
 *    - LevelProgressStore.swift:84-107 (`freeBoundaryLevel = 2`,
 *      `presentedProgress(entitled:)` display clamp, `isAtBoundary`),
 *      LevelPaintingCoordinator.swift:32/82-83/135/155 (no generation past
 *      the boundary while unentitled; held generation fires on entitlement
 *      confirm — AppRoot.swift:820-830 `handleEntitlementConfirmed` after the
 *      backend identify), PaintingHomeView.swift:451 (presented progress).
 *      → Android: the level store (WS3) owns the clamp; it must reference
 *        [FREE_BOUNDARY_LEVEL] and take `entitledForGating` from this store.
 *
 * 4. Journey veil — PaintingHomeView.swift:116 (journey card misted for free
 *    writers; `veil_tapped {journey}` → paywall sheet).
 *    → Android: PaintingHome equivalent consults `isEntitledForGating`.
 *
 * 5. Onboarding paywall skip — OnboardingView.swift:542/627/644 (screen 10 is
 *    skipped in both directions for an already-entitled writer).
 *    → Android: onboarding pager consults `isEntitledForGating`.
 *
 * 6. Ambient paywall pressure — TrialActivityController.swift:18 (trial
 *    lock-screen surface only for unentitled writers, once per rolling week
 *    via [PaywallPressureLedger]); AppRoot.swift:771 ends it on entitlement.
 *    → Android: any ambient trial surface must check both the gate and the
 *      ledger. (Live Activities have no direct Android analogue; deferred.)
 *
 * 7. Widget/quick-action snapshots — GlanceSyncCoordinator.swift:15 and
 *    AppRoot.swift:573/753/806/823 (HomeQuickActionPublisher.refresh) render
 *    at the presented (boundary-held) progress using the PERSISTED
 *    `lastKnownEntitledForGating`, because they run outside the store graph.
 *    → Android: widget sync reads [EntitlementStore.lastKnownEntitledForGating].
 *
 * 8. Adaptive-target offer — AppRoot.swift:291 (tunes the Daily Unlock, which
 *    belongs to the subscription — never shown to free writers).
 *    → Android: adaptive offer presentation consults `isEntitledForGating`.
 */
object EntitlementGates {
    /**
     * The free tier's display boundary: level 2 presents as serenely complete
     * while the counter underneath keeps every second. CONSTANT ONLY here —
     * the level store owns the clamp (`presentedProgress(entitled:)`).
     * Mirrors iOS `LevelProgressStore.freeBoundaryLevel`.
     */
    const val FREE_BOUNDARY_LEVEL = 2

    /**
     * Phase-3 §3: free sessions never ask the mirror — where the reflection
     * would bloom, the veil. Quick Pass included: the pass, the unlock, the
     * seconds, and the strokes are all still granted; only the LLM call is
     * withheld.
     */
    fun freeSessionSkipsLlmReflection(entitledForGating: Boolean): Boolean =
        !entitledForGating

    /**
     * The Daily Unlock (reaching the daily writing target opens the gated
     * apps until midnight) belongs to the subscription. Quick Passes and the
     * emergency breath are free for everyone. This is the value the unlock
     * policy's `dailyUnlockEntitled` flag must be fed.
     */
    fun dailyUnlockEntitled(entitledForGating: Boolean): Boolean =
        entitledForGating

    /**
     * Option C (decision 2026-07-06): a free writer's target crossing is
     * acknowledged where a subscriber's day would open — a sealing-gate block
     * with the trial CTA. Entitlement is re-checked at seal so a mid-session
     * purchase wins, and an earned unlock CTA always keeps its button.
     * Mirrors AppRoot.swift:236-241.
     */
    fun showsFreeTargetMoment(
        freeTargetMomentPending: Boolean,
        entitledForGating: Boolean,
        hasUnlockGrant: Boolean,
    ): Boolean = freeTargetMomentPending && !entitledForGating && !hasUnlockGrant
}
