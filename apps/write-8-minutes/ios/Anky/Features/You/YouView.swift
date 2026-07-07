import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AudioToolbox

struct YouView: View {
    @ObservedObject var viewModel: YouViewModel
    let onWriteRequested: () -> Void
    let onDevelopmentWipe: () -> Void
    let onGateSetupRequested: () -> Void
    let onBack: () -> Void
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
    @State private var showsAccountDeletion = false
    @State private var promptAutoDismissTask: Task<Void, Never>?
    @State private var dailyTargetMinutes = DailyTargetStore.defaultMinutes
    @State private var pendingDailyTargetMinutes: Int?

    init(
        viewModel: YouViewModel,
        onWriteRequested: @escaping () -> Void = {},
        onDevelopmentWipe: @escaping () -> Void = {},
        onGateSetupRequested: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onWriteRequested = onWriteRequested
        self.onDevelopmentWipe = onDevelopmentWipe
        self.onGateSetupRequested = onGateSetupRequested
        self.onBack = onBack
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
            ZStack {
                YouCosmicBackground()

                VStack(spacing: 20) {
                        YouPanel(spacing: 0) {
                        legalButton(icon: "you-icon-settings", title: "Customize your Anky experience", subtitle: "Daily target, name, writing, font, protection.") {
                            path.append(YouRoute.settings)
                        }

                        YouDivider()

                        dataRow

                        YouDivider()

                        legalButton(icon: "you-icon-settings", title: "Write Before You Scroll", subtitle: "Choose the apps Anky gates.") {
                            onGateSetupRequested()
                        }

                        YouDivider()

                        dailyTargetRow

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
            .onAppear {
                refreshDailyTarget()
            }
            .navigationTitle(AnkyLocalization.ui("You"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.ankyInk)
                            .frame(width: 34, height: 38)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(AnkyLocalization.ui("Back to today"))
                }
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
                            .foregroundStyle(Color.ankyMadder.opacity(0.88))
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
                case .account:
                    AccountPage(
                        viewModel: viewModel,
                        dailyReminderEnabled: $dailyReminderEnabled,
                        dailyReminderTime: $dailyReminderTime,
                        biometricIdentityConfirmation: $biometricIdentityConfirmation,
                        isImportingRecoveryPhrase: $isImportingRecoveryPhrase,
                        recoveryPhraseInput: $recoveryPhraseInput,
                        reminderDate: reminderDate,
                        reminderBinding: reminderBinding
                    )
                case .settings:
                    AnkySettingsView(
                        viewModel: viewModel,
                        onGateSetupRequested: onGateSetupRequested
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
                    MissingYouAnkyView()
                }
            }
            }
        }
        .sheet(isPresented: $showsPrivacyPolicy) {
            PrivacyPolicyReflectionSheet()
                .presentationDetents([.fraction(0.8)])
                .presentationDragIndicator(.visible)
                .ankySheetBackground(PrivacySheetPalette.ink)
        }
        .sheet(isPresented: $showsTermsAndConditions) {
            TermsAndConditionsReflectionSheet()
                .presentationDetents([.fraction(0.8)])
                .presentationDragIndicator(.visible)
                .ankySheetBackground(PrivacySheetPalette.ink)
        }
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
        .onChange(of: viewModel.statusMessage) { statusMessage in
            guard statusMessage != nil else { return }
            isShowingSystemPrompt = true
            presentCurrentPromptIfNeeded()
        }
        .onChange(of: viewModel.errorMessage) { errorMessage in
            guard errorMessage != nil else { return }
            isShowingSystemPrompt = true
            presentCurrentPromptIfNeeded()
        }
        .onChange(of: viewModel.isICloudBackupEnabled) { _ in
            if activePrompt == .export, !isShowingSystemPrompt {
                presentCurrentPromptIfNeeded()
            }
        }
        .onChange(of: viewModel.iCloudBackupLastDate) { _ in
            if activePrompt == .export, !isShowingSystemPrompt {
                presentCurrentPromptIfNeeded()
            }
        }
        .onChange(of: viewModel.isICloudBackupWorking) { _ in
            if activePrompt == .export, !isShowingSystemPrompt {
                presentCurrentPromptIfNeeded()
            }
        }
    }

