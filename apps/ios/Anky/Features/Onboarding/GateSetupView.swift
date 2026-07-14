import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

/// User-facing Write Before Scroll setup: authorize Screen Time, choose the
/// apps that pull you out of yourself, and turn the writing gate on.
/// This is the productized surface for what previously lived only in the
/// WBS debug panel.
struct GateSetupView: View {
    @ObservedObject var viewModel: WriteBeforeScrollSpikeViewModel
    let onDone: () -> Void

    @State private var confirmsGateOff = false

    private enum SetupStep {
        case authorize
        case chooseApps
        case turnOn
        case done
    }

    private var currentStep: SetupStep {
        if !viewModel.isScreenTimeAuthorized { return .authorize }
        if !viewModel.state.hasSelection { return .chooseApps }
        if !viewModel.state.shieldActive { return .turnOn }
        return .done
    }

    private var stepCaption: String {
        switch currentStep {
        case .authorize:
            return "Anky needs screen time permission to hold the door."
        case .chooseApps:
            return "Pick the apps that pull you out of yourself."
        case .turnOn:
            return viewModel.isGateOff
                ? AnkyCopyRegistry.gateOffStandingCaption
                : "Anky will block these apps until you write."
        case .done:
            return "The door is standing. Write, and it opens."
        }
    }

    private var stepButtonTitle: String {
        switch currentStep {
        case .authorize: return "Allow Screen Time"
        case .chooseApps: return "Choose apps"
        case .turnOn: return "Stay focused"
        case .done: return "Start writing"
        }
    }

    private func stepAction() {
        switch currentStep {
        case .authorize:
            viewModel.requestAuthorization()
        case .chooseApps:
            #if os(iOS) && canImport(FamilyControls)
            viewModel.isPickerPresented = true
            #endif
        case .turnOn:
            viewModel.forceLock()
        case .done:
            onDone()
        }
    }

    // One line, one image, one action. The single button always does the
    // next needed step; nothing is overexplained.
    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    Spacer(minLength: 24)

