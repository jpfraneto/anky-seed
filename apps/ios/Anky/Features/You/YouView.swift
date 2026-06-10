import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AudioToolbox

struct YouView: View {
    @ObservedObject var viewModel: YouViewModel
    let onWriteRequested: () -> Void
    let onDevelopmentWipe: () -> Void
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var ankyCompanion: AnkyCompanionStore
    @EnvironmentObject private var tabBarCTAController: AnkyTabBarCTAController
    @AppStorage(MirrorConfiguration.userDefaultsKey) private var mirrorBaseURL = MirrorConfiguration.defaultBaseURL
    @AppStorage("anky.dailyReminderEnabled") private var dailyReminderEnabled = false
    @AppStorage("anky.dailyReminderTime") private var dailyReminderTime = 9.0 * 60.0 * 60.0
    @AppStorage("anky.biometricIdentityConfirmation") private var biometricIdentityConfirmation = false
    @AppStorage("anky.biometricPrivacyOnboardingCompleted") private var faceIDPrivacyOnboardingCompleted = false
    @AppStorage("anky.skipNextFaceIDEnableAuthentication") private var skipsNextFaceIDEnableAuthentication = false
    @State private var confirmDeleteAccountAndData = false
    @State private var isImportingBackup = false
    @State private var isImportingRecoveryPhrase = false
    @State private var recoveryPhraseInput = ""
    @State private var showsPrivacyPolicy = false
    @State private var showsTermsAndConditions = false
    @State private var activePrompt: YouPrompt?
    @State private var isShowingSystemPrompt = false
    @State private var path: [YouRoute] = []
    @State private var didCopyAnkyContract = false
    @State private var showsAccountDeletion = false
    @State private var showsReflectionCreditsSheet = false
    @State private var promptAutoDismissTask: Task<Void, Never>?

    init(
        viewModel: YouViewModel,
        onWriteRequested: @escaping () -> Void = {},
        onDevelopmentWipe: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onWriteRequested = onWriteRequested
        self.onDevelopmentWipe = onDevelopmentWipe
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
            ZStack {
                YouCosmicBackground()

                VStack(spacing: 20) {
                        YouPanel(spacing: 0) {
                        dataRow

                        YouDivider()

                        promptButton(.credits, icon: "you-icon-credits", title: "Credits", subtitle: creditsMenuSubtitle)

                        YouDivider()

                        promptButton(.support, icon: "you-icon-support", title: "Support / Feedback", subtitle: "Email support@anky.app")

                        YouDivider()

                        promptButton(.privacy, icon: "you-icon-privacy", title: "Privacy Policy", subtitle: "How your data is handled.")

                        YouDivider()

                        legalButton(icon: "you-icon-terms", title: "Terms & Conditions", subtitle: "The agreement for using Anky") {
                            showsTermsAndConditions = true
                        }

                        if shouldShowFaceIDControl {
                            YouDivider()

                            YouToggleRow(
                                isOn: faceIDBinding,
                                iconName: deviceAuthenticationIconName,
                                title: deviceAuthenticationName,
                                subtitle: biometricIdentityConfirmation ? "On" : "Off"
                            )
                        }

                        /*
                        YouDivider()

                        ankyContractRow
                        */
                    }

                    if showsAccountDeletion {
                        YouPanel(spacing: 0) {
                            Button(role: .destructive) {
                                AnkyHaptics.warning()
                                confirmDeleteAccountAndData = true
                            } label: {
                                YouDestructiveMenuRow(title: "DELETE ACCOUNT AND DATA")
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            }
            .navigationTitle(AnkyLocalization.ui("You"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AnkyHaptics.warning()
                        AnkyHaptics.medium()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            showsAccountDeletion.toggle()
                        }
                    } label: {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(Color.red.opacity(0.88))
                            .frame(width: 34, height: 38)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(AnkyLocalization.ui(showsAccountDeletion ? "Hide delete account action" : "Show delete account action"))
                }
            }
            .navigationDestination(for: YouRoute.self) { route in
                switch route {
                case .allAnkys:
                    YouAllAnkysHistoryView(
                        viewModel: viewModel,
                        onWriteRequested: {
                            path.removeAll()
                            onWriteRequested()
                        }
                    )
                }
            }
            .navigationDestination(for: SessionSummary.self) { session in
                if let artifact = viewModel.artifact(for: session) {
                    RevealView(
                        viewModel: RevealViewModel(artifact: artifact),
                        onDeleted: {
                            viewModel.refresh()
                        },
                        onTryAgain: {
                            path.removeAll()
                            onWriteRequested()
                        }
                    )
                } else {
                    ContentUnavailableView("Anky not found", systemImage: "doc.badge.questionmark")
                }
            }
            }
        }
        .sheet(isPresented: $showsPrivacyPolicy) {
            PrivacyPolicyReflectionSheet()
                .presentationDetents([.fraction(0.8)])
                .presentationDragIndicator(.visible)
                .presentationBackground(PrivacySheetPalette.ink)
        }
        .sheet(isPresented: $showsTermsAndConditions) {
            TermsAndConditionsReflectionSheet()
                .presentationDetents([.fraction(0.8)])
                .presentationDragIndicator(.visible)
                .presentationBackground(PrivacySheetPalette.ink)
        }
        .ankyReflectionCreditsSheet(
            isPresented: $showsReflectionCreditsSheet,
            availableCredits: viewModel.presentedCreditBalance,
            packs: viewModel.creditPackages,
            isRefreshing: viewModel.creditsLoading,
            purchasingPackId: viewModel.purchasingCreditPackageID,
            onRefresh: {
                AnkyHaptics.light()
                Task {
                    await viewModel.refreshCredits()
                }
            },
            onSelectPack: { creditPackage in
                AnkyHaptics.light()
                Task {
                    await viewModel.purchaseCredits(creditPackage)
                }
            }
        )
        .sheet(isPresented: $isImportingRecoveryPhrase) {
            ImportRecoveryPhraseSheet(
                viewModel: viewModel,
                recoveryPhraseInput: $recoveryPhraseInput,
                isPresented: $isImportingRecoveryPhrase
            )
        }
        .alert(AnkyLocalization.ui("Delete Account and Data?"), isPresented: $confirmDeleteAccountAndData) {
            Button(AnkyLocalization.ui("Delete"), role: .destructive) {
                Task {
                    await deleteAccountAndData()
                }
            }
            Button(AnkyLocalization.ui("Cancel"), role: .cancel) {}
        } message: {
            Text(AnkyLocalization.ui("This deletes your Anky data from this device and iCloud. This cannot be undone."))
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: Self.importableContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                _ = viewModel.importBackup(from: url)
            case .failure:
                break
            }
        }
        .onAppear {
            viewModel.refresh()
            isShowingSystemPrompt = viewModel.errorMessage != nil || viewModel.statusMessage != nil
            presentCurrentPromptIfNeeded()
        }
        .onChange(of: viewModel.statusMessage) { _, statusMessage in
            guard statusMessage != nil else { return }
            isShowingSystemPrompt = true
            presentCurrentPromptIfNeeded()
            dismissCreditUpdateMessageIfNeeded(statusMessage)
        }
        .onChange(of: viewModel.errorMessage) { _, errorMessage in
            guard errorMessage != nil else { return }
            isShowingSystemPrompt = true
            presentCurrentPromptIfNeeded()
        }
        .onChange(of: viewModel.creditsLoading) { _, _ in
            refreshCreditsBubbleIfNeeded()
        }
        .onChange(of: viewModel.purchasingCreditPackageID) { _, _ in
            refreshCreditsBubbleIfNeeded()
        }
        .onChange(of: viewModel.creditBalance) { _, _ in
            refreshCreditsBubbleIfNeeded()
        }
        .onChange(of: viewModel.creditPackages.count) { _, _ in
            refreshCreditsBubbleIfNeeded()
        }
        .onChange(of: viewModel.isICloudBackupEnabled) { _, _ in
            if activePrompt == .export, !isShowingSystemPrompt {
                presentCurrentPromptIfNeeded()
            }
        }
        .onChange(of: viewModel.iCloudBackupLastDate) { _, _ in
            if activePrompt == .export, !isShowingSystemPrompt {
                presentCurrentPromptIfNeeded()
            }
        }
        .onChange(of: viewModel.isICloudBackupWorking) { _, _ in
            if activePrompt == .export, !isShowingSystemPrompt {
                presentCurrentPromptIfNeeded()
            }
        }
    }

    private func promptButton(_ prompt: YouPrompt, icon: String, title: String, subtitle: String) -> some View {
        Button {
            AnkyHaptics.light()
            if prompt == .credits {
                openCreditsSheet()
            } else {
                openPrompt(prompt)
            }
        } label: {
            YouMenuRow(icon: icon, title: title, subtitle: subtitle, showsDisclosure: false)
        }
        .buttonStyle(.plain)
    }

    private var dataRow: some View {
        YouDataToggleRow(
            isOn: iCloudBackupBinding,
            icon: "you-icon-export",
            title: "Data",
            subtitle: dataMenuSubtitle,
            action: {
                openPrompt(.export)
            }
        )
    }

    private func openPrompt(_ prompt: YouPrompt) {
        if prompt == .privacy {
            showsPrivacyPolicy = true
            activePrompt = nil
            isShowingSystemPrompt = false
            ankyCompanion.hideBubble()
            return
        }
        activePrompt = prompt
        isShowingSystemPrompt = false
        presentCurrentPromptIfNeeded()
        if prompt == .credits {
            Task {
                await viewModel.refreshCredits(showError: false)
            }
        }
    }

    private func openCreditsSheet() {
        activePrompt = nil
        isShowingSystemPrompt = false
        ankyCompanion.hideBubble()
        showsReflectionCreditsSheet = true
        Task {
            await viewModel.refreshCredits(showError: false)
        }
    }

