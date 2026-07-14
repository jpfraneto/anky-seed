import SwiftUI
import UIKit

struct RevealView: View {
    @StateObject private var viewModel: RevealViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var ankyCompanion: AnkyCompanionStore
    @EnvironmentObject private var tabBarCTAController: AnkyTabBarCTAController
    @State private var confirmDelete = false
    @State private var didAutoStartReflection = false
    @State private var didRequestFirstReflectionReview = false
    @State private var reflectionScrollRequest = 0
    @State private var inlineReflectionActive = false
    @State private var didScrollToStreamingStart = false
    @State private var isReflectionVisible = false
    @State private var didSeeReflection = false
    @State private var isShowingPaywallSheet = false
    @EnvironmentObject private var entitlements: EntitlementStore
    @State private var privacyDisclosure = PrivacyLockDisclosure()
    @State private var isNavigationBarHidden = false
    @State private var lastScrollOffsetY: CGFloat = 0
    @State private var hasObservedScrollOffset = false
    @State private var didCopyWriting = false
    @State private var didClaimWriteBeforeScrollUnlock = false
    private let onBack: (() -> Void)?
    private let onDeleted: () -> Void
    private let onTryAgain: () -> Void
    private let onReflectionReady: () -> Void
    private let writeBeforeScrollUnlockGrant: UnlockGrant?
    private let onWriteBeforeScrollUnlock: () -> Void
    private let startsReflectionOnAppear: Bool
    /// True when an `InteractiveBackSwipeContainer` above owns the
    /// finger-tracked back-swipe — the internal end-of-drag fallback would
    /// fire a second, instant route swap under it.
    private let handlesBackSwipeExternally: Bool

