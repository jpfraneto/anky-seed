import SwiftUI
import UIKit

struct AppRoot: View {
    /// QA override: resets `anky.onboardingCompleted` on every launch so
    /// the full 13-screen flow can be walked repeatedly. It stays off by
    /// default, including DEBUG, so normal device builds match production
    /// onboarding persistence.
    ///
    /// Its siblings live in EntitlementStore.ignoresEntitlementForQA
    /// (purchases persist across onboarding re-runs, so without it QA
    /// walkthroughs jump over the paywall after the first test purchase)
    /// and PaywallView.paywallIsSkippable (the "later" escape hatch).
    #if DEBUG
    private static let alwaysShowsOnboardingForQA = false
    #else
    private static let alwaysShowsOnboardingForQA = false
    #endif

    /// The onboarding revision this build ships. When a writer's completed
    /// revision is older than this, the flow plays again on next launch — a
    /// significant new version's onboarding is a must, even for existing
    /// users who updated. Bump this whenever the onboarding changes enough to
    /// warrant re-showing it. Existing installs default to 0, so they replay
    /// once and then settle at the current revision.
    private static let currentOnboardingVersion = 2

    private enum WriteSurface {
        case home
        case checkIn
        case deepWrite
        case sealing
    }

    private enum HomeRoute: Hashable {
        case archive(Date?)
        case archiveReveal(SavedAnky, Date?)
    }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("anky.biometricIdentityConfirmation") private var faceIDLockEnabled = false
    @AppStorage("anky.biometricPrivacyOnboardingCompleted") private var faceIDPrivacyOnboardingCompleted = false
    @AppStorage("anky.biometricPrivacyPromptPendingAfterFirstAnky") private var faceIDPrivacyPromptPendingAfterFirstAnky = false
    @AppStorage("anky.biometricPrivacyPromptReadyAfterFirstAnkyOpen") private var faceIDPrivacyPromptReadyAfterFirstAnkyOpen = false
    @AppStorage("anky.skipNextFaceIDEnableAuthentication") private var skipsNextFaceIDEnableAuthentication = false
    @AppStorage("anky.onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("anky.onboardingCompletedVersion") private var onboardingCompletedVersion = 0
    @AppStorage("anky.didRequestReviewAfterFirstSeal") private var didRequestReviewAfterFirstSeal = false
    @Environment(\.requestReview) private var requestReview
    @State private var showsDayOneOverlay = false
    @State private var selectedTab = 0
    @State private var revealAfterWriting: SavedAnky?
    @State private var sealingArtifact: SavedAnky?
    @State private var sealingUnlockGrant: UnlockGrant?
    @State private var sealingShowsFreeTargetMoment = false
    /// The on-surface post-session beat picked "reflect" (entitled): open the
    /// mirror directly — the separate writing-recap screen is gone.
    @State private var startsSealingAtMirror = false
    /// The on-surface beat picked "skip" on a gate session: fall through to the
    /// closing gate so an earned unlock is still one deliberate tap away.
    @State private var startsSealingAtGate = false
    /// A free writer completed the slide on the writing surface: the paywall
    /// meets them here, and nothing is sent if they decline.
    @State private var showsReflectPaywall = false
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var suppressFaceIDPrivacyPromptUntilNextActivation = false
    @State private var showsLaunchDialogue = true
    @State private var showsOnboarding = true
    @State private var showsFaceIDActivationPrompt = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var showsICloudRestorePrompt = false
    @State private var isRestoringICloudBackup = false
    @State private var iCloudRestoreErrorMessage: String?
    @State private var preservesContinuedSessionOnNextWriteTab = false
    @State private var writeSurface: WriteSurface = .deepWrite
    @State private var showsGateSetup = false
    @State private var showsSettings = false
    @State private var archiveDate: Date?
    @State private var archiveRevealArtifact: SavedAnky?
    @State private var homePath: [HomeRoute] = []
    @StateObject private var writeViewModel = WriteViewModel()
    @StateObject private var youViewModel = YouViewModel()
    @StateObject private var ankyCompanion = AnkyCompanionStore()
    @StateObject private var tabBarCTAController = AnkyTabBarCTAController()
    @StateObject private var writeBeforeScrollSpike = WriteBeforeScrollSpikeViewModel()
    @StateObject private var entitlements = EntitlementStore()
    @StateObject private var levelPainting = LevelPaintingCoordinator()
    @State private var presentedCeremonyLevel: Int?
    @State private var presentedAdaptiveOffer: AdaptiveTargetOffer?
    @State private var showsEmergencyBreath = false
    @State private var pendingDraftRecovery: ActiveDraftRecovery?
    @State private var confirmsDraftDiscard = false
    /// The one line anky says after the emergency breath: confirmation that
    /// the day actually opened. Cleared by tap or after ten quiet seconds.
    @State private var emergencyUnlockedLine: String?

    /// The main screen IS the painting: closing any surface lands on it.
    private func showMap() {
        selectedTab = 0
        writeSurface = .home
        homePath.removeAll()
        ankyCompanion.hideBubble()
    }

    private func showArchive(date: Date? = nil) {
        archiveDate = date
        archiveRevealArtifact = nil
        selectedTab = 0
        writeSurface = .home
        homePath = [.archive(date)]
        ankyCompanion.hideBubble()
    }

    /// A history row on the main screen opens its entry directly — no
    /// detour through the archive list.
    private func openArchiveEntry(hash: String) {
        guard let artifact = LocalAnkyArchive().list().first(where: { $0.hash == hash }) else {
            showArchive()
            return
        }
        selectedTab = 0
        writeSurface = .home
        archiveRevealArtifact = artifact
        homePath = [.archiveReveal(artifact, archiveDate)]
        ankyCompanion.hideBubble()
    }

    private func showArchiveReveal(_ artifact: SavedAnky) {
        archiveRevealArtifact = artifact
        selectedTab = 0
        writeSurface = .home
        if homePath.last != .archiveReveal(artifact, archiveDate) {
            homePath.append(.archiveReveal(artifact, archiveDate))
        }
        ankyCompanion.hideBubble()
        // 8-Day Gate, Day 4: the writer read an archive echo.
        EightDayGateStore().markCompleted(day: 4)
    }

    private func showWriteInterface() {
        revealAfterWriting = nil
        sealingArtifact = nil
        sealingUnlockGrant = nil
        showsLaunchDialogue = false
        writeSurface = .deepWrite
        selectedTab = 0
        homePath.removeAll()
        writeViewModel.openWritingPortal()
        syncWriteBubble()
    }

    private func showCheckInModePicker() {
        revealAfterWriting = nil
        sealingArtifact = nil
        sealingUnlockGrant = nil
        showsLaunchDialogue = false
        writeSurface = .deepWrite
        selectedTab = 0
        homePath.removeAll()
        ankyCompanion.hideBubble()
        writeViewModel.openWritingPortal()
        syncWriteBubble()
    }

    private func showHomeChamber() {
        revealAfterWriting = nil
        sealingArtifact = nil
        sealingUnlockGrant = nil
        showsLaunchDialogue = false
        writeSurface = .home
        selectedTab = 0
        homePath.removeAll()
        ankyCompanion.hideBubble()
    }

    private func showProfile() {
        selectedTab = 2
        writeSurface = .home
        homePath.removeAll()
        ankyCompanion.hideBubble()
    }

    private func showDeepWriteInterface() {
        revealAfterWriting = nil
        sealingArtifact = nil
        sealingUnlockGrant = nil
        showsLaunchDialogue = false
        writeSurface = .deepWrite
        writeViewModel.beginBlankSessionFromWriteTab()
        selectedTab = 0
        homePath.removeAll()
        writeViewModel.openWritingPortal()
        syncWriteBubble()
    }

    private func checkForActiveDraftRecovery() {
        guard pendingDraftRecovery == nil,
              !writeViewModel.hasStarted,
              writeViewModel.completedArtifact == nil,
              let recovery = ActiveDraftStore().loadRecoverableDraft() else {
            return
        }
        pendingDraftRecovery = recovery
    }

    private func resumeRecoveredDraft() {
        guard let recovery = pendingDraftRecovery,
              writeViewModel.resumeRecoveredDraft(recovery) else {
            return
        }
        pendingDraftRecovery = nil
        revealAfterWriting = nil
        sealingArtifact = nil
        sealingUnlockGrant = nil
        showsLaunchDialogue = false
        writeSurface = .deepWrite
        selectedTab = 0
        homePath.removeAll()
        writeViewModel.openWritingPortal()
        syncWriteBubble()
    }

    /// Write entry from the gate home: resumes an in-flight session instead
    /// of resetting it, so leaving to the home surface mid-writing never
    /// destroys the active draft.
    private func showGateWriteInterface() {
        if writeViewModel.hasStarted && writeViewModel.completedArtifact == nil {
            revealAfterWriting = nil
            sealingArtifact = nil
            sealingUnlockGrant = nil
            showsLaunchDialogue = false
            writeSurface = .deepWrite
            selectedTab = 0
            homePath.removeAll()
            writeViewModel.openWritingPortal()
            syncWriteBubble()
        } else {
            showDeepWriteInterface()
        }
    }

    private func grantWriteBeforeScrollUnlock(fallbackGrant: UnlockGrant? = nil) {
        guard let grant = writeViewModel.consumeWriteBeforeScrollAvailableUnlockGrant() ?? fallbackGrant else {
            return
        }
        defer {
            // Completing the gate means writing through it: only a
            // gate-originated session flips the first-gate flag.
            if writeViewModel.isGateOriginatedSession {
                FirstGateStore().markFirstGateCompleted()
            }
        }
        // A grant applied passively mid-session (Quick Pass, or the daily
        // upgrade over one) already consumed what it needed and cleared the
        // shield — never spend a second pass or re-apply here.
        if grant.tier == .quick, writeViewModel.hasAppliedPassiveQuickUnlock {
            return
        }
        if grant.tier == .daily, writeViewModel.hasAppliedPassiveDailyUnlockUpgrade {
            return
        }
        writeBeforeScrollSpike.applyUnlock(grant)
    }

    @discardableResult
    private func routeToWriteBeforeScrollFromPendingIntent(trigger: String) -> Bool {
        let routeResolver = WriteBeforeScrollAppRouteResolver()
        guard let route = routeResolver.pendingRoute() else {
            return false
        }

        switch route {
        case .emergencyBreathFromShield(let intentID):
            // The shield's emergency button: straight into the breath, never
            // the writing surface, with zero commentary around it.
            selectedTab = 0
            writeSurface = .home
            revealAfterWriting = nil
            showsLaunchDialogue = false
            showsEmergencyBreath = true
            WriteBeforeScrollLaunchBridgeStore().markConsumed(intentID: intentID)
            WriteBeforeScrollEventLogStore().append(
                .pendingIntentConsumed,
                metadata: ["intentID": intentID, "trigger": trigger]
            )
        case .writeBeforeScrollFromShield(let intentID):
            selectedTab = 0
            writeSurface = .deepWrite
            revealAfterWriting = nil
            showsLaunchDialogue = false
            writeViewModel.openWritingPortal()
            writeViewModel.markGateOriginatedSession(
                appDisplayName: WriteBeforeScrollLaunchBridgeStore().lastAttemptedAppDisplayName()
            )
            writeViewModel.showWriteBeforeScrollAnchorReminderIfAvailable()
            WriteBeforeScrollEventLogStore().append(
                .appOpenedWithPendingWBSIntent,
                metadata: [
                    "intentID": intentID,
                    "trigger": trigger
                ]
            )
            WriteBeforeScrollEventLogStore().append(
                .routedToWBSFromShield,
                metadata: ["intentID": intentID]
            )
            WriteBeforeScrollLaunchBridgeStore().markConsumed(intentID: intentID)
            WriteBeforeScrollEventLogStore().append(
                .pendingIntentConsumed,
                metadata: ["intentID": intentID]
            )
        }
        return true
    }

    private func revealOnMap(_ artifact: SavedAnky) {
        revealAfterWriting = nil
        sealingArtifact = artifact
        sealingUnlockGrant = writeViewModel.writeBeforeScrollAvailableUnlockGrant
        // Decision 2026-07-06 (option C): a free writer's target crossing is
        // acknowledged where a subscriber's day would open. Entitlement is
        // re-checked at seal so a mid-session purchase wins, and an earned
        // unlock CTA (rare: re-offered quick grant) always keeps its button.
        sealingShowsFreeTargetMoment = writeViewModel.writeBeforeScrollFreeTargetMomentPending
            && !entitlements.isEntitledForGating
            && sealingUnlockGrant == nil
        startsSealingAtMirror = false
        startsSealingAtGate = false
        selectedTab = 0
        showsLaunchDialogue = false
        // The words stay on the surface they were written on: the keyboard
        // withdraws and the post-session beat rises where it stood, right here
        // on the writing view. Only reflect / skip advance to the mirror/gate.
        writeSurface = .deepWrite
        ankyCompanion.hideBubble()
        backUpToICloudIfEnabled()
        levelPainting.handleSealCompleted()
        GlanceSyncCoordinator.sync()
        syncWriteBubble()
    }

    private func finishSealingToMainScreen(requestingReview: Bool = true) {
        // Unhurried context #1: a session end that is not a Quick Pass in
        // motion. If a ceremony is owed, it plays before the main screen.
        let endedQuickPass = sealingUnlockGrant?.tier == .quick
        sealingArtifact = nil
        sealingUnlockGrant = nil
        startsSealingAtMirror = false
        startsSealingAtGate = false
        revealAfterWriting = nil
        writeViewModel.clearCompletedSession()
        showsLaunchDialogue = false
        writeSurface = .home
        selectedTab = 0
        ankyCompanion.hideBubble()
        syncWriteBubble()
        presentCeremonyIfOwed(unhurried: !endedQuickPass)
        if requestingReview {
            maybeRequestFirstSealReview()
        }
    }

    private func presentCeremonyIfOwed(unhurried: Bool) {
        guard presentedCeremonyLevel == nil,
              !shouldShowOnboarding,
              !faceIDLockEnabled || isUnlocked,
              let level = levelPainting.presentableCeremonyLevel(unhurried: unhurried) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            presentedCeremonyLevel = level
        }
    }