    private func legalButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            AnkyHaptics.light()
            activePrompt = nil
            isShowingSystemPrompt = false
            ankyCompanion.hideBubble()
            action()
        } label: {
            YouMenuRow(icon: icon, title: title, subtitle: subtitle, showsDisclosure: false)
        }
        .buttonStyle(.plain)
    }

    private func presentCurrentPromptIfNeeded() {
        guard isShowingSystemPrompt || activePrompt != nil else {
            return
        }

        let mood: AnkyCompanionMood
        if isConversationThinking {
            mood = .thinking
        } else if viewModel.errorMessage != nil {
            mood = .concerned
        } else {
            mood = .guiding
        }

        ankyCompanion.witness(
            mood: mood,
            bubble: AnkyBubble(
                text: conversationMessage,
                actions: conversationActions,
                isThinking: isConversationThinking,
                close: dismissCurrentPrompt
            )
        )
        schedulePromptAutoDismiss()
    }

    private func dismissCurrentPrompt() {
        promptAutoDismissTask?.cancel()
        promptAutoDismissTask = nil
        activePrompt = nil
        isShowingSystemPrompt = false
        viewModel.dismissMessages()
        ankyCompanion.hideBubble()
    }

    private func schedulePromptAutoDismiss() {
        promptAutoDismissTask?.cancel()
        promptAutoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            dismissCurrentPrompt()
        }
    }

    private func refreshCreditsBubbleIfNeeded() {
        guard activePrompt == .credits, !isShowingSystemPrompt else {
            return
        }
        presentCurrentPromptIfNeeded()
    }

    private var conversationMessage: String {
        if isShowingSystemPrompt {
            return viewModel.errorMessage ?? viewModel.statusMessage ?? activePrompt?.message ?? ""
        }

        if activePrompt == .credits {
            if viewModel.creditsLoading {
                    return AnkyLocalization.ui("Anky is checking the credit gate.")
            }
            return creditsPromptMessage
        }

        if activePrompt == .export {
            if viewModel.isICloudBackupWorking {
                return AnkyLocalization.ui("Anky is updating the encrypted iCloud backup.")
            }
            if viewModel.isICloudBackupEnabled {
                if let date = viewModel.iCloudBackupLastDate {
                    return AnkyLocalization.ui("Encrypted iCloud backup is on. Last updated %@.", date.formatted(date: .abbreviated, time: .shortened))
                }
                return AnkyLocalization.ui("Encrypted iCloud backup is on. It will run after your next writing session.")
            }
            return AnkyLocalization.ui("Export readable writings or turn on encrypted iCloud backup for reinstall recovery.")
        }

        return activePrompt?.message ?? ""
    }

    private var conversationActions: [AnkyChatAction] {
        if isShowingSystemPrompt && (viewModel.errorMessage != nil || viewModel.statusMessage != nil) {
            return []
        }
        if isConversationThinking {
            return []
        }

        return promptActions
    }

    private var isConversationThinking: Bool {
        activePrompt == .credits
            && !isShowingSystemPrompt
            && viewModel.creditsLoading
    }

    private var promptActions: [AnkyChatAction] {
        guard let activePrompt else {
            return []
        }

        switch activePrompt {
        case .privacy:
            return []
        case .export:
            return [
                AnkyChatAction(AnkyLocalization.ui(viewModel.isICloudBackupWorking ? "Backing up" : "Back up now"), isPrimary: true) {
                    Task { await viewModel.backUpToICloudNow() }
                },
                AnkyChatAction(AnkyLocalization.ui("Export writings")) {
                    viewModel.prepareFormattedWritingExport()
                    if let exportURL = viewModel.formattedWritingExportURL {
                        presentShareSheet(item: exportURL)
                    }
                }
            ]
        case .credits:
            if viewModel.hasUnspentGiftCredit {
                return [
                    AnkyChatAction(AnkyLocalization.text(.writeEightMinutes), isPrimary: true) {
                        dismissCurrentPrompt()
                        onWriteRequested()
                    }
                ]
            }

            let packages = Array(viewModel.creditPackages.prefix(3))
            if packages.isEmpty {
                return [
                    AnkyChatAction(AnkyLocalization.ui(viewModel.creditsLoading ? "Loading packs" : "Refresh credits"), isPrimary: true) {
                        Task { await viewModel.refreshCredits() }
                    }
                ]
            }

            return packages.map { creditPackage in
                let isRecommended = creditPackage.title == "11 reflections"
                    || creditPackage.id.hasSuffix(".credits.11")
                let isPurchasing = viewModel.purchasingCreditPackageID == creditPackage.id
                return AnkyChatAction(
                    AnkyLocalization.ui(isPurchasing ? "Loading" : creditPackage.title),
                    subtitle: creditPackage.price,
                    badge: isRecommended ? AnkyLocalization.ui("recommended") : nil,
                    isPrimary: isRecommended
                ) {
                    AnkyHaptics.light()
                    Task { await viewModel.purchaseCredits(creditPackage) }
                }
            }
        case .support:
            return [
                AnkyChatAction(AnkyLocalization.ui("Open email"), isPrimary: true) {
                    if let emailURL = viewModel.supportFeedbackEmailURL {
                        openURL(emailURL)
                    }
                }
            ]
        }
    }

    private var creditsMenuSubtitle: String {
        if viewModel.creditsLoading && viewModel.creditBalance == nil {
            return AnkyLocalization.ui("Loading balance")
        }

        return viewModel.creditSummaryText
    }

    private var dataMenuSubtitle: String {
        if viewModel.isICloudBackupEnabled {
            return AnkyLocalization.ui("Encrypted iCloud backup on")
        }
        return AnkyLocalization.ui("Export writings or enable iCloud")
    }

    private var iCloudBackupBinding: Binding<Bool> {
        Binding {
            viewModel.isICloudBackupEnabled
        } set: { isEnabled in
            AnkyHaptics.light()
            if isEnabled {
                Task { await viewModel.enableICloudBackup() }
            } else {
                viewModel.disableICloudBackup()
            }
        }
    }

    private var shouldShowFaceIDControl: Bool {
        BiometricAuthClient().canAuthenticate()
    }

    private var deviceAuthenticationName: String {
        BiometricAuthClient().deviceAuthenticationName()
    }

    private var deviceAuthenticationIconName: String {
        switch deviceAuthenticationName {
        case "Face ID":
            return "faceid"
        case "Touch ID":
            return "touchid"
        case "Optic ID":
            return "eye"
        default:
            return "lock.fill"
        }
    }

    private var faceIDBinding: Binding<Bool> {
        Binding {
            biometricIdentityConfirmation
        } set: { isEnabled in
            AnkyHaptics.light()
            setFaceID(isEnabled)
        }
    }

    private var creditsPromptMessage: String {
        if viewModel.hasUnspentGiftCredit {
            return AnkyLocalization.text(.creditGiftPrompt)
        }

        let balance: String
        if viewModel.creditsLoading && viewModel.creditBalance == nil {
            balance = AnkyLocalization.ui("Loading...")
        } else if let creditBalance = viewModel.presentedCreditBalance {
            balance = "\(creditBalance)"
        } else {
            balance = AnkyLocalization.ui("unknown")
        }

        return AnkyLocalization.ui(
            "You have %@ reflection %@. Choose a pack to add more.",
            balance,
            AnkyLocalization.ui(balance == "1" ? "credit" : "credits")
        )
    }

    private var ankyContractAddress: String {
        "To be deployed"
    }

    private var ankyContractDisplayAddress: String {
        let prefix = ankyContractAddress.prefix(6)
        let suffix = ankyContractAddress.suffix(6)
        return "\(prefix)...\(suffix)"
    }

    private var ankyContractRow: some View {
        Button {
            ClipboardClient().copy(ankyContractAddress)
            AnkyHaptics.light()
            withAnimation(.easeInOut(duration: 0.18)) {
                didCopyAnkyContract = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation(.easeInOut(duration: 0.18)) {
                    didCopyAnkyContract = false
                }
            }
        } label: {
            YouMenuRow(
                icon: "you-icon-anky-token",
                title: "$ANKY",
                subtitle: didCopyAnkyContract ? "Copied to clipboard" : ankyContractDisplayAddress,
                showsDisclosure: false
            )
        }
        .buttonStyle(.plain)
    }

    private func dismissCreditUpdateMessageIfNeeded(_ statusMessage: String?) {
        guard statusMessage?.localizedCaseInsensitiveContains("credits updated") == true else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard viewModel.statusMessage == statusMessage else {
                return
            }
            dismissCurrentPrompt()
        }
    }

    private static var importableContentTypes: [UTType] {
        [
            UTType(filenameExtension: "zip"),
            UTType(filenameExtension: "anky"),
            .json
        ].compactMap { $0 }
    }

    private var reminderDate: Date {
        let start = Calendar.current.startOfDay(for: Date())
        return start.addingTimeInterval(dailyReminderTime)
    }

    private var reminderBinding: Binding<Date> {
        Binding {
            reminderDate
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            dailyReminderTime = Double((components.hour ?? 9) * 3600 + (components.minute ?? 0) * 60)
            if dailyReminderEnabled {
                Task {
                    await viewModel.setDailyReminder(enabled: true, date: newValue)
                }
            }
        }
    }

    private func presentShareSheet(item: Any) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        let activityViewController = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        rootViewController.present(activityViewController, animated: true)
    }

    private func setFaceID(_ isEnabled: Bool) {
        guard isEnabled != biometricIdentityConfirmation else {
            return
        }

        if !isEnabled {
            biometricIdentityConfirmation = false
            AnkyHaptics.light()
            return
        }

        Task {
            guard await BiometricAuthClient().confirm(reason: AnkyLocalization.text(.protectFaceIDReason)) else {
                AnkyHaptics.warning()
                return
            }
            skipsNextFaceIDEnableAuthentication = true
            faceIDPrivacyOnboardingCompleted = true
            biometricIdentityConfirmation = true
            AnkyHaptics.success()
        }
    }

    @MainActor
    private func deleteAccountAndData() async {
        await viewModel.deleteAccountAndDataEverywhere()
        mirrorBaseURL = MirrorConfiguration.defaultBaseURL
        dailyReminderEnabled = false
        dailyReminderTime = 9.0 * 60.0 * 60.0
        biometricIdentityConfirmation = false
        recoveryPhraseInput = ""
        activePrompt = nil
        isShowingSystemPrompt = true
        ankyCompanion.hideBubble()
        onDevelopmentWipe()
    }
}

