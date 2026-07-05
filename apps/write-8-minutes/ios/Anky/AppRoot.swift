import SwiftUI
import StoreKit
import UIKit

struct AppRoot: View {
    /// QA override: resets `anky.onboardingCompleted` on every launch so
    /// the full 13-screen flow can be walked repeatedly. MUST be set back
    /// to false before shipping a build.
    ///
    /// Its sibling lives in EntitlementStore.ignoresEntitlementForQA:
    /// purchases persist across onboarding re-runs, so without it QA
    /// walkthroughs jump over the paywall after the first test purchase.
    /// Both flags MUST be false before shipping.
    private static let alwaysShowsOnboardingForQA = true

    private enum WriteSurface {
        case home
        case checkIn
        case deepWrite
        case sealing
    }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("anky.biometricIdentityConfirmation") private var faceIDLockEnabled = false
    @AppStorage("anky.biometricPrivacyOnboardingCompleted") private var faceIDPrivacyOnboardingCompleted = false
    @AppStorage("anky.biometricPrivacyPromptPendingAfterFirstAnky") private var faceIDPrivacyPromptPendingAfterFirstAnky = false
    @AppStorage("anky.biometricPrivacyPromptReadyAfterFirstAnkyOpen") private var faceIDPrivacyPromptReadyAfterFirstAnkyOpen = false
    @AppStorage("anky.skipNextFaceIDEnableAuthentication") private var skipsNextFaceIDEnableAuthentication = false
    @AppStorage("anky.onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("anky.didRequestReviewAfterFirstSeal") private var didRequestReviewAfterFirstSeal = false
    @Environment(\.requestReview) private var requestReview
    @State private var showsDayOneOverlay = false
    @State private var selectedTab = 0
    @State private var revealAfterWriting: SavedAnky?
    @State private var sealingArtifact: SavedAnky?
    @State private var sealingUnlockGrant: UnlockGrant?
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

    /// The main screen IS the painting: closing any surface lands on it.
    private func showMap() {
        selectedTab = 0
        writeSurface = .home
        ankyCompanion.hideBubble()
    }

    private func showArchive(date: Date? = nil) {
        archiveDate = date
        archiveRevealArtifact = nil
        selectedTab = 3
        writeSurface = .home
        ankyCompanion.hideBubble()
    }

    private func showArchiveReveal(_ artifact: SavedAnky) {
        archiveRevealArtifact = artifact
        selectedTab = 5
        writeSurface = .home
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
        ankyCompanion.hideBubble()
    }

    private func showProfile() {
        selectedTab = 2
        writeSurface = .home
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
        // A Quick Pass applied passively mid-session already consumed its
        // pass and cleared the shield — never spend a second pass here.
        if grant.tier == .quick, writeViewModel.hasAppliedPassiveQuickUnlock {
            FirstGateStore().markFirstGateCompleted()
            return
        }
        writeBeforeScrollSpike.applyUnlock(grant)
        FirstGateStore().markFirstGateCompleted()
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
        selectedTab = 0
        showsLaunchDialogue = false
        writeSurface = .sealing
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
        Task.detached(priority: .utility) {
            guard let identity = try? WriterIdentityStore().loadOrCreate() else { return }
            try? await LevelSyncClient().reportEmergencyUnlock(identity: identity)
        }
    }

    private func stayAfterSealing() {
        sealingArtifact = nil
        sealingUnlockGrant = nil
        revealAfterWriting = nil
        writeViewModel.beginBlankSessionFromWriteTab()
        showsLaunchDialogue = false
        writeSurface = .deepWrite
        selectedTab = 0
        ankyCompanion.hideBubble()
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
                    NavigationStack {
                        Group {
                            switch writeSurface {
                            case .home:
                                PaintingHomeView(
                                    screenTime: writeBeforeScrollSpike,
                                    onWrite: showGateWriteInterface,
                                    onSetup: { showsGateSetup = true },
                                    onSettings: { showsSettings = true },
                                    onHistory: { showArchive() },
                                    onYou: showProfile,
                                    onEmergency: {
                                        withAnimation(.easeInOut(duration: 0.35)) {
                                            showsEmergencyBreath = true
                                        }
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
                                        showMap()
                                    }
                                )
                            case .sealing:
                                if let sealingArtifact {
                                    PostSessionSealingView(
                                        artifact: sealingArtifact,
                                        unlockGrant: sealingUnlockGrant,
                                        isGateOriginated: writeViewModel.isGateOriginatedSession,
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
                    NavigationStack {
                        ArchiveChamberView(
                            selectedDate: archiveDate,
                            onOpenAnky: showArchiveReveal,
                            onBack: showHomeChamber
                        )
                    }
                case 5:
                    ZStack(alignment: .topLeading) {
                        if let artifact = archiveRevealArtifact {
                            NavigationStack {
                                RevealView(
                                    viewModel: RevealViewModel(artifact: artifact),
                                    onDeleted: {
                                        showArchive(date: archiveDate)
                                    },
                                    onTryAgain: {
                                        beginContinuingWriting(from: artifact)
                                    },
                                    onReflectionReady: backUpToICloudIfEnabled
                                )
                            }
                        } else {
                            ArchiveChamberView(
                                selectedDate: archiveDate,
                                onOpenAnky: showArchiveReveal
                            )
                        }
                        AppBackButton(action: { showArchive(date: archiveDate) })
                            .padding(.leading, 18)
                            .padding(.top, 64)
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
            // passes, every second, and their level-2 painting; the veils
            // return over reflections, the journey, and the next ceremony.

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

            if shouldShowPresenceOverlay {
                AnkyPresenceOverlay(
                    companion: ankyCompanion,
                    defaultSequence: presenceSequence,
                    goldenGlow: selectedTab == 0 && writeViewModel.hasReachedRitualMark,
                    transformToSigil: selectedTab == 0 && writeViewModel.hasStarted && !writeViewModel.hasReachedRitualMark,
                    placement: selectedTab == 0 ? .topTrailing : .trailingCenter,
                    bubblePlacement: selectedTab == 0 ? .top : .bottom
                )
                    .zIndex(40)
            }

        }
        .ignoresSafeArea(.keyboard)
        .statusBarHidden(shouldHideWriteSystemChrome)
        .persistentSystemOverlays(shouldHideWriteSystemChrome ? .hidden : .visible)
        .fullScreenCover(isPresented: $showsSettings) {
            SettingsCoverView(
                viewModel: youViewModel,
                screenTime: writeBeforeScrollSpike
            )
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
            if Self.alwaysShowsOnboardingForQA {
                onboardingCompleted = false
                showsOnboarding = true
                OnboardingFlowProgress.mark(1)
            }
            selectedTab = 0
            writeSurface = .home
            revealAfterWriting = nil
            suppressFaceIDPrivacyPromptUntilNextActivation = false
            writeViewModel.bindWriteBeforeScrollUnlockAvailabilityHandler { _ in
                writeBeforeScrollSpike.refresh()
            }
            // §5.4: Quick Pass unlocks passively the moment the sentence
            // completes — the shield opens with no button and no stillness.
            writeViewModel.bindWriteBeforeScrollPassiveUnlockHandler { grant in
                writeBeforeScrollSpike.applyUnlock(grant)
                FirstGateStore().markFirstGateCompleted()
            }
            writeBeforeScrollSpike.reconcileOnAppActive()
            writeBeforeScrollSpike.handlePendingInterventionIfNeeded(showWrite: showDeepWriteInterface)
            AppOpenStore().loadOrCreate()
            let identityStore = WriterIdentityStore()
            _ = try? identityStore.loadOrCreateRecoveryPhrase()
            _ = try? identityStore.loadOrCreate()
            Task {
                await youViewModel.preloadCredits()
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
                // If the trial was cancelled in Settings, the reminder has
                // nothing honest left to say — this removes it.
                Task {
                    await entitlements.reconcileOnForeground()
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
                writeBeforeScrollSpike.reconcileOnAppActive()
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
                Task {
                    await youViewModel.preloadCredits()
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
        .onChange(of: entitlements.isEntitled) { entitled in
            // Subscribing ends the trial surface the moment it happens.
            if entitled, #available(iOS 16.1, *) {
                TrialActivityController.endAll()
            }
            // Phase-3: refresh every gate, then — race-safely — let the held
            // generation fire: pay → server-confirmed → generate → ceremony.
            let gated = entitlements.isEntitledForGating
            levelPainting.entitledForGating = gated
            writeViewModel.dailyUnlockEntitled = gated
            HomeQuickActionPublisher.refresh(entitled: entitlements.isEntitledForGating)
            GlanceSyncCoordinator.sync()
            if gated {
                Task {
                    await entitlements.syncEntitlementToBackendIfNeeded()
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
            await youViewModel.preloadCredits()
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
                await youViewModel.preloadCredits()
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
        showsOnboarding = !onboardingCompleted
        syncWriteBubble()
    }

    /// Screens 1–10 are done; screen 11 is the gate setup sheet.
    /// `onboardingCompleted` stays false until the Day 1 threshold is
    /// crossed, so a relaunch mid-setup restarts the flow.
    private func finishOnboardingScreens() {
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
        guard !onboardingCompleted, !showsDayOneOverlay else {
            return
        }
        revealAfterWriting = nil
        sealingArtifact = nil
        sealingUnlockGrant = nil
        showsLaunchDialogue = false
        writeSurface = .deepWrite
        selectedTab = 0
        writeViewModel.beginBlankSessionFromWriteTab()
        writeViewModel.openWritingPortal()
        ankyCompanion.hideBubble()
        syncWriteBubble()
        withAnimation(.easeOut(duration: 0.35)) {
            showsDayOneOverlay = true
        }
    }

    private func completeOnboarding() {
        onboardingCompleted = true
        OnboardingFlowProgress.markFinished()
        withAnimation(.easeOut(duration: 0.25)) {
            showsDayOneOverlay = false
        }
        showsLaunchDialogue = false
        writeViewModel.focusWritingKeyboard()
        ankyCompanion.hideBubble()
        syncWriteBubble()
    }

    private var shouldFocusWrite: Bool {
        selectedTab == 0
            && writeSurface == .deepWrite
            && (!faceIDLockEnabled || isUnlocked)
            && !shouldShowOnboarding
            && !showsICloudRestorePrompt
    }

    private var shouldHideWriteSystemChrome: Bool {
        selectedTab == 0
            && writeSurface == .deepWrite
            && (!faceIDLockEnabled || isUnlocked)
            && !shouldShowOnboarding
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

    private var shouldShowOnboarding: Bool {
        showsOnboarding
            && !onboardingCompleted
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
            return writeViewModel.hasReachedRitualMark ? .celebrate : .findingThread
        case 1:
            return .walkRight
        case 2:
            return .waveFront
        default:
            return .idleFront
        }
    }

    private var shouldShowPresenceOverlay: Bool {
        selectedTab != 0 || writeSurface == .deepWrite
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
            ankyCompanion.witness(mood: .listening, sequence: .findingThread)
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

/// Settings opened from the gate home's gear button. Owns its own gate
/// setup sheet so "Apps that are blocked" works from inside the cover.
private struct SettingsCoverView: View {
    @ObservedObject var viewModel: YouViewModel
    @ObservedObject var screenTime: WriteBeforeScrollSpikeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsGateSetup = false

    var body: some View {
        NavigationStack {
            AnkySettingsView(
                viewModel: viewModel,
                onGateSetupRequested: { showsGateSetup = true }
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
        case seal
        case mirror
        case gate
    }

    @StateObject private var mirrorViewModel: RevealViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: Phase = .seal
    @State private var didStart = false
    @State private var sealMinimumElapsed = false
    @State private var mirrorResolved = false
    @State private var didLeaveDuringSeal = false
    @State private var skipsSealMotion = false
    @State private var isFirstGate = false
    @State private var showsPaywallSheet = false
    @EnvironmentObject private var entitlements: EntitlementStore

    private let artifact: SavedAnky
    private let unlockGrant: UnlockGrant?
    private let isGateOriginated: Bool
    private let onUnlock: () -> Void
    private let onDone: () -> Void
    private let onStay: () -> Void

    init(
        artifact: SavedAnky,
        unlockGrant: UnlockGrant?,
        isGateOriginated: Bool = false,
        onUnlock: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onStay: @escaping () -> Void
    ) {
        self.artifact = artifact
        self.unlockGrant = unlockGrant
        self.isGateOriginated = isGateOriginated
        self.onUnlock = onUnlock
        self.onDone = onDone
        self.onStay = onStay
        _mirrorViewModel = StateObject(wrappedValue: RevealViewModel(artifact: artifact))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SealingBackground()

                if phase == .seal {
                    SealBeatView(
                        hashLine: hashLine,
                        skipsMotion: skipsSealMotion
                    )
                    .transition(.opacity)
                } else {
                    MirrorAndGateBeatView(
                        reflectionTitle: reflectionTitle,
                        reflectionText: reflectionText,
                        didFailReflection: didFailReflection,
                        showsReflectionVeil: reflectionVeiled,
                        onVeilTap: { showsPaywallSheet = true },
                        hashLine: hashLine,
                        gateTitle: gateTitle,
                        remainingTodayText: remainingTodayText,
                        firstGateLine: firstGateLine,
                        showsGate: phase == .gate,
                        onGate: unlockGrant == nil ? onDone : onUnlock,
                        onStay: onStay
                    )
                    .padding(.top, max(geometry.safeAreaInsets.top, 18))
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 18))
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsPaywallSheet) {
            PaywallSheet(store: entitlements, origin: "reflection")
        }
        .onAppear(perform: startIfNeeded)
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                if phase == .seal {
                    didLeaveDuringSeal = true
                }
            case .active:
                if didLeaveDuringSeal {
                    sealMinimumElapsed = true
                    skipsSealMotion = true
                    advancePastSealIfReady()
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    private var hashLine: String {
        let prefix = String(artifact.hash.prefix(4))
        let suffix = String(artifact.hash.suffix(4))
        return "sealed · \(prefix)...\(suffix)"
    }

    private var reflectionTitle: String? {
        guard let title = mirrorViewModel.reflection?.title.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return title
    }

    private var reflectionText: String {
        if let reflection = mirrorViewModel.reflection?.reflection.trimmingCharacters(in: .whitespacesAndNewlines),
           !reflection.isEmpty {
            return reflection
        }

        let streaming = mirrorViewModel.streamingReflectionMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !streaming.isEmpty {
            return streaming
        }

        return "sealed. words kept."
    }

    private var didFailReflection: Bool {
        mirrorResolved
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
            return "done"
        }
        // Contextual only when the session came through the gate — closing
        // the loop fast. Organic sessions keep the normal copy.
        return isGateOriginated
            ? WriteBeforeScrollReturnTarget.gateLabel()
            : "continue"
    }

    private var remainingTodayText: String {
        "or stay · \(Self.remainingWritingTimeToday()) left today"
    }

    private var firstGateLine: String? {
        guard isFirstGate, unlockGrant != nil else {
            return nil
        }
        return "you just wrote before you scrolled.\nthat is the whole practice."
    }

    private func startIfNeeded() {
        guard !didStart else {
            return
        }
        didStart = true
        isFirstGate = unlockGrant != nil && !FirstGateStore().hasCompletedFirstGate
        dismissKeyboard()

        Task {
            await mirrorViewModel.prepareAfterFirstRender()
            // Free sessions make zero LLM calls — the veil stands where the
            // reflection would; everything else about the seal is identical.
            if entitlements.isEntitledForGating, mirrorViewModel.reflection == nil {
                await mirrorViewModel.askAnkyForSealedSession()
            }
            await MainActor.run {
                mirrorResolved = true
                advancePastSealIfReady()
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                sealMinimumElapsed = true
                advancePastSealIfReady()
            }
        }
    }

    private func advancePastSealIfReady() {
        guard phase == .seal, sealMinimumElapsed, mirrorResolved else {
            return
        }

        withAnimation(.easeInOut(duration: 0.82)) {
            phase = .mirror
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                guard phase == .mirror else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.78)) {
                    phase = .gate
                }
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private static func remainingWritingTimeToday(
        now: Date = Date(),
        calendar: Calendar = .current,
        sessionIndexStore: SessionIndexStore = SessionIndexStore()
    ) -> String {
        let targetMs = DailyTargetStore().effectiveTargetMs(now: now, calendar: calendar)
        let writtenMs = sessionIndexStore.load()
            .filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
            .reduce(Int64(0)) { total, summary in
                total + summary.durationMs
            }
        return clock(max(0, targetMs - writtenMs))
    }

    private static func clock(_ durationMs: Int64) -> String {
        let totalSeconds = max(0, durationMs / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }
}

private struct SealBeatView: View {
    let hashLine: String
    let skipsMotion: Bool
    @State private var gathersThread = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.ankyViolet.opacity(gathersThread ? 0.20 : 0.10))
                    .frame(width: 126, height: 126)
                    .blur(radius: 26)

                SealingThreadTangle(isGathered: gathersThread || skipsMotion)
                    .offset(y: gathersThread || skipsMotion ? 18 : -86)
                    .scaleEffect(gathersThread || skipsMotion ? 0.54 : 1.25)
                    .opacity(skipsMotion ? 0.76 : 0.9)

                AnkySpriteView(sequence: .findingThread, size: 172)
                    .offset(y: 10)
            }
            .frame(width: 240, height: 230)

            Text(hashLine)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !skipsMotion else {
                gathersThread = true
                return
            }
            withAnimation(.easeInOut(duration: 2.75)) {
                gathersThread = true
            }
        }
    }
}

private struct SealingThreadTangle: View {
    let isGathered: Bool

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { index in
                Text(glyph(for: index))
                    .font(.system(size: isGathered ? 16 : 21, weight: .medium, design: .serif))
                    .foregroundStyle(color(for: index).opacity(isGathered ? 0.72 : 0.42))
                    .rotationEffect(.degrees(Double(index * 23)))
                    .offset(
                        x: isGathered ? CGFloat((index % 5) - 2) * 4 : CGFloat((index % 7) - 3) * 22,
                        y: isGathered ? CGFloat((index % 4) - 2) * 3 : CGFloat((index % 5) - 2) * 18
                    )
            }
        }
        .frame(width: 116, height: 86)
        .blur(radius: isGathered ? 0.4 : 0)
    }

    private func glyph(for index: Int) -> String {
        let glyphs = ["a", "n", "k", "y", ".", "w", "o", "r", "d", "s", "·", "i", "n", "k"]
        return glyphs[index % glyphs.count]
    }

    private func color(for index: Int) -> Color {
        let colors = [
            Color.ankyGold,
            Color.ankyViolet,
            Color.ankySlate,
            Color.ankyInkSoft
        ]
        return colors[index % colors.count]
    }
}

private struct MirrorAndGateBeatView: View {
    let reflectionTitle: String?
    let reflectionText: String
    let didFailReflection: Bool
    var showsReflectionVeil: Bool = false
    var onVeilTap: () -> Void = {}
    let hashLine: String
    let gateTitle: String
    let remainingTodayText: String
    let firstGateLine: String?
    let showsGate: Bool
    let onGate: () -> Void
    let onStay: () -> Void

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
                    VStack(alignment: .leading, spacing: 16) {
                        if let reflectionTitle {
                            Text(reflectionTitle)
                                .font(.system(size: 31, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.ankyViolet)
                                .lineSpacing(3)
                                .transition(.opacity)
                        }

                        Text(reflectionText)
                            .font(.system(size: didFailReflection ? 22 : 25, weight: .regular, design: .serif))
                            .foregroundStyle(didFailReflection ? Color.ankyInkSoft : Color.ankyInk)
                            .lineSpacing(8)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showsGate {
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

                        Button(action: onGate) {
                            Text(gateTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.ankyInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .padding(.horizontal, 22)
                                .frame(minHeight: 46)
                                .frame(maxWidth: .infinity)
                                .background(
                                    LinearGradient(
                                        colors: [Color.ankyGoldLight, Color.ankyGold],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.ankyInk.opacity(0.10), lineWidth: 0.5)
                                )
                                .shadow(color: Color.ankyViolet.opacity(0.14), radius: 12, y: 4)
                        }
                        .buttonStyle(.plain)

                        Button(action: onStay) {
                            Text(remainingTodayText)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.ankyInkSoft)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 10)
                    .transition(.opacity)
                }

                Spacer(minLength: 34)

                Text(hashLine)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ankyInk.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
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
        .accessibilityLabel("Back to today")
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

                Button(action: restore) {
                    HStack(spacing: 10) {
                        if isRestoring {
                            ProgressView()
                                .tint(Color.ankyInk.opacity(0.82))
                        }
                        Text(AnkyLocalization.ui(isRestoring ? "Restoring" : "Restore From iCloud"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.ankyInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        LinearGradient(
                            colors: [Color.ankyGoldLight, Color.ankyGold],
                            startPoint: .top, endPoint: .bottom
                        ),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                    .shadow(color: Color.ankyViolet.opacity(0.14), radius: 16, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)
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
