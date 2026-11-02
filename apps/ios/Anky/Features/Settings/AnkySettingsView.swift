import StoreKit
import SwiftUI

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


    @State private var writingPreferences = WritingPreferencesStore().load()
    @AppStorage(AnkyAppearance.storageKey) private var appearance: AnkyAppearance = .paper
    @State private var showsManageSubscription = false
    @State private var showsPrivacyPolicy = false
    @State private var showsTermsAndConditions = false
    @State private var showsDeleteAccountSheet = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false

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

                writingGroup
                typefaceGroup
                proGroup
                protectionGroup
                supportGroup
                legalGroup
                deleteGroup
                footer
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 48)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.ankyPaper.ignoresSafeArea())
        .environment(\.colorScheme, appearance.colorScheme)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            // Archive counts and iCloud backup state are read here rather
            // than when the view model is built, so opening the drawer never
            // pays for the account-key derivation.
            viewModel.refresh()
            writingPreferences = WritingPreferencesStore().load()
        }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscription)
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
        .sheet(isPresented: $showsDeleteAccountSheet) {
            deleteAccountSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .ankySheetBackground(PrivacySheetPalette.ink)
        }
    }

    // MARK: Writing

    private var writingGroup: some View {
        group(title: "Writing") {
            row(icon: appearance == .night ? "moon" : "sun.max", title: appearance == .night ? "Night" : "Day") {
                SunMoonToggle(isNight: Binding(
                    get: { appearance == .night },
                    set: { isNight in
                        AnkyHaptics.selection()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appearance = isNight ? .night : .paper
                        }
                    }
                ))
            }

            rowDivider

            toggleRow(icon: "delete.backward", title: "Backspace", isOn: preferenceBinding(\.backspaceAllowed))

            rowDivider

            toggleRow(icon: "keyboard", title: "Autocorrect & suggestions", isOn: preferenceBinding(\.autocorrectEnabled))
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

    private func setPreference(_ mutate: (inout WritingPreferences) -> Void) {
        AnkyHaptics.selection()
        mutate(&writingPreferences)
        WritingPreferencesStore().save(writingPreferences)
    }

    // MARK: Look of the writing

    private var typefaceGroup: some View {
        VStack(alignment: .leading, spacing: 28) {
            group(title: "Font") {
                ForEach(Array(AnkyWritingFontChoice.allCases.enumerated()), id: \.element) { index, choice in
                    if index > 0 { listDivider }
                    fontRow(choice)
                }
            }

            group(title: "Ink") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                    ForEach(AnkyInkChoice.allCases, id: \.self) { ink in
                        inkSwatch(ink)
                    }
                }
                .padding(14)
            }

            group(title: "Size") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(AnkyWritingTextSize.allCases, id: \.self) { size in
                            sizeChip(size)
                        }
                    }

                    Text(AnkyLocalization.ui("One that stays. One that listens."))
                        .font(writingPreferences.fontChoice.font(size: writingPreferences.textSize.pointSize))
                        .foregroundStyle(writingPreferences.inkChoice.color)
                        .lineSpacing(writingPreferences.textSize.pointSize * 0.42)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .padding(.horizontal, 2)
                        .animation(.easeInOut(duration: 0.2), value: writingPreferences)
                }
                .padding(14)
            }
        }
    }

    /// Each font's name, written in that font.
    private func fontRow(_ choice: AnkyWritingFontChoice) -> some View {
        let isSelected = writingPreferences.fontChoice == choice
        return Button {
            setPreference { $0.fontChoice = choice }
        } label: {
            HStack {
                Text(AnkyLocalization.ui(choice.displayName))
                    .font(choice.font(size: 20))
                    .foregroundStyle(isSelected ? writingPreferences.inkChoice.color : Color.ankyInk)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(writingPreferences.inkChoice.color)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func inkSwatch(_ ink: AnkyInkChoice) -> some View {
        let isSelected = writingPreferences.inkChoice == ink
        return Button {
            setPreference { $0.inkChoice = ink }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(ink.color)
                    .frame(width: 34, height: 34)
                    .padding(4)
                    .overlay(
                        Circle().strokeBorder(ink.color, lineWidth: isSelected ? 2 : 0)
                    )
                Text(AnkyLocalization.ui(ink.displayName))
                    .font(.fraunces(13, weight: .regular))
                    .foregroundStyle(isSelected ? Color.ankyInk : Color.ankyInkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(AnkyLocalization.ui(ink.displayName)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sizeChip(_ size: AnkyWritingTextSize) -> some View {
        let isSelected = writingPreferences.textSize == size
        return Button {
            setPreference { $0.textSize = size }
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

    private var listDivider: some View {
        Rectangle()
            .fill(Color.ankyInk.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    // MARK: Anky Pro

    private var proGroup: some View {
        group(title: "Anky Pro") {
            Button {
                AnkyHaptics.light()
                showsManageSubscription = true
            } label: {
                row(icon: "circle.hexagongrid", title: "Manage subscription") { chevron }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Protection

    private var protectionGroup: some View {
        group(title: "Protection") {
            toggleRow(icon: "icloud", title: "iCloud backup", isOn: iCloudBackupBinding)
            if let iCloudBackupLine {
                caption(iCloudBackupLine)
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
                row(icon: "trash", title: "Delete All Data", tint: .ankyMadder) { EmptyView() }
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

    private var iCloudBackupLine: String? {
        guard viewModel.isICloudBackupEnabled, let date = viewModel.iCloudBackupLastDate else {
            return nil
        }
        return AnkyLocalization.ui("Encrypted last backup format", date.formatted(date: .abbreviated, time: .shortened))
    }

    private var deleteAccountSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(AnkyLocalization.ui("Delete All Data"))
                        .font(.ankyTitle)
                        .foregroundStyle(Color.ankyMadder)

                    Text(AnkyLocalization.ui("This permanently deletes every writing on this device and your Anky iCloud backup. Anky has no server account: nothing else exists anywhere."))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.ankyPaper)
                        .lineSpacing(5)

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
                                Text(AnkyLocalization.ui("Delete All Data"))
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

    private func feedbackEmailURL(subject: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@anky.app"
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url ?? URL(string: "mailto:support@anky.app")!
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

/// Day or night: a sun and a moon in one capsule; the knob rests on the
/// one in force. A tap anywhere flips it.
private struct SunMoonToggle: View {
    @Binding var isNight: Bool

    var body: some View {
        Button {
            isNight.toggle()
        } label: {
            ZStack(alignment: isNight ? .trailing : .leading) {
                Capsule()
                    .fill(Color.ankyInk.opacity(0.10))
                Circle()
                    .fill(Color.ankyPaper)
                    .shadow(color: Color.ankyInk.opacity(0.18), radius: 2, y: 1)
                    .padding(3)
                HStack(spacing: 0) {
                    Image(systemName: "sun.max.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(isNight ? Color.ankyInkSoft.opacity(0.6) : Color.ankyOchreGlyph)
                    Image(systemName: "moon.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(isNight ? Color.ankyInk : Color.ankyInkSoft.opacity(0.6))
                }
                .font(.system(size: 14, weight: .medium))
            }
            .frame(width: 72, height: 36)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(AnkyLocalization.ui(isNight ? "Night" : "Day")))
        .accessibilityHint(Text(AnkyLocalization.ui("Switches between day and night")))
    }
}

private extension Color {
    static let ankyOchreGlyph = Color(.displayP3, red: 0.85, green: 0.58, blue: 0.12)
}