private enum YouPrompt: Hashable {
    case privacy
    case export
    case credits
    case support

    var message: String {
        switch self {
        case .privacy:
            return AnkyLocalization.ui("Writing stays local unless you export or ask for a reflection.")
        case .export:
            return AnkyLocalization.ui("Your archive is yours. Export readable writings or keep an encrypted iCloud backup.")
        case .credits:
            return AnkyLocalization.ui("Credits are only for reflections. Writing is free.")
        case .support:
            return AnkyLocalization.ui("Send us an email! We want to evolve this app based on your feedback.")
        }
    }
}

private enum YouRoute: Hashable {
    case allAnkys
}

private struct YouAllAnkysHistoryView: View {
    @ObservedObject var viewModel: YouViewModel
    let onWriteRequested: () -> Void

    private let bottomNavigationReserve: CGFloat = 152

    private var sessions: [SessionSummary] {
        viewModel.completeAnkySessions
    }

    private var title: String {
        "\(sessions.count) \(sessions.count == 1 ? "anky" : "ankys")"
    }

    var body: some View {
        ZStack {
            MapDayBackground()

            GeometryReader { geometry in
                let viewportWidth = min(geometry.size.width, UIScreen.main.bounds.width)
                let contentWidth = max(0, viewportWidth * 0.87)
                let horizontalPadding = max(0, (viewportWidth - contentWidth) / 2)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        if sessions.isEmpty {
                            emptyState
                                .frame(width: contentWidth, alignment: .center)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(sessions) { session in
                                    NavigationLink(value: session) {
                                        SessionRow(
                                            session: session,
                                            rowWidth: contentWidth,
                                            showsDayInHeader: true
                                        )
                                        .frame(width: contentWidth, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded {
                                        AnkyHaptics.light()
                                    })
                                }
                            }
                            .frame(width: contentWidth, alignment: .leading)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, bottomNavigationReserve)
                }
                .frame(width: viewportWidth, alignment: .leading)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(MapDayPalette.ink.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            viewModel.refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 96)

            Text(AnkyLocalization.ui("0 ankys"))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(MapDayPalette.gold)

            Button(action: onWriteRequested) {
                HStack(spacing: 10) {
                    Text(AnkyLocalization.ui("WRITE %d MINUTES", AnkyDuration.completeRitualMinutes))
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(MapDayPalette.paper)
                .frame(maxWidth: .infinity)
                .frame(height: 66)
                .background(historyCTAFill, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(MapDayPalette.gold.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.42), radius: 18, y: 8)
                .shadow(color: MapDayPalette.gold.opacity(0.18), radius: 18)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 96)
        }
    }

    private var historyCTAFill: LinearGradient {
        let accent = AnkyverseDayPalette.color(for: AnkyverseCalendar(firstOpenDate: AppOpenStore().loadOrCreate(), calendar: .ankyUTC).position(for: Date()).dayInRegion)
        return LinearGradient(
            colors: [
                accent.opacity(0.68),
                Color(red: 0.11, green: 0.10, blue: 0.18).opacity(0.98),
                accent.opacity(0.34)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct AccountPage: View {
    @ObservedObject var viewModel: YouViewModel
    @Binding var dailyReminderEnabled: Bool
    @Binding var dailyReminderTime: Double
    @Binding var biometricIdentityConfirmation: Bool
    @Binding var isImportingRecoveryPhrase: Bool
    @Binding var recoveryPhraseInput: String
    let reminderDate: Date
    let reminderBinding: Binding<Date>

    var body: some View {
        YouDetailShell(title: "private access", subtitle: "private to this device") {
            YouPanel {
                Text(AnkyLocalization.ui("Private access"))
                    .youCaption()
                Text(AnkyLocalization.ui("Anky created a private local profile for this device."))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(YouPalette.paper)
                Text(AnkyLocalization.ui("Your writing and access stay here unless you choose to export or recover them elsewhere."))
                    .youBody()
            }

            YouPanel {
                Text(AnkyLocalization.ui("Advanced recovery"))
                    .youCaption()
                Text(AnkyLocalization.ui("These words restore your Anky access. Never share them. Anky cannot recover them for you."))
                    .youBody()

                YouDivider()

                Toggle(AnkyLocalization.ui("device lock app protection"), isOn: $biometricIdentityConfirmation)
                    .tint(YouPalette.gold)
                    .foregroundStyle(YouPalette.paper)
                    .font(.system(size: 16))

                Text(AnkyLocalization.ui("Your recovery words can only be shown after device lock protection is enabled."))
                    .youBody()

                Text(AnkyLocalization.ui("Your passcode or biometrics protect local access. They are not an Anky login."))
                    .youBody()

                if viewModel.recoveryPhraseText.isEmpty {
                    YouActionButton(AnkyLocalization.ui("Reveal recovery words")) {
                        Task {
                            await viewModel.revealRecoveryPhrase()
                        }
                    }
                    .disabled(!biometricIdentityConfirmation)
                    .opacity(biometricIdentityConfirmation ? 1 : 0.45)
                } else {
                    Text(viewModel.recoveryPhraseText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(YouPalette.paper)
                        .textSelection(.enabled)

                    VStack(spacing: 10) {
                        YouActionButton(AnkyLocalization.ui("Copy recovery words")) {
                            ClipboardClient().copy(viewModel.recoveryPhraseText)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        YouActionButton(AnkyLocalization.ui("Hide")) {
                            viewModel.hideRecoveryPhrase()
                        }
                    }
                }

                YouActionButton(AnkyLocalization.ui("Recover access")) {
                    recoveryPhraseInput = ""
                    isImportingRecoveryPhrase = true
                }

                if viewModel.isIdentityBackedUpToICloud {
                    YouDisabledRow(AnkyLocalization.ui("Recovery words saved in iCloud Keychain"))
                } else {
                    YouActionButton(AnkyLocalization.ui("Back up recovery words to iCloud Keychain")) {
                        Task { await viewModel.backUpIdentityToICloudKeychain() }
                    }
                }

                Text(AnkyLocalization.ui("This stores your recovery words in your device/cloud keychain. Data export is the separate backup for writing and reflections. Anky cannot read or recover either for you."))
                    .youBody()

                VStack(alignment: .leading, spacing: 8) {
                    Text(AnkyLocalization.ui("Support ID"))
                        .youCaption()
                    Text(viewModel.accountId)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(YouPalette.paperMuted)
                        .textSelection(.enabled)
                }

                YouActionButton(AnkyLocalization.ui("Import recovery backup")) {
                    Task { await viewModel.recoverIdentityFromICloudKeychain() }
                }
            }

            YouPanel {
                Toggle(AnkyLocalization.ui("Daily reminder"), isOn: $dailyReminderEnabled)
                    .tint(YouPalette.gold)
                    .foregroundStyle(YouPalette.paper)
                    .font(.system(size: 16))
                    .onChange(of: dailyReminderEnabled) { _, isEnabled in
                        AnkyHaptics.light()
                        Task {
                            await viewModel.setDailyReminder(enabled: isEnabled, date: reminderDate)
                        }
                    }

                DatePicker(AnkyLocalization.ui("Time"), selection: reminderBinding, displayedComponents: .hourAndMinute)
                    .disabled(!dailyReminderEnabled)
                    .tint(YouPalette.gold)
                    .foregroundStyle(YouPalette.paper)
            }

            YouPanel {
                Text(AnkyLocalization.ui("Ownership note"))
                    .youCaption()
                Text(AnkyLocalization.ui("Your writing belongs to this device unless you choose to export or recover it elsewhere."))
                    .youBody()
            }
        }
    }
}

private struct PrivacyPolicyPage: View {
    var body: some View {
        YouDetailShell(title: "Privacy", subtitle: "Local-first writing and reflection") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.policyCopy.indices, id: \.self) { index in
                    PrivacyCopyLine(Self.policyCopy[index])
                }
            }
        }
    }

    fileprivate static let policyCopy: [PrivacyCopyItem] = [
        .caption("Anky, Inc. - Effective June 7, 2026"),
        .callout("The short version: Anky is local-first. Your writing stays on your device unless you choose to export it, back it up, contact support, or ask Anky for a reflection. When you ask for a reflection, your writing is sent to Anky's mirror service and AI providers so a reflection can be generated. We use providers that don't store your writing. We do not sell your data, use it for advertising, or use your writing to train our own models."),
        .heading("1. Who We Are"),
        .paragraph("Anky is operated by **Anky, Inc.**, a Delaware corporation."),
        .paragraph("Contact: **[support@anky.app](mailto:support@anky.app)**"),
        .paragraph("This Privacy Policy explains how Anky handles information when you use the Anky mobile app, website, mirror service, purchases, support, and related services."),
        .heading("2. What Anky Is"),
        .paragraph("Anky is a local-first writing and reflection app."),
        .paragraph("The core artifact is the `.anky` file: a forward-only writing session created under constraint. The app lets you write, save, revisit, export, import, delete, and optionally reflect on that writing."),
        .paragraph("Anky is not a therapist, medical service, crisis service, financial advisor, legal advisor, or spiritual authority."),
        .heading("3. What Stays On Your Device By Default"),
        .paragraph("The following data is stored locally on your device unless you choose to export it, back it up, recover it elsewhere, contact support, or request a reflection:"),
        .bullets([
            "Your `.anky` writing files",
            "Active writing drafts",
            "Reconstructed readable writing",
            "Local reflections returned by Anky",
            "Session history and Map data",
            "Local app settings",
            "Daily reminder settings",
            "Local Anky access information",
            "Private recovery material stored in secure device storage",
            "Local credit balance cache",
            "Local export/import files you create"
        ]),
        .paragraph("Writing, saving, revealing, copying, browsing Map, and viewing local history do not require sending your writing to Anky's server."),
        .heading("4. What Leaves Your Device"),
        .paragraph("Data leaves your device in these situations:"),
        .subheading("Asking Anky for a reflection or writing nudge"),
        .paragraph("When you tap **Ask Anky** or request a writing nudge, the app sends the exact `.anky` file bytes to Anky's mirror service."),
        .paragraph("The mirror service:"),
        .bullets([
            "Verifies the request",
            "Verifies the `.anky` format and hash",
            "Reconstructs readable text from the `.anky`",
            "Sends the reconstructed writing and prompt to AI service providers",
            "Receives the generated reflection or nudge",
            "Returns the result to your device",
            "Checks credits for reflections and spends one reflection credit after a successful reflection"
        ]),
        .paragraph("The returned reflection is stored locally on your device."),
        .subheading("Purchases and credits"),
        .paragraph("If you buy reflection credits, purchases are processed by Apple and managed through RevenueCat. We do not receive or store your credit card number."),
        .paragraph("Anky uses purchase-related records, credit balances, product identifiers, entitlement information, app user identifiers, transaction status, and related metadata from Apple and RevenueCat to grant and manage reflection credits."),
        .subheading("Local access and request safety"),
        .paragraph("Anky creates a private local profile for your device. Reflection and nudge requests include limited verification metadata so the mirror service can accept the request, prevent abuse, and return credits to the right profile."),
        .paragraph("Credit operations identify your RevenueCat customer with your Anky profile so credits can be loaded, purchased, and spent correctly."),
        .paragraph("Your private recovery material is not sent to Anky."),
        .subheading("Device trial and abuse prevention"),
        .paragraph("For free trials, abuse prevention, fraud prevention, and request safety, the app asks Apple DeviceCheck for a token when DeviceCheck is supported. Reflection and nudge requests send that token to the mirror service as trial proof. The mirror service also uses timestamps, hashes, app version, platform/client, and request intent."),
        .subheading("iCloud, Keychain, backup, export, and import"),
        .paragraph("When you enable backup, recovery, or export features, the selected writing, reflections, recovery information, or related files are stored using Apple services such as iCloud, iCloud Keychain, device backups, or the destination you choose through the share sheet or file picker."),
        .paragraph("Anky cannot control the privacy of files after you export or share them."),
        .subheading("Support"),
        .paragraph("If you contact support, you choose what to send. Support messages include the email address you send from and any Anky support ID, platform, app version, text, screenshots, files, or context you include."),
        .heading("5. What We Do Not Collect"),
        .paragraph("Anky does not require:"),
        .bullets([
            "Your legal name",
            "Your phone number",
            "Your contacts",
            "Your precise location",
            "Your camera",
            "Your microphone",
            "Your photos",
            "Your social accounts",
            "A traditional username/password login"
        ]),
        .paragraph("Anky does not sell personal data."),
        .paragraph("Anky does not use your writing for advertising."),
        .paragraph("Anky does not use your writing to train Anky-owned AI models."),
        .heading("6. Third-Party Services"),
        .paragraph("Anky uses the following third-party services for the app features described in this policy:"),
        .bullets([
            "**Apple** - App Store purchases, refunds, device services, iCloud, iCloud Keychain, device backup, DeviceCheck, notifications, and platform services.",
            "**RevenueCat** - purchase management, credit balances, entitlements, and transaction-related records.",
            "**OpenRouter** - routing reflection requests to AI model providers.",
            "**AI model providers** - generating reflections from the text you choose to send.",
            "**Cloud hosting / infrastructure providers** - operating Anky's mirror service, logs, security, and reliability.",
            "**Email/support providers** - receiving and responding to support requests."
        ]),
        .paragraph("These providers process data according to their own terms and privacy policies."),
        .heading("7. AI Processing"),
        .paragraph("When you ask for a reflection, your writing is processed by AI systems."),
        .paragraph("AI-generated reflections can be inaccurate, incomplete, unexpected, emotionally intense, or not useful. Reflections are generated automatically and should not be treated as professional advice."),
        .paragraph("We design Anky's mirror service to avoid permanently storing raw `.anky` writing, reconstructed writing, or reflection text unless needed for a user-requested support/debugging flow, security, abuse prevention, legal compliance, or another clearly stated purpose."),
        .paragraph("AI providers process requests according to their own data-handling policies. We use privacy-protective settings where available, but we cannot promise that every downstream provider has identical retention practices."),
        .heading("8. Operational Metadata"),
        .paragraph("To operate Anky, we collect and process limited metadata, such as:"),
        .bullets([
            "Anky support ID or app user identifier",
            "Request timestamps",
            "Request hashes",
            "App version",
            "Platform",
            "Credit balance and credit transaction records",
            "Purchase product identifiers",
            "Error states",
            "Provider usage metadata",
            "Security and abuse-prevention signals",
            "Support request metadata"
        ]),
        .paragraph("We use this data to provide reflections, manage credits, prevent abuse, debug issues, respond to support, comply with law, and operate the service."),
        .heading("9. Payments"),
        .paragraph("Payments are handled by Apple through the App Store and managed with RevenueCat."),
        .paragraph("We do not receive your full payment card details."),
        .paragraph("Refunds, billing disputes, and purchase history are handled according to Apple's policies."),
        .heading("10. Tokens And Public References"),
        .paragraph("Anky may display token or public-reference information when those features are available."),
        .paragraph("Your private recovery material remains on your device unless you export, reveal, back up, or otherwise share it."),
        .paragraph("Never share your recovery words. If you lose them, Anky cannot restore access without a backup you control."),
        .paragraph("Some token, transaction, and public-reference information can be public by nature. Anky cannot delete information written to public networks."),
        .heading("11. Data Retention"),
        .paragraph("Local data remains on your device until you delete it, delete the app, reset the app, or remove backups."),
        .paragraph("Reflection-related operational metadata is retained as long as needed to operate the service, manage credits, prevent fraud or abuse, comply with legal obligations, resolve disputes, and maintain security."),
        .paragraph("Purchase records are retained by Apple, RevenueCat, and Anky as needed for billing, accounting, fraud prevention, tax, legal, and support purposes."),
        .paragraph("Support emails are retained as long as needed to respond to you, keep records, and protect Anky."),
        .heading("12. Deletion"),
        .paragraph("You can delete local writing, local reflections, private access, and local app data from inside the app where deletion tools are available, or by deleting the app from your device."),
        .paragraph("Deleting the app does not delete data outside the app, including:"),
        .bullets([
            "Files you exported or shared",
            "iCloud backups or device backups controlled by Apple settings",
            "App Store purchase records",
            "RevenueCat purchase records",
            "Support emails you sent",
            "Backend metadata needed for security, credit accounting, fraud prevention, legal compliance, or dispute resolution",
            "Public network data"
        ]),
        .paragraph("To request deletion of data Anky controls, contact **[support@anky.app](mailto:support@anky.app)**."),
        .heading("13. Children"),
        .paragraph("Anky is not intended for children under 13."),
        .paragraph("If you are under 18, use Anky only with permission from a parent or guardian."),
        .paragraph("We do not knowingly collect personal information from children under 13. If you believe a child has provided us personal information, contact **[support@anky.app](mailto:support@anky.app)**."),
        .heading("14. Your Rights"),
        .paragraph("Depending on where you live, your rights can include access, correction, deletion, export, restriction, or objection to certain uses of your personal data."),
        .paragraph("Because Anky is local-first, much of your data is only on your device and can be managed by you directly."),
        .paragraph("For requests about data Anky controls, contact **[support@anky.app](mailto:support@anky.app)**."),
        .heading("15. Security"),
        .paragraph("We use reasonable technical and organizational measures to protect data we process."),
        .paragraph("No system is perfectly secure. You are responsible for protecting your device, passcode, recovery words, exported files, iCloud account, and any place where you store or share your writing."),
        .heading("16. International Users"),
        .paragraph("Anky, Inc. is based in the United States. Data sent to Anky or its service providers is processed in the United States or other countries where those providers operate."),
        .heading("17. Changes"),
        .paragraph("We update this Privacy Policy when the policy changes."),
        .paragraph("When we do, we will update the effective date. Continued use of Anky after changes means you accept the updated policy."),
        .heading("18. Contact"),
        .paragraph("**Anky, Inc.**"),
        .paragraph("Contact: **[support@anky.app](mailto:support@anky.app)**")
    ]
}

fileprivate enum PrivacyCopyItem {
    case caption(String)
    case callout(String)
    case heading(String)
    case subheading(String)
    case paragraph(String)
    case bullets([String])
}

private struct PrivacyPolicyReflectionSheet: View {
    var body: some View {
        ZStack {
            PrivacySheetPalette.ink.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privacy Policy")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(PrivacySheetPalette.heading)
                            .tracking(0)

                        Text("Your writing is sacred and we take that seriously. All of the code is open source.")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrivacySheetPalette.paper.opacity(0.54))
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(PrivacyPolicyPage.policyCopy.enumerated()), id: \.offset) { _, item in
                        PrivacyPolicyReflectionLine(item: item)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 52)
            }
        }
    }
}

private struct TermsAndConditionsReflectionSheet: View {
    var body: some View {
        ZStack {
            PrivacySheetPalette.ink.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terms & Conditions")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(PrivacySheetPalette.heading)
                            .tracking(0)

                        Text("Writing and reflection agreement")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrivacySheetPalette.paper.opacity(0.54))
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(Self.termsCopy.enumerated()), id: \.offset) { _, item in
                        PrivacyPolicyReflectionLine(item: item)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 52)
            }
        }
    }

    private static let termsCopy: [PrivacyCopyItem] = [
        .caption("Anky, Inc. - Effective June 7, 2026"),
        .callout("Important: Anky is a writing and reflection app. It is not therapy, medical care, crisis support, financial advice, legal advice, or spiritual authority. By using Anky, you agree that you remain responsible for your writing, your decisions, your device, your recovery words, your purchases, and how you use AI-generated reflections."),
        .heading("1. Acceptance"),
        .paragraph("These Terms and Conditions are an agreement between you and **Anky, Inc.**, a Delaware corporation."),
        .paragraph("By downloading, accessing, or using Anky, you agree to these Terms."),
        .paragraph("If you do not agree, do not use Anky."),
        .heading("2. What Anky Provides"),
        .paragraph("Anky lets you:"),
        .bullets([
            "Write forward-only `.anky` sessions",
            "Save writing locally",
            "Revisit local writing history",
            "Export or import writing files",
            "Manage private Anky access",
            "Buy or use reflection credits",
            "Ask Anky for AI-generated reflections",
            "Use related features we provide over time"
        ]),
        .paragraph("We may change, suspend, or discontinue any part of Anky at any time."),
        .heading("3. Age Requirement"),
        .paragraph("Anky is not intended for children under 13."),
        .paragraph("If you are under 18, you may use Anky only with permission from a parent or guardian."),
        .paragraph("By using Anky, you represent that you meet these requirements."),
        .heading("4. Anky Is Not Professional Advice"),
        .paragraph("Anky is not a therapist, doctor, emergency service, financial advisor, legal advisor, religious authority, or spiritual authority."),
        .paragraph("AI-generated reflections are for personal writing reflection only."),
        .paragraph("They may be inaccurate, incomplete, unexpected, emotionally intense, or not useful."),
        .paragraph("Do not rely on Anky for medical, mental health, legal, financial, emergency, or safety decisions."),
        .paragraph("If you may hurt yourself or someone else, or if you are in immediate danger, contact local emergency services or a trusted person immediately."),
        .heading("5. Your Writing"),
        .paragraph("You own your writing."),
        .paragraph("By using Anky, you give Anky, Inc. a limited permission to process your writing only as needed to provide the features you choose, such as saving locally, generating a reflection, exporting, importing, backing up, debugging, support, security, and abuse prevention."),
        .paragraph("You are responsible for what you write, export, send, share, or back up."),
        .paragraph("Do not write, upload, export, or share content through Anky in a way that violates the law or harms others."),
        .heading("6. Local-First Design"),
        .paragraph("Anky is designed to be local-first."),
        .paragraph("Your writing normally stays on your device."),
        .paragraph("When you ask for a reflection, you understand that your writing is sent to Anky's mirror service and AI service providers to generate the reflection. We use providers that don't store your writing."),
        .paragraph("When you export, share, back up, or contact support, you are choosing to send or store data outside the app."),
        .heading("7. Private Access And Recovery"),
        .paragraph("Anky may create private local access for your device."),
        .paragraph("You are responsible for protecting your recovery words, device passcode, biometric access, iCloud account, and exported files."),
        .paragraph("Never share your recovery words."),
        .paragraph("If you lose your recovery words, Anky may not be able to restore your credits, profile state, or related data."),
        .paragraph("Anky is not responsible for losses caused by lost recovery words, compromised devices, shared credentials, or unauthorized access to your device or accounts."),
        .heading("8. Purchases, Credits, and Refunds"),
        .paragraph("Writing in Anky is free."),
        .paragraph("Reflections may require credits."),
        .paragraph("Credits are digital app credits used only inside Anky for reflection requests. Credits are not money, not cryptocurrency, not stored value, not withdrawable, not redeemable for cash, and not transferable unless we explicitly say otherwise."),
        .paragraph("Purchases are processed through Apple's App Store and may be managed by RevenueCat."),
        .paragraph("We do not handle or store your full payment card details."),
        .paragraph("Refunds are handled by Apple according to Apple's policies."),
        .paragraph("We may change pricing, credit packs, free trials, or credit rules at any time, subject to applicable law and App Store rules."),
        .heading("9. AI-Generated Reflections"),
        .paragraph("AI-generated reflections are produced automatically."),
        .paragraph("You understand that reflections may:"),
        .bullets([
            "Be wrong",
            "Miss important context",
            "Sound more certain than they are",
            "Be emotionally uncomfortable",
            "Fail to understand your language, tone, or intent",
            "Contain unexpected content",
            "Be unavailable because of technical errors"
        ]),
        .paragraph("You remain responsible for interpreting and using any reflection."),
        .paragraph("Anky, Inc. is not responsible for decisions you make based on AI-generated content."),
        .heading("10. Token References"),
        .paragraph("Anky may display token references, public references, or related information."),
        .paragraph("These references are informational only."),
        .paragraph("Nothing in Anky is financial advice, investment advice, tax advice, legal advice, or an offer to buy or sell any token, security, or asset."),
        .paragraph("Using Anky does not require buying, holding, or trading any token."),
        .paragraph("Public-network transactions may be public, irreversible, volatile, risky, and outside Anky's control."),
        .paragraph("You are responsible for your own purchases, transactions, taxes, and financial decisions."),
        .heading("11. User Conduct"),
        .paragraph("You agree not to:"),
        .bullets([
            "Use Anky if you do not meet the age requirements",
            "Use Anky for illegal activity",
            "Abuse, attack, disrupt, or overload Anky's systems",
            "Circumvent credits, paywalls, trials, app attestation, or security controls",
            "Reverse engineer, scrape, extract, or publish Anky's private prompts, model instructions, or backend systems",
            "Use bots, scripts, or automation to abuse the app",
            "Attempt to access another person's data, recovery words, private access, or account",
            "Upload or share content that violates another person's rights",
            "Use Anky to generate instructions for harming yourself or others",
            "Misrepresent Anky, Anky, Inc., or any affiliation with us"
        ]),
        .paragraph("We may suspend, restrict, or terminate access if we believe you violated these Terms, abused the service, created risk, or used Anky unlawfully."),
        .heading("12. Intellectual Property"),
        .paragraph("Anky, Inc. owns Anky's software, design, name, logos, characters, visual assets, prompts, product concepts, documentation, and related intellectual property."),
        .paragraph("You may not copy, modify, distribute, sell, reverse engineer, or create derivative works from Anky except where allowed by law or by an open-source license we explicitly provide."),
        .paragraph("You retain ownership of your own writing."),
        .heading("13. Feedback"),
        .paragraph("If you send us feedback, ideas, suggestions, bug reports, or feature requests, you give Anky, Inc. permission to use them without restriction or compensation."),
        .paragraph("This does not give us ownership of your private writing."),
        .heading("14. Third-Party Services"),
        .paragraph("Anky depends on third-party services, which may include Apple, RevenueCat, OpenRouter, AI model providers, cloud hosting providers, email providers, and public networks."),
        .paragraph("We are not responsible for third-party services, terms, outages, policies, prices, decisions, or data practices."),
        .paragraph("Your use of third-party services may be subject to their terms and privacy policies."),
        .heading("15. App Store Terms"),
        .paragraph("If you downloaded Anky from Apple's App Store, Apple's terms also apply."),
        .paragraph("Apple is not responsible for Anky, its content, support, warranties, or claims, except as required by applicable law or Apple's own terms."),
        .heading("16. Availability"),
        .paragraph("Anky may be unavailable, delayed, interrupted, inaccurate, or discontinued."),
        .paragraph("We do not guarantee that Anky will always work, that reflections will always be available, that credits will always sync instantly, or that local data will never be lost."),
        .paragraph("Back up anything important."),
        .heading("17. Termination"),
        .paragraph("You may stop using Anky at any time."),
        .paragraph("You can delete the app and delete local data where the app provides deletion tools."),
        .paragraph("We may suspend, limit, or terminate your access to Anky at any time if we believe it is necessary to protect Anky, users, third parties, or the integrity of the service."),
        .heading("18. Disclaimer of Warranties"),
        .paragraph("ANKY IS PROVIDED \"AS IS\" AND \"AS AVAILABLE.\""),
        .paragraph("TO THE FULLEST EXTENT PERMITTED BY LAW, ANKY, INC. DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, NON-INFRINGEMENT, ACCURACY, AVAILABILITY, SECURITY, AND RELIABILITY."),
        .paragraph("YOUR USE OF ANKY IS AT YOUR OWN RISK."),
        .heading("19. Limitation of Liability"),
        .paragraph("TO THE FULLEST EXTENT PERMITTED BY LAW, ANKY, INC. AND ITS OWNERS, DIRECTORS, OFFICERS, EMPLOYEES, CONTRACTORS, SERVICE PROVIDERS, AND AFFILIATES WILL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR LOST PROFITS, LOST DATA, LOST WRITING, LOST CREDITS, LOST TOKENS, LOST RECOVERY ACCESS, DEVICE COMPROMISE, EMOTIONAL DISTRESS, OR DECISIONS MADE BASED ON AI-GENERATED CONTENT."),
        .paragraph("TO THE FULLEST EXTENT PERMITTED BY LAW, ANKY, INC.'S TOTAL LIABILITY FOR ANY CLAIM WILL NOT EXCEED THE GREATER OF:"),
        .paragraph("(A) THE AMOUNT YOU PAID TO ANKY, INC. THROUGH THE APP IN THE 12 MONTHS BEFORE THE CLAIM, OR"),
        .paragraph("(B) $50 USD."),
        .paragraph("Some jurisdictions do not allow certain limitations, so some of these limits may not apply to you."),
        .heading("20. Indemnification"),
        .paragraph("You agree to defend, indemnify, and hold harmless Anky, Inc. and its owners, directors, officers, employees, contractors, service providers, and affiliates from claims, damages, losses, liabilities, costs, and expenses arising from:"),
        .bullets([
            "Your use of Anky",
            "Your writing or exported content",
            "Your violation of these Terms",
            "Your violation of law",
            "Your violation of another person's rights",
            "Your misuse of AI-generated reflections",
            "Your token, transaction, or recovery activity"
        ]),
        .heading("21. Governing Law"),
        .paragraph("These Terms are governed by the laws of the State of Delaware, without regard to conflict-of-law principles, except where your local law requires otherwise."),
        .heading("22. Disputes and Arbitration"),
        .paragraph("To the fullest extent permitted by law, disputes between you and Anky, Inc. will be resolved through binding individual arbitration, not in a class action or jury trial."),
        .paragraph("You and Anky, Inc. agree to bring claims only on an individual basis."),
        .paragraph("This section does not prevent either party from seeking relief in small claims court or seeking injunctive relief for intellectual property, security, or unauthorized access issues."),
        .paragraph("If this arbitration section is not enforceable where you live, the rest of these Terms still apply."),
        .heading("23. Changes"),
        .paragraph("We may update these Terms from time to time."),
        .paragraph("When we do, we will update the effective date. Continued use of Anky after changes means you accept the updated Terms."),
        .heading("24. Contact"),
        .paragraph("**Anky, Inc.**"),
        .paragraph("Contact: **[support@anky.app](mailto:support@anky.app)**")
    ]
}