    init(
        viewModel: RevealViewModel,
        startsReflectionOnAppear: Bool = false,
        writeBeforeScrollUnlockGrant: UnlockGrant? = nil,
        onBack: (() -> Void)? = nil,
        onDeleted: @escaping () -> Void = {},
        onTryAgain: @escaping () -> Void = {},
        onReflectionReady: @escaping () -> Void = {},
        onWriteBeforeScrollUnlock: @escaping () -> Void = {},
        handlesBackSwipeExternally: Bool = false
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.startsReflectionOnAppear = startsReflectionOnAppear
        self.writeBeforeScrollUnlockGrant = writeBeforeScrollUnlockGrant
        self.onBack = onBack
        self.onDeleted = onDeleted
        self.onTryAgain = onTryAgain
        self.onReflectionReady = onReflectionReady
        self.onWriteBeforeScrollUnlock = onWriteBeforeScrollUnlock
        self.handlesBackSwipeExternally = handlesBackSwipeExternally
    }

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)

            VStack(spacing: 0) {
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear
                                .frame(height: 0)
                                .trackRevealScrollOffset()

                            WritingSessionStatsHeader(
                                wordCount: viewModel.wordCount,
                                duration: viewModel.duration,
                                backspaceCount: viewModel.backspaceCount,
                                enterCount: viewModel.enterCount
                            )
                            .padding(.bottom, 14)

                            if let grant = writeBeforeScrollUnlockGrant,
                               !didClaimWriteBeforeScrollUnlock {
                                WriteBeforeScrollSealedUnlockButton(grant: grant) {
                                    AnkyHaptics.light()
                                    didClaimWriteBeforeScrollUnlock = true
                                    onWriteBeforeScrollUnlock()
                                }
                                .padding(.bottom, 18)
                                .transition(.opacity)
                            }

                            SelectableWritingText(
                                text: viewModel.reconstructedText
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .id(RevealScrollTarget.writing)

                            VStack(spacing: 10) {
                                PrivacyDivider {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        privacyDisclosure.toggle()
                                    }
                                }

                                if privacyDisclosure.isExpanded {
                                    Text(AnkyLocalization.ui("Your writing is sacred. It stays on your phone and only leaves if you ask for a reflection. Anky mirrors it back and never stores it."))
                                        .font(.system(size: 13, weight: .medium))
                                        .lineSpacing(4)
                                        .foregroundStyle(RevealPalette.paper.opacity(0.62))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .padding(.top, 34)

                            if viewModel.hasFallbackReflection {
                                // A stored provider-outage apology is a failed
                                // reflection, not Anky's thoughts: offer the
                                // retry, loudly (feedback 2026-07-08).
                                FallbackReflectionRetryCard(onRetry: retryUnavailableReflection)
                                    .padding(.top, 36)
                                    .id(RevealScrollTarget.reflection)
                                    .trackReflectionVisibility()
                                    .transition(.opacity)
                            } else if let reflection = viewModel.reflection {
                                ReflectionMarkdownPanel(
                                    title: reflection.title,
                                    markdown: reflection.reflection,
                                    showsStandaloneTitle: viewModel.isComplete
                                )
                                .padding(.top, 36)
                                .id(RevealScrollTarget.reflection)
                                .trackReflectionVisibility()
                                .trackReflectionEndVisibility()
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else if !viewModel.streamingReflectionMarkdown.isEmpty {
                                ReflectionMarkdownPanel(
                                    title: nil,
                                    markdown: viewModel.streamingReflectionMarkdown,
                                    showsStandaloneTitle: viewModel.isComplete
                                )
                                .opacity(0.92)
                                .padding(.top, 36)
                                .id(RevealScrollTarget.reflection)
                                .trackReflectionVisibility()
                                .transition(.opacity)
                            } else if !entitlements.isEntitledForGating {
                                // Phase-3 §3: where the reflection would
                                // bloom, the veil — the same card, misted,
                                // one tap from the paywall.
                                VeiledFeature(
                                    surface: "reflection",
                                    message: AnkyCopyRegistry.veilReflection,
                                    onTap: { isShowingPaywallSheet = true }
                                ) {
                                    ReflectionGhost()
                                }
                                .frame(height: 240)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 36)
                                .id(RevealScrollTarget.reflection)
                                .trackReflectionVisibility()
                                .transition(.opacity)
                            } else if inlineReflectionActive, viewModel.isAskingAnky {
                                // Phase-2 §7: the watercolor veil breathes
                                // while anky reads — same wait as the
                                // ceremony, never a spinner.
                                ZStack {
                                    WatercolorVeilView(
                                        message: AnkyLocalization.ui(AnkyCopyRegistry.reflectionWait),
                                        register: .pale
                                    )

                                    Image("anky-reading")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 190)
                                        .offset(y: -14)
                                        .shadow(color: Color.ankyGold.opacity(0.18), radius: 18, y: 8)
                                        .accessibilityHidden(true)
                                }
                                .frame(height: 240)
                                .frame(maxWidth: .infinity)
                                .background(Color.ankyPaper.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding(.top, 36)
                                .id(RevealScrollTarget.reflection)
                                .trackReflectionVisibility()
                                .transition(.opacity)
                            } else if inlineReflectionActive, let errorMessage = viewModel.errorMessage {
                                VStack(alignment: .leading, spacing: 18) {
                                    ReflectionErrorPanel(
                                        message: errorMessage
                                    )
                                    RetryReflectionButton(onRetry: retryUnavailableReflection)
                                    FounderContactLine()
                                }
                                .padding(.top, 36)
                                .id(RevealScrollTarget.reflection)
                                .trackReflectionVisibility()
                                .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, 138)
                    }
                    .onChange(of: reflectionScrollRequest) { _ in
                        scrollToReflection(with: scrollProxy, anchor: .top)
                    }
                    .onChange(of: viewModel.reflection?.id) { reflectionID in
                        guard reflectionID != nil else { return }
                        guard inlineReflectionActive else { return }
                        guard !didScrollToStreamingStart else { return }
                        scrollToReflection(with: scrollProxy, anchor: .top)
                    }
                    .onChange(of: viewModel.streamingReflectionMarkdown) { newValue in
                        guard !newValue.isEmpty, !didScrollToStreamingStart else { return }
                        didScrollToStreamingStart = true
                        scrollToReflection(with: scrollProxy, anchor: .top)
                    }
                    .onChange(of: viewModel.errorMessage) { errorMessage in
                        guard inlineReflectionActive, errorMessage != nil else { return }
                        scrollToReflection(with: scrollProxy, anchor: .top)
                    }
                    .onPreferenceChange(ReflectionVisibilityPreferenceKey.self) { isVisible in
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            isReflectionVisible = isVisible
                        }
                        if isVisible {
                            didSeeReflection = true
                        }
                    }
                    .onPreferenceChange(ReflectionEndVisibilityPreferenceKey.self) { isVisible in
                        guard isVisible else { return }
                        requestFirstReflectionReviewIfNeeded()
                    }
                    .onPreferenceChange(RevealScrollOffsetPreferenceKey.self) { offsetY in
                        updateNavigationVisibility(offsetY: offsetY)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                updateNavigationVisibility(translation: value.translation)
                            }
                    )
                    .coordinateSpace(name: RevealCoordinateSpace.scroll)
                }
            }

        }
        .toolbar(isNavigationBarHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(onBack != nil)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            // The back chevron lives on the same bar as the hour, copy, and
            // delete — one navbar, one height.
            if let onBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(RevealPalette.paper)
                            .frame(width: 34, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AnkyLocalization.ui("Back"))
                }
            }
            ToolbarItem(placement: .principal) {
                Text(viewModel.compactHeaderLine)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(RevealPalette.paper.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.middle)
                    .frame(maxWidth: 154)
                    .accessibilityLabel(viewModel.compactHeaderLine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 18) {
                    Image(systemName: didCopyWriting ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(didCopyWriting ? Color.ankySage : RevealPalette.paper)
                        .frame(width: 34, height: 38)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            copyWriting()
                        }
                        .onLongPressGesture(minimumDuration: 0.55) {
                            copyReflectionPrompt()
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(AnkyLocalization.ui(didCopyWriting ? "Writing copied" : "Copy writing"))
                        .accessibilityHint(AnkyLocalization.ui("Long press to copy the reflection prompt for your own AI tool."))

                    Button {
                        AnkyHaptics.warning()
                        confirmDelete = true
                    } label: {
                        if viewModel.isDeleting {
                            ProgressView()
                                .tint(RevealPalette.paper)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.ankyMadder.opacity(0.88))
                                .frame(width: 34, height: 38)
                                .contentShape(Rectangle())
                        }
                    }
                    .disabled(viewModel.isDeleting)
                    .accessibilityLabel(AnkyLocalization.ui("Delete writing session"))
                }
                .padding(.horizontal, 2)
            }
        }
        .alert(AnkyLocalization.ui("Delete writing session?"), isPresented: $confirmDelete) {
            Button(AnkyLocalization.ui("Delete"), role: .destructive) {
                AnkyHaptics.warning()
                viewModel.deleteSession()
            }
            Button(AnkyLocalization.ui("Cancel"), role: .cancel) {}
        } message: {
            Text(AnkyLocalization.ui("This permanently deletes this writing session. This cannot be undone."))
        }
        .sheet(isPresented: $isShowingPaywallSheet) {
            PaywallSheet(store: entitlements, origin: "reflection")
        }
        .onAppear {
            Task {
                await viewModel.prepareAfterFirstRender()
            }
            ankyCompanion.hideBubble()
            isNavigationBarHidden = false
            tabBarCTAController.setScrollHidden(false)
            if startsReflectionOnAppear, !didAutoStartReflection, viewModel.reflection == nil,
               entitlements.isEntitledForGating {
                didAutoStartReflection = true
                beginInlineReflection()
            }
            syncRevealBottomBar()
        }
        .onDisappear {
            ankyCompanion.hideBubble()
            tabBarCTAController.hide()
        }
        .onChange(of: revealBottomBarSnapshot) { _ in
            syncRevealBottomBar()
        }
        .onChange(of: viewModel.isDeleted) { isDeleted in
            guard isDeleted else {
                return
            }
            onDeleted()
            dismiss()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard !handlesBackSwipeExternally else {
                        return
                    }
                    let isHorizontalBackSwipe = value.translation.width > 80
                        && value.startLocation.x < 44
                        && abs(value.translation.height) < 60
                    if isHorizontalBackSwipe {
                        if let onBack {
                            onBack()
                        } else {
                            dismiss()
                        }
                    }
                }
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: shouldShowBottomAction)
    }

    /// Retry for a writing whose reflection never arrived (a stored
    /// provider-outage apology, or a fresh inline failure): clear the
    /// apology if one is persisted, then re-ask through the normal inline
    /// flow (feedback 2026-07-08).
    private func retryUnavailableReflection() {
        viewModel.clearFallbackReflection()
        beginInlineReflection()
    }

    private func beginInlineReflection() {
        // Phase-3: free sessions never ask the mirror — the veil card is
        // already standing where the reflection would appear.
        guard entitlements.isEntitledForGating else {
            requestReflectionScroll()
            return
        }
        inlineReflectionActive = true
        didScrollToStreamingStart = false
        requestReflectionScroll()
        ankyCompanion.hideBubble(returningTo: .thinking)
        Task {
            await viewModel.askAnky()
            if viewModel.reflection != nil {
                if !didScrollToStreamingStart {
                    requestReflectionScroll()
                }
                try? await Task.sleep(nanoseconds: 850_000_000)
                if !didSeeReflection && !isReflectionVisible {
                    onReflectionReady()
                }
            }
        }
    }

    private func requestReflectionScroll() {
        withAnimation(.easeInOut(duration: 0.45)) {
            reflectionScrollRequest += 1
        }
    }

    private func scrollToReflection(with proxy: ScrollViewProxy, anchor: UnitPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.58)) {
                proxy.scrollTo(RevealScrollTarget.reflection, anchor: anchor)
            }
        }
    }

    private func updateNavigationVisibility(offsetY: CGFloat) {
        guard allowsScrollChromeHiding else {
            setNavigationChromeHidden(false)
            lastScrollOffsetY = offsetY
            hasObservedScrollOffset = true
            return
        }

        guard hasObservedScrollOffset else {
            hasObservedScrollOffset = true
            lastScrollOffsetY = offsetY
            return
        }

        let delta = offsetY - lastScrollOffsetY
        lastScrollOffsetY = offsetY

        guard abs(delta) > 4 else {
            return
        }

        if delta < 0, offsetY < -36, !isNavigationBarHidden {
            setNavigationChromeHidden(true)
        } else if delta > 0, isNavigationBarHidden {
            setNavigationChromeHidden(false)
        }
    }

    private func updateNavigationVisibility(translation: CGSize) {
        guard allowsScrollChromeHiding else {
            setNavigationChromeHidden(false)
            return
        }

        guard abs(translation.height) > abs(translation.width), abs(translation.height) > 10 else {
            return
        }

        if translation.height < 0 {
            setNavigationChromeHidden(true)
        } else {
            setNavigationChromeHidden(false)
        }
    }

    private func setNavigationChromeHidden(_ isHidden: Bool) {
        let resolvedIsHidden = allowsScrollChromeHiding ? isHidden : false
        guard isNavigationBarHidden != resolvedIsHidden || tabBarCTAController.isScrollHidden != resolvedIsHidden else {
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            isNavigationBarHidden = resolvedIsHidden
            tabBarCTAController.setScrollHidden(resolvedIsHidden)
        }
    }

    private var allowsScrollChromeHiding: Bool {
        viewModel.isComplete
    }

    private func copyWriting() {
        viewModel.copy(.writing)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            didCopyWriting = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                didCopyWriting = false
            }
        }
    }

    private func copyReflectionPrompt() {
        guard viewModel.isComplete else {
            return
        }

        viewModel.copy(.reflectionPrompt)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            didCopyWriting = true
        }
        ankyCompanion.witness(
            mood: .guiding,
            sequence: .waveFront,
            bubble: AnkyBubble(
                text: AnkyLocalization.ui("The reflection prompt is on your clipboard. Take it to your favorite AI tool and get a reflection from it."),
                close: {
                    ankyCompanion.hideBubble()
                }
            )
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                didCopyWriting = false
            }
        }
    }

    private var bottomActionTitle: String {
        if viewModel.isAskingAnky {
            return AnkyLocalization.ui("Receiving reflection...")
        }
        if viewModel.reflection != nil {
            return AnkyLocalization.ui("READ REFLECTION")
        }
        if !entitlements.isEntitledForGating {
            return AnkyLocalization.ui("SEE WHAT ANKY SAW")
        }
        if viewModel.isComplete {
            return AnkyLocalization.ui("REFLECT THIS ANKY")
        }
        return AnkyLocalization.ui("ASK ANKY FOR REFLECTION")
    }

    private var revealBottomBarSnapshot: RevealBottomBarSnapshot {
        RevealBottomBarSnapshot(
            title: bottomActionTitle,
            isLoading: viewModel.isAskingAnky,
            isEnabled: bottomActionIsEnabled,
            shouldShow: shouldShowBottomAction,
            streamTick: viewModel.reflectionStreamTick
        )
    }

    private var shouldShowBottomAction: Bool {
        if viewModel.reflection != nil {
            return !isReflectionVisible
        }
        return true
    }

    private var bottomActionIsEnabled: Bool {
        if viewModel.isAskingAnky {
            return false
        }
        if viewModel.reflection != nil {
            return true
        }
        return viewModel.isComplete ? viewModel.canSubmitReflectionRequest : true
    }

    private func syncRevealBottomBar() {
        guard shouldShowBottomAction else {
            tabBarCTAController.hide(resetScrollHidden: false)
            return
        }

        tabBarCTAController.show(
            title: bottomActionTitle,
            isLoading: viewModel.isAskingAnky,
            isEnabled: bottomActionIsEnabled,
            accentColor: viewModel.ctaAccentColor,
            streamTick: viewModel.reflectionStreamTick,
            action: bottomAction
        )
    }

    private func bottomAction() {
        if viewModel.reflection != nil {
            AnkyHaptics.light()
            requestReflectionScroll()
        } else if !entitlements.isEntitledForGating {
            AnkyHaptics.light()
            AnkyFunnel.report(AnkyFunnel.veilTapped, origin: "reflection")
            isShowingPaywallSheet = true
        } else {
            AnkyHaptics.light()
            beginInlineReflection()
        }
    }

    private func requestFirstReflectionReviewIfNeeded() {
        guard !didRequestFirstReflectionReview,
              viewModel.shouldRequestReviewAfterReadingFirstReflection else {
            return
        }

        didRequestFirstReflectionReview = true
        viewModel.markFirstReflectionReviewRequested()
        requestReview()
    }

}

