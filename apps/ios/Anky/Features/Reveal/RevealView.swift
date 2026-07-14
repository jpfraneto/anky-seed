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
    /// P1: the live text selection inside the rendered reflection, if any.
    /// Empty → Share falls back to the reflection's opening passage.
    @State private var selectedReflectionText = ""
    @State private var shareQuote: String?
    /// P2: full-screen teleprompter recording, opened once a reflection exists.
    @State private var isShowingRecording = false
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
                                    showsStandaloneTitle: viewModel.isComplete,
                                    onSelectionChange: { selectedReflectionText = $0 }
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
                                    showsStandaloneTitle: viewModel.isComplete,
                                    isStreaming: true
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

                    if viewModel.reflection != nil {
                        Button {
                            AnkyHaptics.light()
                            isShowingRecording = true
                        } label: {
                            Image(systemName: "video")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(RevealPalette.paper)
                                .frame(width: 34, height: 38)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(AnkyLocalization.ui("Record yourself reading this"))

                        Button {
                            shareReflectionCard()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(RevealPalette.paper)
                                .frame(width: 34, height: 38)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(AnkyLocalization.ui("Share as a card"))
                        .accessibilityHint(AnkyLocalization.ui("Select a passage first, or share the opening."))
                    }

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
        .sheet(isPresented: Binding(
            get: { shareQuote != nil },
            set: { if !$0 { shareQuote = nil } }
        )) {
            if let shareQuote {
                ShareCardPreviewView(quote: shareQuote)
            }
        }
        .fullScreenCover(isPresented: $isShowingRecording) {
            if let reflection = viewModel.reflection {
                AnkyRecordingView(
                    reflectionText: ReflectionShareQuote.plainText(reflection.reflection),
                    onClose: { isShowingRecording = false }
                )
            }
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

    /// P1: render the branded "anky method" cards from the reader's selection
    /// (or the reflection's opening if nothing is selected) and hand them to the
    /// native share sheet. Copy is untouched — this is a separate affordance.
    private func shareReflectionCard() {
        guard let reflection = viewModel.reflection else { return }
        AnkyHaptics.light()
        shareQuote = ReflectionShareQuote.make(
            selection: selectedReflectionText,
            fullReflection: reflection.reflection
        )
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
    /// While the reflection is still streaming we render the full accumulated
    /// buffer inline through the incremental text view — no title pull-out, so
    /// the structure never churns as characters arrive (P0-1).
    var isStreaming = false
    /// Reports the reader's live text selection up so Share can quote it (P1).
    var onSelectionChange: ((String) -> Void)?

    private var displayTitle: String {
        guard !isStreaming, separatesLeadingTitle, showsStandaloneTitle else {
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
        if isStreaming {
            return markdown.softWrappedMarkdownForDisplay()
        }
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

            if isStreaming {
                ReflectionStreamingText(text: displayBody)
            } else {
                SelectableReflectionText(text: displayBody, onSelectionChange: onSelectionChange)
            }
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

/// Shared configuration for the reflection text views so the completed and
/// streaming variants render into identically-configured UITextViews.
private enum ReflectionTextViewFactory {
    static func make() -> UITextView {
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
        textView.layer.cornerRadius = 0
        return textView
    }

    static func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 56
        uiView.bounds.size.width = width
        uiView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

/// The finished reflection: static text, rendered in full on each update.
/// Copy yields plain text (the attributed string carries no markdown markers),
/// and the live selection is reported up so Share can quote it (P1).
private struct SelectableReflectionText: UIViewRepresentable {
    let text: String
    var style: ReflectionTextStyle = .standard
    var onSelectionChange: ((String) -> Void)?

    init(
        text: String,
        style: ReflectionTextStyle = .standard,
        onSelectionChange: ((String) -> Void)? = nil
    ) {
        self.text = text
        self.style = style
        self.onSelectionChange = onSelectionChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = ReflectionTextViewFactory.make()
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onSelectionChange = onSelectionChange
        textView.backgroundColor = .clear
        if textView.bounds.width > 0 {
            textView.textContainer.size = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        }
        textView.attributedText = ReflectionAttributedRenderer(text: text, style: style).attributed()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        ReflectionTextViewFactory.sizeThatFits(proposal, uiView: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSelectionChange: ((String) -> Void)?

        init(onSelectionChange: ((String) -> Void)?) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let range = textView.selectedTextRange,
                  let selected = textView.text(in: range), !selected.isEmpty else {
                onSelectionChange?("")
                return
            }
            onSelectionChange?(selected)
        }
    }
}

/// The live-streaming reflection.
///
/// P0-1: the reflection arrives as paragraph-sized SSE deltas that the view
/// model appends into a single accumulated buffer. Re-setting the full
/// `attributedText` on every delta re-lays-out the entire (growing) document
/// and reads as a flash — each paragraph appearing to be removed and replaced.
///
/// Here we still render markdown from the *full accumulated buffer* every
/// update — so formatting stays correct and identity is stable — but we splice
/// only the changed tail into the text view's `textStorage`. The already
/// laid-out prefix is never rebuilt: no flash, no O(n) relayout per chunk, no
/// scroll jump. A markdown token that only closes later (`**bo` + `ld**`)
/// renders as plain text until it closes; when it does, the earlier range
/// restyles and we fall back to a single full re-render for that update. Text
/// is never dropped and the parser never crashes on a partial token.
private struct ReflectionStreamingText: UIViewRepresentable {
    let text: String
    var style: ReflectionTextStyle = .standard

    final class Coordinator {
        /// The plain-string contents currently laid out in the text view,
        /// used to detect the pure-append fast path.
        var renderedString: String = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        ReflectionTextViewFactory.make()
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.backgroundColor = .clear
        if textView.bounds.width > 0 {
            textView.textContainer.size = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        }

        let attributed = ReflectionAttributedRenderer(text: text, style: style).attributed()
        let newString = attributed.string as NSString
        let previous = context.coordinator.renderedString as NSString

        if newString.isEqual(to: context.coordinator.renderedString) {
            return
        }

        let storage = textView.textStorage
        // Longest common prefix in UTF-16 units.
        let ceiling = min(newString.length, previous.length)
        var prefix = 0
        while prefix < ceiling,
              newString.character(at: prefix) == previous.character(at: prefix) {
            prefix += 1
        }

        storage.beginEditing()
        if previous.length > 0, prefix == previous.length {
            // Pure append: keep the laid-out prefix, splice only the new tail.
            let tailRange = NSRange(location: prefix, length: newString.length - prefix)
            storage.append(attributed.attributedSubstring(from: tailRange))
        } else {
            // First render, or a token closing restyled an earlier range.
            storage.setAttributedString(attributed)
        }
        storage.endEditing()

        context.coordinator.renderedString = attributed.string
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        ReflectionTextViewFactory.sizeThatFits(proposal, uiView: uiView)
    }
}

/// Builds the styled reflection body from Anky's lightweight markdown. Shared
/// by the completed view and the live streaming view so both render identically.
private struct ReflectionAttributedRenderer {
    let text: String
    var style: ReflectionTextStyle = .standard

    private var lines: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    func attributed() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = self.lines
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
            } else if text[index...].hasPrefix("**") {
                // Unclosed bold marker mid-stream (`**bo` before `ld**` lands):
                // show the marker literally until it closes, never drop it.
                append("**", to: result, inlineStyle: .normal, paragraph: paragraph)
                index = text.index(index, offsetBy: 2)
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

// MARK: - P1: branded share cards ("the anky method")

/// The output shapes. 4:5 is the default feed card; 9:16 is the story card.
private enum ShareCardFormat: CaseIterable, Hashable {
    case ratio4x5
    case ratio9x16

    /// Logical size in points; rendered at scale 3 → 1080×1350 and 1080×1920.
    var logicalSize: CGSize {
        switch self {
        case .ratio4x5:  return CGSize(width: 360, height: 450)
        case .ratio9x16: return CGSize(width: 360, height: 640)
        }
    }

    /// Long quotes need the quieter ground: a 4:5 whose quote runs past ~380
    /// characters uses the Minimal base instead. 9:16 always uses its own base.
    static let minimalThreshold = 380

    func baseAssetName(quoteLength: Int) -> String {
        switch self {
        case .ratio9x16:
            return "ShareCardBase_9x16"
        case .ratio4x5:
            return quoteLength > Self.minimalThreshold ? "ShareCardBase_Minimal" : "ShareCardBase_4x5"
        }
    }
}

/// Chooses what the card quotes: the reader's live selection if there is one,
/// otherwise the reflection's opening passage — always plain text, markdown
/// stripped, so the composited card stays clean whatever the source markup.
enum ReflectionShareQuote {
    /// A selection may run long (up to `selectionLimit`) so the Minimal-base
    /// rule can engage; with no selection we quote the opening `openingLimit`.
    static func make(
        selection: String,
        fullReflection: String,
        selectionLimit: Int = 600,
        openingLimit: Int = 280
    ) -> String {
        let selected = plainText(selection)
        if !selected.isEmpty {
            return clamp(selected, to: selectionLimit)
        }
        return clamp(plainText(fullReflection), to: openingLimit)
    }

    /// Strips lightweight markdown so a quote reads as prose, never as markup.
    static func plainText(_ text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                // Leading block markers: heading hashes, quote carets.
                while let first = trimmed.first, first == "#" || first == ">" {
                    trimmed.removeFirst()
                    trimmed = trimmed.trimmingCharacters(in: .whitespaces)
                }
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    trimmed.removeFirst(2)
                }
                return trimmed
            }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }

        var joined = lines.joined(separator: " ")
        for marker in ["**", "`", "*", "_"] {
            joined = joined.replacingOccurrences(of: marker, with: "")
        }
        while joined.contains("  ") {
            joined = joined.replacingOccurrences(of: "  ", with: " ")
        }
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keeps the quote at/under `limit` characters, preferring to end on a
    /// sentence boundary, then a word boundary; adds an ellipsis if it cut mid.
    private static func clamp(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }

        let capped = String(text.prefix(limit))
        let sentenceEnders: Set<Character> = [".", "!", "?", "\u{2026}"]
        if let lastSentence = capped.lastIndex(where: { sentenceEnders.contains($0) }),
           capped.distance(from: capped.startIndex, to: lastSentence) >= limit / 2 {
            let end = capped.index(after: lastSentence)
            return String(capped[..<end]).trimmingCharacters(in: .whitespaces)
        }
        if let lastSpace = capped.lastIndex(of: " ") {
            return String(capped[..<lastSpace]).trimmingCharacters(in: .whitespaces) + "\u{2026}"
        }
        return capped + "\u{2026}"
    }
}

/// One share card — a lazure base with the quote composited in Fraunces (never
/// baked into the asset, so any quote length stays crisp), "— Anky", and the
/// "the anky method" wordmark. The quote sits in each base's calm center field,
/// clear of the violet borders (4:5) or the bottom fifth (9:16). It auto-scales
/// to fit that field down to a ~17pt floor, then truncates with an ellipsis.
private struct ReflectionShareCard: View {
    let format: ShareCardFormat
    let quote: String

    private var size: CGSize { format.logicalSize }

    /// Deep violet-umber ink (#3D2E4F) — never pure black, per the lazure rule.
    private let quoteInk = Color(red: 0.239, green: 0.180, blue: 0.310)

    /// Starting quote size; steps down with length before auto-scaling engages.
    private var startFontSize: CGFloat {
        switch quote.count {
        case ..<90:   return 30
        case ..<170:  return 26
        case ..<260:  return 22
        default:      return 19
        }
    }

    /// The floor: below this the quote truncates rather than shrinking further.
    /// 17pt at the logical (÷3) canvas is ~17pt "equivalent at export."
    private let floorFontSize: CGFloat = 17

    private struct Placement {
        let quoteRect: CGRect
        let footerCenter: CGPoint
        let attributionInFooter: Bool
    }

    private var placement: Placement {
        let w = size.width, h = size.height
        switch format {
        case .ratio9x16:
            // Quote in the upper cream field, clear of the bottom fifth; the
            // attribution and wordmark live down there, above the gold thread.
            return Placement(
                quoteRect: CGRect(x: w * 0.12, y: h * 0.15, width: w * 0.76, height: h * 0.50),
                footerCenter: CGPoint(x: w / 2, y: h * 0.88),
                attributionInFooter: true
            )
        case .ratio4x5:
            // Centered field, clear of the violet corners and the right thread.
            return Placement(
                quoteRect: CGRect(x: w * 0.16, y: h * 0.14, width: w * 0.68, height: h * 0.56),
                footerCenter: CGPoint(x: w / 2, y: h * 0.925),
                attributionInFooter: false
            )
        }
    }

    var body: some View {
        let place = placement
        ZStack {
            base

            Group {
                if place.attributionInFooter {
                    quoteText(maxHeight: place.quoteRect.height)
                } else {
                    VStack(spacing: 14) {
                        quoteText(maxHeight: place.quoteRect.height - 42)
                        attribution
                    }
                }
            }
            .frame(width: place.quoteRect.width, height: place.quoteRect.height)
            .position(x: place.quoteRect.midX, y: place.quoteRect.midY)

            Group {
                if place.attributionInFooter {
                    VStack(spacing: 12) {
                        attribution
                        wordmark
                    }
                } else {
                    wordmark
                }
            }
            .position(x: place.footerCenter.x, y: place.footerCenter.y)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func quoteText(maxHeight: CGFloat) -> some View {
        let lineHeight = floorFontSize * 1.34
        let maxLines = max(1, Int(maxHeight / lineHeight))
        return Text("\u{201C}\(quote)\u{201D}")
            .font(.fraunces(startFontSize, weight: .regular))
            .foregroundStyle(quoteInk)
            .lineSpacing(startFontSize * 0.24)
            .multilineTextAlignment(.center)
            .lineLimit(maxLines)
            .minimumScaleFactor(floorFontSize / startFontSize)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var base: some View {
        if let image = UIImage(named: format.baseAssetName(quoteLength: quote.count)) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Lazure placeholder until the base assets land.
            LinearGradient(
                colors: [
                    Color.ankyViolet.opacity(0.14),
                    Color.ankyPaper,
                    Color.ankyGoldLight.opacity(0.34)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var attribution: some View {
        Text("— Anky")
            .font(.fraunces(15, weight: .semibold, italic: true))
            .foregroundStyle(Color.ankyGold)
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            AnkySunGlyph(size: 15, color: Color.ankyGold)
            Text("the anky method")
                .font(.fraunces(13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.ankyGold)
        }
    }
}

/// Rasterizes one card at export resolution, composited in-app so text is never
/// baked into an asset. Main-actor because `ImageRenderer` is.
private enum ReflectionShareCardRenderer {
    @MainActor
    static func image(for format: ShareCardFormat, quote: String) -> UIImage? {
        let renderer = ImageRenderer(content: ReflectionShareCard(format: format, quote: quote))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(format.logicalSize)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

private struct ShareCardImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The single Share entry point opens this preview. Ratio choice (4:5 default /
/// 9:16) happens here on the card, not in the system share sheet; the Share
/// button exports the selected ratio only.
private struct ShareCardPreviewView: View {
    let quote: String

    @Environment(\.dismiss) private var dismiss
    @State private var format: ShareCardFormat
    @State private var shareItem: ShareCardImage?

    init(quote: String) {
        self.quote = quote
        // A long quote would truncate on 4:5, so open on 9:16 (which shows it
        // whole); the reader can still toggle back to the Minimal 4:5 card.
        let initial: ShareCardFormat = quote.count > ShareCardFormat.minimalThreshold ? .ratio9x16 : .ratio4x5
        _format = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 22) {
            GeometryReader { geo in
                let logical = format.logicalSize
                let scale = min(geo.size.width / logical.width, geo.size.height / logical.height)
                ReflectionShareCard(format: format, quote: quote)
                    .frame(width: logical.width, height: logical.height)
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.ankyViolet.opacity(0.16), radius: 18, y: 8)
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)

            Picker("", selection: $format) {
                Text(AnkyLocalization.ui("4:5")).tag(ShareCardFormat.ratio4x5)
                Text(AnkyLocalization.ui("9:16")).tag(ShareCardFormat.ratio9x16)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            AnkyPrimaryButton("Share") {
                if let image = ReflectionShareCardRenderer.image(for: format, quote: quote) {
                    shareItem = ShareCardImage(image: image)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .background(Color.ankyPaper.ignoresSafeArea())
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
    }
}

/// Thin bridge to the native share sheet.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