private struct PrivacyPolicyReflectionLine: View {
    let item: PrivacyCopyItem

    var body: some View {
        switch item {
        case .caption(let text):
            Text(AnkyLocalization.ui(text))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(PrivacySheetPalette.paper.opacity(0.46))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .callout(let text):
            Text(attributedText(from: text))
                .font(.system(size: 16, weight: .semibold))
                .lineSpacing(5)
                .foregroundStyle(PrivacySheetPalette.paper)
                .tint(PrivacySheetPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(PrivacySheetPalette.gold.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(PrivacySheetPalette.gold.opacity(0.22), lineWidth: 1)
                        )
                )
                .textSelection(.enabled)
        case .heading(let text):
            Text(AnkyLocalization.ui(text))
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(PrivacySheetPalette.heading)
                .tracking(0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        case .subheading(let text):
            Text(AnkyLocalization.ui(text))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PrivacySheetPalette.gold)
                .tracking(0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        case .paragraph(let text):
            Text(attributedText(from: text))
                .font(.system(size: 16))
                .lineSpacing(6)
                .foregroundStyle(PrivacySheetPalette.paper)
                .tint(PrivacySheetPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("•")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(PrivacySheetPalette.gold)
                        Text(attributedText(from: text))
                            .font(.system(size: 16))
                            .lineSpacing(5)
                            .foregroundStyle(PrivacySheetPalette.paper)
                            .tint(PrivacySheetPalette.gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.leading, 3)
        }
    }

    private func attributedText(from text: String) -> AttributedString {
        let localized = AnkyLocalization.ui(text)
        return (try? AttributedString(markdown: localized)) ?? AttributedString(localized)
    }
}

private enum PrivacySheetPalette {
    static let ink = Color(hex: 0x080713)
    static let paper = Color(hex: 0xFFF0C9)
    static let gold = Color(hex: 0xE8C879)
    static let heading = Color(hex: 0xF6D978)
    static let violet = Color(hex: 0x6F5DFF)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private struct PrivacyCopyLine: View {
    let item: PrivacyCopyItem

    init(_ item: PrivacyCopyItem) {
        self.item = item
    }

    var body: some View {
        switch item {
        case .caption(let text):
            Text(AnkyLocalization.ui(text))
                .youCaption()
        case .callout(let text):
            Text(attributedText(from: text))
                .font(.system(size: 16, weight: .semibold))
                .lineSpacing(5)
                .foregroundStyle(YouPalette.paper)
                .tint(YouPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(YouPalette.gold.opacity(0.08))
                )
        case .heading(let text):
            Text(AnkyLocalization.ui(text))
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(YouPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        case .subheading(let text):
            Text(AnkyLocalization.ui(text))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(YouPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text):
            MarkdownArticleText(text)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(YouPalette.gold)
                        MarkdownArticleText(text)
                    }
                }
            }
        }
    }

    private func attributedText(from text: String) -> AttributedString {
        let localized = AnkyLocalization.ui(text)
        return (try? AttributedString(markdown: localized)) ?? AttributedString(localized)
    }
}

private struct ExportDataPage: View {
    @ObservedObject var viewModel: YouViewModel
    @Binding var isImportingBackup: Bool
    @Binding var confirmClearWritingData: Bool

