import SwiftUI
import RevenueCat

#if canImport(UIKit)
import UIKit
#endif

/// The settings page, painted in lazure: one scroll of translucent veils
/// over the breathing wall. Everything the writer can tune lives here —
/// with the ritual as the clear default.
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
    @State private var writerName = ""
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
        GeometryReader { geometry in
            ZStack {
                LazureWall(mood: .dawn)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        ZStack(alignment: .topTrailing) {
                            Text(AnkyLocalization.ui("Customize your Anky experience"))
                                .font(.ankyTitle)
                                .foregroundStyle(Color.ankyInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.trailing, 100)

                            Image("anky-flow-settings")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 144, height: 144)
                                .offset(y: -14)
                                .shadow(color: Color.ankyGold.opacity(0.12), radius: 12, y: 4)
                                .accessibilityHidden(true)
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 4)

                        subscriptionSection
                        dailyTargetSection
                        silenceSection
                        nameSection
                        writingSection
                        typefaceSection
                        protectionSection
                        identitySection
                        accountDeletionSection
                        paintingsSection
                        supportSection
                        legalSection
                        aboutSection
                        #if DEBUG && ANKY_INTERNAL_DEBUG
                        LevelDebugSection()
                        #endif
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 60)
                    .frame(width: min(geometry.size.width, 620), alignment: .leading)
                    .frame(width: geometry.size.width, alignment: .center)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            refreshDailyTarget()
            writerName = WritingAnchorStore().writerName ?? ""
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

    // MARK: Daily target

    private var subscriptionSection: some View {
        section(title: "Subscription") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    AnkyHaptics.light()
                    showsSubscriptionPaywall = true
                } label: {
                    VeilCard {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: subscriptionStatusSymbol)
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(entitlements.isEntitledForGating ? Color.ankyGold : Color.ankyInkSoft)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(AnkyLocalization.ui(subscriptionStatusTitle))
                                    .font(.ankyLabel)
                                    .foregroundStyle(Color.ankyInk)
                                Text(AnkyLocalization.ui(subscriptionStatusDetail))
                                    .font(.ankyCaption)
                                    .foregroundStyle(Color.ankyInkSoft)
                                    .lineSpacing(3)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.ankyInkSoft.opacity(0.75))
                                .padding(.top, 4)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button {
                    guard !entitlements.isRestoring else {
                        return
                    }
                    AnkyHaptics.light()
                    Task {
                        await entitlements.restore()
                    }
                } label: {
                    Text(AnkyLocalization.ui(entitlements.isRestoring ? "Restoring…" : "Restore Purchases"))
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankySlate)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)

                if let restoreLine = entitlements.restoreStatusLine {
                    Text(AnkyLocalization.ui(restoreLine))
                        .font(.ankyCaption)
                        .foregroundStyle(Color.ankyInkSoft)
                        .padding(.leading, 4)
                }
            }
        }
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

    private var subscriptionStatusDetail: String {
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
        if entitlements.packages.isEmpty {
            return "The plans are settling in. You can still write for free."
        }
        return "Writing and core features stay free. Tap to compare Anky Pro plans."
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

    private var dailyTargetSection: some View {
        section(title: "Your daily writing") {
            VeilCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(AnkyLocalization.ui("daily target minutes a day format", Int(targetMinutes)))
                            .font(.ankyHeading)
                            .foregroundStyle(Color.ankyInk)
                        Spacer()
                        AnkySunGlyph(size: 22, color: .ankyGold)
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
                    .tint(Color.ankyGold)

                    Text(AnkyLocalization.ui(dailyTargetFootnote))
                        .font(.ankyCaption)
                        .foregroundStyle(Color.ankyInkSoft)
                        .lineSpacing(3)
                }
            }
        }
    }

    private var dailyTargetFootnote: String {
        if let pendingTargetMinutes, pendingTargetMinutes != effectiveTargetMinutes {
            let key = entitlements.isEntitledForGating
                ? "pending Pro daily target footnote format"
                : "pending free daily target footnote format"
            return AnkyLocalization.ui(key, effectiveTargetMinutes, pendingTargetMinutes)
        }
        return entitlements.isEntitledForGating
            ? "With Anky Pro, reaching this target automatically unlocks protected apps for the rest of the day. Sessions are never cut short."
            : "Your target tracks your writing progress. Automatic rest-of-day unlocking after you reach it is an Anky Pro feature."
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

    // MARK: Silence (D3)

    /// How long the writing must rest before the channel closes and the Geshtu
    /// surfaces. A setting, not a fixed law — but never below three seconds, so
    /// a thoughtful pause is never mistaken for an ending. The canonical 8000
    /// sentinel that marks a sealed session is unaffected by this dial.
    private var silenceSection: some View {
        section(title: "The silence that closes the channel") {
            VeilCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(silenceSeconds))\(AnkyLocalization.ui("s of silence"))")
                            .font(.ankyHeading)
                            .foregroundStyle(Color.ankyInk)
                        Spacer()
                        Image(systemName: "hourglass")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(Color.ankyViolet)
                    }

                    Slider(
                        value: $silenceSeconds,
                        in: silenceSecondsRange,
                        step: 1
                    ) { isEditing in
                        if !isEditing {
                            commitSilenceDuration()
                        }
                    }
                    .tint(Color.ankyGold)

                    Text(AnkyLocalization.ui("When your writing rests this long, the words settle and the Geshtu rises to receive them."))
                        .font(.ankyCaption)
                        .foregroundStyle(Color.ankyInkSoft)
                        .lineSpacing(3)
                }
            }
        }
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

    // MARK: Name

    private var nameSection: some View {
        section(title: "How should Anky call you?") {
            VeilCard {
                TextField(AnkyLocalization.ui("your name"), text: $writerName)
                    .font(.ankyProse)
                    .foregroundStyle(Color.ankyInk)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit(saveWriterName)
                    .onChange(of: writerName) { _ in
                        saveWriterName()
                    }
            }
        }
    }

    private func saveWriterName() {
        let store = WritingAnchorStore()
        store.save(writerName: writerName, anchorSentence: store.anchorSentence)
    }

    // MARK: Writing chamber

    private var writingSection: some View {
        section(title: "Writing") {
            VeilCard(padding: 0) {
                VStack(spacing: 0) {
                    toggleRow(
                        icon: "delete.backward",
                        title: "Backspace",
                        subtitle: "Off keeps the ritual: words only move forward.",
                        isOn: Binding(
                            get: { writingPreferences.backspaceAllowed },
                            set: { newValue in
                                AnkyHaptics.light()
                                writingPreferences.backspaceAllowed = newValue
                                WritingPreferencesStore().save(writingPreferences)
                            }
                        )
                    )

                    LazureDivider().padding(.horizontal, 18)

                    toggleRow(
                        icon: "keyboard",
                        title: "Autocorrect & suggestions",
                        subtitle: "The keyboard's spelling help and word bar.",
                        isOn: Binding(
                            get: { writingPreferences.autocorrectEnabled },
                            set: { newValue in
                                AnkyHaptics.light()
                                writingPreferences.autocorrectEnabled = newValue
                                WritingPreferencesStore().save(writingPreferences)
                            }
                        )
                    )

                    LazureDivider().padding(.horizontal, 18)

                    terminalStillnessRow
                }
            }
        }
    }

    private var terminalStillnessRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "timer")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.ankyViolet)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AnkyLocalization.ui("Stillness before reflection"))
                        .font(.ankyLabel)
                        .foregroundStyle(Color.ankyInk)
                    Text("\(terminalStillnessSeconds) seconds")
                        .font(.ankyCaption)
                        .foregroundStyle(Color.ankyInkSoft)
                }

                Spacer()
            }

            Slider(
                value: Binding(
                    get: { Double(terminalStillnessSeconds) },
                    set: { newValue in
                        let seconds = Int(newValue.rounded())
                        writingPreferences.terminalSilenceMs = Int64(seconds) * 1000
                        WritingPreferencesStore().save(writingPreferences)
                    }
                ),
                in: 1...8,
                step: 1
            )
            .tint(Color.ankyGold)
        }
        .padding(18)
    }

    private var terminalStillnessSeconds: Int {
        Int(writingPreferences.effectiveTerminalSilenceMs / 1000)
    }

    // MARK: Typeface

    private var typefaceSection: some View {
        section(title: "Font & size") {
            VeilCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        ForEach(AnkyWritingFontChoice.allCases, id: \.self) { choice in
                            fontChip(choice)
                        }
                    }

                    HStack(spacing: 10) {
                        ForEach(AnkyWritingTextSize.allCases, id: \.self) { size in
                            sizeChip(size)
                        }
                    }

                    LazureDivider()

                    Text(AnkyLocalization.ui("One that stays. One that listens."))
                        .font(writingPreferences.fontChoice.font(size: writingPreferences.textSize.pointSize))
                        .foregroundStyle(Color.ankyInk)
                        .lineSpacing(writingPreferences.textSize.pointSize * 0.42)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeInOut(duration: 0.2), value: writingPreferences)
                }
            }
        }
    }

    private func fontChip(_ choice: AnkyWritingFontChoice) -> some View {
        let isSelected = writingPreferences.fontChoice == choice
        return Button {
            AnkyHaptics.selection()
            writingPreferences.fontChoice = choice
            WritingPreferencesStore().save(writingPreferences)
        } label: {
            VStack(spacing: 5) {
                Text("Aa")
                    .font(choice.font(size: 21))
                    .foregroundStyle(Color.ankyInk)
                Text(AnkyLocalization.ui(choice.displayName))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                        ? LinearGradient(colors: [Color.ankyGoldLight.opacity(0.7), Color.ankyGold.opacity(0.45)],
                                         startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color.ankyPaper.opacity(0.5), Color.ankyPaper.opacity(0.3)],
                                         startPoint: .top, endPoint: .bottom)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.ankyInk.opacity(isSelected ? 0.16 : 0.08), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func sizeChip(_ size: AnkyWritingTextSize) -> some View {
        let isSelected = writingPreferences.textSize == size
        return Button {
            AnkyHaptics.selection()
            writingPreferences.textSize = size
            WritingPreferencesStore().save(writingPreferences)
        } label: {
            Text(AnkyLocalization.ui(size.displayName))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ankyInk.opacity(isSelected ? 0.95 : 0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    Capsule()
                        .fill(
                            isSelected
                            ? LinearGradient(colors: [Color.ankyGoldLight.opacity(0.7), Color.ankyGold.opacity(0.45)],
                                             startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Color.ankyPaper.opacity(0.5), Color.ankyPaper.opacity(0.3)],
                                             startPoint: .top, endPoint: .bottom)
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.ankyInk.opacity(isSelected ? 0.16 : 0.08), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Protection & data

    private var protectionSection: some View {
        section(title: "Protection") {
            VeilCard(padding: 0) {
                VStack(spacing: 0) {
                    toggleRow(
                        icon: "icloud",
                        title: "iCloud backup",
                        subtitle: iCloudSubtitle,
                        isOn: iCloudBackupBinding
                    )

                    if BiometricAuthClient().canAuthenticate() {
                        LazureDivider().padding(.horizontal, 18)

                        toggleRow(
                            icon: deviceAuthenticationIconName,
                            title: BiometricAuthClient().deviceAuthenticationName() + " lock",
                            subtitle: "Ask before opening your writing.",
                            isOn: faceIDBinding
                        )
                    }

                    LazureDivider().padding(.horizontal, 18)

                    navigationRow(
                        icon: "shield",
                        title: "Apps that are blocked",
                        subtitle: "Choose what waits until you have written.",
                        action: {
                            AnkyHaptics.light()
                            onGateSetupRequested()
                        }
                    )
                }
            }
        }
    }

    // MARK: Identity (self-sovereign keys)

    /// The writer owns their account outright: a public address anyone can
    /// verify their writing against, and the 12 words that ARE the account —
    /// held only on this device, never on an Anky server.
    private var identitySection: some View {
        section(title: "Your keys") {
            VeilCard {
                VStack(alignment: .leading, spacing: 16) {
                    // Public address — safe to share, the writer's identity
                    // on Base. Derived from the recovery phrase.
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "key.horizontal")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(Color.ankyViolet)
                            Text(AnkyLocalization.ui("Public address"))
                                .font(.ankyLabel)
                                .foregroundStyle(Color.ankyInk)
                            Spacer()
                            Button {
                                copyAddress()
                            } label: {
                                HStack(spacing: 5) {
                                    if didCopyAddress {
                                        Text(AnkyLocalization.ui("Copied"))
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    Image(systemName: didCopyAddress ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundStyle(didCopyAddress ? Color.ankyGold : Color.ankyInkSoft)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AnkyLocalization.ui("Copy public address"))
                        }

                        // The full address, wrapping so every character shows —
                        // tap to copy, or select it by hand.
                        Text(viewModel.accountId)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.ankyInk)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(11)
                            .background(Color.ankyPaper.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onTapGesture { copyAddress() }

                        Text(AnkyLocalization.ui("Derived from your recovery phrase. Safe to share — it's how anyone can verify your writing is yours."))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                            .lineSpacing(3)
                    }

                    LazureDivider()

                    // Recovery phrase — the account itself. Revealed only
                    // behind a device-owner check; never leaves the device.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(Color.ankyViolet)
                            Text(AnkyLocalization.ui("Recovery phrase"))
                                .font(.ankyLabel)
                                .foregroundStyle(Color.ankyInk)
                        }

                        Text(AnkyLocalization.ui("These 12 words are your account. Anyone who has them controls it. Anky never sees them and cannot recover them for you — write them down and keep them somewhere only you can reach."))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.ankyInkSoft)
                            .lineSpacing(3)

                        if viewModel.recoveryPhraseText.isEmpty {
                            Button {
                                Task { await viewModel.revealRecoveryPhrase() }
                            } label: {
                                Text(AnkyLocalization.ui("Reveal recovery phrase"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.ankyInk)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.ankyGold.opacity(0.20), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.ankyGold.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        } else {
                            RecoveryWordsGrid(words: viewModel.recoveryPhraseWords)

                            HStack(spacing: 10) {
                                Button {
                                    copyRecoveryPhrase()
                                } label: {
                                    Label(
                                        AnkyLocalization.ui(didCopyRecoveryPhrase ? "Copied" : "Copy"),
                                        systemImage: didCopyRecoveryPhrase ? "checkmark" : "doc.on.doc"
                                    )
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(didCopyRecoveryPhrase ? Color.ankyGold : Color.ankyInk)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.ankyPaper.opacity(0.5), in: Capsule())
                                        .overlay(Capsule().strokeBorder((didCopyRecoveryPhrase ? Color.ankyGold : Color.ankyInk).opacity(didCopyRecoveryPhrase ? 0.5 : 0.10), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    viewModel.hideRecoveryPhrase()
                                } label: {
                                    Text(AnkyLocalization.ui("Hide"))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.ankyInkSoft)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.ankyPaper.opacity(0.5), in: Capsule())
                                        .overlay(Capsule().strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
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

    private var accountDeletionSection: some View {
        section(title: "Delete account") {
            Button(role: .destructive) {
                deleteConfirmationText = ""
                showsDeleteAccountSheet = true
            } label: {
                VeilCard {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.ankyMadder)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(AnkyLocalization.ui("Delete Account & Data"))
                                .font(.ankyLabel)
                                .foregroundStyle(Color.ankyMadder)
                            Text(AnkyLocalization.ui("Permanently delete this device archive, iCloud backup, and Anky server records."))
                                .font(.ankyCaption)
                                .foregroundStyle(Color.ankyInkSoft)
                                .lineSpacing(3)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.ankyMadder.opacity(0.55), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .tint(Color.ankyMadder)
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

    /// Spec §3.1 disclosure: how the level paintings relate to the writing.
    private var paintingsSection: some View {
        section(title: "Your paintings") {
            VeilCard {
                Text(AnkyLocalization.ui(AnkyCopyRegistry.paintingDisclosure))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.ankyInkSoft)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var iCloudSubtitle: String {
        if viewModel.isICloudBackupEnabled {
            if let date = viewModel.iCloudBackupLastDate {
                return AnkyLocalization.ui("Encrypted last backup format", date.formatted(date: .abbreviated, time: .shortened))
            }
            return "Encrypted backup is on."
        }
        return "Keep an encrypted copy of your archive."
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

    // MARK: Support

    private var supportSection: some View {
        section(title: "Support") {
            VeilCard(padding: 0) {
                VStack(spacing: 0) {
                    linkRow(
                        icon: "bubble.left.and.bubble.right",
                        title: "Chat with the founder",
                        subtitle: "Telegram — a human answers.",
                        url: Self.founderChatURL
                    )

                    LazureDivider().padding(.horizontal, 18)

                    linkRow(
                        icon: "paperplane",
                        title: "Send feedback",
                        subtitle: "Anky grows from what you tell us.",
                        url: feedbackEmailURL(subject: "Anky feedback")
                    )

                    LazureDivider().padding(.horizontal, 18)

                    linkRow(
                        icon: "envelope",
                        title: "Contact via email",
                        subtitle: "support@anky.app",
                        url: feedbackEmailURL(subject: "Hello Anky")
                    )

                    LazureDivider().padding(.horizontal, 18)

                    ShareLink(item: Self.shareURL, message: Text(AnkyLocalization.ui("Write before you scroll."))) {
                        rowLabel(
                            icon: "square.and.arrow.up",
                            title: "Share Anky",
                            subtitle: "Give a friend a door before the noise.",
                            trailingIcon: nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func feedbackEmailURL(subject: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@anky.app"
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url ?? URL(string: "mailto:support@anky.app")!
    }

    // MARK: Legal & about

    private var legalSection: some View {
        section(title: "Legal") {
            VeilCard(padding: 0) {
                VStack(spacing: 0) {
                    navigationRow(
                        icon: "hand.raised",
                        title: "Privacy Policy",
                        subtitle: "Your writing stays yours.",
                        action: {
                            AnkyHaptics.light()
                            showsPrivacyPolicy = true
                        }
                    )

                    LazureDivider().padding(.horizontal, 18)

                    navigationRow(
                        icon: "doc.text",
                        title: "Terms & Conditions",
                        subtitle: "The agreement for using Anky.",
                        action: {
                            AnkyHaptics.light()
                            showsTermsAndConditions = true
                        }
                    )
                }
            }
        }
    }

    private var aboutSection: some View {
        section(title: "About") {
            VeilCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        AnkySunGlyph(size: 24, color: .ankyViolet)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AnkyLocalization.ui("Anky"))
                                .font(.ankyLabel)
                                .foregroundStyle(Color.ankyInk)
                            Text(AnkyLocalization.ui("Version format", viewModel.appVersion))
                                .font(.ankyCaption)
                                .foregroundStyle(Color.ankyInkSoft)
                        }
                        Spacer()
                    }
                    .padding(18)

                    if let onReplayOnboarding {
                        LazureDivider().padding(.horizontal, 18)

                        navigationRow(
                            icon: "sparkles",
                            title: "Walk through the introduction again",
                            subtitle: "Replay the onboarding, from the first door.",
                            action: {
                                AnkyHaptics.light()
                                onReplayOnboarding()
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: Row builders

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AnkyLocalization.ui(title))
                .font(.ankyHeading)
                .foregroundStyle(Color.ankyInk.opacity(0.85))
                .padding(.horizontal, 4)
            content()
        }
    }

    private func rowLabel(icon: String, title: String, subtitle: String, trailingIcon: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.ankyViolet)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(AnkyLocalization.ui(title))
                    .font(.ankyLabel)
                    .foregroundStyle(Color.ankyInk)
                Text(AnkyLocalization.ui(subtitle))
                    .font(.ankyCaption)
                    .foregroundStyle(Color.ankyInkSoft)
            }

            Spacer()

            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.7))
            }
        }
        .padding(18)
        .contentShape(Rectangle())
    }

    private func navigationRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(icon: icon, title: title, subtitle: subtitle, trailingIcon: "chevron.right")
        }
        .buttonStyle(.plain)
    }

    private func linkRow(icon: String, title: String, subtitle: String, url: URL) -> some View {
        Link(destination: url) {
            rowLabel(icon: icon, title: title, subtitle: subtitle, trailingIcon: "arrow.up.right")
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.ankyViolet)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(AnkyLocalization.ui(title))
                    .font(.ankyLabel)
                    .foregroundStyle(Color.ankyInk)
                Text(AnkyLocalization.ui(subtitle))
                    .font(.ankyCaption)
                    .foregroundStyle(Color.ankyInkSoft)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.ankyGold)
        }
        .padding(18)
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
                .background(Color.ankyPaper.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.ankyGold.opacity(0.22), lineWidth: 0.5)
                )
            }
        }
    }
}