private struct RevealBottomBarSnapshot: Equatable {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let shouldShow: Bool
    let streamTick: Int
}

private struct WriteBeforeScrollSealedUnlockButton: View {
    let grant: UnlockGrant
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "lock.open")
                    .font(.system(size: 15, weight: .semibold))

                Text(AnkyLocalization.ui(title))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            .foregroundStyle(RevealPalette.paper.opacity(0.92))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .fill(RevealPalette.gold.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .stroke(RevealPalette.gold.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AnkyLocalization.ui(title))
    }

    private var title: String {
        switch grant.tier {
        case .quick:
            return "unlock apps · 15 min"
        case .daily:
            return "unlock apps · rest of day"
        }
    }
}

private struct RevealHeader: View {
    let metadata: String
    let isDeleting: Bool
    let dismiss: DismissAction
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RevealHeaderGlassButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                tint: RevealPalette.paper,
                stroke: RevealPalette.gold.opacity(0.24),
                action: {
                    dismiss()
                }
            )

            Text(metadata)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(RevealPalette.paper.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            RevealHeaderGlassButton(
                systemName: "trash",
                accessibilityLabel: "Delete writing session",
                tint: Color.ankyMadder.opacity(0.88),
                stroke: Color.ankyMadder.opacity(0.22),
                isLoading: isDeleting,
                isEnabled: !isDeleting,
                action: delete
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(RevealPalette.ink.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.ankyInk.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}

private struct RevealHeaderGlassButton: View {
    let systemName: String
    let accessibilityLabel: String
    let tint: Color
    let stroke: Color
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    private let size: CGFloat = 40

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                label
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(tint)
            .frame(width: 50, height: 50)
            .disabled(!isEnabled)
            .accessibilityLabel(accessibilityLabel)
        } else {
            Button(action: action) {
                label
                    .background(Color.ankyPaperDeep.opacity(0.60), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private var label: some View {
        if #available(iOS 26.0, *) {
            if isLoading {
                ProgressView()
                    .tint(RevealPalette.paper)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: systemName == "trash" ? 17 : 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
        } else {
            if isLoading {
                ProgressView()
                    .tint(RevealPalette.paper)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: systemName == "trash" ? 15 : 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .contentShape(Circle())
            }
        }
    }
}

private enum RevealScrollTarget {
    case writing
    case reflection
}

private enum RevealCoordinateSpace {
    static let scroll = "revealScroll"
}

private struct RevealScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ReflectionVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct ReflectionEndVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private extension View {
    func trackRevealScrollOffset() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RevealScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(RevealCoordinateSpace.scroll)).minY
                )
            }
        )
    }

    func trackReflectionVisibility() -> some View {
        background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                let screenHeight = UIScreen.main.bounds.height
                let isVisible = frame.minY < screenHeight - 138 && frame.maxY > 128

                Color.clear.preference(key: ReflectionVisibilityPreferenceKey.self, value: isVisible)
            }
        )
    }

    func trackReflectionEndVisibility() -> some View {
        background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                let screenHeight = UIScreen.main.bounds.height
                let bottomIsVisible = frame.maxY > 128 && frame.maxY < screenHeight - 110

                Color.clear.preference(key: ReflectionEndVisibilityPreferenceKey.self, value: bottomIsVisible)
            }
        )
    }
}