    var body: some View {
        YouDetailShell(title: "Export data", subtitle: "Your archive is yours") {
            YouPanel {
                Text(AnkyLocalization.ui("%d writings · %d reflections", viewModel.ankyFileURLs.count, viewModel.reflectionFileURLs.count))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(YouPalette.gold)

                Text(AnkyLocalization.ui("Readable exports include plaintext writing. Keep them somewhere private."))
                    .youBody()
            }

            YouPanel {
                if let formattedWritingExportURL = viewModel.formattedWritingExportURL {
                    ShareLink(item: formattedWritingExportURL) {
                        YouActionLabel(AnkyLocalization.ui("Export writings"))
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        AnkyHaptics.light()
                    })
                } else {
                    YouDisabledRow(AnkyLocalization.ui("No writing to export yet"))
                }
            }

            YouPanel {
                YouToggleRow(
                    isOn: iCloudBackupBinding,
                    iconName: "icloud",
                    title: AnkyLocalization.ui("Encrypted iCloud backup"),
                    subtitle: AnkyLocalization.ui(viewModel.isICloudBackupEnabled ? "On" : "Off")
                )

                Text(AnkyLocalization.ui(viewModel.isICloudBackupEnabled ? "Anky backs up writing and reflections after each writing session." : "Turn this on for iCloud recovery after reinstalling."))
                    .youBody()

                if let lastDate = viewModel.iCloudBackupLastDate {
                    Text(AnkyLocalization.ui("Last backup: %@", lastDate.formatted(date: .abbreviated, time: .shortened)))
                        .youBody()
                }

                if viewModel.isICloudBackupEnabled {
                    YouActionButton(AnkyLocalization.ui(viewModel.isICloudBackupWorking ? "Backing up" : "Back up now")) {
                        Task { await viewModel.backUpToICloudNow() }
                    }
                }
            }

            YouDangerPanel {
                Text(AnkyLocalization.ui("Danger zone"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(YouPalette.danger)
                Text(AnkyLocalization.ui("This removes local .anky files, local reflections, and the local map index from this device. Export a backup first if you want to keep them."))
                    .youBody()
                YouActionButton(AnkyLocalization.ui("Delete local data"), role: .destructive) {
                    confirmClearWritingData = true
                }
            }
        }
        .onAppear {
            viewModel.prepareFormattedWritingExport()
        }
    }

    private var iCloudBackupBinding: Binding<Bool> {
        Binding {
            viewModel.isICloudBackupEnabled
        } set: { isEnabled in
            if isEnabled {
                Task { await viewModel.enableICloudBackup() }
            } else {
                viewModel.disableICloudBackup()
            }
        }
    }
}

struct CreditsPage: View {
    @ObservedObject var viewModel: YouViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        YouDetailShell(title: "credits", subtitle: "reflection fuel") {
            YouPanel {
                Text(viewModel.creditDetailTitle)
                    .font(.system(size: 62, weight: .bold))
                    .foregroundStyle(YouPalette.gold)
                    .shadow(color: YouPalette.gold.opacity(0.35), radius: 18)
                Text(viewModel.creditDetailCaption)
                    .youCaption()
            }

            YouPanel {
                YouRuleRow(AnkyLocalization.ui("1 credit = reflection"))
                YouRuleRow(AnkyLocalization.ui("ask anky spends one credit"))
                YouRuleRow(AnkyLocalization.ui("writing is always free"))
            }

            YouPanel {
                if viewModel.hasUnspentGiftCredit {
                    YouDisabledRow(AnkyLocalization.text(.creditPacksLocked))
                    Text(AnkyLocalization.text(.creditGiftDetail))
                        .youBody()
                } else if viewModel.creditsLoading && viewModel.creditPackages.isEmpty {
                    YouDisabledRow(AnkyLocalization.ui("loading credit packs"))
                } else if viewModel.creditPackages.isEmpty {
                    YouDisabledRow(AnkyLocalization.ui("no credit packs available"))
                } else {
                    ForEach(viewModel.creditPackages) { creditPackage in
                        CreditPackageButton(
                            creditPackage: creditPackage,
                            isPurchasing: viewModel.purchasingCreditPackageID == creditPackage.id
                        ) {
                            AnkyHaptics.light()
                            Task {
                                await viewModel.purchaseCredits(creditPackage)
                            }
                        }
                    }
                }

                YouActionButton(AnkyLocalization.ui("refresh credits")) {
                    Task {
                        await viewModel.refreshCredits()
                    }
                }
            }

            YouPanel {
                YouActionButton(AnkyLocalization.ui("support / feedback")) {
                    if let emailURL = viewModel.supportFeedbackEmailURL {
                        openURL(emailURL)
                    }
                }

                Text(AnkyLocalization.ui("email support@anky.app. include only what you choose to write."))
                    .youBody()
            }
        }
    }
}

private struct CreditPackageButton: View {
    let creditPackage: RevenueCatCreditPackage
    let isPurchasing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AnkyLocalization.ui(creditPackage.title))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(YouPalette.paper)
                    Text(AnkyLocalization.ui(creditPackage.subtitle))
                        .youCaption()
                }

                Spacer()

                Text(isPurchasing ? "..." : creditPackage.price)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(YouPalette.gold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(YouPalette.buttonFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(YouPalette.gold.opacity(0.32), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }
}

private struct MarkdownArticleText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(attributedText)
            .font(.system(size: 16))
            .lineSpacing(5)
            .foregroundStyle(YouPalette.paper)
            .tint(YouPalette.gold)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedText: AttributedString {
        let localized = AnkyLocalization.ui(text)
        return (try? AttributedString(markdown: localized)) ?? AttributedString(localized)
    }
}

