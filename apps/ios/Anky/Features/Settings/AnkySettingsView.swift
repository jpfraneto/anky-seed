import SwiftUI
import RevenueCat

#if canImport(UIKit)
import UIKit
#endif

/// The settings page: one scroll of flat plates on paper, the same surface as
/// the drawer and the stats. Every row is a single line — what it is, and
/// its control — with the ritual as the clear default.
struct AnkySettingsView: View {
    @ObservedObject var viewModel: YouViewModel
    let onGateSetupRequested: () -> Void
    /// Re-enter the onboarding flow from the top. Nil on routes that can't
    /// host the replay (the row simply doesn't appear there).
    var onReplayOnboarding: (() -> Void)?
    @EnvironmentObject private var entitlements: EntitlementStore

    @AppStorage("anky.biometricIdentityConfirmation") private var biometricIdentityConfirmation = false
    @AppStorage("anky.biometricPrivacyOnboardingCompleted") private var faceIDPrivacyOnboardingCompleted = false
    @AppStorage("anky.skipNextFaceIDEnableAuthentication") private var skipsNextFaceIDEnableAuthentication = false

    @State private var targetMinutes: Double = Double(DailyTargetStore.defaultMinutes)
    @State private var effectiveTargetMinutes = DailyTargetStore.defaultMinutes
    @State private var pendingTargetMinutes: Int?
    @State private var serverAddress = MirrorConfiguration.currentBaseURL()
    @State private var serverStatus: String?
    @State private var isConnectingServer = false
    @State private var writingPreferences = WritingPreferencesStore().load()
    /// D3 — the silence that closes the channel, in seconds (bounds 3…30).
    @State private var silenceSeconds: Double =
        Double(WritingPreferencesStore().load().effectiveTerminalSilenceMs) / 1000
    @State private var showsPrivacyPolicy = false
    @State private var showsTermsAndConditions = false
    @State private var showsSubscriptionPaywall = false
    @State private var showsDeleteAccountSheet = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var didCopyAddress = false
    @State private var didCopyRecoveryPhrase = false

    private static let founderChatURL = URL(string: "https://t.me/jpfraneto")!
    private static let shareURL = URL(string: "https://anky.app")!

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                Text(AnkyLocalization.ui("Settings"))
                    .font(.fraunces(30, weight: .regular))
                    .foregroundStyle(Color.ankyInk)
                    .padding(.top, 34)
                    .padding(.horizontal, 4)

