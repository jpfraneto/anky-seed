import SwiftUI
import UIKit

struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("anky.biometricIdentityConfirmation") private var faceIDLockEnabled = false
    @AppStorage("anky.biometricPrivacyOnboardingCompleted") private var faceIDPrivacyOnboardingCompleted = false
    @AppStorage("anky.biometricPrivacyPromptPendingAfterFirstAnky") private var faceIDPrivacyPromptPendingAfterFirstAnky = false
    @AppStorage("anky.biometricPrivacyPromptReadyAfterFirstAnkyOpen") private var faceIDPrivacyPromptReadyAfterFirstAnkyOpen = false
    @AppStorage("anky.skipNextFaceIDEnableAuthentication") private var skipsNextFaceIDEnableAuthentication = false
    @State private var selectedTab = 0
    @State private var revealAfterWriting: SavedAnky?
    @State private var isUnlocked = false
    @State private var failedAuthAttempts = 0
    @State private var isAuthenticating = false
    @State private var suppressFaceIDPrivacyPromptUntilNextActivation = false
    @State private var recoveryPhraseInput = ""
    @State private var showsLaunchDialogue = true
    @State private var showsOnboarding = true
    @State private var showsFaceIDActivationPrompt = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var showsICloudRestorePrompt = false
    @State private var isRestoringICloudBackup = false
    @State private var iCloudRestoreErrorMessage: String?
    @StateObject private var writeViewModel = WriteViewModel()
    @StateObject private var youViewModel = YouViewModel()
    @StateObject private var ankyCompanion = AnkyCompanionStore()
    @StateObject private var tabBarCTAController = AnkyTabBarCTAController()

    private func showMap() {
        selectedTab = 1
    }

    private func showWriteInterface() {
        revealAfterWriting = nil
        showsLaunchDialogue = false
        selectedTab = 0
        syncWriteBubble()
    }

    private func revealOnMap(_ artifact: SavedAnky) {
        revealAfterWriting = artifact
        selectedTab = 1
        showsLaunchDialogue = false
        backUpToICloudIfEnabled()
        syncWriteBubble()
    }

    var body: some View {
        ZStack {
            TabView(selection: selectedTabBinding) {
                NavigationStack {
                    WriteView(
                        viewModel: writeViewModel,
                        shouldFocus: shouldFocusWrite,
                        onCompleted: revealOnMap,
                        onCloseToMap: {
                            showMap()
                        }
                    )
                }
                .tabItem {
                    Label(AnkyLocalization.text(.tabWrite), systemImage: "square.and.pencil")
                }
                .tag(0)

                MapView(
                    revealAfterWriting: $revealAfterWriting,
                    onTryAgain: beginRetryWriting,
                    onBackupRequested: backUpToICloudIfEnabled
                )
                    .tabItem {
                        Label(AnkyLocalization.text(.tabMap), systemImage: "map")
                    }
                    .tag(1)

                YouView(
                    viewModel: youViewModel,
                    onWriteRequested: showWriteInterface,
                    onDevelopmentWipe: resetForFreshDevelopmentLaunch
                )
                    .tabItem {
                        Label(AnkyLocalization.text(.tabYou), systemImage: "person.crop.circle")
                    }
                    .tag(2)
            }
            .environmentObject(ankyCompanion)
            .environmentObject(tabBarCTAController)
            .toolbar((selectedTab == 0 || tabBarCTAController.isScrollHidden) ? .hidden : .visible, for: .tabBar)

            AnkyTabBarFrameReader(controller: tabBarCTAController)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            AnkyTabBarCTAOverlay(controller: tabBarCTAController)
                .zIndex(75)

            if faceIDLockEnabled && !isUnlocked {
                LockFailureView(
                    allowsRecoveryPhrase: failedAuthAttempts >= 2,
                    recoveryPhraseInput: $recoveryPhraseInput,
                    retry: {
                        Task {
                            await authenticateIfNeeded()
                        }
                    },
                    recover: recoverIdentity
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

            if shouldShowOnboarding {
                AnkyOnboardingView {
                    completeOnboarding()
                }
                .transition(.opacity)
                .zIndex(110)
            }

            AnkyPresenceOverlay(
                companion: ankyCompanion,
                defaultSequence: presenceSequence,
                goldenGlow: selectedTab == 0 && writeViewModel.hasReachedRitualMark,
                transformToSigil: selectedTab == 0 && writeViewModel.hasStarted && !writeViewModel.hasReachedRitualMark,
                placement: selectedTab == 0 ? .writeRightLane : .trailingCenter,
                bubblePlacement: selectedTab == 0 ? .top : .bottom
            )
                .zIndex(40)
        }
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardHeight = keyboardOverlap(from: notification)
            syncWriteBubble()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
            syncWriteBubble()
        }
        .onAppear {
            selectedTab = 0
            revealAfterWriting = nil
            suppressFaceIDPrivacyPromptUntilNextActivation = false
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
            syncWriteBubble()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
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
                    failedAuthAttempts = 0
                    recoveryPhraseInput = ""
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: faceIDLockEnabled) { _, enabled in
            if enabled {
                faceIDPrivacyOnboardingCompleted = true
                faceIDPrivacyPromptPendingAfterFirstAnky = false
                faceIDPrivacyPromptReadyAfterFirstAnkyOpen = false
                failedAuthAttempts = 0
                recoveryPhraseInput = ""
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
                failedAuthAttempts = 0
                recoveryPhraseInput = ""
            }
        }
        .onChange(of: writeViewModel.hasStarted) { _, hasStarted in
            if hasStarted {
                showsLaunchDialogue = false
                ankyCompanion.hideBubble(returningTo: .listening)
            }
            syncWriteBubble()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != 0 {
                if writeViewModel.hasActiveDotAnky {
                    writeViewModel.clearCurrentSession()
                }
                ankyCompanion.hideBubble()
            } else {
                syncWriteBubble()
            }
        }
        .onChange(of: isUnlocked) { _, _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.isErrorMessageVisible) { _, _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.errorMessage) { _, _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.shouldShowNudgeDialogue) { _, _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.nudgeMessage) { _, _ in
            syncWriteBubble()
        }
        .onChange(of: writeViewModel.isRequestingNudge) { _, _ in
            syncWriteBubble()
        }
        .onChange(of: faceIDPrivacyOnboardingCompleted) { _, _ in
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
            failedAuthAttempts = 0
            recoveryPhraseInput = ""
            return
        }
        guard !isUnlocked, !isAuthenticating else {
            return
        }

        isAuthenticating = true
        isUnlocked = false
        let ok = await BiometricAuthClient().confirm(reason: AnkyLocalization.text(.unlockFaceIDReason))
        isUnlocked = ok
        if ok {
            failedAuthAttempts = 0
            recoveryPhraseInput = ""
        } else {
            failedAuthAttempts += 1
        }
        isAuthenticating = false
    }

    private func recoverIdentity(_ phraseText: String) {
        do {
            _ = try WriterIdentityStore().importRecoveryPhrase(phraseText)
            youViewModel.refresh()
            recoveryPhraseInput = ""
            failedAuthAttempts = 0
            isUnlocked = true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func closeLaunchDialogue() {
        withAnimation(.easeOut(duration: 0.22)) {
            showsLaunchDialogue = false
        }
        ankyCompanion.hideBubble()
    }

    private func beginLaunchWriting() {
        closeLaunchDialogue()
        ankyCompanion.hideBubble(returningTo: .listening)
        writeViewModel.openWritingPortal()
    }

    private func beginRetryWriting() {
        showsLaunchDialogue = false
        writeViewModel.clearCompletedSession()
        ankyCompanion.hideBubble(returningTo: .listening)
        selectedTab = 0
        writeViewModel.openWritingPortal()
    }

    private func resetForFreshDevelopmentLaunch() {
        selectedTab = 0
        revealAfterWriting = nil
        faceIDLockEnabled = false
        faceIDPrivacyOnboardingCompleted = false
        faceIDPrivacyPromptPendingAfterFirstAnky = false
        faceIDPrivacyPromptReadyAfterFirstAnkyOpen = false
        suppressFaceIDPrivacyPromptUntilNextActivation = false
        isUnlocked = true
        failedAuthAttempts = 0
        isAuthenticating = false
        skipsNextFaceIDEnableAuthentication = false
        recoveryPhraseInput = ""
        showsLaunchDialogue = true
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
                selectedTab = 1
                showsICloudRestorePrompt = false
                isRestoringICloudBackup = false
                ankyCompanion.hideBubble()
            } catch {
                iCloudRestoreErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Anky could not restore from iCloud."
                isRestoringICloudBackup = false
            }
        }
    }

    private func createNewLocalAccount() {
        showsICloudRestorePrompt = false
        iCloudRestoreErrorMessage = nil
        showsLaunchDialogue = false
        showsOnboarding = true
        syncWriteBubble()
    }

    private func completeOnboarding() {
        withAnimation(.easeOut(duration: 0.18)) {
            showsOnboarding = false
        }
        showsLaunchDialogue = false
        selectedTab = 0
        ankyCompanion.hideBubble(returningTo: .listening)
        writeViewModel.openWritingPortal()
        syncWriteBubble()
    }

    private var shouldFocusWrite: Bool {
        selectedTab == 0
            && (!faceIDLockEnabled || isUnlocked)
            && !shouldShowOnboarding
            && !showsICloudRestorePrompt
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
            && (!faceIDLockEnabled || isUnlocked)
            && !shouldShowOnboarding
            && !writeViewModel.hasActiveDotAnky
            && !writeViewModel.hasReachedRitualMark
            && keyboardHeight == 0
            && !shouldShowWriteErrorDialogue
    }

    private var shouldShowOnboarding: Bool {
        showsOnboarding
            && selectedTab == 0
            && (!faceIDLockEnabled || isUnlocked)
            && !showsICloudRestorePrompt
    }

    private var shouldShowWriteErrorDialogue: Bool {
        selectedTab == 0
            && (!faceIDLockEnabled || isUnlocked)
            && writeViewModel.isErrorMessageVisible
            && writeViewModel.errorMessage != nil
    }

    private var shouldShowWriteNudgeDialogue: Bool {
        selectedTab == 0
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

    private func syncWriteBubble() {
        guard selectedTab == 0, !faceIDLockEnabled || isUnlocked else {
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
                    AnkyChatAction("start again", isPrimary: true) {
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
        failedAuthAttempts = 0
        recoveryPhraseInput = ""
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

private struct LockFailureView: View {
    let allowsRecoveryPhrase: Bool
    @Binding var recoveryPhraseInput: String
    let retry: () -> Void
    let recover: (String) -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { geometry in
                Image("tellmewhoyouare")
                    .resizable()
                    .scaledToFit()
                    .frame(height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .ignoresSafeArea()

            if allowsRecoveryPhrase {
                VStack {
                    Spacer()

                    SeedPhraseEntry(text: $recoveryPhraseInput)
                        .frame(height: 116)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 34)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !allowsRecoveryPhrase else {
                return
            }
            retry()
        }
        .onChange(of: recoveryPhraseInput) { _, phrase in
            let normalized = phrase
                .lowercased()
                .split { $0.isWhitespace || $0.isNewline }
                .joined(separator: " ")
            guard normalized.split(separator: " ").count == 12 else {
                return
            }
            recover(normalized)
        }
    }
}

private struct ICloudRestorePromptView: View {
    let isRestoring: Bool
    let errorMessage: String?
    let restore: () -> Void
    let createNew: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Image("you-bg-cosmos")
                .resizable()
                .scaledToFill()
                .opacity(0.34)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Image("AnkySigil")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .shadow(color: AnkyTheme.gold.opacity(0.28), radius: 18)

                VStack(spacing: 10) {
                    Text("I remember you.")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(AnkyTheme.goldBright)
                        .multilineTextAlignment(.center)

                    Text("An encrypted Anky backup is waiting in iCloud.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AnkyTheme.text.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                if let errorMessage {
                    Text(errorMessage)
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
                                .tint(Color.black.opacity(0.82))
                        }
                        Text(isRestoring ? "Restoring" : "Restore From iCloud")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.black.opacity(0.84))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(AnkyTheme.goldBright, in: Capsule())
                    .shadow(color: AnkyTheme.gold.opacity(0.24), radius: 18, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)
                .padding(.top, 8)

                Button("Create new account", action: createNew)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AnkyTheme.text.opacity(0.62))
                    .disabled(isRestoring)

                Spacer()
            }
            .padding(.horizontal, 34)
        }
    }
}

private struct SeedPhraseEntry: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        textView.textColor = UIColor.white.withAlphaComponent(0.88)
        textView.tintColor = UIColor.white.withAlphaComponent(0.82)
        textView.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.textAlignment = .center
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 14, bottom: 16, right: 14)
        textView.layer.cornerRadius = 6
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}