private struct AnkyExperienceView: View {
    @StateObject private var viewModel = AnkyExperienceViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showCopyPrompt = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if !viewModel.isFinished {
                ExperienceForwardOnlyTextView(
                    text: viewModel.activeDisplayedText,
                    focusID: viewModel.keyboardFocusID,
                    shouldFocus: true,
                    onCharacter: viewModel.accept
                )
                .padding(24)
            }

            VStack {
                HStack {
                    Text(viewModel.elapsedClockText)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.58))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityLabel(AnkyLocalization.ui("Anky experience time %@", viewModel.elapsedClockText))

                    Spacer()

                    Button {
                        viewModel.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.72))
                            .frame(width: 42, height: 42)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AnkyLocalization.ui("Close The Anky Experience"))
                }

                Spacer()
            }
            .safeAreaPadding(.top, 8)
            .padding(.horizontal, 12)

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showCopyPrompt = true
                        }
                    } label: {
                        AnkyWitnessView(mood: .warm, size: .small, sequence: .idleBlink)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AnkyLocalization.ui("Anky companion"))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }

            if showCopyPrompt {
                VStack {
                    Spacer()

                    AnkyConversationPromptView(
                        message: AnkyLocalization.ui("copy your .anky or copy your writing."),
                        actions: [
                            AnkyChatAction(AnkyLocalization.ui("copy your .anky"), isPrimary: true) {
                                viewModel.copyCurrentAnky()
                            },
                            AnkyChatAction(AnkyLocalization.ui("copy your writing")) {
                                viewModel.copyCurrentWriting()
                            }
                        ],
                        close: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showCopyPrompt = false
                            }
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 76)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

private struct ExperienceCopyControls: View {
    @ObservedObject var viewModel: AnkyExperienceViewModel

    var body: some View {
        VStack(spacing: 10) {
            if viewModel.canCopyOpening {
                HStack(spacing: 10) {
                    ExperienceActionButton(
                        title: viewModel.lastCopiedAction == .openingAnky ? "copied .anky" : "copy opening .anky",
                        systemName: "doc.on.doc"
                    ) {
                        viewModel.copyOpeningAnky()
                    }

                    ExperienceActionButton(
                        title: viewModel.lastCopiedAction == .openingText ? "copied text" : "copy opening text",
                        systemName: "text.quote"
                    ) {
                        viewModel.copyOpeningText()
                    }
                }
            }

            if viewModel.canCopyClosing {
                HStack(spacing: 10) {
                    ExperienceActionButton(
                        title: viewModel.lastCopiedAction == .closingAnky ? "copied .anky" : "copy closing .anky",
                        systemName: "doc.on.doc"
                    ) {
                        viewModel.copyClosingAnky()
                    }

                    ExperienceActionButton(
                        title: viewModel.lastCopiedAction == .closingText ? "copied text" : "copy closing text",
                        systemName: "text.quote"
                    ) {
                        viewModel.copyClosingText()
                    }
                }
            }
        }
    }
}

private struct ExperienceActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(Color.primary.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ExperiencePortalRing: View {
    let progress: Double
    let clockText: String
    let subtitle: String

    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .indigo, .purple, .white
    ]

    var body: some View {
        ZStack {
            ForEach(colors.indices, id: \.self) { index in
                ExperienceRingSegment(
                    index: index,
                    progress: 1,
                    color: colors[index].opacity(0.18),
                    lineWidth: 12
                )

                ExperienceRingSegment(
                    index: index,
                    progress: progress,
                    color: colors[index],
                    lineWidth: 12
                )
            }

            Circle()
                .fill(.thinMaterial)
                .frame(width: 176, height: 176)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

            VStack(spacing: 8) {
                Text(clockText)
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(AnkyLocalization.ui(subtitle))
                    .font(.system(size: 11, weight: .medium))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.secondary.opacity(0.86))
                    .frame(width: 128)
            }
        }
        .frame(width: 220, height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AnkyLocalization.ui("%@. %@", clockText, subtitle))
    }
}