    /// Phase-2 §1: the adaptive-target offer plays only in unhurried air —
    /// on the home surface, never over a gate intent, a ceremony, onboarding,
    /// or a paywall — and at most once per missed-streak episode.
    ///
    /// Phase-3: adaptive-target offers exist to tune the Daily Unlock, which
    /// belongs to the subscription — they are never shown to free writers.
    private func presentAdaptiveOfferIfNeeded() {
        guard presentedAdaptiveOffer == nil,
              entitlements.isEntitledForGating,
              !showsEmergencyBreath,
              writeSurface == .home,
              selectedTab == 0,
              presentedCeremonyLevel == nil,
              !shouldShowOnboarding,
              !showsDayOneOverlay,
              !faceIDLockEnabled || isUnlocked else {
            return
        }
        let targetMinutes = DailyTargetStore().effectiveTargetMinutes()
        guard let offer = AdaptiveTargetPolicy.evaluate(
            sessions: SessionIndexStore().load(),
            currentTargetMinutes: targetMinutes,
            firstOpenDate: AppOpenStore().loadOrCreate()
        ) else {
            return
        }
        let offerStore = AdaptiveTargetOfferStore()
        guard !offerStore.hasShown(episodeKey: offer.episodeKey) else {
            return
        }
        offerStore.markShown(episodeKey: offer.episodeKey)
        withAnimation(.easeInOut(duration: 0.4)) {
            presentedAdaptiveOffer = offer
        }
    }

