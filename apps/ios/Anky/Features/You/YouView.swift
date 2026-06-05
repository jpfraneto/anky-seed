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
    @AppStorage(MirrorConfiguration.userDefaultsKey) private var mirrorBaseURL = MirrorConfiguration.defaultBaseURL
    @AppStorage("anky.dailyReminderEnabled") private var dailyReminderEnabled = false
    @AppStorage("anky.dailyReminderTime") private var dailyReminderTime = 9.0 * 60.0 * 60.0
    @AppStorage("anky.biometricIdentityConfirmation") private var biometricIdentityConfirmation = false
    @State private var confirmClearArchive = false
    @State private var confirmClearReflections = false
    @State private var confirmClearWritingData = false
    @State private var confirmResetIdentity = false
    @State private var confirmDevelopmentWipe = false
    @State private var isImportingBackup = false
    @State private var isImportingRecoveryPhrase = false
    @State private var recoveryPhraseInput = ""
    @State private var showsPrivacyPolicy = false
    @State private var showsTermsAndConditions = false
    @State private var activePrompt: YouPrompt?
    @State private var isShowingSystemPrompt = false

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
        ZStack {
            YouCosmicBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    YouTitle(title: "Your Anky", subtitle: "Private on this phone")
                        .padding(.top, 18)

                    YouStatsPanel(
                        ankys: viewModel.completeAnkyCount,
                        minutes: viewModel.totalWritingMinutes,
                        streak: viewModel.currentStreak
                    )

                    YouPanel(spacing: 0) {
                        promptButton(.identity, icon: "you-icon-account", title: "Identity", subtitle: identityMenuSubtitle)

                        YouDivider()

                        promptButton(.privacy, icon: "you-icon-privacy", title: "Privacy Policy", subtitle: "What leaves this phone")

                        YouDivider()

                        legalButton(icon: "you-icon-terms", title: "Terms & Conditions", subtitle: "The agreement for using Anky") {
                            showsTermsAndConditions = true
                        }

                        YouDivider()

                        promptButton(.export, icon: "you-icon-export", title: "Data", subtitle: dataMenuSubtitle)

                        YouDivider()

                        promptButton(.credits, icon: "you-icon-credits", title: "Credits", subtitle: creditsMenuSubtitle)

                        YouDivider()

                        promptButton(.support, icon: "you-icon-support", title: "Support / Feedback", subtitle: "Email support@anky.app")
                    }

                    #if DEBUG
                    YouDangerPanel {
                        Text("development")
                            .youCaption()
                        Text("wipe this install")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(YouPalette.paper)
                        Text("deletes local writing, reflections, session state, app settings, local identity, and the icloud keychain identity backup for this app.")
                            .youBody()
                        YouActionButton("wipe everything", role: .destructive) {
                            confirmDevelopmentWipe = true
                        }
                    }
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 220)
            }
            .safeAreaPadding(.top, 44)

        }
        .toolbar(.hidden, for: .navigationBar)
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
        .sheet(isPresented: $isImportingRecoveryPhrase) {
            ImportRecoveryPhraseSheet(
                viewModel: viewModel,
                recoveryPhraseInput: $recoveryPhraseInput,
                isPresented: $isImportingRecoveryPhrase
            )
        }
        .confirmationDialog("delete local writing data?", isPresented: $confirmClearWritingData, titleVisibility: .visible) {
            Button("delete local writing data", role: .destructive) {
                viewModel.clearLocalWritingData()
            }
        }
        .confirmationDialog("clear local .anky archive?", isPresented: $confirmClearArchive, titleVisibility: .visible) {
            Button("clear .anky archive", role: .destructive) {
                viewModel.clearLocalArchive()
            }
        }
        .confirmationDialog("clear local reflections?", isPresented: $confirmClearReflections, titleVisibility: .visible) {
            Button("clear reflections", role: .destructive) {
                viewModel.clearLocalReflections()
            }
        }
        .confirmationDialog("reset local identity?", isPresented: $confirmResetIdentity, titleVisibility: .visible) {
            Button("reset identity", role: .destructive) {
                viewModel.resetIdentityForDevelopment()
            }
        } message: {
            Text("Resetting identity creates a new Anky Base account. Credits are tied to your current account. Save your recovery phrase before resetting.")
        }
        #if DEBUG
        .confirmationDialog("wipe this install?", isPresented: $confirmDevelopmentWipe, titleVisibility: .visible) {
            Button("wipe everything", role: .destructive) {
                viewModel.wipeEverythingForDevelopment()
                mirrorBaseURL = MirrorConfiguration.defaultBaseURL
                dailyReminderEnabled = false
                dailyReminderTime = 9.0 * 60.0 * 60.0
                biometricIdentityConfirmation = false
                recoveryPhraseInput = ""
                activePrompt = nil
                isShowingSystemPrompt = false
                ankyCompanion.hideBubble()
                onDevelopmentWipe()
            }
        } message: {
            Text("This deletes local writing, reflections, drafts, app settings, local identity, and the iCloud Keychain identity backup for this app. This cannot reset server-side credits on old accounts, but it creates a new local account.")
        }
        #endif
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
        .onChange(of: viewModel.isIdentityBackedUpToICloud) { _, _ in
            if activePrompt == .identity, !isShowingSystemPrompt {
                presentCurrentPromptIfNeeded()
            }
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
        } label: {
            YouMenuRow(icon: icon, title: title, subtitle: subtitle, showsDisclosure: false)
        }
        .buttonStyle(.plain)
    }

    private func legalButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
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
    }

    private func dismissCurrentPrompt() {
        activePrompt = nil
        isShowingSystemPrompt = false
        viewModel.dismissMessages()
        ankyCompanion.hideBubble()
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
                return "Anky is checking the credit gate."
            }
            return creditsPromptMessage
        }

        if activePrompt == .identity, viewModel.isIdentityBackedUpToICloud {
            return "Your recovery phrase is saved in iCloud Keychain. Use Data when you want a writing and reflection backup."
        }

        if activePrompt == .export {
            if viewModel.isICloudBackupWorking {
                return "Anky is updating the encrypted iCloud backup."
            }
            if viewModel.isICloudBackupEnabled {
                if let date = viewModel.iCloudBackupLastDate {
                    return "Encrypted iCloud backup is on. Last updated \(date.formatted(date: .abbreviated, time: .shortened))."
                }
                return "Encrypted iCloud backup is on. It will run after your next writing session."
            }
            return "Turn on encrypted iCloud backup to restore writing and reflections after reinstalling."
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
        case .identity:
            var actions = [
                AnkyChatAction("Import account", isPrimary: viewModel.isIdentityBackedUpToICloud) {
                    Task { await viewModel.recoverIdentityFromICloudKeychain() }
                },
              
            ]
            if !viewModel.isIdentityBackedUpToICloud {
                actions.insert(
                    AnkyChatAction("Back up recovery phrase", isPrimary: true) {
                        Task { await viewModel.backUpIdentityToICloudKeychain() }
                    },
                    at: 0
                )
            }
            return actions
        case .privacy:
            return []
        case .export:
            var actions = [AnkyChatAction]()

            if viewModel.isICloudBackupEnabled {
                actions.append(
                    AnkyChatAction(viewModel.isICloudBackupWorking ? "Backing up" : "Back up now", isPrimary: true) {
                        Task { await viewModel.backUpToICloudNow() }
                    }
                )
                actions.append(
                    AnkyChatAction("Turn off iCloud") {
                        viewModel.disableICloudBackup()
                    }
                )
            } else {
                actions.append(
                    AnkyChatAction("Enable iCloud backup", isPrimary: true) {
                        Task { await viewModel.enableICloudBackup() }
                    }
                )
            }

            actions.append(
                AnkyChatAction("Restore backup") {
                    isImportingBackup = true
                }
            )
            if let backupZipURL = viewModel.backupZipURL {
                actions.append(
                    AnkyChatAction("Export zip") {
                        presentShareSheet(item: backupZipURL)
                    }
                )
            }
            return actions
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
                    AnkyChatAction(viewModel.creditsLoading ? "Loading packs" : "Refresh credits", isPrimary: true) {
                        Task { await viewModel.refreshCredits() }
                    }
                ]
            }

            return packages.map { creditPackage in
                let isRecommended = creditPackage.title == "11 reflections"
                    || creditPackage.id.hasSuffix(".credits.11")
                let isPurchasing = viewModel.purchasingCreditPackageID == creditPackage.id
                return AnkyChatAction(
                    isPurchasing ? "Loading" : creditPackage.title,
                    subtitle: creditPackage.price,
                    badge: isRecommended ? "recommended" : nil,
                    isPrimary: isRecommended
                ) {
                    AnkyHaptics.light()
                    Task { await viewModel.purchaseCredits(creditPackage) }
                }
            }
        case .support:
            return [
                AnkyChatAction("Open email", isPrimary: true) {
                    if let emailURL = viewModel.supportFeedbackEmailURL {
                        openURL(emailURL)
                    }
                }
            ]
        case .developer:
            return [
                AnkyChatAction("Repair map", isPrimary: true) {
                    viewModel.rebuildSessionIndex()
                },
                AnkyChatAction("Delete local data") {
                    confirmClearWritingData = true
                }
            ]
        }
    }

    private var creditsMenuSubtitle: String {
        if viewModel.creditsLoading && viewModel.creditBalance == nil {
            return "Loading balance"
        }

        return viewModel.creditSummaryText
    }

    private var identityMenuSubtitle: String {
        viewModel.isIdentityBackedUpToICloud
            ? "Recovery phrase saved in iCloud"
            : "Save recovery phrase to iCloud"
    }

    private var dataMenuSubtitle: String {
        if viewModel.isICloudBackupEnabled {
            return "Encrypted iCloud backup on"
        }
        return "Export, restore, or enable iCloud"
    }

    private var creditsPromptMessage: String {
        if viewModel.hasUnspentGiftCredit {
            return AnkyLocalization.text(.creditGiftPrompt)
        }

        let balance: String
        if viewModel.creditsLoading && viewModel.creditBalance == nil {
            balance = "Loading..."
        } else if let creditBalance = viewModel.presentedCreditBalance {
            balance = "\(creditBalance)"
        } else {
            balance = "unknown"
        }

        return "You have \(balance) reflection \(balance == "1" ? "credit" : "credits"). Choose a pack to add more."
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
}