struct RevealBackgroundTexture: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Ellipse()
                    .fill(RevealPalette.violet.opacity(0.055))
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

private struct PrivacyDivider: View {
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(RevealPalette.gold.opacity(0.22))
                    .frame(height: 1)

                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(RevealPalette.goldSoft)
                    .frame(width: 28, height: 28)
                    .background(Color.ankyPaperDeep.opacity(0.55), in: Circle())

                Rectangle()
                    .fill(RevealPalette.gold.opacity(0.22))
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AnkyLocalization.ui("Toggle privacy message"))
    }
}

private struct WritingSessionStatsHeader: View {
    let wordCount: Int
    let duration: String
    let backspaceCount: Int
    let enterCount: Int

    var body: some View {
        HStack(spacing: 12) {
            WritingSessionStat(symbolName: "text.word.spacing", value: "\(wordCount)")
            WritingSessionStat(symbolName: "timer", value: duration)
            WritingSessionStat(symbolName: "delete.backward", value: "\(backspaceCount)")
            WritingSessionStat(symbolName: "return", value: "\(enterCount)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AnkyLocalization.ui("%d words, %@, %d backspaces, %d enters", wordCount, duration, backspaceCount, enterCount))
    }
}

private struct WritingSessionStat: View {
    let symbolName: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 13, height: 13)
                .symbolRenderingMode(.hierarchical)

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(RevealPalette.paper.opacity(0.44))
    }
}