    /// Phase-2 §3/§4: anky:// deep links from the widget and quick action.
    /// anky://write lands on the writing surface, anky://painting on the
    /// painting home.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "anky" else { return }
        switch url.host?.lowercased() {
        case "write":
            showGateWriteInterface()
        default:
            showHomeChamber()
        }
    }

    /// Phase-2 §2: the breath finished — everything opens for the rest of
    /// the day. No pass consumed, no commentary, one analytics event.
    private func completeEmergencyBreath() {
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? now.addingTimeInterval(24 * 60 * 60)
        writeBeforeScrollSpike.applyUnlock(
            UnlockGrant(tier: .daily, unlockedUntil: endOfDay, grantedAt: now),
            source: .emergency
        )
        withAnimation(.easeInOut(duration: 0.5)) {
            showsEmergencyBreath = false
        }
        emergencyUnlockedLine = AnkyLocalization.ui("Your apps are unlocked.")
        syncWriteBubble()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard emergencyUnlockedLine != nil else { return }
            emergencyUnlockedLine = nil
            ankyCompanion.hideBubble()
        }
        Task.detached(priority: .utility) {
            guard let identity = try? WriterIdentityStore().loadOrCreate() else { return }
            try? await LevelSyncClient().reportEmergencyUnlock(identity: identity)
        }
    }

    /// The back door from a continued-writing session that hasn't started
    /// typing yet: return to the reflection screen it came from, gate beat
    /// already standing — Done and continue-writing both live again.
    private func returnToSealingGate(_ artifact: SavedAnky) {
        revealAfterWriting = nil
        sealingArtifact = artifact
        sealingUnlockGrant = nil
        sealingShowsFreeTargetMoment = false
        showsLaunchDialogue = false
        writeSurface = .sealing
        selectedTab = 0
        ankyCompanion.hideBubble()
        syncWriteBubble()
    }

    /// The on-surface beat's "slide to reflect": the single deliberate act
    /// that lets the writing leave the device. A free writer meets the paywall
    /// right here — nothing is sent unless they subscribe. An entitled writer
    /// advances into the mirror, where anky reflects on the sealed session.
    private func reflectFromWritingSurface() {
        guard entitlements.isEntitledForGating else {
            showsReflectPaywall = true
            return
        }
        startsSealingAtMirror = true
        startsSealingAtGate = false
        writeSurface = .sealing
    }

    /// The on-surface beat's "skip": the words never left the device. A gate
    /// session still falls through to its closing gate (the only place apps
    /// open — never before the writer crosses it); an organic session closes
    /// straight to the main landing.
    private func skipFromWritingSurface() {
        if sealingUnlockGrant != nil {
            startsSealingAtMirror = false
            startsSealingAtGate = true
            writeSurface = .sealing
        } else {
            finishSealingToMainScreen()
        }
    }

    private func stayAfterSealing() {
        guard let artifact = sealingArtifact else {
            showDeepWriteInterface()
            return
        }
        sealingArtifact = nil
        sealingUnlockGrant = nil
        startsSealingAtMirror = false
        startsSealingAtGate = false
        revealAfterWriting = nil
        showsLaunchDialogue = false
        writeSurface = .deepWrite
        if !writeViewModel.continueSession(from: artifact) {
            writeViewModel.beginBlankSessionFromWriteTab()
        }
        ankyCompanion.hideBubble(returningTo: .listening)
        preservesContinuedSessionOnNextWriteTab = true
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = 0
        }
        writeViewModel.openWritingPortal()
        syncWriteBubble()
        maybeRequestFirstSealReview()
    }

    /// The one rating ask, at the genuine high point: right after the
    /// writer's first sealed session, once the ceremony has settled.
    /// Never during onboarding, never repeated.
    private func maybeRequestFirstSealReview() {
        guard !didRequestReviewAfterFirstSeal else {
            return
        }
        didRequestReviewAfterFirstSeal = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            requestReview()
        }
    }

    private func grantWriteBeforeScrollUnlockAndReturnToAttemptedApp() {
        // Only a gate-originated session closes the loop back into the
        // attempted app; organic sessions just land on the painting.
        let returnURL = writeViewModel.isGateOriginatedSession
            ? WriteBeforeScrollReturnTarget.currentReturnURL()
            : nil
        grantWriteBeforeScrollUnlock(fallbackGrant: sealingUnlockGrant)
        finishSealingToMainScreen(requestingReview: false)

        guard let returnURL else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            UIApplication.shared.open(returnURL)
        }
    }

    var body: some View {
        ZStack {
            Group {
                switch selectedTab {
                case 0:
                    NavigationStack(path: $homePath) {
                        Group {
                            switch writeSurface {
                            case .home:
                                PaintingHomeView(
                                    screenTime: writeBeforeScrollSpike,
                                    onWrite: showGateWriteInterface,
                                    onSetup: { showsGateSetup = true },
                                    onSettings: { showsSettings = true },
                                    onHistory: { showArchive() },
                                    onOpenEntry: { session in
                                        openArchiveEntry(hash: session.hash)
                                    },
                                    onYou: showProfile,
                                    onEmergency: {
                                        withAnimation(.easeInOut(duration: 0.35)) {
                                            showsEmergencyBreath = true
                                        }
                                    },
                                    onBeginRitual: {
                                        levelPainting.beginPaintingRitual()
                                    }
                                )
                            case .checkIn:
                                CheckInFlowView(
                                    onDeepWrite: showDeepWriteInterface,
                                    onClose: showHomeChamber
                                )
                            case .deepWrite:
                                WriteView(
                                    viewModel: writeViewModel,
                                    shouldFocus: shouldFocusWrite,
                                    onCompleted: revealOnMap,
                                    onCloseToMap: {
                                        if let artifact = writeViewModel.pendingContinuedArtifact {
                                            returnToSealingGate(artifact)
                                        } else {
                                            showMap()
                                        }
                                    },
                                    onReflect: reflectFromWritingSurface,
                                    onSkip: skipFromWritingSurface,
                                    onContinueWriting: stayAfterSealing
                                )
                            case .sealing:
                                if let sealingArtifact {
                                    PostSessionSealingView(
                                        artifact: sealingArtifact,
                                        unlockGrant: sealingUnlockGrant,
                                        isGateOriginated: writeViewModel.isGateOriginatedSession,
                                        showsFreeTargetMoment: sealingShowsFreeTargetMoment,
                                        startsAtGate: writeViewModel.isWaitingToResumeContinuedDraft || startsSealingAtGate,
                                        startsAtMirror: startsSealingAtMirror,
                                        quickPassesRemaining: writeViewModel.writeBeforeScrollQuickPassesRemaining,
                                        onMomentShown: {
                                            // The day's one showing is spent only
                                            // when the moment actually renders.
                                            writeViewModel.markFreeTargetMomentPresented()
                                        },
                                        onEmergency: {
                                            withAnimation(.easeInOut(duration: 0.35)) {
                                                showsEmergencyBreath = true
                                            }
                                        },
                                        onUnlock: {
                                            grantWriteBeforeScrollUnlockAndReturnToAttemptedApp()
                                        },
                                        onDone: { finishSealingToMainScreen() },
                                        onStay: stayAfterSealing
                                    )
                                } else {
                                    WriteView(
                                        viewModel: writeViewModel,
                                        shouldFocus: shouldFocusWrite,
                                        onCompleted: revealOnMap,
                                        onCloseToMap: {
                                            showMap()
                                        }
                                    )
                                }
                            }
                        }
                        .navigationDestination(for: HomeRoute.self) { route in
                            switch route {
                            case .archive(let date):
                                ArchiveChamberView(
                                    selectedDate: date,
                                    onOpenAnky: { artifact in
                                        archiveDate = date
                                        showArchiveReveal(artifact)
                                    },
                                    onBack: {
                                        homePath.removeAll()
                                        showHomeChamber()
                                    }
                                )
                            case .archiveReveal(let artifact, let date):
                                RevealView(
                                    viewModel: RevealViewModel(artifact: artifact),
                                    onBack: {
                                        if homePath.isEmpty {
                                            showHomeChamber()
                                        } else {
                                            homePath.removeLast()
                                        }
                                    },
                                    onDeleted: {
                                        if homePath.isEmpty {
                                            showHomeChamber()
                                        } else {
                                            homePath.removeLast()
                                        }
                                    },
                                    onReflectionReady: backUpToICloudIfEnabled
                                )
                                .onAppear {
                                    archiveDate = date
                                }
                            }
                        }
                    }
                case 2:
                    // Back navigation lives inside YouView's own toolbar so
                    // pushed pages (Settings) show a single system chevron.
                    YouView(
                        viewModel: youViewModel,
                        onWriteRequested: showWriteInterface,
                        onDevelopmentWipe: resetForFreshDevelopmentLaunch,
                        onGateSetupRequested: { showsGateSetup = true },
                        onBack: showHomeChamber
                    )
                case 3:
                    InteractiveBackSwipeContainer(onBack: showHomeChamber) {
                        NavigationStack {
                            ArchiveChamberView(
                                selectedDate: archiveDate,
                                onOpenAnky: showArchiveReveal,
                                onBack: showHomeChamber,
                                handlesBackSwipeExternally: true
                            )
                        }
                    }
                case 5:
                    ZStack(alignment: .topLeading) {
                        if let artifact = archiveRevealArtifact {
                            // The archive stands beneath so the finger-tracked
                            // back-swipe reveals it, exactly like a navigation
                            // pop (feedback 2026-07-08). Back also travels in
                            // RevealView's own navigation bar, level with the
                            // hour, copy, and delete.
                            ArchiveChamberView(
                                selectedDate: archiveDate,
                                onOpenAnky: showArchiveReveal
                            )
                            InteractiveBackSwipeContainer(onBack: { showArchive(date: archiveDate) }) {
                                NavigationStack {
                                    RevealView(
                                        viewModel: RevealViewModel(artifact: artifact),
                                        onBack: { showArchive(date: archiveDate) },
                                        onDeleted: {
                                            showArchive(date: archiveDate)
                                        },
                                        onTryAgain: {
                                            beginContinuingWriting(from: artifact)
                                        },
                                        onReflectionReady: backUpToICloudIfEnabled,
                                        handlesBackSwipeExternally: true
                                    )
                                }
                            }
                        } else {
                            ArchiveChamberView(
                                selectedDate: archiveDate,
                                onOpenAnky: showArchiveReveal
                            )
                            AppBackButton(action: { showArchive(date: archiveDate) })
                                .padding(.leading, 18)
                                .padding(.top, 64)
                        }
                    }
                default:
                    EmptyView()
                }
            }
            .environmentObject(ankyCompanion)
            .environmentObject(tabBarCTAController)
            .environmentObject(entitlements)

            AnkyTabBarFrameReader(controller: tabBarCTAController)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            AnkyTabBarCTAOverlay(controller: tabBarCTAController)
                .zIndex(75)

            if faceIDLockEnabled && !isUnlocked {
                LockFailureView(
                    retry: {
                        Task {
                            await authenticateIfNeeded()
                        }
                    }
                )
                .zIndex(100)
            }

            if showsICloudRestorePrompt {
                ICloudRestorePromptView(
                    isRestoring: isRestoringICloudBackup,
                    errorMessage: iCloudRestoreErrorMessage,
                    restore: restoreFromICloud,
                    createNew: createNewLocalAccount
                )
                .zIndex(120)
            }

            // The unveiling: plays over the main screen at unhurried moments,
            // below onboarding/paywall, above everything else. The frame sits
            // exactly where the main screen holds it — it never moves.
            if let ceremonyLevel = presentedCeremonyLevel {
                UnveilCeremonyView(level: ceremonyLevel, coordinator: levelPainting) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        presentedCeremonyLevel = nil
                    }
                    writeSurface = .home
                    selectedTab = 0
                    // Level-up: the widget and quick action move to the new
                    // painting at 0%.
                    GlanceSyncCoordinator.sync()
                    HomeQuickActionPublisher.refresh(entitled: entitlements.isEntitledForGating)
                }
                .transition(.opacity)
                .zIndex(90)
            }

            // Phase-2 §1: the adaptive-target offer, in unhurried air only —
            // below the ceremony and every threshold surface.
            if let adaptiveOffer = presentedAdaptiveOffer {
                AdaptiveTargetOfferView(
                    offer: adaptiveOffer,
                    onLower: {
                        DailyTargetStore().applyImmediateTarget(adaptiveOffer.suggestedTargetMinutes)
                        withAnimation(.easeInOut(duration: 0.4)) {
                            presentedAdaptiveOffer = nil
                        }
                    },
                    onKeep: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            presentedAdaptiveOffer = nil
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(85)
            }

            // Phase-2 §2: the emergency breath, above the ceremony, below
            // onboarding — thirty pastel seconds, then the open day.
            if showsEmergencyBreath {
                EmergencyBreathView(
                    onComplete: completeEmergencyBreath,
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showsEmergencyBreath = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(95)
            }

            if shouldShowOnboarding {
                AnkyOnboardingView(entitlements: entitlements) {
                    finishOnboardingScreens()
                }
                .transition(.opacity)
                .zIndex(110)
            }

            // Phase-3: there is no lapsed lockout screen. A lapse is a
            // narrowing, not a death — the writer keeps the gate, the
            // passes, every free level 1–8 painting, and delivered art; the
            // veils return only over new Pro generation and Pro journeys.

            // Screen 12 of onboarding: the Day 1 threshold, laid over the
            // already-breathing writing surface. Dismissing it completes
            // onboarding and drops the writer into their first session.
            if showsDayOneOverlay {
                DayOneThresholdOverlay {
                    completeOnboarding()
                }
                .transition(.opacity)
                .zIndex(115)
            }

            // The old floating companion made the app feel noisier than the
            // ritual. Keep the dialogue transport alive for important system
            // copy, but hide the draggable character presence everywhere.
            AnkyPresenceOverlay(
                companion: ankyCompanion,
                defaultSequence: presenceSequence,
                goldenGlow: isOnWritingSurface && writeViewModel.hasReachedRitualMark,
                transformToSigil: false,
                showsPresence: false,
                placement: presencePlacement,
                bubblePlacement: selectedTab == 0 ? .top : .bottom
            )
                .zIndex(40)

        }
        .ignoresSafeArea(.keyboard)
        .statusBarHidden(shouldHideWriteSystemChrome)
        .persistentSystemOverlays(shouldHideWriteSystemChrome ? .hidden : .visible)
        .onChange(of: levelPainting.owedCeremonyAssetsReady) { ready in
            // A summoned custom painting (level 9+) just finished generating
            // while the writer waited on the home surface — play its unveiling
            // the moment the canvas is cached.
            if ready, writeSurface == .home, selectedTab == 0 {
                presentCeremonyIfOwed(unhurried: true)
            }
        }
        .fullScreenCover(isPresented: $showsSettings) {
            SettingsCoverView(
                viewModel: youViewModel,
                screenTime: writeBeforeScrollSpike,
                onReplayOnboarding: replayOnboarding
            )
            .environmentObject(entitlements)
        }
        .sheet(
            isPresented: $showsGateSetup,
            onDismiss: {
                // Screen 11 → 12: however the gate setup sheet closes
                // (Done or swipe), a first-run user crosses into Day 1.
                presentDayOneThresholdIfNeeded()
            }
        ) {
            GateSetupView(viewModel: writeBeforeScrollSpike) {
                showsGateSetup = false
            }
        }
        .sheet(isPresented: $showsReflectPaywall) {
            PaywallSheet(store: entitlements, origin: "reflection")
        }
        .overlay {
            if let pendingDraftRecovery {
                DraftRecoveryOverlay(
                    recovery: pendingDraftRecovery,
                    onResume: resumeRecoveredDraft,
                    onDiscard: { confirmsDraftDiscard = true }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .alert(AnkyLocalization.ui("Discard recovered draft?"), isPresented: $confirmsDraftDiscard) {
            Button(AnkyLocalization.ui("Discard"), role: .destructive) {
                ActiveDraftStore().clear()
                pendingDraftRecovery = nil
            }
            Button(AnkyLocalization.ui("Cancel"), role: .cancel) {}
        } message: {
            Text(AnkyLocalization.ui("This is the only copy of the interrupted writing session unless you resume it."))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardHeight = keyboardOverlap(from: notification)
            syncWriteBubble()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
            syncWriteBubble()
        }
        .onReceive(NotificationCenter.default.publisher(for: .writeBeforeScrollNotificationTapped)) { _ in
            routeToWriteBeforeScrollFromPendingIntent(trigger: "notification")
        }
        .onReceive(NotificationCenter.default.publisher(for: .ankyQuickActionTapped)) { _ in
            if let url = AnkyQuickActionRouter.consumePendingURL() {
                handleDeepLink(url)
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onAppear {
            checkForActiveDraftRecovery()
            if Self.alwaysShowsOnboardingForQA {
                onboardingCompleted = false
                showsOnboarding = true
                OnboardingFlowProgress.mark(1)
            }
            selectedTab = 0
            // Anky is an app for writing: a cold launch opens on the writing
            // surface, ready for words — written today or not (feedback
            // 2026-07-08). First run keeps .home underneath the onboarding
            // overlay; day one enters the writing surface through its own
            // threshold flow.
            if hasCompletedCurrentOnboarding {
                showGateWriteInterface()
            } else {
                writeSurface = .home
            }
            revealAfterWriting = nil
            suppressFaceIDPrivacyPromptUntilNextActivation = false
            writeViewModel.bindWriteBeforeScrollUnlockAvailabilityHandler { _ in
                writeBeforeScrollSpike.refresh()
            }
            // §5.4: Quick Pass unlocks passively the moment the sentence
            // completes — the shield opens with no button and no stillness.
            // The 15-minute window starts only when the writer leaves Anky;
            // the same handler carries the on-the-spot daily upgrade.
            // The first-gate flag stays exclusive to gate-originated sessions.
            writeViewModel.bindWriteBeforeScrollPassiveUnlockHandler { grant in
                writeBeforeScrollSpike.applyUnlock(
                    grant,
                    startsCountingOnExit: grant.tier == .quick
                )
                if writeViewModel.isGateOriginatedSession {
                    FirstGateStore().markFirstGateCompleted()
                }
            }
            // A persisted writing-sourced Daily Unlock is paid local state,
            // never entitlement proof. Invalidate it before RevenueCat's
            // fetch-current response; free Quick Pass/emergency grants stay.
            writeBeforeScrollSpike.reconcileOnAppActive(hasCurrentVerifiedPro: false)
            writeBeforeScrollSpike.handlePendingInterventionIfNeeded(showWrite: showDeepWriteInterface)
            AppOpenStore().loadOrCreate()
            let identityStore = WriterIdentityStore()
            _ = try? identityStore.loadOrCreateRecoveryPhrase()
            _ = try? identityStore.loadOrCreate()
            // The one deterministic purchases bootstrap: identity is on
            // disk by now, so RevenueCat configures under the wallet
            // address — never anonymously, never lazily from a feature
            // path. If identity failed, this no-ops (fail closed) and the
            // next foreground retries.
            Task {
                await AnkyPurchases.identifyCurrentWriter()
                entitlements.start()
                await entitlements.reconcileOnForeground()
                reconcileVerifiedSubscriptionState()
            }
            Task {
                await authenticateIfNeeded()
            }
            Task {
                await checkForICloudRestore()
            }
            presentFaceIDActivationPromptIfNeeded()
            let routedFromGateAtLaunch = routeToWriteBeforeScrollFromPendingIntent(trigger: "launch")
            // Phase-3: every gate consults the same entitlement truth.
            levelPainting.entitledForGating = entitlements.isEntitledForGating
            writeViewModel.dailyUnlockEntitled = entitlements.isEntitledForGating
            writeViewModel.serverNudgeEntitled = entitlements.isEntitledForGating
            levelPainting.refreshOnForeground()
            // Unhurried context #2: a normal app open — no gate intent, no
            // active writing. The unveiling plays before the main screen.
            if !routedFromGateAtLaunch, writeSurface == .home {
                presentCeremonyIfOwed(unhurried: true)
                presentAdaptiveOfferIfNeeded()
            }
            if let url = AnkyQuickActionRouter.consumePendingURL() {
                handleDeepLink(url)
            }
            HomeQuickActionPublisher.refresh(entitled: entitlements.isEntitledForGating)
            GlanceSyncCoordinator.sync()
            syncWriteBubble()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                checkForActiveDraftRecovery()
                // If the trial was cancelled in Settings, the reminder has
                // nothing honest left to say — this removes it. Also the
                // fail-closed retry path: a launch that couldn't load
                // identity configures RevenueCat here instead.
                Task {
                    writeBeforeScrollSpike.reconcileOnAppActive(hasCurrentVerifiedPro: false)
                    await AnkyPurchases.identifyCurrentWriter()
                    entitlements.start()
                    await entitlements.reconcileOnForeground()
                    reconcileVerifiedSubscriptionState()
                    // Phase-2 §5: the honest trial surface — evaluated only
                    // once entitlement state is fresh; ends on subscribe.
                    if #available(iOS 16.1, *) {
                        if entitlements.isEntitledForGating {
                            TrialActivityController.endAll()
                        } else {
                            TrialActivityController.evaluate(entitlements: entitlements)
                        }
                    }
                }
                GlanceSyncCoordinator.sync()
                var routedFromGate = false
                if writeSurface != .sealing {
                    writeBeforeScrollSpike.handlePendingInterventionIfNeeded(showWrite: showDeepWriteInterface)
                    routedFromGate = routeToWriteBeforeScrollFromPendingIntent(trigger: "active")
                }
                levelPainting.refreshOnForeground()
                if !routedFromGate, writeSurface == .home, selectedTab == 0 {
                    presentCeremonyIfOwed(unhurried: true)
                    presentAdaptiveOfferIfNeeded()
                }
                if faceIDLockEnabled && !isUnlocked && !isAuthenticating {
                    Task {
                        await authenticateIfNeeded()
                    }
                } else {
                    presentFaceIDActivationPromptIfNeeded()
                }
            case .background:
                if faceIDLockEnabled {
                    isUnlocked = false
                }
                // A Quick Pass earned mid-sentence opens the shield right
                // away, but its 15 minutes belong to the attempted app, not
                // time spent still writing inside Anky.
                writeBeforeScrollSpike.startPendingQuickPassWindowIfNeeded()
                // Quick Pass ends in motion: an app-switch after the passive
                // unlock seals immediately; keystrokes are never lost.
                writeViewModel.sealIfLeftInMotion()
                // Phase-2 §3: every backgrounding follows any seal or
                // level-up, so the icon's one line stays true.
                HomeQuickActionPublisher.refresh(entitled: entitlements.isEntitledForGating)
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: entitlements.verificationState) { verificationState in
            // Subscribing ends the trial surface the moment it happens.
            if verificationState.hasVerifiedPro, #available(iOS 16.1, *) {
                TrialActivityController.endAll()
            }
            // Phase-3: refresh every gate, then — race-safely — let the held
            // generation fire: pay → server-confirmed → generate → ceremony.
            let gated = entitlements.isEntitledForGating
            levelPainting.entitledForGating = gated
            writeViewModel.dailyUnlockEntitled = gated
            writeViewModel.serverNudgeEntitled = gated
            HomeQuickActionPublisher.refresh(entitled: entitlements.isEntitledForGating)
            GlanceSyncCoordinator.sync()
            if gated {
                // Entitlement landing after the day's writing still opens
                // the day: the shield must never stand over a met target.
                writeBeforeScrollSpike.reconcileDailyUnlockIfOwed(
                    hasCurrentVerifiedPro: true
                )
                Task {
                    await entitlements.identifyToBackendIfNeeded()
                    levelPainting.handleEntitlementConfirmed()
                    presentCeremonyIfOwed(unhurried: writeSurface == .home && selectedTab == 0)
                }
            }
        }
        .onChange(of: faceIDLockEnabled) { enabled in
            if enabled {
                faceIDPrivacyOnboardingCompleted = true
                faceIDPrivacyPromptPendingAfterFirstAnky = false
                faceIDPrivacyPromptReadyAfterFirstAnkyOpen = false
                if skipsNextFaceIDEnableAuthentication {
                    skipsNextFaceIDEnableAuthentication = false
                    isUnlocked = true
                } else {
                    isUnlocked = false
                    Task {
                        await authenticateIfNeeded()
                    }
                }
            } else {
                isUnlocked = true
            }
        }
        .onChange(of: writeViewModel.hasStarted) { hasStarted in
            if hasStarted {
                showsLaunchDialogue = false
                ankyCompanion.hideBubble(returningTo: .listening)
            }
            syncWriteBubble()
        }
        .onChange(of: selectedTab) { tab in
            if tab != 0 {
                if writeViewModel.hasActiveDotAnky {
                    writeViewModel.persistForNavigation()
                }
                ankyCompanion.hideBubble()
            } else if writeSurface == .sealing {
                ankyCompanion.hideBubble()
            } else {
                if preservesContinuedSessionOnNextWriteTab {
                    preservesContinuedSessionOnNextWriteTab = false
                    writeSurface = .deepWrite
                } else {
                    showsLaunchDialogue = false
                    writeSurface = .home
                }
                syncWriteBubble()
            }
        }
        .onChange(of: isUnlocked) { _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.isErrorMessageVisible) { _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.errorMessage) { _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.shouldShowNudgeDialogue) { _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.quickPassUnlockLine) { _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.nudgeMessage) { _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.isRequestingNudge) { _ in
            syncWriteBubble()
        }
        .onChange(of: faceIDPrivacyOnboardingCompleted) { _ in
            syncWriteBubble()
        }
        .alert(AnkyLocalization.text(.activateFaceID), isPresented: $showsFaceIDActivationPrompt) {
            Button(AnkyLocalization.text(.activateFaceID)) {
                Task {
                    await enableFaceIDLockFromOnboarding()
                }
            }
            Button(AnkyLocalization.text(.notNow), role: .cancel) {
                faceIDPrivacyOnboardingCompleted = true
                faceIDPrivacyPromptPendingAfterFirstAnky = false
                faceIDPrivacyPromptReadyAfterFirstAnkyOpen = false
            }
        } message: {
            Text(AnkyLocalization.text(.faceIDPrompt))
        }
    }

    /// Propagates only the fetch-current RevenueCat answer into paid client
    /// behavior. On failure this is false, which closes paid generation and
    /// removes a writing-sourced daily grant without touching free unlocks.
    private func reconcileVerifiedSubscriptionState() {
        let hasCurrentVerifiedPro = entitlements.isEntitledForGating
        levelPainting.entitledForGating = hasCurrentVerifiedPro
        writeViewModel.dailyUnlockEntitled = hasCurrentVerifiedPro
        writeViewModel.serverNudgeEntitled = hasCurrentVerifiedPro
        writeBeforeScrollSpike.reconcileOnAppActive(
            hasCurrentVerifiedPro: hasCurrentVerifiedPro
        )
        HomeQuickActionPublisher.refresh(entitled: hasCurrentVerifiedPro)
        GlanceSyncCoordinator.sync(entitled: hasCurrentVerifiedPro)
    }

    private func authenticateIfNeeded() async {
        guard faceIDLockEnabled else {
            isUnlocked = true
            return
        }
        guard !isUnlocked, !isAuthenticating else {
            return
        }

        isAuthenticating = true
        isUnlocked = false
        let ok = await BiometricAuthClient().confirm(reason: AnkyLocalization.text(.unlockFaceIDReason))
        isUnlocked = ok
        isAuthenticating = false
    }

    private func closeLaunchDialogue() {
        withAnimation(.easeOut(duration: 0.22)) {
            showsLaunchDialogue = false
        }
        ankyCompanion.hideBubble()
    }

    private func beginLaunchWriting() {
        showDeepWriteInterface()
    }

    private func beginRetryWriting() {
        showsLaunchDialogue = false
        writeSurface = .deepWrite
        writeViewModel.clearCompletedSession()
        ankyCompanion.hideBubble(returningTo: .listening)
        selectedTab = 0
        writeViewModel.openWritingPortal()
    }

    private func beginContinuingWriting(from artifact: SavedAnky) {
        showsLaunchDialogue = false
        writeSurface = .deepWrite
        revealAfterWriting = nil
        guard writeViewModel.continueSession(from: artifact) else {
            beginRetryWriting()
            return
        }

        ankyCompanion.hideBubble(returningTo: .listening)
        preservesContinuedSessionOnNextWriteTab = true
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = 0
        }
        writeViewModel.openWritingPortal()
    }

    private func resetForFreshDevelopmentLaunch() {
        selectedTab = 0
        revealAfterWriting = nil
        faceIDLockEnabled = false
        faceIDPrivacyOnboardingCompleted = false
        faceIDPrivacyPromptPendingAfterFirstAnky = false
        faceIDPrivacyPromptReadyAfterFirstAnkyOpen = false
        onboardingCompleted = false
        suppressFaceIDPrivacyPromptUntilNextActivation = false
        isUnlocked = true
        isAuthenticating = false
        skipsNextFaceIDEnableAuthentication = false
        showsLaunchDialogue = true
        writeSurface = .home
        onboardingCompletedVersion = 0
        showsOnboarding = true
        showsICloudRestorePrompt = false
        isRestoringICloudBackup = false
        iCloudRestoreErrorMessage = nil
        keyboardHeight = 0
        writeViewModel.clearCurrentSession()
        youViewModel.refresh()
        ankyCompanion.hideBubble()
        AppOpenStore().loadOrCreate()
        let identityStore = WriterIdentityStore()
        _ = try? identityStore.loadOrCreateRecoveryPhrase()
        _ = try? identityStore.loadOrCreate()
        Task {
            await AnkyPurchases.identifyCurrentWriter()
            entitlements.start()
        }
        DispatchQueue.main.async {
            syncWriteBubble()
        }
    }

    private func backUpToICloudIfEnabled() {
        Task.detached {
            ICloudBackupStore().backUpIfEnabled()
        }
    }

    private func checkForICloudRestore() async {
        guard LocalAnkyArchive().list().isEmpty,
              ReflectionStore().list().isEmpty,
              ICloudBackupStore().hasRestorableBackup() else {
            return
        }

        await MainActor.run {
            showsICloudRestorePrompt = true
            showsLaunchDialogue = false
            ankyCompanion.hideBubble()
        }
    }

    private func restoreFromICloud() {
        guard !isRestoringICloudBackup else {
            return
        }

        isRestoringICloudBackup = true
        iCloudRestoreErrorMessage = nil
        Task {
            do {
                _ = try ICloudBackupStore().restoreFromICloud()
                youViewModel.refresh()
                // A restored backup can carry a different wallet — hand
                // RevenueCat the adopted identity before anything gated.
                await AnkyPurchases.identifyCurrentWriter()
                entitlements.start()
                await entitlements.reconcileOnForeground()
                selectedTab = 0
                writeSurface = .home
                showsICloudRestorePrompt = false
                isRestoringICloudBackup = false
                ankyCompanion.hideBubble()
            } catch {
                iCloudRestoreErrorMessage = (error as? LocalizedError)?.errorDescription ?? AnkyLocalization.ui("Anky could not restore from iCloud.")
                isRestoringICloudBackup = false
            }
        }
    }

    private func createNewLocalAccount() {
        showsICloudRestorePrompt = false
        iCloudRestoreErrorMessage = nil
        showsLaunchDialogue = false
        showsOnboarding = !hasCompletedCurrentOnboarding
        syncWriteBubble()
    }

    /// Screens 1–10 are done; screen 11 is the gate setup sheet.
    /// `onboardingCompleted` stays false until the Day 1 threshold is
    /// crossed, so a relaunch mid-setup restarts the flow.
    private func finishOnboardingScreens() {
        selectedTab = 0
        writeSurface = .deepWrite
        withAnimation(.easeOut(duration: 0.18)) {
            showsOnboarding = false
        }
        showsLaunchDialogue = false
        ankyCompanion.hideBubble()
        syncWriteBubble()
        OnboardingFlowProgress.mark(12)
        showsGateSetup = true
    }

    /// Screen 12: land on the live writing surface (session opened,
    /// countdown armed) with the Day 1 threshold laid over it.
    private func presentDayOneThresholdIfNeeded() {
        guard !hasCompletedCurrentOnboarding, !showsDayOneOverlay else {
            return
        }
        revealAfterWriting = nil
        sealingArtifact = nil
        sealingUnlockGrant = nil
        showsLaunchDialogue = false
        writeSurface = .deepWrite
        selectedTab = 0
        if !writeViewModel.hasStarted {
            writeViewModel.beginBlankSessionFromWriteTab()
        }
        writeViewModel.openWritingPortal()
        ankyCompanion.hideBubble()
        syncWriteBubble()
        withAnimation(.easeOut(duration: 0.35)) {
            showsDayOneOverlay = true
        }
    }

    private func completeOnboarding() {
        onboardingCompleted = true
        onboardingCompletedVersion = Self.currentOnboardingVersion
        OnboardingFlowProgress.markFinished()
        withAnimation(.easeOut(duration: 0.25)) {
            showsDayOneOverlay = false
        }
        showsLaunchDialogue = false
        writeViewModel.focusWritingKeyboard()
        ankyCompanion.hideBubble()
        syncWriteBubble()
    }

    /// Settings → "Walk through the introduction again": drop the completed
    /// flags and re-enter the flow from the top over the home surface.
    private func replayOnboarding() {
        showsSettings = false
        onboardingCompleted = false
        onboardingCompletedVersion = 0
        selectedTab = 0
        writeSurface = .home
        showsDayOneOverlay = false
        showsGateSetup = false
        OnboardingFlowProgress.mark(1)
        withAnimation(.easeInOut(duration: 0.25)) {
            showsOnboarding = true
        }
    }

    private var shouldFocusWrite: Bool {
        selectedTab == 0
            && writeSurface == .deepWrite
            && (!faceIDLockEnabled || isUnlocked)
            && !shouldShowOnboarding
            && !showsGateSetup
            && !showsDayOneOverlay
            && !showsICloudRestorePrompt
            && pendingDraftRecovery == nil
    }

    private var shouldHideWriteSystemChrome: Bool {
        selectedTab == 0
            && writeSurface == .deepWrite
            && (!faceIDLockEnabled || isUnlocked)
            && !shouldShowOnboarding
            && !showsGateSetup
            && !showsDayOneOverlay
            && !showsICloudRestorePrompt
            && writeViewModel.hasStarted
            && !writeViewModel.isPausedOnDraft
            && !writeViewModel.isWaitingToResumeContinuedDraft
            && writeViewModel.completedArtifact == nil
    }

    private var shouldShowBottomTabBar: Bool {
        false
    }

    private var selectedTabBinding: Binding<Int> {
        Binding {
            selectedTab
        } set: { tab in
            if selectedTab != tab {
                AnkyHaptics.light()
            }
            selectedTab = tab
        }
    }

    private var shouldShowLaunchDialogue: Bool {
        showsLaunchDialogue
            && selectedTab == 0
            && writeSurface == .deepWrite
            && (!faceIDLockEnabled || isUnlocked)
            && !shouldShowOnboarding
            && !writeViewModel.hasActiveDotAnky
            && !writeViewModel.hasReachedRitualMark
            && keyboardHeight == 0
            && !shouldShowWriteErrorDialogue
    }

    /// Onboarding counts as done only when the writer finished THIS build's
    /// revision — an older completed revision (including the 0 that existing
    /// installs carry) replays the flow once.
    private var hasCompletedCurrentOnboarding: Bool {
        onboardingCompleted && onboardingCompletedVersion >= Self.currentOnboardingVersion
    }

    private var shouldShowOnboarding: Bool {
        showsOnboarding
            && !hasCompletedCurrentOnboarding
            && selectedTab == 0
            && (!faceIDLockEnabled || isUnlocked)
            && !showsICloudRestorePrompt
    }

    private var shouldShowWriteErrorDialogue: Bool {
        selectedTab == 0
            && writeSurface == .deepWrite
            && (!faceIDLockEnabled || isUnlocked)
            && writeViewModel.isErrorMessageVisible
            && writeViewModel.errorMessage != nil
    }

    private var shouldShowWriteNudgeDialogue: Bool {
        selectedTab == 0
            && writeSurface == .deepWrite
            && (!faceIDLockEnabled || isUnlocked)
            && writeViewModel.shouldShowNudgeDialogue
            && !writeViewModel.nudgeDialogueMessage.isEmpty
    }

    private var launchDialogueMessage: String {
        guard writeViewModel.todayAnkyCount > 0 else {
            return AnkyLocalization.text(.launchEmpty)
        }

        return AnkyLocalization.text(.launchCountFormat, writeViewModel.todayAnkyCount)
    }

    private func keyboardOverlap(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }

        return max(0, UIScreen.main.bounds.maxY - frame.minY)
    }

    private var presenceSequence: AnkySequenceName {
        switch selectedTab {
        case 0:
            // Never .findingThread here: those frames are independent
            // illustrations, not registered animation cels — looping them
            // makes the companion jump around. Seated is steady.
            return writeViewModel.hasReachedRitualMark ? .celebrate : .seated
        case 1:
            return .walkRight
        case 2:
            return .waveFront
        default:
            return .idleFront
        }
    }

    private var isOnWritingSurface: Bool {
        selectedTab == 0 && writeSurface == .deepWrite
    }

    /// Where the companion stands: mid-writing he drifts to the top-left
    /// (the back button's vacated corner) and witnesses from there; before
    /// the first keystroke he waits top-right, out of the pill's way.
    private var presencePlacement: AnkyPresencePlacement {
        guard isOnWritingSurface else {
            return .trailingCenter
        }
        return writeViewModel.hasStarted ? .topLeading : .topTrailing
    }

    private func syncWriteBubble() {
        guard selectedTab == 0, !faceIDLockEnabled || isUnlocked else {
            return
        }

        guard writeSurface != .sealing else {
            ankyCompanion.hideBubble()
            return
        }

        guard !shouldShowOnboarding else {
            ankyCompanion.hideBubble()
            return
        }

        if shouldShowWriteErrorDialogue, let errorMessage = writeViewModel.errorMessage {
            ankyCompanion.witness(
                mood: .concerned,
                sequence: .softConcern,
                bubble: AnkyBubble(
                    text: errorMessage,
                    close: {
                        writeViewModel.dismissCurrentPrompt()
                        ankyCompanion.hideBubble()
                    }
                )
            )
            return
        }

        // The emergency breath's promise, kept and confirmed: one line from
        // anky, then quiet.
        if let unlockedLine = emergencyUnlockedLine {
            ankyCompanion.witness(
                mood: .celebrating,
                sequence: .celebrate,
                bubble: AnkyBubble(
                    text: unlockedLine,
                    close: {
                        emergencyUnlockedLine = nil
                        ankyCompanion.hideBubble()
                    }
                )
            )
            return
        }

        // §5.4 through the companion's mouth: the passive Quick Pass unlock
        // is announced by anky, not by chrome floating over the writing.
        if isOnWritingSurface, let unlockLine = writeViewModel.quickPassUnlockLine {
            ankyCompanion.witness(
                mood: .guiding,
                sequence: .waveFront,
                bubble: AnkyBubble(
                    text: unlockLine,
                    close: {
                        writeViewModel.clearQuickPassUnlockLine()
                        ankyCompanion.hideBubble(returningTo: .listening)
                    }
                )
            )
            return
        }

        if shouldShowWriteNudgeDialogue {
            let actions = writeViewModel.isPausedOnDraft
                ? [
                    AnkyChatAction(AnkyLocalization.ui("start again"), isPrimary: true) {
                        beginRetryWriting()
                    }
                ]
                : []
            ankyCompanion.witness(
                mood: .listening,
                sequence: .shyListening,
                bubble: AnkyBubble(
                    text: writeViewModel.nudgeDialogueMessage,
                    actions: actions,
                    isThinking: writeViewModel.isRequestingNudge,
                    close: {
                        writeViewModel.dismissCurrentPrompt()
                        ankyCompanion.hideBubble(returningTo: .listening)
                    }
                )
            )
            return
        }

        if shouldShowLaunchDialogue {
            ankyCompanion.witness(
                mood: .guiding,
                sequence: .waveFront,
                bubble: AnkyBubble(
                    text: launchDialogueMessage,
                    actions: [
                        AnkyChatAction(writeViewModel.todayAnkyCount > 0 ? AnkyLocalization.text(.writeAgain) : AnkyLocalization.text(.writeMinutesFormat, AnkyDuration.completeRitualMinutes), isPrimary: true) {
                            beginLaunchWriting()
                        }
                    ],
                    steps: [
                        AnkyBubbleStep(AnkyLocalization.text(.stepWriteOneCharacter)),
                        AnkyBubbleStep(AnkyLocalization.text(.stepKeepThreadAlive)),
                        AnkyBubbleStep(AnkyLocalization.text(.stepLetSilenceCloseIt))
                    ],
                    close: closeLaunchDialogue
                )
            )
            return
        }

        if writeViewModel.hasStarted {
            ankyCompanion.witness(mood: .listening, sequence: .shyListening)
        } else {
            ankyCompanion.hideBubble()
        }
    }

    private func enableFaceIDLockFromOnboarding() async {
        guard BiometricAuthClient().canAuthenticate() else {
            faceIDPrivacyOnboardingCompleted = true
            faceIDPrivacyPromptPendingAfterFirstAnky = false
            faceIDPrivacyPromptReadyAfterFirstAnkyOpen = false
            syncWriteBubble()
            return
        }

        let confirmed = await BiometricAuthClient().confirm(reason: AnkyLocalization.text(.protectFaceIDReason))
        faceIDPrivacyOnboardingCompleted = true
        faceIDPrivacyPromptPendingAfterFirstAnky = false
        faceIDPrivacyPromptReadyAfterFirstAnkyOpen = false
        guard confirmed else {
            syncWriteBubble()
            return
        }

        isUnlocked = true
        skipsNextFaceIDEnableAuthentication = true
        faceIDLockEnabled = true
        ankyCompanion.hideBubble()
    }

    private func presentFaceIDActivationPromptIfNeeded() {
        guard !faceIDPrivacyOnboardingCompleted,
              !faceIDLockEnabled,
              !showsFaceIDActivationPrompt,
              BiometricAuthClient().canAuthenticate() else {
            return
        }
        guard SessionIndexStore().load().contains(where: { $0.isComplete }) else {
            return
        }

        DispatchQueue.main.async {
            guard !faceIDLockEnabled, !faceIDPrivacyOnboardingCompleted else {
                return
            }
            showsFaceIDActivationPrompt = true
        }
    }
}