private enum YouPrompt: Hashable {
    case identity
    case privacy
    case export
    case credits
    case support
    case developer

    var message: String {
        switch self {
        case .identity:
            return "iCloud Keychain can restore your recovery phrase. Data export backs up writing and reflections."
        case .privacy:
            return "Writing stays local unless you export or ask for a reflection."
        case .export:
            return "Your archive is yours. Export it or restore one."
        case .credits:
            return "Credits are only for reflections. Writing is free."
        case .support:
            return "Send support or feedback by email. Include only what you choose to write."
        case .developer:
            return "Local tools. Repair first, delete only when you mean it."
        }
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
        YouDetailShell(title: "local identity", subtitle: "private to this device") {
            YouPanel {
                Text("Local identity")
                    .youCaption()
                Text("Anky created a Base account for this device.")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(YouPalette.paper)
                Text("Your writing and identity live here unless you choose to export or recover them elsewhere.")
                    .youBody()
            }

            YouPanel {
                Text("Advanced recovery")
                    .youCaption()
                Text("This phrase controls your Anky Base account. Never share it. Anky cannot recover it for you.")
                    .youBody()

                YouDivider()

                Toggle("face id app lock", isOn: $biometricIdentityConfirmation)
                    .tint(YouPalette.gold)
                    .foregroundStyle(YouPalette.paper)
                    .font(.system(size: 16))

                Text("Your recovery phrase can only be shown after face id is enabled.")
                    .youBody()

                Text("Your password/biometrics protect local access. They are not an Anky login.")
                    .youBody()

                if viewModel.recoveryPhraseText.isEmpty {
                    YouActionButton("Reveal recovery phrase") {
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
                        YouActionButton("Copy recovery phrase") {
                            ClipboardClient().copy(viewModel.recoveryPhraseText)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        YouActionButton("Hide") {
                            viewModel.hideRecoveryPhrase()
                        }
                    }
                }

                YouActionButton("Recover identity") {
                    recoveryPhraseInput = ""
                    isImportingRecoveryPhrase = true
                }

                if viewModel.isIdentityBackedUpToICloud {
                    YouDisabledRow("Recovery phrase saved in iCloud Keychain")
                } else {
                    YouActionButton("Back up recovery phrase to iCloud Keychain") {
                        Task { await viewModel.backUpIdentityToICloudKeychain() }
                    }
                }

                Text("This stores your recovery phrase in your device/cloud keychain. Data export is the separate backup for writing and reflections. Anky cannot read or recover either for you.")
                    .youBody()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Anky address")
                        .youCaption()
                    Text(viewModel.accountId)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(YouPalette.paperMuted)
                        .textSelection(.enabled)
                }

                YouActionButton("Import account") {
                    Task { await viewModel.recoverIdentityFromICloudKeychain() }
                }
            }

            YouPanel {
                Toggle("Daily reminder", isOn: $dailyReminderEnabled)
                    .tint(YouPalette.gold)
                    .foregroundStyle(YouPalette.paper)
                    .font(.system(size: 16))
                    .onChange(of: dailyReminderEnabled) { _, isEnabled in
                        Task {
                            await viewModel.setDailyReminder(enabled: isEnabled, date: reminderDate)
                        }
                    }

                DatePicker("Time", selection: reminderBinding, displayedComponents: .hourAndMinute)
                    .disabled(!dailyReminderEnabled)
                    .tint(YouPalette.gold)
                    .foregroundStyle(YouPalette.paper)
            }

            YouPanel {
                Text("Ownership note")
                    .youCaption()
                Text("Your writing belongs to this device unless you choose to export or recover it elsewhere.")
                    .youBody()
            }
        }
    }
}