private struct SelectableWritingText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.tintColor = UIColor(RevealPalette.gold)
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        textView.backgroundColor = .clear
        if textView.bounds.width > 0 {
            textView.textContainer.size = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        }
        textView.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body).lazureSerif,
                .foregroundColor: UIColor(Color.ankyInk),
                .paragraphStyle: paragraph
            ]
        )
        textView.layer.cornerRadius = 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 56
        uiView.bounds.size.width = width
        uiView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

private struct ReflectionMarkdownPanel: View {
    let title: String?
    let markdown: String
    var separatesLeadingTitle = true
    /// Short writings get short reflections — a brute-forced title over one
    /// of those is the first line said twice. Below the full ritual the
    /// reflection renders as it came, with no standalone heading.
    var showsStandaloneTitle = true

    private var displayTitle: String {
        guard separatesLeadingTitle, showsStandaloneTitle else {
            return ""
        }
        guard let resolved = (title ?? markdown.firstMarkdownHeadingText)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !resolved.isEmpty else {
            return ""
        }
        // A title that only repeats the body's opening words reads as a
        // stutter — show the body alone in that case.
        if markdown.firstMarkdownHeadingText == nil,
           Self.normalizedOpening(markdown).hasPrefix(Self.normalizedOpening(resolved)) {
            return ""
        }
        return resolved
    }