private struct ExperienceRingSegment: View {
    let index: Int
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        let start = Double(index) / 8
        let end = min(Double(index + 1) / 8, progress)
        Circle()
            .trim(from: start, to: max(start, end))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .frame(width: 206, height: 206)
    }
}

@MainActor
private final class AnkyExperienceViewModel: ObservableObject {
    @Published private(set) var phase: AnkyExperiencePhase = .openingAnky
    @Published private(set) var totalRemainingSeconds = Constants.totalSeconds
    @Published private(set) var keyboardFocusID = UUID()
    @Published private(set) var openingDisplayedText = ""
    @Published private(set) var closingDisplayedText = ""
    @Published private(set) var openingProtocolText = ""
    @Published private(set) var closingProtocolText = ""
    @Published private(set) var lastCopiedAction: AnkyExperienceCopyAction?

    private var openingWriter = AnkyWriter()
    private var closingWriter = AnkyWriter()
    private var startDate: Date?
    private var tickerTask: Task<Void, Never>?
    private var openingClosed = false
    private var closingClosed = false
    private var warningBellPlayed = false
    private var closingBellPlayed = false
    private var finishedBellPlayed = false

    var isWriting: Bool {
        phase != .finished
    }

    var isFinished: Bool {
        phase == .finished
    }

    var activeDisplayedText: String {
        openingDisplayedText
    }

    var canCopyOpening: Bool {
        !openingProtocolText.isEmpty
    }

    var canCopyClosing: Bool {
        closingClosed && !closingProtocolText.isEmpty
    }

    var shouldShowCopyControls: Bool {
        !isWriting && (canCopyOpening || canCopyClosing)
    }

    var totalProgress: Double {
        1 - Double(totalRemainingSeconds) / Double(Constants.totalSeconds)
    }

    var clockText: String {
        Self.clock(totalRemainingSeconds)
    }

    var elapsedClockText: String {
        Self.clock(Constants.totalSeconds - totalRemainingSeconds)
    }

    var centerSubtitle: String {
        switch phase {
        case .openingAnky:
            return AnkyLocalization.ui("the experience is open")
        case .portal:
            return AnkyLocalization.ui("the experience is open")
        case .closingWarning:
            return AnkyLocalization.ui("the experience is open")
        case .closingAnky:
            return AnkyLocalization.ui("the experience is open")
        case .finished:
            return AnkyLocalization.ui("the experience is complete")
        }
    }

    func start() {
        guard tickerTask == nil else {
            return
        }

        startDate = Date()
        phase = .openingAnky
        totalRemainingSeconds = Constants.totalSeconds
        playBell()
        keyboardFocusID = UUID()
        startTicker()
    }

    func stop() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    func accept(_ character: Character) {
        let now = Self.nowMs()
        guard phase != .finished else {
            return
        }
        guard openingWriter.accept(character, at: now) else { return }
        openingDisplayedText.append(character)
        openingProtocolText = openingWriter.text
    }

    func copyCurrentAnky() {
        copy(openingProtocolText, action: .openingAnky)
    }

    func copyCurrentWriting() {
        copy(parsedText(from: openingProtocolText, fallback: openingDisplayedText), action: .openingText)
    }

    func copyOpeningAnky() {
        copy(openingProtocolText, action: .openingAnky)
    }

    func copyOpeningText() {
        copy(parsedText(from: openingProtocolText, fallback: openingDisplayedText), action: .openingText)
    }

    func copyClosingAnky() {
        copy(closingProtocolText, action: .closingAnky)
    }

    func copyClosingText() {
        copy(parsedText(from: closingProtocolText, fallback: closingDisplayedText), action: .closingText)
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let startDate else {
            return
        }

        let elapsed = max(0, Int(Date().timeIntervalSince(startDate)))
        totalRemainingSeconds = max(0, Constants.totalSeconds - elapsed)

        if elapsed >= Constants.totalSeconds, !openingClosed {
            finishOpeningAnky()
        }

        let nextPhase = Self.phase(forElapsed: elapsed)
        if nextPhase != phase {
            withAnimation(.easeInOut(duration: 0.24)) {
                phase = nextPhase
            }
        }

        if nextPhase == .finished, !finishedBellPlayed {
            finishedBellPlayed = true
            playBell()
            stop()
        }
    }

    private func finishOpeningAnky() {
        openingClosed = true
        guard openingWriter.isStarted, !openingWriter.isClosed else {
            return
        }
        openingWriter.closeWithTerminalSilence()
        openingProtocolText = openingWriter.text
    }

    private func finishClosingAnky() {
        closingClosed = true
        guard closingWriter.isStarted, !closingWriter.isClosed else {
            return
        }
        closingWriter.closeWithTerminalSilence()
        closingProtocolText = closingWriter.text
    }

    private func copy(_ text: String, action: AnkyExperienceCopyAction) {
        guard !text.isEmpty else {
            return
        }
        ClipboardClient().copy(text)
        lastCopiedAction = action
    }

    private func parsedText(from protocolText: String, fallback: String) -> String {
        guard let parsed = try? AnkyParser.parse(protocolText) else {
            return fallback
        }
        return AnkyReconstructor.reconstructText(parsed)
    }

    private func playBell() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }

    private static func phase(forElapsed elapsed: Int) -> AnkyExperiencePhase {
        if elapsed >= Constants.totalSeconds {
            return .finished
        }
        return .openingAnky
    }

    private static func clock(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let minutes = safeSeconds / 60
        let seconds = safeSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private enum Constants {
        static let totalSeconds = 88 * 60
    }
}

private enum AnkyExperiencePhase: Equatable {
    case openingAnky
    case portal
    case closingWarning
    case closingAnky
    case finished
}

private enum AnkyExperienceCopyAction {
    case openingAnky
    case openingText
    case closingAnky
    case closingText
}