private struct PrivacyPolicyPage: View {
    var body: some View {
        YouDetailShell(title: "Privacy", subtitle: "Local-first. Private. Sovereign.") {
            VStack(spacing: 12) {


                Text("Privacy is the shape of Anky, not a feature added later.")
                    .font(.system(size: 19, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(YouPalette.paper)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.policyCopy.indices, id: \.self) { index in
                    PrivacyCopyLine(Self.policyCopy[index])
                }
            }

            YouPanel {
                Text("Questions, deletion requests, and privacy reports")
                    .youCaption()

                Text("jp@anky.app")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(YouPalette.paper)
                    .textSelection(.enabled)
            }
        }
    }

    fileprivate static let policyCopy: [PrivacyCopyItem] = [
        .caption("Last updated: 2026-05-14"),
        .paragraph("Anky is a local-first writing app. The core artifact is the `.anky` file on your device. The app should let you write, save, revisit, export, import, and delete your writing without making a server the owner of your interior life."),
        .heading("The private artifact"),
        .paragraph("Your `.anky` writing is stored on your device by default. A saved `.anky` file contains the accepted writing stream and timing data for a session."),
        .paragraph("Anky computes a SHA-256 hash of the exact `.anky` bytes. The hash is for integrity. It is not encryption. If someone has the same `.anky` bytes, they can compute the same hash."),
        .paragraph("The source is direct: [local archive](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Storage/LocalAnkyArchive.swift), [protocol](https://github.com/jpfraneto/anky-seed/tree/main/apps/ios/Anky/Core/Protocol)."),
        .heading("Local identity"),
        .paragraph("Anky creates a local Base account, stores its recovery phrase in device secure storage, and derives the Anky address locally. The recovery phrase is not sent to Anky."),
        .paragraph("The relevant code is [writer identity](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Identity/WriterIdentityStore.swift) and [keychain storage](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Identity/KeychainClient.swift)."),
        .heading("When plaintext leaves"),
        .paragraph("Writing, saving, hashing, reading the map, and keeping local backups do not require plaintext to leave your device."),
        .paragraph("Plaintext can leave when you choose an action that sends it somewhere: asking Anky for a reflection, exporting or sharing files, importing a backup from a place you chose, or contacting support with text you provide."),
        .paragraph("The processing and backup paths are [reflection client](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Mirror/MirrorClient.swift), [backup importer](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Storage/BackupImporter.swift), and [you page model](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Features/You/YouViewModel.swift)."),
        .heading("Reflections"),
        .paragraph("When you ask for a reflection, the app sends the saved `.anky` bytes to the configured mirror service. The mirror checks the hash, reconstructs readable text for processing, and returns a reflection."),
        .paragraph("The local app stores the returned reflection as a local sidecar. Reflections are optional. Writing is free and does not depend on reflections."),
        .heading("Backups and deletion"),
        .paragraph("Exports and backups can contain plaintext writing, reflections, and related local metadata. Keep them somewhere private."),
        .paragraph("Deleting local writing data removes local `.anky` files, local reflections, and the local session index from this app's storage area. It does not automatically delete backend records already created by optional processing."),
        .heading("What this does not claim"),
        .paragraph("Anky does not claim that hashes encrypt writing. Anky does not claim anonymity. Timing, identity identifiers, processing requests, purchases, and support requests can be linkable."),
        .paragraph("Anky does not claim optional processing is local-only. If you ask for a reflection, plaintext writing is sent for processing."),
        .paragraph("Anky does claim the default direction of the app is local-first: the `.anky` file belongs first to the person who wrote it.")
    ]
}

fileprivate enum PrivacyCopyItem {
    case caption(String)
    case heading(String)
    case paragraph(String)
}

private struct PrivacyPolicyReflectionSheet: View {
    var body: some View {
        ZStack {
            PrivacySheetPalette.ink.ignoresSafeArea()
            PrivacySheetBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privacy")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(PrivacySheetPalette.heading)
                            .tracking(0)

                        Text("Local-first. Private. Sovereign.")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PrivacySheetPalette.paper.opacity(0.54))
                    }
                    .padding(.bottom, 8)