                planGroup
                writingGroup
                typefaceGroup
                protectionGroup
                keysGroup
                // Pointing the app at another server is a development tool,
                // not a setting a writer should meet.
                #if DEBUG
                serverGroup
                #endif
                supportGroup
                legalGroup
                deleteGroup
                footer
                #if DEBUG && ANKY_INTERNAL_DEBUG
                LevelDebugSection()
                #endif
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 48)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.ankyPaper.ignoresSafeArea())
        // The page is paper in either appearance; keep the system controls
        // (switches, sliders, the server field) drawn for it.
        .environment(\.colorScheme, .light)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            // The account id, archive counts and iCloud backup state this
            // screen shows are read here rather than when the view model is
            // built — the seed is the only surface that needs them, and the
            // read derives the wallet from its recovery phrase.
            viewModel.refresh()
            refreshDailyTarget()
            serverAddress = MirrorConfiguration.currentBaseURL()
            writingPreferences = WritingPreferencesStore().load()
            silenceSeconds = Double(writingPreferences.effectiveTerminalSilenceMs) / 1000
            // Always open with the recovery phrase concealed.
            viewModel.hideRecoveryPhrase()
            Task {
                await entitlements.loadPackages()
            }
        }
        .onDisappear {
            // Never leave the seed words sitting in memory once Settings closes.
            viewModel.hideRecoveryPhrase()
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
        .sheet(isPresented: $showsSubscriptionPaywall) {
            PaywallSheet(store: entitlements, origin: "settings")
        }
        .sheet(isPresented: $showsDeleteAccountSheet) {
            deleteAccountSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .ankySheetBackground(PrivacySheetPalette.ink)
        }
    }

    // MARK: Plan

    private var planGroup: some View {
        group {
            Button {
                AnkyHaptics.light()
                showsSubscriptionPaywall = true
            } label: {
                VStack(spacing: 0) {
                    row(icon: subscriptionStatusSymbol, title: subscriptionStatusTitle) {
                        if !entitlements.isEntitledForGating {
                            value(AnkyLocalization.ui("Anky Pro"))
                        }
                        chevron
                    }
                    if let detail = subscriptionStatusDetail {
                        caption(detail)
                    }
                }
            }
            .buttonStyle(.plain)

            rowDivider

            Button {
                guard !entitlements.isRestoring else {
                    return
                }
                AnkyHaptics.light()
                Task {
                    await entitlements.restore()
                }
            } label: {
                VStack(spacing: 0) {
                    row(icon: "arrow.clockwise", title: "Restore Purchases") {
                        if entitlements.isRestoring {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if let restoreLine = entitlements.restoreStatusLine {
                        caption(restoreLine)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Writing

    private var writingGroup: some View {
        group(title: "Writing") {
            row(icon: "sun.max", title: "Daily target") {
                value(AnkyLocalization.ui("minute count format", Int(targetMinutes)))
            }
            Slider(
                value: $targetMinutes,
                in: Double(DailyTargetStore.minutesRange.lowerBound)...Double(DailyTargetStore.minutesRange.upperBound),
                step: 1
            ) { isEditing in
                if !isEditing {
                    commitDailyTarget()
                }
            }
            .tint(Color.ankyInk)
            .padding(.leading, 54)
            .padding(.trailing, 16)
            .padding(.bottom, 12)

            if let pendingTargetFootnote {
                caption(pendingTargetFootnote)
            }

            rowDivider

            toggleRow(icon: "delete.backward", title: "Backspace", isOn: preferenceBinding(\.backspaceAllowed))

            rowDivider

            toggleRow(icon: "keyboard", title: "Autocorrect & suggestions", isOn: preferenceBinding(\.autocorrectEnabled))

            rowDivider

            toggleRow(icon: "hourglass", title: "8 second rule", isOn: preferenceBinding(\.eightSecondRuleEnabled))

            // The stillness the rule waits for. One dial, in the model's own
            // bounds, and only while the rule is in force.
            if writingPreferences.eightSecondRuleEnabled {
                HStack(spacing: 12) {
                    Slider(value: $silenceSeconds, in: silenceSecondsRange, step: 1) { isEditing in
                        if !isEditing {
                            commitSilenceDuration()
                        }
                    }
                    .tint(Color.ankyInk)

                    value(AnkyLocalization.ui("%d seconds", Int(silenceSeconds)))
                        .frame(minWidth: 86, alignment: .trailing)
                }
                .padding(.leading, 54)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private func preferenceBinding(_ keyPath: WritableKeyPath<WritingPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { writingPreferences[keyPath: keyPath] },
            set: { newValue in
                AnkyHaptics.light()
                writingPreferences[keyPath: keyPath] = newValue
                WritingPreferencesStore().save(writingPreferences)
            }
        )
    }

    // MARK: Typeface

    private var typefaceGroup: some View {
        group(title: "Font & size") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(AnkyWritingFontChoice.allCases, id: \.self) { choice in
                        fontChip(choice)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(AnkyWritingTextSize.allCases, id: \.self) { size in
                        sizeChip(size)
                    }
                }

                Text(AnkyLocalization.ui("One that stays. One that listens."))
                    .font(writingPreferences.fontChoice.font(size: writingPreferences.textSize.pointSize))
                    .foregroundStyle(Color.ankyInk)
                    .lineSpacing(writingPreferences.textSize.pointSize * 0.42)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.horizontal, 2)
                    .animation(.easeInOut(duration: 0.2), value: writingPreferences)
            }
            .padding(14)
        }
    }

    private func fontChip(_ choice: AnkyWritingFontChoice) -> some View {
        let isSelected = writingPreferences.fontChoice == choice
        return Button {
            AnkyHaptics.selection()
            writingPreferences.fontChoice = choice
            WritingPreferencesStore().save(writingPreferences)
        } label: {
            Text("Aa")
                .font(choice.font(size: 20))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .modifier(ChipStyle(isSelected: isSelected, cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(AnkyLocalization.ui(choice.displayName)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sizeChip(_ size: AnkyWritingTextSize) -> some View {
        let isSelected = writingPreferences.textSize == size
        return Button {
            AnkyHaptics.selection()
            writingPreferences.textSize = size
            WritingPreferencesStore().save(writingPreferences)
        } label: {
            Text(AnkyLocalization.ui(size.displayName))
                .font(.fraunces(14, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .modifier(ChipStyle(isSelected: isSelected, cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Protection

    private var protectionGroup: some View {
        group(title: "Protection") {
            toggleRow(icon: "icloud", title: "iCloud backup", isOn: iCloudBackupBinding)
            if let iCloudBackupLine {
                caption(iCloudBackupLine)
            }

            if BiometricAuthClient().canAuthenticate() {
                rowDivider

                toggleRow(
                    icon: deviceAuthenticationIconName,
                    title: AnkyLocalization.ui(
                        "%@ lock",
                        BiometricAuthClient().deviceAuthenticationName()
                    ),
                    isOn: faceIDBinding
                )
            }

            rowDivider

            Button {
                AnkyHaptics.light()
                onGateSetupRequested()
            } label: {
                row(icon: "shield", title: "Blocked apps") { chevron }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Identity (self-sovereign keys)

    /// The writer owns their account outright: a public address anyone can
    /// verify their writing against, and the 12 words that ARE the account —
    /// held only on this device, never on an Anky server.
    private var keysGroup: some View {
        group(title: "Your keys") {
            // Public address — safe to share, derived from the recovery
            // phrase. The row is the copy button.
            Button {
                copyAddress()
            } label: {
                row(icon: "key.horizontal", title: "Public address") {
                    Text(viewModel.accountId)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.ankyInkSoft)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 116)
                    Image(systemName: didCopyAddress ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ankyInkSoft)
                        .frame(width: 18)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("Copy public address"))

            rowDivider

            // Recovery phrase — the account itself. Revealed only behind a
            // device-owner check; never leaves the device.
            Button {
                if isRecoveryPhraseRevealed {
                    viewModel.hideRecoveryPhrase()
                } else {
                    Task { await viewModel.revealRecoveryPhrase() }
                }
            } label: {
                row(icon: "lock.shield", title: "Recovery phrase") {
                    Image(systemName: isRecoveryPhraseRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ankyInkSoft)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui(isRecoveryPhraseRevealed ? "Hide" : "Reveal recovery phrase"))

            if isRecoveryPhraseRevealed {
                VStack(alignment: .leading, spacing: 12) {
                    RecoveryWordsGrid(words: viewModel.recoveryPhraseWords)

                    Text(AnkyLocalization.ui("These 12 words are your account. Anyone who has them controls it. Anky never sees them and cannot recover them for you — write them down and keep them somewhere only you can reach."))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.ankyInkSoft)
                        .lineSpacing(2)

                    Button {
                        copyRecoveryPhrase()
                    } label: {
                        Label(
                            AnkyLocalization.ui(didCopyRecoveryPhrase ? "Copied" : "Copy"),
                            systemImage: didCopyRecoveryPhrase ? "checkmark" : "doc.on.doc"
                        )
                        .font(.fraunces(15, weight: .regular))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .modifier(ChipStyle(isSelected: false, cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }

    private var isRecoveryPhraseRevealed: Bool {
        !viewModel.recoveryPhraseText.isEmpty
    }

    // MARK: Server

    private var serverGroup: some View {
        group(title: "Anky server") {
            HStack(spacing: 16) {
                Image(systemName: "server.rack")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.ankyInk)
                    .frame(width: 22)

                TextField("https://anky.example.com", text: $serverAddress)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.ankyInk)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { connectServer() }

                Button {
                    connectServer()
                } label: {
                    if isConnectingServer {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(AnkyLocalization.ui("Connect"))
                            .font(.fraunces(15, weight: .regular))
                            .foregroundStyle(Color.ankyInk)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isConnectingServer)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)

            if serverStatus != nil || serverAddress != MirrorConfiguration.defaultBaseURL {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let serverStatus {
                        Text(AnkyLocalization.ui(serverStatus))
                            .foregroundStyle(serverStatus == "Connected." ? Color.ankyInkSoft : Color.ankyMadder)
                    }
                    Spacer(minLength: 0)
                    if serverAddress != MirrorConfiguration.defaultBaseURL {
                        Button {
                            MirrorConfiguration.reset()
                            serverAddress = MirrorConfiguration.defaultBaseURL
                            serverStatus = "Using Anky's default server."
                            AnkyHaptics.light()
                        } label: {
                            Text(AnkyLocalization.ui("Use default"))
                                .foregroundStyle(Color.ankyInk)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .disabled(isConnectingServer)
                    }
                }
                .font(.system(size: 12, weight: .regular))
                .padding(.leading, 54)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: Support

    private var supportGroup: some View {
        group(title: "Support") {
            Link(destination: Self.founderChatURL) {
                row(icon: "bubble.left.and.bubble.right", title: "Chat with the founder") { externalMark }
            }
            .buttonStyle(.plain)

            rowDivider

            Link(destination: feedbackEmailURL(subject: "Anky feedback")) {
                row(icon: "envelope", title: "Send feedback") { externalMark }
            }
            .buttonStyle(.plain)

            rowDivider

            ShareLink(item: Self.shareURL, message: Text(AnkyLocalization.ui("Write before you scroll."))) {
                row(icon: "square.and.arrow.up", title: "Share Anky") { EmptyView() }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Legal

    private var legalGroup: some View {
        group(title: "Legal") {
            Button {
                AnkyHaptics.light()
                showsPrivacyPolicy = true
            } label: {
                row(icon: "hand.raised", title: "Privacy Policy") { chevron }
            }
            .buttonStyle(.plain)

            rowDivider

            Button {
                AnkyHaptics.light()
                showsTermsAndConditions = true
            } label: {
                row(icon: "doc.text", title: "Terms & Conditions") { chevron }
            }
            .buttonStyle(.plain)

            if let onReplayOnboarding {
                rowDivider

                Button {
                    AnkyHaptics.light()
                    onReplayOnboarding()
                } label: {
                    row(icon: "sparkles", title: "Walk through the introduction again") { chevron }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Delete

    private var deleteGroup: some View {
        group {
            Button(role: .destructive) {
                deleteConfirmationText = ""
                showsDeleteAccountSheet = true
            } label: {
                row(icon: "trash", title: "Delete Account & Data", tint: .ankyMadder) { EmptyView() }
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        Text("Anky · " + AnkyLocalization.ui("Version format", viewModel.appVersion))
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
            .frame(maxWidth: .infinity)
    }

    // MARK: Row builders

    /// One titled block of rows on a single flat plate.
    private func group(title: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(AnkyLocalization.ui(title))
                    .font(.fraunces(14, weight: .regular))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                    .padding(.horizontal, 6)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.ankyPaperDeep.opacity(0.6))
            )
        }
    }

    /// Every row is one line: glyph, name, and whatever it controls or shows.
    private func row(
        icon: String,
        title: String,
        tint: Color = .ankyInk,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 22)

            Text(AnkyLocalization.ui(title))
                .font(.fraunces(17, weight: .regular))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        row(icon: icon, title: title) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.ankyInk)
        }
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.fraunces(15, weight: .regular))
            .foregroundStyle(Color.ankyInkSoft)
            .monospacedDigit()
            .lineLimit(1)
    }

    /// A line of fact under a row, aligned with the row's name.
    private func caption(_ text: String) -> some View {
        Text(AnkyLocalization.ui(text))
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.ankyInkSoft)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 54)
            .padding(.trailing, 16)
            .padding(.bottom, 12)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.ankyInkSoft.opacity(0.6))
    }

    private var externalMark: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.ankyInkSoft.opacity(0.6))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.ankyInk.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 54)
    }

    // MARK: State & actions

    private var pendingTargetFootnote: String? {
        guard let pendingTargetMinutes, pendingTargetMinutes != effectiveTargetMinutes else {
            return nil
        }
        return AnkyLocalization.ui(
            "pending daily target footnote format",
            effectiveTargetMinutes,
            pendingTargetMinutes
        )
    }

    private var iCloudBackupLine: String? {
        guard viewModel.isICloudBackupEnabled, let date = viewModel.iCloudBackupLastDate else {
            return nil
        }
        return AnkyLocalization.ui("Encrypted last backup format", date.formatted(date: .abbreviated, time: .shortened))
    }


    private var subscriptionStatusSymbol: String {
        guard entitlements.isEntitledForGating else {
            return "seal"
        }
        return entitlements.isPromotionalEntitlement ? "gift" : "checkmark.seal.fill"
    }

    private var subscriptionStatusTitle: String {
        if entitlements.isEntitledForGating {
            if entitlements.isPromotionalEntitlement {
                return "Complimentary access"
            }
            if entitlements.isInIntroTrialForGating {
                return "Free trial"
            }
            switch entitlements.activeProductID {
            case AnkyPurchasesConfig.annualProductID:
                return "Annual subscription"
            case AnkyPurchasesConfig.monthlyProductID:
                return "Monthly subscription"
            default:
                return "Active subscription"
            }
        }
        return "Free"
    }

    private var subscriptionStatusDetail: String? {
        if entitlements.isEntitledForGating {
            if entitlements.isPromotionalEntitlement {
                guard let endDate = entitlements.activeExpirationDate else {
                    return "Granted access, open-ended. Nothing is charged and nothing renews."
                }
                let date = endDate.formatted(date: .abbreviated, time: .omitted)
                return AnkyLocalization.ui("Granted access through date format", date)
            }
            if let renewalDate = entitlements.activeRenewalDate {
                let price = activeSubscriptionPriceLine
                let date = renewalDate.formatted(date: .abbreviated, time: .omitted)
                if entitlements.isInIntroTrialForGating {
                    return AnkyLocalization.ui("Trial ends date price format", date, price)
                }
                return AnkyLocalization.ui("Renews date price format", date, price)
            }
            return AnkyLocalization.ui("Anky unlocked active plan format", activeSubscriptionPriceLine)
        }
        return nil
    }

    private var activeSubscriptionPriceLine: String {
        // Never borrow another plan's price when the active product cannot be
        // resolved. StoreKit truth or an explicit unavailable state only.
        let product = entitlements.activePackage?.storeProduct
        guard let price = SubscriptionPriceFormatter.price(product) else {
            return AnkyLocalization.ui("App Store price unavailable")
        }
        if entitlements.activeProductID == AnkyPurchasesConfig.monthlyProductID {
            return AnkyLocalization.ui("price per month format", price)
        }
        return AnkyLocalization.ui("price per year format", price)
    }

    private func refreshDailyTarget() {
        let store = DailyTargetStore()
        effectiveTargetMinutes = store.effectiveTargetMinutes()
        pendingTargetMinutes = store.pendingTargetMinutes()
        targetMinutes = Double(pendingTargetMinutes ?? effectiveTargetMinutes)
    }

    private func commitDailyTarget() {
        AnkyHaptics.selection()
        let change = DailyTargetStore().requestTargetChange(to: Int(targetMinutes))
        WriteBeforeScrollEventLogStore().append(
            .targetChanged,
            metadata: [
                "oldMinutes": "\(change.oldMinutes)",
                "newMinutes": "\(change.newMinutes)"
            ]
        )
        refreshDailyTarget()
    }

    private var silenceSecondsRange: ClosedRange<Double> {
        let lower = Double(AnkyDuration.minTerminalSilenceMs / 1000)
        let upper = Double(AnkyDuration.maxTerminalSilenceMs / 1000)
        return lower...upper
    }

    private func commitSilenceDuration() {
        AnkyHaptics.selection()
        let ms = Int64((silenceSeconds * 1000).rounded())
        WritingPreferencesStore().update { $0.terminalSilenceMs = ms }
        writingPreferences = WritingPreferencesStore().load()
        silenceSeconds = Double(writingPreferences.effectiveTerminalSilenceMs) / 1000
    }

    private func connectServer() {
        guard !isConnectingServer else { return }
        isConnectingServer = true
        serverStatus = nil
        Task {
            do {
                let url = try MirrorConfiguration.normalizedBaseURL(from: serverAddress)
                try await MirrorConfiguration.checkConnection(to: url)
                _ = try MirrorConfiguration.save(url.absoluteString)
                await MainActor.run {
                    serverAddress = url.absoluteString
                    serverStatus = "Connected."
                    isConnectingServer = false
                    AnkyHaptics.success()
                }
            } catch {
                await MainActor.run {
                    serverStatus = (error as? LocalizedError)?.errorDescription ?? "Could not connect to that server."
                    isConnectingServer = false
                    AnkyHaptics.warning()
                }
            }
        }
    }

    private func copyAddress() {
        ClipboardClient().copy(viewModel.accountId)
        AnkyHaptics.success()
        withAnimation(.easeInOut(duration: 0.15)) { didCopyAddress = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.25)) { didCopyAddress = false }
        }
    }

    private func copyRecoveryPhrase() {
        ClipboardClient().copy(viewModel.recoveryPhraseText)
        AnkyHaptics.success()
        withAnimation(.easeInOut(duration: 0.15)) { didCopyRecoveryPhrase = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.25)) { didCopyRecoveryPhrase = false }
        }
    }

    private var deleteAccountSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(AnkyLocalization.ui("Delete Account & Data"))
                        .font(.ankyTitle)
                        .foregroundStyle(Color.ankyMadder)

                    Text(AnkyLocalization.ui("This permanently deletes all writings and paintings on this device, your Anky iCloud backup, and all server records for this account: subscription state, session ledger, level progress, generation history, and usage events."))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.ankyPaper)
                        .lineSpacing(5)

                    Text(AnkyLocalization.ui("Your writings were never stored on the Anky server. The server only saw .anky bytes transiently when you asked for reflection or painting generation."))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ankyPaper)
                        .lineSpacing(5)

                    Text(AnkyLocalization.ui("An active App Store subscription is not cancelled here. Cancel it separately in Settings → Apple ID → Subscriptions."))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.ankyPaper)
                        .lineSpacing(5)

                    Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                        Label(AnkyLocalization.ui("Open Apple Subscriptions"), systemImage: "arrow.up.forward.app")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .tint(Color.ankyGold)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(AnkyLocalization.ui("Type DELETE to confirm."))
                            .font(.ankyCaption)
                            .foregroundStyle(Color.ankyPaper.opacity(0.82))
                        TextField("DELETE", text: $deleteConfirmationText)
                            .textInputAutocapitalization(.characters)
                            .disableAutocorrection(true)
                            .padding(12)
                            .background(Color.ankyPaper.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(Color.ankyPaper)
                    }

                    Button(role: .destructive) {
                        Task { await performAccountDeletion() }
                    } label: {
                        HStack {
                            Spacer()
                            if isDeletingAccount {
                                ProgressView()
                                    .tint(Color.ankyPaper)
                            } else {
                                Text(AnkyLocalization.ui("Delete Account & Data"))
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(Color.ankyMadder, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color.ankyPaper)
                    }
                    .disabled(deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "DELETE" || isDeletingAccount)
                    .opacity(deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE" ? 1 : 0.55)
                }
                .padding(22)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AnkyLocalization.ui("Cancel")) {
                        showsDeleteAccountSheet = false
                    }
                    .disabled(isDeletingAccount)
                }
            }
        }
    }

    @MainActor
    private func performAccountDeletion() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        await viewModel.deleteAccountAndDataEverywhere()
        isDeletingAccount = false
        if viewModel.errorMessage == nil {
            showsDeleteAccountSheet = false
        }
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

    private var deviceAuthenticationIconName: String {
        switch BiometricAuthClient().deviceAuthenticationName() {
        case "Face ID":
            return "faceid"
        case "Touch ID":
            return "touchid"
        case "Optic ID":
            return "eye"
        default:
            return "lock"
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

    private func feedbackEmailURL(subject: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@anky.app"
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url ?? URL(string: "mailto:support@anky.app")!
    }
}

/// The revealed recovery phrase as a numbered two-column grid — the shape
/// people expect to copy onto paper, one word at a time.
private struct RecoveryWordsGrid: View {
    let words: [String]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.6))
                        .frame(width: 18, alignment: .trailing)
                    Text(word)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.ankyInk)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Color.ankyPaper.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
    }
}

/// The one selectable plate the settings use: ink when chosen, paper when not.
private struct ChipStyle: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .foregroundStyle(isSelected ? Color.ankyPaper : Color.ankyInk)
            .background(isSelected ? Color.ankyInk : Color.ankyPaper.opacity(0.7), in: shape)
            .overlay(shape.strokeBorder(Color.ankyInk.opacity(isSelected ? 0 : 0.10), lineWidth: 0.5))
            .contentShape(shape)
    }
}
