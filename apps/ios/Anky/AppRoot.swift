import SwiftUI
import UIKit

struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("anky.biometricIdentityConfirmation") private var faceIDLockEnabled = false
    @State private var selectedTab = 0
    @State private var revealAfterWriting: SavedAnky?
    @State private var isUnlocked = false
    @State private var failedAuthAttempts = 0
    @State private var isAuthenticating = false
    @State private var recoveryPhraseInput = ""
    @State private var showsLaunchDialogue = true
    @State private var keyboardHeight: CGFloat = 0
    @State private var companionMessageIndexByTab: [Int: Int] = [:]
    @StateObject private var writeViewModel = WriteViewModel()
    @StateObject private var youViewModel = YouViewModel()
    @StateObject private var ankyCompanion = AnkyCompanionStore()

    private func showMap() {
        selectedTab = 1
    }

    private func revealOnMap(_ artifact: SavedAnky) {
        revealAfterWriting = artifact
        showsLaunchDialogue = true
        selectedTab = 1
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
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
                    Label("Write", systemImage: "square.and.pencil")
                }
                .tag(0)

                MapView(
                    revealAfterWriting: $revealAfterWriting,
                    onTryAgain: beginRetryWriting,
                    onOpenCredits: openCredits
                )
                    .tabItem {
                        Label("Map", systemImage: "map")
                    }
                    .tag(1)

                YouView(viewModel: youViewModel)
                    .tabItem {
                        Label("You", systemImage: "person.crop.circle")
                    }
                    .tag(2)
            }
            .environmentObject(ankyCompanion)

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

            AnkyPresenceOverlay(
                companion: ankyCompanion,
                defaultSequence: presenceSequence,
                goldenGlow: selectedTab == 0 && writeViewModel.hasReachedRitualMark,
                transformToSigil: selectedTab == 0 && writeViewModel.hasStarted && !writeViewModel.hasReachedRitualMark,
                dockedToDialogue: false,
                onTap: presenceTapHandler
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
            syncWriteBubble()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if faceIDLockEnabled && !isUnlocked && !isAuthenticating {
                    Task {
                        await authenticateIfNeeded()
                    }
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
                isUnlocked = false
                failedAuthAttempts = 0
                recoveryPhraseInput = ""
                Task {
                    await authenticateIfNeeded()
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
        let ok = await BiometricAuthClient().confirm(reason: "Unlock ANKY.")
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
        ankyCompanion.hideBubble(returningTo: .listening)
        selectedTab = 0
        writeViewModel.openWritingPortal()
    }

    private func openCredits() {
        selectedTab = 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            ankyCompanion.witness(
                mood: .guiding,
                sequence: .waveFront,
                bubble: AnkyBubble(text: "open credits to restore the reflection gate.")
            )
        }
    }

    private var shouldFocusWrite: Bool {
        selectedTab == 0
            && (!faceIDLockEnabled || isUnlocked)
    }

    private var shouldShowLaunchDialogue: Bool {
        showsLaunchDialogue
            && selectedTab == 0
            && (!faceIDLockEnabled || isUnlocked)
            && !writeViewModel.hasActiveDotAnky
            && !writeViewModel.hasReachedRitualMark
            && keyboardHeight == 0
            && !shouldShowWriteErrorDialogue
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
            return "the living .anky string is the state of this session."
        }

        return "ankys today: \(writeViewModel.todayAnkyCount)"
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

    private var presenceTapHandler: (() -> Bool)? {
        return {
            if writeViewModel.hasStarted && !writeViewModel.hasReachedRitualMark {
                return writeViewModel.startAnkyNudgeIfPossible()
            }
            if selectedTab == 0 && writeViewModel.replayRecentPromptIfAvailable() {
                return true
            }
            showCompanionNote()
            return true
        }
    }

    private func syncWriteBubble() {
        guard selectedTab == 0, !faceIDLockEnabled || isUnlocked else {
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
            ankyCompanion.witness(
                mood: .listening,
                sequence: .shyListening,
                bubble: AnkyBubble(
                    text: writeViewModel.nudgeDialogueMessage,
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
                        AnkyChatAction(writeViewModel.todayAnkyCount > 0 ? "write again" : "write \(AnkyDuration.completeRitualMinutes) minutes", isPrimary: true) {
                            beginLaunchWriting()
                        }
                    ],
                    steps: [
                        AnkyBubbleStep("write one character"),
                        AnkyBubbleStep("keep the thread alive"),
                        AnkyBubbleStep("let silence close it")
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

    private func showCompanionNote() {
        showsLaunchDialogue = false
        let messages = companionMessages(for: selectedTab)
        let index = companionMessageIndexByTab[selectedTab, default: 0]
        companionMessageIndexByTab[selectedTab] = index + 1
        let message = messages[index % messages.count]
        ankyCompanion.witness(
            mood: .guiding,
            sequence: presenceSequence,
            bubble: AnkyBubble(text: message)
        )
    }

    private func dismissCompanionNote() {
        ankyCompanion.hideBubble()
    }

    private func companionMessages(for tab: Int) -> [String] {
        switch tab {
        case 0:
            if writeViewModel.hasReachedRitualMark {
                return [
                    "you are here. the ritual is complete; let the final silence close it.",
                    "you are here. this .anky is ready to become an artifact.",
                    "you are here. the thread crossed \(AnkyDuration.completeRitualMinutes) minutes. stay quiet and let it seal."
                ]
            }
            return [
                "you are here. this is the writing surface: one living thread, one character at a time.",
                "you are here. deletion is blocked on purpose; keep moving forward without editing.",
                "you are here. writing stays local unless you export it or ask for a reflection.",
                "you are here. \(AnkyDuration.completeRitualMinutes) minutes turns a fragment into a complete .anky."
            ]
        case 1:
            return [
                "you are here. the map is your local trail; every day exists even when it is quiet.",
                "you are here. tap a day to reopen its .ankys and saved reflections.",
                "you are here. the trail begins on the first day this app opened on this device.",
                "you are here. fragments and complete ankys both stay in your local archive."
            ]
        case 2:
            return [
                "you are here. this page is for identity, privacy, exports, and reflection credits.",
                "you are here. your identity unlocks reflections, backups, and credit balance.",
                "you are here. data leaves this phone only when you choose export or reflection.",
                "you are here. credits buy reflections; writing itself stays free."
            ]
        default:
            return ["you are here."]
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
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
        }
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