private struct ExperienceForwardOnlyTextView: UIViewRepresentable {
    let text: String
    let focusID: UUID
    let shouldFocus: Bool
    let onCharacter: (Character) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .title3)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = UIColor.label.withAlphaComponent(0.34)
        textView.tintColor = UIColor.label.withAlphaComponent(0.62)
        textView.textAlignment = .natural
        textView.keyboardDismissMode = .none
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true

        if shouldFocus {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if context.coordinator.focusID != focusID {
            context.coordinator.focusID = focusID
            if shouldFocus {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        }

        if shouldFocus, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }

        let end = uiView.endOfDocument
        uiView.selectedTextRange = uiView.textRange(from: end, to: end)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(focusID: focusID, onCharacter: onCharacter)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var focusID: UUID
        private let onCharacter: (Character) -> Void

        init(focusID: UUID, onCharacter: @escaping (Character) -> Void) {
            self.focusID = focusID
            self.onCharacter = onCharacter
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard range.length == 0,
                  replacement.count == 1,
                  let character = replacement.first,
                  character != "\n",
                  character != "\r" else {
                return false
            }

            onCharacter(character)
            return false
        }
    }
}

private struct ImportRecoveryPhraseSheet: View {
    @ObservedObject var viewModel: YouViewModel
    @Binding var recoveryPhraseInput: String
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                YouCosmicBackground()
                VStack(spacing: 16) {
                    TextEditor(text: $recoveryPhraseInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(YouPalette.paper)
                        .padding(12)
                        .frame(minHeight: 140)
                        .background(YouPalette.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(YouPalette.goldDim, lineWidth: 1))

                    Text(AnkyLocalization.ui("recovering replaces the private access used for Ask Anky and future credit balances. local .anky files stay on this device."))
                        .youBody()

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(AnkyLocalization.ui("recover access"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AnkyLocalization.ui("cancel")) {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AnkyLocalization.ui("recover")) {
                        Task {
                            if await viewModel.importRecoveryPhrase(recoveryPhraseInput) {
                                isPresented = false
                            }
                        }
                    }
                    .disabled(recoveryPhraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct YouDetailShell<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            YouCosmicBackground()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(YouPalette.gold)
                            .frame(width: 44, height: 44)
                            .background(YouPalette.panel, in: Circle())
                            .overlay(Circle().stroke(YouPalette.goldDim, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 3) {
                        Text(AnkyLocalization.ui(title))
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(YouPalette.gold)
                        Text(AnkyLocalization.ui(subtitle))
                            .font(.system(size: 12))
                            .foregroundStyle(YouPalette.paperMuted)
                    }

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 18)
                .padding(.top, 64)
                .padding(.bottom, 14)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBackGesture()
    }
}

private struct YouCosmicBackground: View {
    var body: some View {
        ZStack {
            Image("you-bg-cosmos")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Color(red: 5 / 255, green: 5 / 255, blue: 14 / 255)
                .opacity(0.32)
                .ignoresSafeArea()
        }
    }
}

private struct YouTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(AnkyLocalization.ui(title))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(YouPalette.gold)
            if !subtitle.isEmpty {
                Text(AnkyLocalization.ui(subtitle))
                    .font(.system(size: 14))
                    .foregroundStyle(YouPalette.paperMuted)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct YouAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(YouPalette.gold.opacity(0.72), lineWidth: 1.5)
                .frame(width: 124, height: 124)
                .shadow(color: YouPalette.gold.opacity(0.24), radius: 16)

            Circle()
                .stroke(YouPalette.gold.opacity(0.42), lineWidth: 1)
                .frame(width: 116, height: 116)

            Image("you-avatar-anky")
                .resizable()
                .scaledToFill()
                .frame(width: 108, height: 108)
                .clipShape(Circle())

            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(YouPalette.gold)
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(45))
                    .offset(y: -68)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
        .frame(width: 144, height: 144)
    }
}

private struct YouStatsPanel: View {
    let ankys: Int
    let minutes: Int
    let streak: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            YouPanel(spacing: 0) {
                HStack(spacing: 0) {
                    YouStatCell(icon: "you-icon-feather-stat", value: "\(ankys)", label: "Ankys")
                    YouVerticalDivider()
                    YouStatCell(icon: "you-icon-clock-stat", value: "\(minutes)", label: "Minutes")
                    YouVerticalDivider()
                    YouStatCell(icon: "you-icon-flame-stat", value: "\(streak)", label: "Streak")
                }
            }
            .frame(height: 68)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AnkyLocalization.ui("Open all ankys"))
    }
}

private struct YouStatCell: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(YouPalette.paper)
                Text(AnkyLocalization.ui(label))
                    .font(.system(size: 10))
                    .foregroundStyle(YouPalette.paperMuted)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct YouMenuRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var showsDisclosure = true

    var body: some View {
        HStack(spacing: 13) {
            YouMenuIcon(icon: icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(AnkyLocalization.ui(title))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(YouPalette.paper)
                Text(AnkyLocalization.ui(subtitle))
                    .font(.system(size: 12))
                    .foregroundStyle(YouPalette.paperMuted)
            }

            Spacer()

            if showsDisclosure {
                Image("you-icon-chevron-right")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .opacity(0.82)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 14)
    }
}

private struct YouDataToggleRow: View {
    @Binding var isOn: Bool
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Button {
                AnkyHaptics.light()
                action()
            } label: {
                HStack(spacing: 13) {
                    YouMenuIcon(icon: icon)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(AnkyLocalization.ui(title))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(YouPalette.paper)
                        Text(AnkyLocalization.ui(subtitle))
                            .font(.system(size: 12))
                            .foregroundStyle(YouPalette.paperMuted)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(AnkyLocalization.ui(title), isOn: $isOn)
                .labelsHidden()
                .tint(YouPalette.gold)
                .accessibilityLabel(AnkyLocalization.ui("Encrypted iCloud backup"))
        }
        .padding(.vertical, 14)
    }
}

private struct YouToggleRow: View {
    @Binding var isOn: Bool
    let iconName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: iconName)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(YouPalette.gold)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(AnkyLocalization.ui(title))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(YouPalette.paper)
                Text(AnkyLocalization.ui(subtitle))
                    .font(.system(size: 12))
                    .foregroundStyle(YouPalette.paperMuted)
            }

            Spacer()

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(YouPalette.gold)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct YouMenuIcon: View {
    let icon: String

    private var systemName: String {
        switch icon {
        case "you-icon-account":
            return "person"
        case "you-icon-privacy":
            return "shield"
        case "you-icon-terms":
            return "doc.text"
        case "you-icon-export":
            return "square.and.arrow.down"
        case "you-icon-credits":
            return "sparkles"
        case "you-icon-support":
            return "ellipsis.message"
        case "you-icon-faceid":
            return "faceid"
        case "you-icon-anky-token":
            return "dollarsign.circle"
        default:
            return "circle"
        }
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 21, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(YouPalette.gold)
            .frame(width: 24, height: 24)
    }
}

private struct YouDestructiveMenuRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "trash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(YouPalette.danger)
                .frame(width: 24, height: 24)

            Text(AnkyLocalization.ui(title))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(YouPalette.danger)
                .lineLimit(1)

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 14)
    }
}

private struct YouPanel<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YouPalette.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(YouPalette.goldDim, lineWidth: 1)
        )
    }
}

private struct YouDangerPanel<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.18, green: 0.035, blue: 0.055).opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(YouPalette.danger.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct YouActionButton: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            if role == .destructive {
                AnkyHaptics.warning()
            } else {
                AnkyHaptics.light()
            }
            action()
        } label: {
            YouActionLabel(title, destructive: role == .destructive)
        }
        .buttonStyle(.plain)
    }
}

private struct YouActionLabel: View {
    let title: String
    var destructive = false

    init(_ title: String, destructive: Bool = false) {
        self.title = title
        self.destructive = destructive
    }

    var body: some View {
        Text(AnkyLocalization.ui(title))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(destructive ? YouPalette.danger : YouPalette.gold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(YouPalette.buttonFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke((destructive ? YouPalette.danger : YouPalette.gold).opacity(0.38), lineWidth: 1)
            )
    }
}

private struct YouDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(AnkyLocalization.ui(title))
                .youCaption()
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(YouPalette.paper)
        }
    }
}

private struct YouRuleRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(YouPalette.gold.opacity(0.72))
                .frame(width: 5, height: 5)
            Text(AnkyLocalization.ui(text))
                .youBody()
        }
    }
}

private struct YouDisabledRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(AnkyLocalization.ui(text))
            .youBody()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(YouPalette.panelStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct YouDivider: View {
    var body: some View {
        Rectangle()
            .fill(YouPalette.gold.opacity(0.13))
            .frame(height: 1)
    }
}

private struct YouVerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(YouPalette.gold.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}

private enum YouPalette {
    static let ink = Color(red: 0.031, green: 0.027, blue: 0.071)
    static let panel = Color(red: 0.08, green: 0.055, blue: 0.15).opacity(0.72)
    static let panelStrong = Color(red: 0.075, green: 0.061, blue: 0.13).opacity(0.82)
    static let buttonFill = Color(red: 0.19, green: 0.13, blue: 0.09).opacity(0.74)
    static let gold = Color(red: 0.91, green: 0.79, blue: 0.48)
    static let goldDim = gold.opacity(0.32)
    static let paper = Color(red: 1, green: 0.94, blue: 0.79)
    static let paperMuted = Color(red: 0.86, green: 0.81, blue: 0.92).opacity(0.72)
    static let danger = Color(red: 0.97, green: 0.44, blue: 0.44)
}

private extension Text {
    func youBody() -> some View {
        self
            .font(.system(size: 14))
            .lineSpacing(3)
            .foregroundStyle(YouPalette.paperMuted)
    }

    func youCaption() -> some View {
        self
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(YouPalette.gold.opacity(0.88))
    }
}

private extension View {
    func enableSwipeBackGesture() -> some View {
        background(SwipeBackGestureEnabler().frame(width: 0, height: 0))
    }
}

private struct SwipeBackGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            enableGesture(from: controller)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            enableGesture(from: uiViewController)
        }
    }

    private func enableGesture(from controller: UIViewController) {
        guard let navigationController = controller.navigationController else { return }
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        navigationController.interactivePopGestureRecognizer?.delegate = nil
    }
}