    private func promptButton(_ prompt: YouPrompt, icon: String, title: String, subtitle: String) -> some View {
        Button {
            AnkyHaptics.light()
            openPrompt(prompt)
        } label: {
            YouMenuRow(icon: icon, title: title, subtitle: subtitle, showsDisclosure: false)
        }
        .buttonStyle(.plain)
    }

    private var dailyTargetRow: some View {
        HStack(spacing: 13) {
            Image(systemName: "timer")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(YouPalette.gold)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(AnkyLocalization.ui("Daily target"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(YouPalette.paper)
                Text(AnkyLocalization.ui(dailyTargetSubtitle))
                    .font(.system(size: 12))
                    .foregroundStyle(YouPalette.paperMuted)
            }

            Spacer()

            Stepper(
                value: Binding(
                    get: { pendingDailyTargetMinutes ?? dailyTargetMinutes },
                    set: { changeDailyTarget(to: $0) }
                ),
                in: DailyTargetStore.minutesRange
            ) {
                EmptyView()
            }
            .labelsHidden()
        }
        .padding(.vertical, 14)
    }

    private var dailyTargetSubtitle: String {
        if let pendingDailyTargetMinutes {
            return "\(dailyTargetMinutes) min today · \(pendingDailyTargetMinutes) min from tomorrow"
        }
        return "\(dailyTargetMinutes) minute\(dailyTargetMinutes == 1 ? "" : "s") of writing opens the day"
    }

    private func refreshDailyTarget() {
        let store = DailyTargetStore()
        dailyTargetMinutes = store.effectiveTargetMinutes()
        pendingDailyTargetMinutes = store.pendingTargetMinutes()
    }

    private func changeDailyTarget(to minutes: Int) {
        let change = DailyTargetStore().requestTargetChange(to: minutes)
        WriteBeforeScrollEventLogStore().append(
            .targetChanged,
            metadata: [
                "oldMinutes": "\(change.oldMinutes)",
                "newMinutes": "\(change.newMinutes)"
            ]
        )
        refreshDailyTarget()
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
        if viewModel.errorMessage != nil {
            mood = .concerned
        } else {
            mood = .guiding
        }

        ankyCompanion.witness(
            mood: mood,
            bubble: AnkyBubble(
                text: conversationMessage,
                actions: conversationActions,
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

    private var conversationMessage: String {
        if isShowingSystemPrompt {
            return viewModel.errorMessage ?? viewModel.statusMessage ?? activePrompt?.message ?? ""
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

        return promptActions
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
    case support

    var message: String {
        switch self {
        case .privacy:
            return AnkyLocalization.ui("Writing stays local unless you export or ask for a reflection.")
        case .export:
            return AnkyLocalization.ui("Your archive is yours. Export readable writings or keep an encrypted iCloud backup.")
        case .support:
            return AnkyLocalization.ui("Send us an email! We want to evolve this app based on your feedback.")
        }
    }
}

private enum YouRoute: Hashable {
    case allAnkys
    case account
    case settings
}

private struct YouAllAnkysHistoryView: View {
    @ObservedObject var viewModel: YouViewModel
    let onWriteRequested: () -> Void

    private let bottomNavigationReserve: CGFloat = 152

    private var sessions: [SessionSummary] {
        viewModel.completeAnkySessions
    }

    private var title: String {
        "\(sessions.count) \(AnkyLocalization.ui(sessions.count == 1 ? "anky" : "ankys"))"
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
        .toolbarColorScheme(.light, for: .navigationBar)
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
                .shadow(color: Color.ankyViolet.opacity(0.18), radius: 18, y: 8)
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
                accent.opacity(0.34),
                Color.ankyPaper.opacity(0.92),
                accent.opacity(0.20)
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
                    .onChange(of: dailyReminderEnabled) { isEnabled in
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
                ForEach(Array(LegalMarkdownDocument.privacyPolicy.items.enumerated()), id: \.offset) { _, item in
                    PrivacyCopyLine(item)
                }
            }
        }
    }

}

fileprivate enum PrivacyCopyItem {
    case caption(String)
    case callout(String)
    case heading(String)
    case subheading(String)
    case paragraph(String)
    case bullets([String])
}

private enum LegalMarkdownDocument: String {
    case privacyPolicy = "PrivacyPolicy"
    case termsAndConditions = "TermsAndConditions"

    var items: [PrivacyCopyItem] {
        guard
            let url = localizedURL,
            let markdown = try? String(contentsOf: url, encoding: .utf8)
        else {
            return [.paragraph(AnkyLocalization.ui("Legal document unavailable. Please contact support@anky.app."))]
        }

        return PrivacyMarkdownParser.items(from: markdown)
    }

    private var localizedURL: URL? {
        if let localization = Bundle.main.preferredLocalizations.first,
           let url = Bundle.main.url(
            forResource: rawValue,
            withExtension: "md",
            subdirectory: nil,
            localization: localization
           ) {
            return url
        }

        return Bundle.main.url(forResource: rawValue, withExtension: "md")
    }
}

private enum PrivacyMarkdownParser {
    static func items(from markdown: String) -> [PrivacyCopyItem] {
        var items: [PrivacyCopyItem] = []
        var paragraphLines: [String] = []
        var bulletLines: [String] = []
        var calloutLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: " ")
            if items.isEmpty {
                items.append(.caption(text))
            } else {
                items.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        func flushBullets() {
            guard !bulletLines.isEmpty else { return }
            items.append(.bullets(bulletLines))
            bulletLines.removeAll()
        }

        func flushCallout() {
            guard !calloutLines.isEmpty else { return }
            items.append(.callout(calloutLines.joined(separator: "\n")))
            calloutLines.removeAll()
        }

        func flushOpenBlocks() {
            flushParagraph()
            flushBullets()
            flushCallout()
        }

        let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalizedMarkdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                flushOpenBlocks()
                continue
            }

            if line.hasPrefix("### ") {
                flushOpenBlocks()
                items.append(.subheading(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flushOpenBlocks()
                items.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix(">") {
                flushParagraph()
                flushBullets()
                calloutLines.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                flushCallout()
                bulletLines.append(String(line.dropFirst(2)))
            } else {
                flushBullets()
                flushCallout()
                paragraphLines.append(line)
            }
        }

        flushOpenBlocks()
        return items
    }
}

struct PrivacyPolicyReflectionSheet: View {
    var body: some View {
        ZStack {
            PrivacySheetPalette.ink.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AnkyLocalization.ui("Privacy Policy"))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(PrivacySheetPalette.heading)
                            .tracking(0)

                        Text(AnkyLocalization.ui("Your writing is sacred and we take that seriously. All of the code is open source."))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrivacySheetPalette.paper.opacity(0.54))
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(LegalMarkdownDocument.privacyPolicy.items.enumerated()), id: \.offset) { _, item in
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

struct TermsAndConditionsReflectionSheet: View {
    var body: some View {
        ZStack {
            PrivacySheetPalette.ink.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AnkyLocalization.ui("Terms & Conditions"))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(PrivacySheetPalette.heading)
                            .tracking(0)

                        Text(AnkyLocalization.ui("Writing and reflection agreement"))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrivacySheetPalette.paper.opacity(0.54))
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(LegalMarkdownDocument.termsAndConditions.items.enumerated()), id: \.offset) { _, item in
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

private struct PrivacyPolicyReflectionLine: View {
    let item: PrivacyCopyItem

    var body: some View {
        switch item {
        case .caption(let text):
            Text(text)
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
            Text(text)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(PrivacySheetPalette.heading)
                .tracking(0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        case .subheading(let text):
            Text(text)
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
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

enum PrivacySheetPalette {
    // Lazure remap: the sheet surface is paper, its text is ink.
    // `ink` names the *surface* role (sheet background, now warm paper);
    // `paper` names the *text* role (now violet ink).
    static let ink = Color.ankyPaper
    static let paper = Color.ankyInk
    static let gold = Color.ankyGold
    static let heading = Color.ankyInk
    static let violet = Color.ankyViolet
}

private struct PrivacyCopyLine: View {
    let item: PrivacyCopyItem

    init(_ item: PrivacyCopyItem) {
        self.item = item
    }

    var body: some View {
        switch item {
        case .caption(let text):
            Text(text)
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
            Text(text)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(YouPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        case .subheading(let text):
            Text(text)
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
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
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
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct AnkyExperienceView: View {
    @StateObject private var viewModel = AnkyExperienceViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showCopyPrompt = false

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)

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
                        .foregroundStyle(Color.ankyInk.opacity(0.58))
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
                            .foregroundStyle(Color.ankyInk.opacity(0.72))
                            .frame(width: 42, height: 42)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AnkyLocalization.ui("Close The Anky Experience"))
                }

                Spacer()
            }
            .ankySafeAreaTopPadding(8)
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
            Label(AnkyLocalization.ui(title), systemImage: systemName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(Color.ankyInk.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.ankyInk.opacity(0.10), lineWidth: 0.5)
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
        .ankyMadder, .ankyApricot, .ankyGold, .ankySage,
        .ankySlate, .ankyViolet, .ankyRose, .ankyGoldLight
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
                        .stroke(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
                )

            VStack(spacing: 8) {
                Text(clockText)
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ankyInk.opacity(0.88))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(AnkyLocalization.ui(subtitle))
                    .font(.system(size: 11, weight: .medium))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.86))
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
        textView.textColor = UIColor(Color.ankyInk).withAlphaComponent(0.34)
        textView.tintColor = UIColor(Color.ankyInk).withAlphaComponent(0.62)
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

                    Text(AnkyLocalization.ui("recovering replaces the private access used for Ask Anky and your subscription. local .anky files stay on this device."))
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
    // Lazure remap: the cosmos gave way to the breathing dawn wall.
    var body: some View {
        LazureWall(mood: .dawn)
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
        case "you-icon-support":
            return "ellipsis.message"
        case "you-icon-faceid":
            return "faceid"
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
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.ankyPaper.opacity(0.80), Color.ankyPaper.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.ankyViolet.opacity(0.14), radius: 18, y: 6)
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
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.ankyMadder.opacity(0.12), Color.ankyMadder.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(YouPalette.danger.opacity(0.30), lineWidth: 0.5)
        )
        .shadow(color: Color.ankyViolet.opacity(0.14), radius: 18, y: 6)
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
            .foregroundStyle(destructive ? YouPalette.danger : Color.ankyInk)
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
            .fill(Color.ankyInk.opacity(0.08))
            .frame(height: 0.5)
    }
}

private struct YouVerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.ankyInk.opacity(0.08))
            .frame(width: 0.5)
            .padding(.vertical, 8)
    }
}

private enum YouPalette {
    // Lazure remap: surfaces became paper washes, text became ink.
    // `ink` names the *surface* role (was near-black, now warm paper);
    // `paper` names the *text* role (was cream, now violet ink).
    static let ink = Color.ankyPaper
    static let panel = Color.ankyPaper.opacity(0.72)
    static let panelStrong = Color.ankyPaperDeep.opacity(0.82)
    static let buttonFill = Color.ankyGoldLight.opacity(0.28)
    static let gold = Color.ankyGold
    static let goldDim = gold.opacity(0.32)
    static let paper = Color.ankyInk
    static let paperMuted = Color.ankyInkSoft
    static let danger = Color.ankyMadder
}

private struct MissingYouAnkyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.questionmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(YouPalette.gold.opacity(0.78))

            Text(AnkyLocalization.ui("Anky not found"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(YouPalette.paper)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(YouPalette.ink.ignoresSafeArea())
    }
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

extension View {
    @ViewBuilder
    func ankySheetBackground(_ color: Color) -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(color)
        } else {
            background(color)
        }
    }
}

private extension View {
    func enableSwipeBackGesture() -> some View {
        background(SwipeBackGestureEnabler().frame(width: 0, height: 0))
    }

    @ViewBuilder
    func ankySafeAreaTopPadding(_ length: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            safeAreaPadding(.top, length)
        } else {
            padding(.top, length)
        }
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