/// Restores an interrupted writing session without exposing or discarding it silently.
private struct DraftRecoveryOverlay: View {
    let recovery: ActiveDraftRecovery
    let onResume: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Spacer(minLength: 28)

                    Image("anky-recover-writing")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 210)
                        .shadow(color: Color.ankyViolet.opacity(0.16), radius: 18, y: 8)
                        .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text(AnkyLocalization.ui("Recover writing"))
                            .font(.system(size: 34, weight: .medium, design: .serif))
                            .foregroundStyle(Color.ankyInk)
                            .multilineTextAlignment(.center)

                        Text(AnkyLocalization.ui("Your words are still here."))
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundStyle(Color.ankyInkSoft)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        Text(recovery.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.ankyInkSoft)

                        HStack(spacing: 22) {
                            Label(AnkyDuration.clock(recovery.durationMs), systemImage: "clock")
                            Label(wordCountText, systemImage: "text.word.spacing")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ankyInk)
                    }

                    Button(action: onResume) {
                        Label(AnkyLocalization.ui("Resume writing"), systemImage: "arrow.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ThreadButtonStyle())

                    Button(role: .destructive, action: onDiscard) {
                        Label(AnkyLocalization.ui("Discard draft"), systemImage: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ankyMadder)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        }
    }

    private var wordCountText: String {
        let unit = AnkyLocalization.ui(recovery.wordCount == 1 ? "word" : "words")
        return "\(recovery.wordCount) \(unit)"
    }
}