    private static func normalizedOpening(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var displayBody: String {
        let body = showsStandaloneTitle
            ? (displayTitle.isEmpty
                ? markdown
                : markdown.removingLeadingMarkdownHeading(matching: displayTitle))
            : Self.strippingEchoedLeadingHeading(from: markdown)
        return body.softWrappedMarkdownForDisplay()
    }

    /// A leading `# heading` the body immediately repeats is the brute-forced
    /// title again — it goes. A genuine heading with its own words stays.
    private static func strippingEchoedLeadingHeading(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstLine = lines.first, firstLine.hasPrefix("#") else {
            return trimmed
        }
        let headingText = firstLine
            .drop(while: { $0 == "#" })
            .trimmingCharacters(in: .whitespaces)
        let body = lines.dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headingText.isEmpty, !body.isEmpty,
              normalizedOpening(body).hasPrefix(normalizedOpening(headingText)) else {
            return trimmed
        }
        return body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !displayTitle.isEmpty {
                Text(displayTitle)
                    .font(.system(size: 23, weight: .bold, design: .serif))
                    .foregroundStyle(RevealPalette.markdownHeading)
                    .tracking(0)
                    .textSelection(.enabled)
            }

            SelectableReflectionText(text: displayBody)
        }
    }
}

extension String {
    func softWrappedMarkdownForDisplay() -> String {
        let sourceLines = replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var output: [String] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            output.append(paragraph.joined(separator: " "))
            paragraph.removeAll()
        }

        for line in sourceLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                if output.last != "" {
                    output.append("")
                }
                continue
            }

            if Self.isDisplayMarkdownBlockLine(trimmed) {
                flushParagraph()
                output.append(trimmed)
            } else {
                paragraph.append(trimmed)
            }
        }

        flushParagraph()
        while output.last == "" {
            output.removeLast()
        }
        return output.joined(separator: "\n")
    }

    private static func isDisplayMarkdownBlockLine(_ line: String) -> Bool {
        if markdownHeadingText(from: line) != nil {
            return true
        }
        if line.hasPrefix(">") || line.hasPrefix("- ") || line.hasPrefix("* ") {
            return true
        }
        if line == "---" || line == "***" || line == "___" || line == "\u{2014}" {
            return true
        }
        if let dotIndex = line.firstIndex(of: ".") {
            let numberText = line[..<dotIndex]
            let restStart = line.index(after: dotIndex)
            if !numberText.isEmpty,
               numberText.allSatisfy(\.isNumber),
               restStart < line.endIndex,
               line[restStart] == " " {
                return true
            }
        }
        return false
    }

    var firstMarkdownHeadingText: String? {
        let lines = replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let heading = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }
        return Self.markdownHeadingText(from: heading)
    }

    func removingLeadingMarkdownHeading(matching title: String) -> String {
        let lines = replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let headingIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              let heading = Self.markdownHeadingText(from: lines[headingIndex]),
              Self.normalizedHeading(heading) == Self.normalizedHeading(title) else {
            return self
        }

        var bodyStart = headingIndex + 1
        while bodyStart < lines.count, lines[bodyStart].trimmingCharacters(in: .whitespaces).isEmpty {
            bodyStart += 1
        }

        return lines.dropFirst(bodyStart).joined(separator: "\n")
    }

    private static func markdownHeadingText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["### ", "## ", "# "] {
            if trimmed.hasPrefix(marker) {
                return String(trimmed.dropFirst(marker.count))
            }
        }
        return nil
    }

    private static func normalizedHeading(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct ReflectionErrorPanel: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AnkyLocalization.ui("the mirror did not open"))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(RevealPalette.markdownHeading)
                .tracking(0)

            Text(AnkyLocalization.ui(message))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.ankyMadder.opacity(0.82))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}