                    Image("anky-gate-door")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 271)
                        .frame(height: 250)
                        .accessibilityHidden(true)

                    Text(AnkyLocalization.ui("Door closed, focus opens."))
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ankyInk)
                        .multilineTextAlignment(.center)

                    Text(AnkyLocalization.ui(stepCaption))
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft)
                        .multilineTextAlignment(.center)

                    selectedAppsPanel

                    AnkyPrimaryButton(stepButtonTitle, action: stepAction)
                        .padding(.top, 2)

                    if currentStep != .done {
                        Button(action: onDone) {
                            Text(AnkyLocalization.ui("Skip"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }

                    // The honest exit (2026-07-06): one control, one
                    // confirmation. Turning the gate back on is the same
                    // single button it always was.
                    if currentStep == .done {
                        Button {
                            confirmsGateOff = true
                        } label: {
                            Text(AnkyLocalization.ui(AnkyCopyRegistry.gateOffLink))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 26)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            viewModel.refresh()
        }
        .alert(
            AnkyLocalization.ui(AnkyCopyRegistry.gateOffConfirmTitle),
            isPresented: $confirmsGateOff
        ) {
            Button(AnkyLocalization.ui(AnkyCopyRegistry.gateOffConfirm), role: .destructive) {
                viewModel.turnGateOff()
            }
            Button(AnkyLocalization.ui(AnkyCopyRegistry.gateOffCancel), role: .cancel) {}
        } message: {
            Text(AnkyLocalization.ui(AnkyCopyRegistry.gateOffConfirmBody))
        }
        #if os(iOS) && canImport(FamilyControls)
        .familyActivityPicker(
            headerText: AnkyLocalization.ui("Pick the apps that pull you out of yourself."),
            footerText: AnkyLocalization.ui("Anky will put a writing gate before them."),
            isPresented: $viewModel.isPickerPresented,
            selection: $viewModel.selection
        )
        .onChange(of: viewModel.isPickerPresented) { isPresented in
            if !isPresented {
                viewModel.saveSelection()
            }
        }
        #endif
    }

    @ViewBuilder
    private var selectedAppsPanel: some View {
        #if os(iOS) && canImport(FamilyControls)
        if viewModel.isScreenTimeAuthorized {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(AnkyLocalization.ui("Blocked apps"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ankyInk)
                    Spacer()
                    Button {
                        viewModel.isPickerPresented = true
                    } label: {
                        Text(AnkyLocalization.ui(viewModel.state.hasSelection ? "Change" : "Choose"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.ankyViolet)
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.state.hasSelection {
                    selectedBlockedIconGrid
                } else {
                    Text(AnkyLocalization.ui("Choose the apps you want Anky to hold behind the writing door."))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ankyInkSoft)
                        .lineSpacing(3)
                }
            }
            .padding(18)
            .background(Color.ankyPaper.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
            )
        }
        #endif
    }

    private var selectedBlockedIconGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 14)], spacing: 14) {
            ForEach(selectedBlockedIconNames, id: \.self) { imageName in
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 74, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
                    )
            }
        }
    }

    private var selectedBlockedIconNames: [String] {
        #if os(iOS) && canImport(FamilyControls)
        let appTokens = Array(viewModel.selection.applicationTokens)
        let categoryCount = viewModel.selection.categoryTokens.count
        let recognizedNames = appTokens.compactMap(Self.blockedIconName)
        let fallbackCount = max(0, appTokens.count - recognizedNames.count)
        let fallbacks = Self.defaultSelectedIconNames
            .filter { !recognizedNames.contains($0) }
            .prefix(fallbackCount)
        let categoryFallbacks = Self.defaultSelectedIconNames
            .filter { !recognizedNames.contains($0) && !fallbacks.contains($0) }
            .prefix(categoryCount)
        return Array(recognizedNames + fallbacks + categoryFallbacks)
        #else
        return []
        #endif
    }

    #if os(iOS) && canImport(FamilyControls)
    private static func blockedIconName(for token: ApplicationToken) -> String? {
        let application = Application(token: token)
        let candidates = [
            application.localizedDisplayName,
            application.bundleIdentifier
        ]
        .compactMap { $0 }
        .map(normalizedAppIdentifier)

        for candidate in candidates {
            if let exact = iconNameByIdentifier[candidate] {
                return exact
            }
            if let fuzzy = iconNameByIdentifier.first(where: { identifier, _ in
                guard identifier.count > 2, candidate.count > 2 else { return false }
                return candidate.contains(identifier) || identifier.contains(candidate)
            })?.value {
                return fuzzy
            }
        }

        return nil
    }

    private static func normalizedAppIdentifier(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static let iconNameByIdentifier: [String: String] = [
        "whatsapp": "blocked-whatsapp",
        "netwhatsappwhatsapp": "blocked-whatsapp",
        "youtube": "blocked-youtube",
        "comgoogleiosyoutube": "blocked-youtube",
        "chrome": "blocked-chrome",
        "comgooglechromeios": "blocked-chrome",
        "instagram": "blocked-instagram",
        "comburbninstagram": "blocked-instagram",
        "tiktok": "blocked-tiktok",
        "commusicallymusically": "blocked-tiktok",
        "facebook": "blocked-facebook",
        "comfacebookfacebook": "blocked-facebook",
        "spotify": "blocked-spotify",
        "comspotifyclient": "blocked-spotify",
        "snapchat": "blocked-snapchat",
        "comtoychatsnapchat": "blocked-snapchat",
        "netflix": "blocked-netflix",
        "comnetflixnetflix": "blocked-netflix",
        "reddit": "blocked-reddit",
        "comredditreddit": "blocked-reddit",
        "linkedin": "blocked-linkedin",
        "comlinkedinlinkedin": "blocked-linkedin",
        "discord": "blocked-discord",
        "comhammerandchiseldiscord": "blocked-discord",
        "chatgpt": "blocked-chatgpt",
        "comopenaichat": "blocked-chatgpt",
        "claude": "blocked-claude",
        "comanthropicclaude": "blocked-claude",
        "telegram": "blocked-telegram",
        "phtelegrachtelegraph": "blocked-telegram",
        "x": "blocked-x",
        "twitter": "blocked-x",
        "comatebitsphone": "blocked-x"
    ]
    #endif

    private static let defaultSelectedIconNames = [
        "blocked-instagram",
        "blocked-x",
        "blocked-tiktok",
        "blocked-youtube",
        "blocked-whatsapp",
        "blocked-chrome",
        "blocked-facebook",
        "blocked-spotify",
        "blocked-snapchat",
        "blocked-netflix",
        "blocked-reddit",
        "blocked-linkedin",
        "blocked-discord",
        "blocked-chatgpt",
        "blocked-claude",
        "blocked-telegram"
    ]
}