private struct SettingsCoverView: View {
    @ObservedObject var viewModel: YouViewModel
    @ObservedObject var screenTime: WriteBeforeScrollSpikeViewModel
    let onReplayOnboarding: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsGateSetup = false

    var body: some View {
        NavigationStack {
            AnkySettingsView(
                viewModel: viewModel,
                onGateSetupRequested: { showsGateSetup = true },
                onReplayOnboarding: onReplayOnboarding
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        AnkyHaptics.light()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.ankyInk)
                            .frame(width: 34, height: 38)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(AnkyLocalization.ui("Back"))
                }
            }
        }
        .background {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showsGateSetup) {
            GateSetupView(viewModel: screenTime) {
                showsGateSetup = false
            }
        }
    }
}

private enum WriteBeforeScrollReturnTarget {
    static func currentDisplayName(
        bridgeStore: WriteBeforeScrollLaunchBridgeStore = WriteBeforeScrollLaunchBridgeStore()
    ) -> String? {
        let pendingName = bridgeStore.loadPendingIntent()?.attemptedAppDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let pendingName, !pendingName.isEmpty {
            return pendingName
        }
        return bridgeStore.lastAttemptedAppDisplayName()
    }

    static func currentReturnURL() -> URL? {
        returnURL(for: currentDisplayName())
    }