/// The big, unmissable retry: the reflection request itself, again.
private struct RetryReflectionButton: View {
    let onRetry: () -> Void

    var body: some View {
        AnkyPrimaryButton("ask for the reflection again", action: onRetry)
    }
}

/// Stands where a stored provider-outage apology used to masquerade as a
/// reflection: name what happened, then hand over the retry
/// (feedback 2026-07-08).
private struct FallbackReflectionRetryCard: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(AnkyLocalization.ui("the mirror did not open"))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(RevealPalette.markdownHeading)

            Text(AnkyLocalization.ui("This writing never received its reflection. Your words are safe on this device."))
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(RevealPalette.paper.opacity(0.78))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            RetryReflectionButton(onRetry: onRetry)

            FounderContactLine()
        }
        .padding(.vertical, 8)
    }
}

private enum ReflectionTextStyle {
    case standard
    case readingPage

    var bodyFont: UIFont {
        UIFont.preferredFont(forTextStyle: .body).lazureSerif
    }

    var headingFont: UIFont {
        switch self {
        case .standard:
            return UIFont.preferredFont(forTextStyle: .title3).lazureSerif
        case .readingPage:
            return UIFont.preferredFont(forTextStyle: .title2).lazureSerif
        }
    }

    var codeFont: UIFont {
        UIFont.preferredFont(forTextStyle: .callout)
    }

    var lineSpacing: CGFloat {
        switch self {
        case .standard: 5
        case .readingPage: 7
        }
    }

    var paragraphSpacing: CGFloat {
        switch self {
        case .standard: 4
        case .readingPage: 8
        }
    }
}

private struct SelectableReflectionText: UIViewRepresentable {
    let text: String
    var style: ReflectionTextStyle = .standard

    init(
        text: String,
        style: ReflectionTextStyle = .standard
    ) {
        self.text = text
        self.style = style
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.tintColor = UIColor(RevealPalette.gold)
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.backgroundColor = .clear
        if textView.bounds.width > 0 {
            textView.textContainer.size = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        }
        textView.attributedText = attributedReflection()
        textView.layer.cornerRadius = 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 56
        uiView.bounds.size.width = width
        uiView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    private var lines: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private func attributedReflection() -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            result.append(attributedLine(line))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    private func attributedLine(_ line: String) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing
        paragraph.paragraphSpacing = trimmed.isEmpty ? style.paragraphSpacing + 5 : style.paragraphSpacing

        if isHorizontalRule(trimmed) {
            paragraph.lineSpacing = 0
            paragraph.paragraphSpacingBefore = 12
            paragraph.paragraphSpacing = 12
            return NSAttributedString(string: "", attributes: [.paragraphStyle: paragraph])
        }

        if trimmed.isEmpty {
            return NSAttributedString(string: "", attributes: [.paragraphStyle: paragraph])
        }

        if let heading = headingText(from: trimmed) {
            return NSAttributedString(
                string: heading,
                attributes: [
                    .font: style.headingFont,
                    .foregroundColor: UIColor(RevealPalette.markdownHeading),
                    .paragraphStyle: paragraph
                ]
            )
        }

        if let quote = quoteText(from: trimmed) {
            let attributed = NSMutableAttributedString(string: quote, attributes: baseAttributes(paragraph: paragraph, italic: true))
            attributed.addAttribute(
                .foregroundColor,
                value: UIColor(Color.ankyInkSoft.opacity(0.80)),
                range: NSRange(location: 0, length: attributed.length)
            )
            return attributed
        }

        if let bullet = bulletText(from: trimmed) {
            return inlineAttributedString("• \(bullet)", paragraph: paragraph)
        }

        if let numbered = numberedText(from: trimmed) {
            return inlineAttributedString("\(numbered.marker) \(numbered.text)", paragraph: paragraph)
        }

        return inlineAttributedString(trimmed, paragraph: paragraph)
    }