                    Text("Privacy is the shape of Anky, not a feature added later.")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PrivacySheetPalette.paper)
                        .lineSpacing(6)

                    ForEach(Array(PrivacyPolicyPage.policyCopy.enumerated()), id: \.offset) { _, item in
                        PrivacyPolicyReflectionLine(item: item)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Questions, deletion requests, and privacy reports")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(PrivacySheetPalette.paper.opacity(0.46))

                        Text("jp@anky.app")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(PrivacySheetPalette.gold)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 8)
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
            PrivacySheetBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terms & Conditions")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(PrivacySheetPalette.heading)
                            .tracking(0)

                        Text("The agreement for using Anky.")
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
        .caption("Last updated: 2026-06-05"),
        .paragraph("By using Anky, you agree to use it as a private writing tool and to make your own decisions about what you write, export, share, delete, or send for reflection."),
        .heading("Your writing"),
        .paragraph("Your writing belongs to you. Anky stores `.anky` files locally by default. You are responsible for keeping backups if you want to preserve writing outside this install."),
        .heading("Reflections"),
        .paragraph("Reflections are optional. Asking for a reflection sends the `.anky` writing to the configured mirror service so it can return a response. Reflections may require credits."),
        .heading("Credits and purchases"),
        .paragraph("Credits are used for reflections, not writing. The first reflection is limited by device checks to reduce abuse. Paid credit purchases are handled through Apple and RevenueCat where available."),
        .heading("Backups and recovery"),
        .paragraph("iCloud Keychain recovery stores the recovery phrase for your local identity. Data export is the separate backup path for writing and reflections."),
        .heading("No professional advice"),
        .paragraph("Anky is not medical, legal, financial, or emergency advice. Do not rely on Anky reflections as a substitute for professional support."),
        .heading("Acceptable use"),
        .paragraph("Do not use Anky to abuse services, evade credit limits, interfere with the app, or submit content you do not have the right to submit."),
        .heading("Changes"),
        .paragraph("Anky may change these terms as the product evolves. Continued use after changes means you accept the updated terms."),
        .heading("Contact"),
        .paragraph("Questions about these terms can be sent to support@anky.app.")
    ]
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
        case .heading(let text):
            Text(text)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(PrivacySheetPalette.heading)
                .tracking(0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        case .paragraph(let text):
            Text(attributedText(from: text))
                .font(.system(size: 18))
                .lineSpacing(7)
                .foregroundStyle(PrivacySheetPalette.paper)
                .tint(PrivacySheetPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func attributedText(from text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct PrivacySheetBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach([0.19, 0.47, 0.78], id: \.self) { position in
                    Rectangle()
                        .fill(PrivacySheetPalette.gold.opacity(0.075))
                        .frame(height: 1)
                        .offset(y: proxy.size.height * position)
                }

                Ellipse()
                    .fill(PrivacySheetPalette.violet.opacity(0.055))
                    .frame(width: proxy.size.width * 1.2, height: 280)
                    .blur(radius: 42)
                    .offset(y: proxy.size.height * 0.4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
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
            Text(text)
                .youCaption()
        case .heading(let text):
            Text(text)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(YouPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        case .paragraph(let text):
            MarkdownArticleText(text)
        }
    }
}

private struct ExportDataPage: View {
    @ObservedObject var viewModel: YouViewModel
    @Binding var isImportingBackup: Bool
    @Binding var confirmClearWritingData: Bool

    var body: some View {
        YouDetailShell(title: "Export data", subtitle: "Your archive is yours") {
            YouPanel {
                Text("\(viewModel.ankyFileURLs.count) local .anky files · \(viewModel.reflectionFileURLs.count) reflections")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(YouPalette.gold)

                Text("Backups may include plaintext writing and reflections. Keep them somewhere private.")
                    .youBody()
            }

            YouPanel {
                if let backupZipURL = viewModel.backupZipURL {
                    ShareLink(item: backupZipURL) {
                        YouActionLabel("Export backup zip")
                    }
                } else {
                    YouDisabledRow("No local data to export yet")
                }

                YouActionButton("Restore backup") {
                    isImportingBackup = true
                }
            }

            YouPanel {
                Text("Encrypted iCloud backup")
                    .youCaption()
                Text(viewModel.isICloudBackupEnabled ? "On" : "Off")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(YouPalette.gold)
                Text(viewModel.isICloudBackupEnabled ? "Anky backs up writing and reflections after each writing session." : "Turn this on to restore writing and reflections from iCloud after reinstalling.")
                    .youBody()

                if let lastDate = viewModel.iCloudBackupLastDate {
                    Text("Last backup: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                        .youBody()
                }

                if viewModel.isICloudBackupEnabled {
                    YouActionButton(viewModel.isICloudBackupWorking ? "Backing up" : "Back up now") {
                        Task { await viewModel.backUpToICloudNow() }
                    }
                    YouActionButton("Turn off iCloud backup") {
                        viewModel.disableICloudBackup()
                    }
                } else {
                    YouActionButton("Enable iCloud backup") {
                        Task { await viewModel.enableICloudBackup() }
                    }
                }
            }

            YouDangerPanel {
                Text("Danger zone")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(YouPalette.danger)
                Text("This removes local .anky files, local reflections, and the local map index from this device. Export a backup first if you want to keep them.")
                    .youBody()
                YouActionButton("Delete local data", role: .destructive) {
                    confirmClearWritingData = true
                }
            }
        }
        .onAppear {
            viewModel.prepareBackupExport()
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
                YouRuleRow("1 credit = reflection")
                YouRuleRow("ask anky spends one credit")
                YouRuleRow("writing is always free")
            }

            YouPanel {
                if viewModel.hasUnspentGiftCredit {
                    YouDisabledRow(AnkyLocalization.text(.creditPacksLocked))
                    Text(AnkyLocalization.text(.creditGiftDetail))
                        .youBody()
                } else if viewModel.creditsLoading && viewModel.creditPackages.isEmpty {
                    YouDisabledRow("loading credit packs")
                } else if viewModel.creditPackages.isEmpty {
                    YouDisabledRow("no credit packs available")
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

                YouActionButton("refresh credits") {
                    Task {
                        await viewModel.refreshCredits()
                    }
                }
            }

            YouPanel {
                YouActionButton("support / feedback") {
                    if let emailURL = viewModel.supportFeedbackEmailURL {
                        openURL(emailURL)
                    }
                }

                Text("email support@anky.app. include only what you choose to write.")
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
                    Text(creditPackage.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(YouPalette.paper)
                    Text(creditPackage.subtitle)
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
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct DeveloperPage: View {
    @Binding var mirrorBaseURL: String
    @Binding var confirmClearArchive: Bool
    @Binding var confirmClearReflections: Bool
    @Binding var confirmResetIdentity: Bool
    @ObservedObject var viewModel: YouViewModel

    var body: some View {
        YouDetailShell(title: "developer", subtitle: "local tools") {
            YouPanel {
                TextField("mirror base url", text: $mirrorBaseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(YouPalette.paper)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(12)
                    .background(YouPalette.panelStrong, in: RoundedRectangle(cornerRadius: 12))

                Text("simulator local mirror: http://127.0.0.1:3000. physical devices should use the deployed https mirror or an https tunnel to local.")
                    .youBody()

                YouActionButton("repair map index") {
                    viewModel.rebuildSessionIndex()
                }
            }

            YouPanel {
                YouActionButton("clear local reflections", role: .destructive) {
                    confirmClearReflections = true
                }
                YouActionButton("clear local .anky archive", role: .destructive) {
                    confirmClearArchive = true
                }
                YouActionButton("reset local identity", role: .destructive) {
                    confirmResetIdentity = true
                }
            }
        }
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
                        .accessibilityLabel("Anky experience time \(viewModel.elapsedClockText)")

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
                    .accessibilityLabel("Close The Anky Experience")
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
                    .accessibilityLabel("Anky companion")
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }

            if showCopyPrompt {
                VStack {
                    Spacer()

                    AnkyConversationPromptView(
                        message: "copy your .anky or copy your writing.",
                        actions: [
                            AnkyChatAction("copy your .anky", isPrimary: true) {
                                viewModel.copyCurrentAnky()
                            },
                            AnkyChatAction("copy your writing") {
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

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.secondary.opacity(0.86))
                    .frame(width: 128)
            }
        }
        .frame(width: 220, height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clockText). \(subtitle)")
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
            return "the experience is open"
        case .portal:
            return "the experience is open"
        case .closingWarning:
            return "the experience is open"
        case .closingAnky:
            return "the experience is open"
        case .finished:
            return "the experience is complete"
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

                    Text("recovering replaces the local identity used for ask anky and future credit balances. local .anky files stay on this device.")
                        .youBody()

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("recover identity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("recover") {
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
                        Text(title)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(YouPalette.gold)
                        Text(subtitle)
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
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(YouPalette.gold)
            if !subtitle.isEmpty {
                Text(subtitle)
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

    var body: some View {
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
                Text(label)
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
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(YouPalette.paper)
                Text(subtitle)
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
        Button(role: role, action: action) {
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
        Text(title)
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
            Text(title)
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
            Text(text)
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
        Text(text)
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