    static func gateLabel() -> String {
        "go back to \(currentDisplayName() ?? "the app")"
    }

    private static func returnURL(for displayName: String?) -> URL? {
        guard let displayName else {
            return nil
        }

        let normalized = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized == "x" || normalized.contains("twitter") {
            return URL(string: "https://x.com/")
        }
        if normalized.contains("tiktok") || normalized.contains("tik tok") {
            return URL(string: "https://www.tiktok.com/")
        }
        if normalized.contains("instagram") {
            return URL(string: "https://www.instagram.com/")
        }
        if normalized.contains("youtube") {
            return URL(string: "https://www.youtube.com/")
        }
        if normalized.contains("reddit") {
            return URL(string: "https://www.reddit.com/")
        }
        if normalized.contains("facebook") {
            return URL(string: "https://www.facebook.com/")
        }
        if normalized.contains("threads") {
            return URL(string: "https://www.threads.net/")
        }
        if normalized.contains("snapchat") {
            return URL(string: "https://www.snapchat.com/")
        }
        return nil
    }
}

private struct PostSessionSealingView: View {
    private enum Phase: Int {
        /// The writer's own words, returned to them on the mirror, with the
        /// slide-to-reflect control. Nothing has left the device here.
        case writing
        /// The reflection streaming onto the mirror after the slide.
        case mirror
        /// The closing beat — unlock / continue / done.
        case gate
    }

    @StateObject private var mirrorViewModel: RevealViewModel
    @State private var phase: Phase = .writing
    @State private var didStart = false
    @State private var mirrorResolved = false
    @State private var didAttemptReflection = false
    @State private var isFirstGate = false
    @State private var showsPaywallSheet = false
    @State private var paywallOrigin = "reflection"
    @EnvironmentObject private var entitlements: EntitlementStore

    private let artifact: SavedAnky
    private let unlockGrant: UnlockGrant?
    private let isGateOriginated: Bool
    private let showsFreeTargetMoment: Bool
    private let quickPassesRemaining: Int
    private let onMomentShown: () -> Void
    private let onEmergency: () -> Void
    private let onUnlock: () -> Void
    private let onDone: () -> Void
    private let onStay: () -> Void
    /// The on-surface beat already played the slide: open on the mirror and
    /// send at once, skipping the (now-retired) in-flow writing recap.
    private let startsAtMirror: Bool