    private func headingText(from line: String) -> String? {
        for marker in ["### ", "## ", "# "] {
            if line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count))
            }
        }
        return nil
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        if line == "---" || line == "***" || line == "___" || line == "\u{2014}" {
            return true
        }
        guard line.count <= 5 else {
            return false
        }
        return !line.isEmpty && line.allSatisfy { character in
            character == "-" || character == "*" || character == "_" || character == "\u{2014}"
        }
    }

    private func bulletText(from line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private func quoteText(from line: String) -> String? {
        guard line.hasPrefix(">") else {
            return nil
        }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private func numberedText(from line: String) -> (marker: String, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }
        let numberText = line[..<dotIndex]
        let restStart = line.index(after: dotIndex)
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              restStart < line.endIndex,
              line[restStart] == " " else {
            return nil
        }
        return ("\(numberText).", String(line[line.index(after: restStart)...]))
    }

    private func inlineAttributedString(_ text: String, paragraph: NSMutableParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = text.startIndex

        while index < text.endIndex {
            if text[index...].hasPrefix("**"),
               let end = text[text.index(index, offsetBy: 2)...].range(of: "**") {
                let contentStart = text.index(index, offsetBy: 2)
                append(String(text[contentStart..<end.lowerBound]), to: result, inlineStyle: .strong, paragraph: paragraph)
                index = end.upperBound
            } else if text[index] == "*",
                      let end = text[text.index(after: index)...].firstIndex(of: "*") {
                let contentStart = text.index(after: index)
                append(String(text[contentStart..<end]), to: result, inlineStyle: .emphasis, paragraph: paragraph)
                index = text.index(after: end)
            } else if text[index] == "`",
                      let end = text[text.index(after: index)...].firstIndex(of: "`") {
                let contentStart = text.index(after: index)
                append(String(text[contentStart..<end]), to: result, inlineStyle: .code, paragraph: paragraph)
                index = text.index(after: end)
            } else if text[index] == "*" || text[index] == "`" {
                append(String(text[index]), to: result, inlineStyle: .normal, paragraph: paragraph)
                index = text.index(after: index)
            } else {
                let nextStrong = text[index...].range(of: "**")?.lowerBound
                let nextEmphasis = text[index...].firstIndex(of: "*")
                let nextCode = text[index...].firstIndex(of: "`")
                let next = [nextStrong, nextEmphasis, nextCode].compactMap { $0 }.min() ?? text.endIndex
                append(String(text[index..<next]), to: result, inlineStyle: .normal, paragraph: paragraph)
                index = next
            }
        }

        return result
    }

    private func baseAttributes(paragraph: NSMutableParagraphStyle, italic: Bool = false) -> [NSAttributedString.Key: Any] {
        [
            .font: italic
                ? UIFont.italicSystemFont(ofSize: style.bodyFont.pointSize)
                : style.bodyFont,
            .foregroundColor: UIColor(Color.ankyInkSoft),
            .paragraphStyle: paragraph
        ]
    }

    private func append(
        _ string: String,
        to result: NSMutableAttributedString,
        inlineStyle: InlineStyle,
        paragraph: NSMutableParagraphStyle
    ) {
        var attributes = baseAttributes(paragraph: paragraph)
        switch inlineStyle {
        case .normal:
            break
        case .strong:
            attributes[.foregroundColor] = UIColor(Color.ankyInk)
            attributes[.font] = UIFont.systemFont(ofSize: style.bodyFont.pointSize, weight: .semibold).lazureSerif
        case .emphasis:
            attributes[.font] = UIFont.italicSystemFont(ofSize: style.bodyFont.pointSize)
        case .code:
            attributes[.foregroundColor] = UIColor(Color.ankyInk.opacity(0.82))
            attributes[.font] = UIFont.monospacedSystemFont(ofSize: style.codeFont.pointSize, weight: .regular)
        }
        result.append(NSAttributedString(string: string, attributes: attributes))
    }

    private enum InlineStyle {
        case normal
        case strong
        case emphasis
        case code
    }
}

/// The reading room is set in serif — New York via the serif descriptor,
/// falling back to the system face when the design is unavailable.
private extension UIFont {
    var lazureSerif: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.serif) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

enum RevealPalette {
    // Lazure remap: the reading room is paper, the words are ink.
    // `ink` names the *surface* role (was near-black, now warm paper);
    // `paper` names the *text* role (was cream, now violet ink).
    static let appBackground = Color.ankyPaper
    static let ink = Color.ankyPaper
    static let paper = Color.ankyInk
    static let gold = Color.ankyGold
    static let markdownHeading = Color.ankyViolet
    static let violet = Color.ankyViolet
    static let goldSoft = gold.opacity(0.82)
    static let buttonFill = Color.ankyGoldLight.opacity(0.62)
}