    init(
        artifact: SavedAnky,
        unlockGrant: UnlockGrant?,
        isGateOriginated: Bool = false,
        showsFreeTargetMoment: Bool = false,
        startsAtGate: Bool = false,
        startsAtMirror: Bool = false,
        quickPassesRemaining: Int = UnlockPolicy.quickPassDailyAllowance,
        onMomentShown: @escaping () -> Void = {},
        onEmergency: @escaping () -> Void = {},
        onUnlock: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onStay: @escaping () -> Void
    ) {
        self.artifact = artifact
        self.unlockGrant = unlockGrant
        self.isGateOriginated = isGateOriginated
        self.showsFreeTargetMoment = showsFreeTargetMoment
        self.startsAtMirror = startsAtMirror
        self.quickPassesRemaining = quickPassesRemaining
        self.onMomentShown = onMomentShown
        self.onEmergency = onEmergency
        self.onUnlock = onUnlock
        self.onDone = onDone
        self.onStay = onStay
        // Entry phase: the writer reflected on the writing surface → mirror;
        // re-entry from a continued session's back button → gate; otherwise
        // the legacy in-flow writing beat.
        _phase = State(initialValue: startsAtMirror ? .mirror : (startsAtGate ? .gate : .writing))
        _mirrorViewModel = StateObject(wrappedValue: RevealViewModel(artifact: artifact))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SealingBackground()

                if phase == .writing {
                    SealingWritingBeatView(
                        writing: artifact.reconstructedText,
                        onReflect: onReflectSlideCompleted,
                        onContinueWriting: onStay,
                        onSkip: skipReflection
                    )
                    .padding(.top, max(geometry.safeAreaInsets.top, 18))
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 18))
                    .transition(.opacity)
                } else if isReadingChamber {
                    // P0-2: the wait after sliding to send is a decompression
                    // chamber, not a spinner. It crossfades to the reflection
                    // the moment the first token streams (isReadingChamber flips
                    // false once streamingReflectionMarkdown fills).
                    AnkyReadingChamber(
                        wordCount: mirrorViewModel.wordCount,
                        durationText: readingDurationText
                    )
                    // Full-bleed: no safe-area padding — the chamber's own
                    // background runs edge to edge under the status bar and home
                    // indicator; its content stays centered via internal spacers.
                    .transition(.opacity)
                } else {
                    MirrorAndGateBeatView(
                        reflectionText: reflectionText,
                        didFailReflection: didFailReflection,
                        showsReflectionVeil: false,
                        gateTitle: gateTitle,
                        firstGateLine: firstGateLine,
                        showsGate: phase == .gate,
                        freeTargetMoment: showsFreeTargetMoment,
                        showsEmergencyLink: quickPassesRemaining <= 0,
                        onMomentSubscribe: {
                            paywallOrigin = "free_target_moment"
                            showsPaywallSheet = true
                        },
                        onEmergency: onEmergency,
                        onGate: unlockGrant == nil ? onDone : onUnlock
                    )
                    .padding(.top, max(geometry.safeAreaInsets.top, 18))
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 18))
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.55), value: isReadingChamber)
        }
        .sheet(isPresented: $showsPaywallSheet) {
            PaywallSheet(store: entitlements, origin: paywallOrigin)
        }
        .onAppear(perform: startIfNeeded)
    }

    /// P0-2: true while the mirror is being asked but nothing has streamed
    /// back yet — the beat that becomes the reading chamber. Flips false the
    /// moment the first reflection token lands (or the request resolves), which
    /// crossfades the chamber into the streaming reflection.
    private var isReadingChamber: Bool {
        phase == .mirror
            && didAttemptReflection
            && !mirrorResolved
            && mirrorViewModel.reflection == nil
            && mirrorViewModel.streamingReflectionMarkdown
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A friendly whole-minute phrasing for the acknowledgment line
    /// ("You wrote 847 words in 8 minutes") — the raw `AnkyDuration.formatted`
    /// ("8m 03s") reads wrong inside a sentence.
    private var readingDurationText: String {
        let minutes = max(1, Int((Double(artifact.durationMs) / 60_000.0).rounded()))
        return minutes == 1
            ? AnkyLocalization.ui("1 minute")
            : AnkyLocalization.ui("%d minutes", minutes)
    }

    private var reflectionText: String {
        if let reflection = mirrorViewModel.reflection?.reflection.trimmingCharacters(in: .whitespacesAndNewlines),
           !reflection.isEmpty {
            return Self.dedupedReflection(reflection)
        }

        let streaming = mirrorViewModel.streamingReflectionMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !streaming.isEmpty {
            // P0-1: the accumulated buffer only ever grows — render it as-is so
            // the text streams monotonically. `dedupedReflection` strips heading
            // echoes and repeated openings by scanning the *whole* text, which
            // is non-monotonic mid-stream (a line present one tick is removed the
            // next) and reads as paragraphs flashing in and out. Dedup belongs to
            // the finished reflection above, applied once when it resolves.
            return streaming
        }

        // Actively reflecting but nothing has streamed yet: the indicator
        // carries the moment — don't flash the closing line.
        if didAttemptReflection && !mirrorResolved {
            return ""
        }

        return AnkyLocalization.ui("Sealed. Words kept.")
    }

    private var didFailReflection: Bool {
        didAttemptReflection
            && mirrorResolved
            && !reflectionVeiled
            && mirrorViewModel.reflection == nil
            && mirrorViewModel.streamingReflectionMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Phase-3 §3: free sessions never ask the mirror — where the reflection
    /// would bloom, the veil. Quick Pass included: the pass, the unlock, the
    /// seconds, and the strokes are all still granted.
    private var reflectionVeiled: Bool {
        !entitlements.isEntitledForGating && mirrorViewModel.reflection == nil
    }

    private var gateTitle: String {
        guard unlockGrant != nil else {
            return AnkyLocalization.ui("Done")
        }
        // Contextual only when the session came through the gate — closing
        // the loop fast. Organic sessions keep the normal copy.
        return isGateOriginated
            ? WriteBeforeScrollReturnTarget.gateLabel()
            : AnkyLocalization.ui("Continue")
    }

    private var firstGateLine: String? {
        guard isFirstGate, unlockGrant != nil else {
            return nil
        }
        return AnkyLocalization.ui("You just wrote before you scrolled.\nThat is the whole practice.")
    }

    private func startIfNeeded() {
        guard !didStart else {
            return
        }
        didStart = true
        isFirstGate = unlockGrant != nil && !FirstGateStore().hasCompletedFirstGate
        dismissKeyboard()
        // Load the accent color and any reflection ALREADY cached on this
        // device. This never sends the writing anywhere — the artifact only
        // leaves the phone when the writer completes the slide below.
        Task {
            await mirrorViewModel.prepareAfterFirstRender()
            // The writer already completed the slide on the writing surface
            // (entitlement was checked there): send now — the cached reflection,
            // if any, resolves in prepareAfterFirstRender just above.
            if startsAtMirror {
                await MainActor.run { onReflectSlideCompleted() }
            }
        }
    }

    /// The writer completed the slide — the single deliberate act that lets
    /// their writing leave the device. A free writer meets the offer instead;
    /// nothing is sent until they choose to subscribe.
    private func onReflectSlideCompleted() {
        guard entitlements.isEntitledForGating else {
            paywallOrigin = "reflection"
            showsPaywallSheet = true
            return
        }
        // A reflection already cached on device (e.g. a re-entered session):
        // reveal it, don't ask again.
        if mirrorViewModel.reflection != nil {
            mirrorResolved = true
            withAnimation(.easeInOut(duration: 0.6)) {
                phase = .gate
            }
            if showsFreeTargetMoment {
                onMomentShown()
            }
            return
        }
        didAttemptReflection = true
        mirrorResolved = false
        withAnimation(.easeInOut(duration: 0.6)) {
            phase = .mirror
        }
        Task {
            await mirrorViewModel.askAnkyForSealedSession()
            await MainActor.run {
                mirrorResolved = true
                showGate()
            }
        }
    }

    /// The writer chose not to reflect — close the loop with their words never
    /// having left the device.
    private func skipReflection() {
        showGate()
    }

    private func showGate() {
        withAnimation(.easeInOut(duration: 0.72)) {
            phase = .gate
        }
        if showsFreeTargetMoment {
            onMomentShown()
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private static func remainingTargetMs(
        for artifact: SavedAnky,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int64 {
        let targetMs = DailyTargetStore().effectiveTargetMs(now: now, calendar: calendar)
        return max(0, targetMs - artifact.durationMs)
    }

    private static func clock(_ durationMs: Int64) -> String {
        let totalSeconds = max(0, durationMs / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }

    private static func dedupedReflection(_ text: String) -> String {
        removingRepeatedOpening(from: removingHeadingEcho(from: text))
    }

    /// The mirror titles some reflections with their own first words —
    /// `# That's a very direct preface.` followed by a body that opens with
    /// the same sentence. A heading the body immediately repeats says
    /// nothing twice; it goes.
    private static func removingHeadingEcho(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstLine = lines.first, firstLine.hasPrefix("#") else {
            return trimmed
        }
        let headingText = firstLine
            .drop(while: { $0 == "#" })
            .trimmingCharacters(in: .whitespaces)
        let body = lines.dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headingText.isEmpty, !body.isEmpty,
              normalizedOpening(body).hasPrefix(normalizedOpening(headingText)) else {
            return trimmed
        }
        return body
    }

    private static func normalizedOpening(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func removingRepeatedOpening(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { return trimmed }

        let maxPrefixLength = min(trimmed.count / 2, 140)
        guard maxPrefixLength >= 20 else { return trimmed }

        for length in stride(from: maxPrefixLength, through: 20, by: -1) {
            let firstEnd = trimmed.index(trimmed.startIndex, offsetBy: length)
            let prefix = trimmed[..<firstEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = trimmed[firstEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty, rest.hasPrefix(prefix) {
                return rest
            }
        }

        return trimmed
    }
}

/// The mirror after a session: the writer's own words returned to them, with
/// the slide-to-reflect control beneath. The writing never leaves the device
/// from here — only a completed slide sends it.
private struct SealingWritingBeatView: View {
    let writing: String
    let onReflect: () -> Void
    let onContinueWriting: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            // The mirror: their own words, held in the frame.
            ScrollView(showsIndicators: false) {
                Text(displayWriting)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInk)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.ankyPaper.opacity(0.55))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.ankyGold.opacity(0.18), lineWidth: 0.7)
                    )
            )
            .shadow(color: Color.ankyViolet.opacity(0.12), radius: 16, y: 6)

            SlideToReflect(label: "slide to reflect", onComplete: onReflect)
                .padding(.horizontal, 2)

            HStack(spacing: 24) {
                Button(action: onContinueWriting) {
                    Text(AnkyLocalization.ui("continue writing"))
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft)
                        .underline()
                }
                .buttonStyle(.plain)

                Button(action: onSkip) {
                    Text(AnkyLocalization.ui("skip"))
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.78))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    private var displayWriting: String {
        let trimmed = writing.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AnkyLocalization.ui("Sealed. Words kept.") : trimmed
    }
}

/// The single deliberate act that lets a writer's words leave the device: a
/// left-to-right slide, ticking a soft haptic as it travels, sending only
/// when it completes past the threshold. Until then, nothing is transmitted.
/// Shared by the post-session action bar (on the writing surface) and the
/// re-entry sealing flow. Internal, not private, so `WriteView` can host it.
struct SlideToReflect: View {
    let label: String
    let onComplete: () -> Void

    @State private var dragX: CGFloat = 0
    @State private var completed = false
    @State private var lastTickStep = 0

    private let knob: CGFloat = 52
    private let inset: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - knob - inset * 2)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.ankyInk.opacity(0.07))
                    .overlay(Capsule().strokeBorder(Color.ankyGold.opacity(0.30), lineWidth: 0.5))

                Text(AnkyLocalization.ui(label))
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(maxWidth: .infinity)
                    .opacity(0.9 * Double(1 - min(1, dragX / travel)))

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.ankyGoldLight, Color.ankyGold],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(Circle().strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                        .shadow(color: Color.ankyViolet.opacity(0.18), radius: 8, y: 3)
                    Image(systemName: completed ? "checkmark" : "arrow.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.ankyInk)
                }
                .frame(width: knob, height: knob)
                .offset(x: inset + dragX)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !completed else { return }
                            let x = min(max(0, value.translation.width), travel)
                            dragX = x
                            let step = Int(x / 20)
                            if step != lastTickStep {
                                lastTickStep = step
                                UIImpactFeedbackGenerator(style: .soft)
                                    .impactOccurred(intensity: 0.35 + 0.5 * Double(x / travel))
                            }
                        }
                        .onEnded { _ in
                            guard !completed else { return }
                            if dragX >= travel * 0.9 {
                                completed = true
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                                    dragX = travel
                                }
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                onComplete()
                                // Ready the control again for the free-writer
                                // paywall bounce; if we advanced past .writing
                                // this view is already gone.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    completed = false
                                    lastTickStep = 0
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                        dragX = 0
                                    }
                                }
                            } else {
                                lastTickStep = 0
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                    dragX = 0
                                }
                            }
                        }
                )
            }
        }
        .frame(height: knob + inset * 2)
    }
}

private struct MirrorAndGateBeatView: View {
    let reflectionText: String
    let didFailReflection: Bool
    var showsReflectionVeil: Bool = false
    var onVeilTap: () -> Void = {}
    let gateTitle: String
    let firstGateLine: String?
    let showsGate: Bool
    var freeTargetMoment: Bool = false
    var showsEmergencyLink: Bool = false
    var onMomentSubscribe: () -> Void = {}
    var onEmergency: () -> Void = {}
    let onGate: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 54)

                if showsReflectionVeil {
                    // The reflection-shaped card under the parchment mist —
                    // one tap from the paywall, never a dead end.
                    VeiledFeature(
                        surface: "reflection",
                        message: AnkyCopyRegistry.veilReflection,
                        onTap: onVeilTap
                    ) {
                        ReflectionGhost()
                    }
                    .frame(height: 235)
                    .frame(maxWidth: .infinity)
                } else {
                    // The pre-stream wait is handled upstream by the reading
                    // chamber (P0-2); by the time this beat shows, the reflection
                    // is streaming or resolved — no spinner here.
                    RawReflectionMarkdownText(
                        markdown: reflectionText,
                        didFailReflection: didFailReflection
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)

                    if didFailReflection {
                        FounderContactLine()
                            .transition(.opacity)
                    }
                }

                if showsGate, freeTargetMoment {
                    freeTargetMomentBlock
                } else if showsGate {
                    VStack(spacing: 13) {
                        if let firstGateLine {
                            Text(firstGateLine)
                                .font(.system(size: 15, weight: .medium, design: .serif))
                                .foregroundStyle(Color.ankyViolet.opacity(0.92))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity)
                                .transition(.opacity)
                        }

                        AnkyPrimaryButton(gateTitle, action: onGate)

                    }
                    .padding(.top, 10)
                    .transition(.opacity)
                }

                Spacer(minLength: 34)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    /// Decision 2026-07-06 (option C): the free writer's target moment —
    /// acknowledgment first, the subscriber fact second, the trial as an
    /// open door. Dismissible in one tap; with no passes left the emergency
    /// breath stays quietly visible so there is always a free way forward.
    private var freeTargetMomentBlock: some View {
        VStack(spacing: 14) {
            Text(AnkyLocalization.ui(AnkyCopyRegistry.freeTargetMomentTitle))
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(AnkyLocalization.ui(AnkyCopyRegistry.freeTargetMomentLine))
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: .infinity)

            Text(AnkyLocalization.ui(AnkyCopyRegistry.freeTargetMomentSubscriberLine))
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(Color.ankyViolet.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: .infinity)

            AnkyPrimaryButton(AnkyCopyRegistry.freeTargetMomentCTA, action: onMomentSubscribe)

            if showsEmergencyLink {
                Button(action: onEmergency) {
                    Text(AnkyLocalization.ui(AnkyCopyRegistry.emergencyLink))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.75))
                }
                .buttonStyle(.plain)
            }

            Button(action: onGate) {
                Text(AnkyLocalization.ui(AnkyCopyRegistry.freeTargetMomentDismiss))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
        .transition(.opacity)
    }
}

/// P0-2: the decompression chamber.
///
/// The writer just emptied themselves for eight minutes and slid to send. This
/// is where they land while Anky reads — not a spinner, a held breath. A
/// full-bleed lazure ground, the Anky character breathing in the lower third,
/// one line naming what just happened, and a slow rotation of witness-lines
/// beneath it. It holds until the reflection begins to stream, then crossfades
/// away. Serif is New York (`design: .serif`) — the app's Fraunces stand-in,
/// since Fraunces is not bundled.
private struct AnkyReadingChamber: View {
    let wordCount: Int
    let durationText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breatheIn = false
    @State private var witnessIndex = 0

    /// Quiet, not mystical-kitsch — the register of a witness, not an oracle.
    private static let witnessLines: [String] = [
        "Nothing you wrote is wasted.",
        "It stays between you two.",
        "No one else will ever read this.",
        "You showed up. That is the whole practice.",
        "The page kept every word.",
        "This was yours before it was anything.",
        "Whatever it was, it is out of you now.",
        "You met yourself for eight minutes."
    ]

    private let rotation = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 16) {
                    Text(acknowledgment)
                        .font(.fraunces(20, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(Color.ankyInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AnkyLocalization.ui(Self.witnessLines[witnessIndex]))
                        .font(.fraunces(16, weight: .regular))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .id(witnessIndex)
                        .transition(.opacity)
                }
                .padding(.horizontal, 40)

                Spacer(minLength: 32)

                // Lower third: the character, breathing.
                ankyImage
                    .frame(height: 200)
                    .scaleEffect(breatheIn ? 1.03 : 1.0)
                    .opacity(breatheIn ? 1.0 : 0.9)
                    .shadow(color: Color.ankyGold.opacity(0.18), radius: 22, y: 10)
                    .accessibilityHidden(true)

                Spacer(minLength: 40)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                breatheIn = true
            }
        }
        .onReceive(rotation) { _ in
            withAnimation(.easeInOut(duration: 0.9)) {
                witnessIndex = (witnessIndex + 1) % Self.witnessLines.count
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(acknowledgment)
    }

    private var acknowledgment: String {
        AnkyLocalization.ui(
            "You wrote %d words in %@. Anky is reading them now.",
            wordCount,
            durationText
        )
    }

    @ViewBuilder
    private var ankyImage: some View {
        Image("anky-reading")
            .resizable()
            .scaledToFit()
    }

    @ViewBuilder
    private var background: some View {
        if let image = UIImage(named: "ReadingScreenBackground") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            // Soft violet→gold lazure placeholder until the asset lands.
            LinearGradient(
                colors: [
                    Color.ankyViolet.opacity(0.16),
                    Color.ankyPaper,
                    Color.ankyGoldLight.opacity(0.30)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct ReflectionMarkdownBlock: Equatable {
    enum Kind: Equatable {
        case heading(level: Int)
        case paragraph
        case quote
        case bullet
        case numbered(marker: String)
        case rule
    }

    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [ReflectionMarkdownBlock] {
        markdown.softWrappedMarkdownForDisplay()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { block(from: String($0).trimmingCharacters(in: .whitespaces)) }
    }

    private static func block(from line: String) -> ReflectionMarkdownBlock? {
        guard !line.isEmpty else { return nil }

        for (marker, level) in [("### ", 3), ("## ", 2), ("# ", 1)] {
            if line.hasPrefix(marker) {
                return ReflectionMarkdownBlock(
                    kind: .heading(level: level),
                    text: String(line.dropFirst(marker.count))
                )
            }
        }

        if line == "---" || line == "***" || line == "___" || line == "\u{2014}" {
            return ReflectionMarkdownBlock(kind: .rule, text: "")
        }
        if line.hasPrefix(">") {
            return ReflectionMarkdownBlock(
                kind: .quote,
                text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            )
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return ReflectionMarkdownBlock(kind: .bullet, text: String(line.dropFirst(2)))
        }
        if let dot = line.firstIndex(of: ".") {
            let number = line[..<dot]
            let textStart = line.index(after: dot)
            if !number.isEmpty,
               number.allSatisfy(\.isNumber),
               textStart < line.endIndex,
               line[textStart] == " " {
                return ReflectionMarkdownBlock(
                    kind: .numbered(marker: "\(number)."),
                    text: String(line[line.index(after: textStart)...])
                )
            }
        }
        return ReflectionMarkdownBlock(kind: .paragraph, text: line)
    }
}

private struct RawReflectionMarkdownText: View {
    let markdown: String
    let didFailReflection: Bool
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 18
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 28

    private var blocks: [ReflectionMarkdownBlock] {
        ReflectionMarkdownBlock.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
                    .padding(.bottom, spacing(after: block))
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: ReflectionMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(inlineMarkdown(block.text))
                .font(.system(
                    size: headingSize(level: level),
                    weight: level == 1 ? .bold : .semibold,
                    design: .serif
                ))
                .foregroundStyle(Color.ankyViolet)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph:
            prose(block.text)
        case .quote:
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Color.ankyGold.opacity(0.72))
                    .frame(width: 2)
                Text(inlineMarkdown(block.text))
                    .font(.system(size: bodySize, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(Color.ankyInkSoft)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .bullet:
            listRow(marker: "•", text: block.text)
        case .numbered(let marker):
            listRow(marker: marker, text: block.text)
        case .rule:
            Rectangle()
                .fill(Color.ankyInk.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 5)
        }
    }

    private func prose(_ text: String) -> some View {
        Text(inlineMarkdown(text))
            .font(.system(size: didFailReflection ? bodySize - 1 : bodySize, weight: .regular, design: .serif))
            .foregroundStyle(didFailReflection ? Color.ankyInkSoft : Color.ankyInk)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(marker)
                .font(.system(size: bodySize, weight: .semibold, design: .serif))
                .foregroundStyle(Color.ankyViolet)
                .frame(width: 24, alignment: .trailing)
            Text(inlineMarkdown(text))
                .font(.system(size: bodySize, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInk)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func headingSize(level: Int) -> CGFloat {
        switch level {
        case 1: return titleSize
        case 2: return max(bodySize + 4, titleSize - 4)
        default: return max(bodySize + 2, titleSize - 7)
        }
    }

    private func spacing(after block: ReflectionMarkdownBlock) -> CGFloat {
        switch block.kind {
        case .heading: return 14
        case .paragraph, .quote: return 18
        case .bullet, .numbered: return 9
        case .rule: return 12
        }
    }
}

private struct SealingBackground: View {
    var body: some View {
        // The sealing is an evening-mood moment: a violet-forward lazure wash.
        LazureWall(mood: .dusk)
    }
}

private struct AnkyBottomTabBar: View {
    @Binding var selection: Int

    private let tabs: [AnkyBottomTab] = [
        AnkyBottomTab(index: 0, title: .tabWrite, systemImage: "square.and.pencil"),
        AnkyBottomTab(index: 1, title: .tabMap, systemImage: "map.fill"),
        AnkyBottomTab(index: 2, title: .tabYou, systemImage: "person.crop.circle.fill")
    ]

    var body: some View {
        GeometryReader { geometry in
            let width = min(max(geometry.size.width - 88, 0), 360)
            let height: CGFloat = 74
            let bottomPadding = max(18, geometry.safeAreaInsets.bottom + 8)

            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    Button {
                        guard selection != tab.index else {
                            return
                        }
                        AnkyHaptics.light()
                        selection = tab.index
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 27, weight: .semibold))
                                .symbolRenderingMode(.monochrome)

                            Text(AnkyLocalization.text(tab.title))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(selection == tab.index ? AnkyBottomTabPalette.selected : AnkyBottomTabPalette.unselected)
                        .shadow(
                            color: selection == tab.index ? Color.ankyViolet.opacity(0.30) : Color.ankyViolet.opacity(0),
                            radius: 6, y: 1
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if selection == tab.index {
                                Capsule()
                                    .fill(AnkyBottomTabPalette.selectionFill)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AnkyLocalization.text(tab.title))
                    .accessibilityAddTraits(selection == tab.index ? .isSelected : [])
                }
            }
            .padding(6)
            .frame(width: width, height: height)
            .background {
                Capsule()
                    .fill(AnkyBottomTabPalette.background)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(AnkyBottomTabPalette.border, lineWidth: 0.5)
                    )
                    .shadow(color: Color.ankyViolet.opacity(0.16), radius: 16, y: 6)
            }
            .position(
                x: geometry.size.width / 2,
                y: geometry.size.height - bottomPadding - height / 2
            )
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct AnkyBottomTab: Identifiable {
    let index: Int
    let title: AnkyLocalizedKey
    let systemImage: String

    var id: Int {
        index
    }
}

private enum AnkyBottomTabPalette {
    static let selected = Color.ankyGold
    static let unselected = Color.ankyInkSoft
    static let background = Color.ankyPaper.opacity(0.82)
    static let selectionFill = Color.ankyViolet.opacity(0.12)
    static let border = Color.ankyInk.opacity(0.08)
}

private struct LockFailureView: View {
    let retry: () -> Void

    var body: some View {
        ZStack {
            LazureWall(mood: .dusk)

            GeometryReader { geometry in
                Image("tellmewhoyouare")
                    .resizable()
                    .scaledToFit()
                    .frame(height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .ignoresSafeArea()

        }
        .contentShape(Rectangle())
        .onTapGesture {
            retry()
        }
    }
}

private struct AppBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.ankyInk)
                .frame(width: 48, height: 48)
                .background(Color.ankyPaper.opacity(0.55), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                .shadow(color: Color.ankyViolet.opacity(0.16), radius: 14, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AnkyLocalization.ui("Back to today"))
    }
}

private struct ICloudRestorePromptView: View {
    let isRestoring: Bool
    let errorMessage: String?
    let restore: () -> Void
    let createNew: () -> Void

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)

            Image("you-bg-cosmos")
                .resizable()
                .scaledToFill()
                .opacity(0.10)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Image("AnkySigil")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .shadow(color: AnkyTheme.gold.opacity(0.28), radius: 18)

                VStack(spacing: 10) {
                    Text(AnkyLocalization.ui("I remember you."))
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(AnkyTheme.goldBright)
                        .multilineTextAlignment(.center)

                    Text(AnkyLocalization.ui("An encrypted Anky backup is waiting in iCloud."))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AnkyTheme.text.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                if let errorMessage {
                    Text(AnkyLocalization.ui(errorMessage))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AnkyTheme.danger.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 10)
                }

                AnkyPrimaryButton(
                    isRestoring ? "Restoring" : "Restore From iCloud",
                    isLoading: isRestoring,
                    action: restore
                )
                .padding(.top, 8)

                Button(AnkyLocalization.ui("Create new account"), action: createNew)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AnkyTheme.text.opacity(0.62))
                    .disabled(isRestoring)

                Spacer()
            }
            .padding(.horizontal, 34)
        }
    }
}
