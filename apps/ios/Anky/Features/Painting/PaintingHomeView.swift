import SwiftUI
import ImageIO
import UIKit

/// THE PAINTING IS THE APP.
///
/// The main screen is a two-page pager: page one is the current level's
/// painting at its true progress, page two the journey map. Everything else
/// (write, quick pass, history, blocked apps) is quiet chrome beneath the
/// frame. No streak pill, no flame, no day counter — the paintings and the
/// journey tiles tell the story in the product's own language.
struct PaintingHomeView: View {
    @ObservedObject var screenTime: WriteBeforeScrollSpikeViewModel
    let onWrite: () -> Void
    let onSetup: () -> Void
    let onSettings: () -> Void
    let onHistory: () -> Void
    let onOpenEntry: (SessionSummary) -> Void
    let onYou: () -> Void
    let onEmergency: () -> Void
    /// The writer offers their chapter to be painted (custom levels, 9+).
    let onBeginRitual: () -> Void

    @State private var signal = SignalCalculator.snapshot(
        screenTimeState: WriteBeforeScrollScreenTimeState(),
        unlockState: UnlockState(grant: nil, lastWroteAt: nil),
        events: [],
        sessionDays: []
    )
    @State private var quickPassesRemaining = QuickPassStore.dailyAllowance
    @State private var dailyTargetMinutes = DailyTargetStore.defaultMinutes
    @State private var targetMetToday = false
    @State private var levelProgress = AnkyLevel.progress(forTotalSeconds: 0)
    @State private var package: PaintingPackage?
    @State private var revealAssets: PaintingRevealAssets?
    @State private var theme = LevelTheme.fallback
    @State private var displayedProgress: Double = 0
    @State private var strokeBeatSeconds = 0
    @State private var heroPage = 0
    @State private var showsGallery = false
    @State private var showsProgressAsSeconds = false
    @State private var ceremonyOwed = false
    @State private var recentSessions: [SessionSummary] = []
    @State private var sessionLevels: [String: Int] = [:]
    @State private var avatarImage = AvatarStore().loadImage()
    @State private var atBoundary = false
    @State private var showsBoundaryVeil = false
    @State private var showsJourneyPaywall = false
    /// A custom level (9+) has been reached but its painting has not been
    /// summoned yet — the canvas waits with the ritual invitation.
    @State private var needsRitual = false
    /// The custom level whose painting the ritual would summon next.
    @State private var ritualLevel = 0
    /// True once the writer has offered their chapter and anky is painting.
    @State private var isSummoningPainting = false
    @EnvironmentObject private var entitlements: EntitlementStore

    private enum GatePhase {
        case needsAuthorization
        case needsSelection
        case ready
    }

    private var phase: GatePhase {
        if !screenTime.isScreenTimeAuthorized { return .needsAuthorization }
        if !signal.isGateConfigured { return .needsSelection }
        return .ready
    }

    var body: some View {
        ZStack {
            LazureWall(mood: theme.wallMood)

            GeometryReader { geometry in
                let frame = PaintingFrameMetrics.frameRect(in: geometry.size)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 24)
                            .padding(.top, 12)

                        heroPager(side: frame.width)
                            .frame(height: frame.width + 44)
                            .padding(.top, max(8, frame.minY - 96))

                        chrome
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                            .padding(.bottom, 120)
                    }
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            avatarImage = AvatarStore().loadImage()
            screenTime.refresh()
            refreshEverything()
            playStrokeBeatIfOwed()
        }
        .onChange(of: screenTime.state) { _ in
            refreshSignal()
        }
        .fullScreenCover(isPresented: $showsGallery) {
            GalleryView(
                currentLevel: levelProgress.level,
                currentLevelProgress: levelProgress.percent
            )
        }
        .fullScreenCover(isPresented: $showsBoundaryVeil) {
            BoundaryCeremonyVeilView(entitlements: entitlements)
        }
        .sheet(isPresented: $showsJourneyPaywall) {
            PaywallSheet(store: entitlements, origin: "journey")
        }
        .onChange(of: entitlements.verificationState) { state in
            // A display-only cached entitlement may paint continuity, but it
            // must never dissolve a paid boundary. Only current verification
            // can close the veil and expose Pro progression.
            if state.hasVerifiedPro {
                showsBoundaryVeil = false
            }
            refreshEverything()
        }
    }

    // MARK: Hero pager

    private func heroPager(side: CGFloat) -> some View {
        VStack(spacing: 14) {
            TabView(selection: $heroPage) {
                paintingPage(side: side)
                    .tag(0)
                if entitlements.isEntitledForGating {
                    JourneyCardView(side: side)
                        .tag(1)
                } else {
                    // Phase-3 §3: the journey misted, Anky waiting at tile 1.
                    VeiledFeature(
                        surface: "journey",
                        message: AnkyCopyRegistry.veilJourney,
                        onTap: { showsJourneyPaywall = true }
                    ) {
                        JourneyCardView(side: side, heldAtFirstTile: true)
                    }
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity)
                    .tag(1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: side + 8)

            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { page in
                    Circle()
                        .fill(heroPage == page ? Color.ankyGold : Color.ankyInkSoft.opacity(0.28))
                        .frame(width: 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: heroPage)
        }
    }

    private func paintingPage(side: CGFloat) -> some View {
        VStack {
            ZStack(alignment: .bottom) {
                Group {
                    if needsRitual {
                        // Past level 8 the painting is no longer automatic:
                        // the canvas waits until the writer offers their
                        // chapter to be painted.
                        ritualCanvas
                    } else if let revealAssets {
                        // A completed painting whose ceremony is still owed
                        // carries a small waiting glow until the unveiling.
                        PaintingView(
                            assets: revealAssets,
                            progress: displayedProgress,
                            glowTint: theme.glowTint,
                            glowStrength: ceremonyOwed ? 1.45 : 1
                        )
                    } else {
                        // Package not ready yet: a waiting canvas, breathing.
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.ankyPaperDeep)
                            .overlay(
                                Text(AnkyLocalization.ui("anky is preparing your canvas…"))
                                    .font(.ankyCaption)
                                    .foregroundStyle(Color.ankyInkSoft)
                            )
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .onTapGesture {
                    if needsRitual {
                        // The ritual button owns this canvas — a stray tap
                        // opens the gallery, never a summon.
                        showsGallery = true
                    } else if strokeBeatSeconds > 0 {
                        skipStrokeBeat()
                    } else if atBoundary {
                        // §2: at the held-100% moment, the painting opens
                        // onto the veiled next canvas, one tap from the ask.
                        showsBoundaryVeil = true
                    } else {
                        showsGallery = true
                    }
                }

                if !needsRitual {
                    frameFooter
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
            .frame(width: side, height: side)
            .background {
                // Report the frame's true global rect so the unveiling
                // ceremony can hold the painting in exactly this spot.
                GeometryReader { proxy in
                    let rect = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { Self.reportFramePosition(rect) }
                        .onChange(of: rect) { newRect in
                            Self.reportFramePosition(newRect)
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                Text(AnkyLocalization.ui("level short format", levelProgress.level))
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ankyGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.ankyInk.opacity(0.35), in: Capsule())
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The waiting canvas for a custom level (9+): the writer offers their
    /// chapter, and anky paints it. A ritual, chosen — never automatic.
    private var ritualCanvas: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.ankyPaperDeep)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isSummoningPainting {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.ankyGold)
                        Text(AnkyLocalization.ui(AnkyCopyRegistry.ritualInFlight(level: ritualLevel)))
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundStyle(Color.ankyInkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                } else {
                    VStack(spacing: 18) {
                        AnkySunGlyph(color: Color.ankyGold.opacity(0.85))
                            .frame(width: 26, height: 26)

                        Text(AnkyLocalization.ui(AnkyCopyRegistry.ritualInvitation(level: ritualLevel)))
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundStyle(Color.ankyInk)
                            .multilineTextAlignment(.center)

                        Button {
                            AnkyHaptics.medium()
                            isSummoningPainting = true
                            onBeginRitual()
                        } label: {
                            Text(AnkyLocalization.ui(AnkyCopyRegistry.ritualButton))
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.ankyInk)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule().fill(Color.ankyGold.opacity(0.22))
                                )
                                .overlay(
                                    Capsule().strokeBorder(Color.ankyGold.opacity(0.55), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Text(AnkyLocalization.ui(AnkyCopyRegistry.ritualDisclosure))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.ankyInkSoft.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 26)
                }
            }
    }

    /// Spiral + progress bar + percent, resting on the frame's bottom edge.
    private var frameFooter: some View {
        HStack(spacing: 10) {
            AnkySunGlyph()
                .frame(width: 18, height: 18)
                .opacity(0.9)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.ankyInk.opacity(0.25))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.ankyGoldLight, .ankyGold],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geometry.size.width * displayedProgress))
                }
            }
            .frame(height: 4)

            Text(showsProgressAsSeconds
                ? "\(levelProgress.secondsIntoLevel)s / \(levelProgress.secondsRequired)s"
                : "\(Int((displayedProgress * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ankyPaper)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(minWidth: showsProgressAsSeconds ? 104 : 32, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ankyInk.opacity(0.30), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            AnkyHaptics.light()
            withAnimation(.easeInOut(duration: 0.18)) {
                showsProgressAsSeconds.toggle()
            }
        }
    }

    // MARK: Chrome beneath the frame

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 18) {
            primaryCTA

            if phase == .ready, targetMetToday {
                // The day's mission is done — say so; a quick-pass offer here
                // would be redundant noise.
                Text(AnkyLocalization.ui(signal.isCurrentlyUnlocked
                    ? "daily target met · your apps are open"
                    : "daily target met"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(maxWidth: .infinity)
            } else if phase == .ready, quickPassesRemaining > 0 {
                Button(action: onWrite) {
                    Text(AnkyLocalization.ui("Quick pass count format", quickPassesRemaining))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ankyInkSoft)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            // Phase-2 §2: the emergency door must be reachable from inside
            // the app whenever the shield stands — the notification hop is
            // never the only route (it doesn't exist with notifications
            // denied).
            if phase == .ready, signal.isShieldActive, !signal.isCurrentlyUnlocked {
                Button(action: onEmergency) {
                    Text(AnkyLocalization.ui(AnkyCopyRegistry.emergencyLink))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.75))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(AnkyLocalization.ui("Emergency: open your apps without writing"))
            }

            historyCard

            // The maker's mark, resting at the bottom of the main screen.
            Text(AnkyLocalization.ui("Made with love by Anky, Inc"))
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInkSoft.opacity(0.65))
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }

    private var primaryCTA: some View {
        Button {
            switch phase {
            case .needsAuthorization, .needsSelection:
                onSetup()
            case .ready:
                onWrite()
            }
        } label: {
            HStack(spacing: 10) {
                // Ink, not gold: the sun must read against the gold wash.
                AnkySunGlyph(color: Color.ankyInk.opacity(0.78))
                    .frame(width: 20, height: 20)
                Text(AnkyLocalization.ui(phase == .ready ? "Write" : (phase == .needsSelection ? "Choose apps" : "Continue setup")))
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Color.ankyInk)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                // Lazure, not flat pigment: translucent gold veils brushed
                // over paper, light pooling at the top edge.
                ZStack {
                    Capsule()
                        .fill(Color.ankyPaper.opacity(0.55))
                        .background(.ultraThinMaterial, in: Capsule())
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.ankyGoldLight.opacity(0.62),
                                    Color.ankyGold.opacity(0.34),
                                    theme.buttonWarmth.opacity(0.44),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Capsule()
                        .fill(
                            RadialGradient(
                                colors: [Color.ankyPaper.opacity(0.42), .clear],
                                center: UnitPoint(x: 0.24, y: 0),
                                startRadius: 2,
                                endRadius: 140
                            )
                        )
                }
            }
            .overlay(Capsule().strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
            .shadow(color: Color.ankyViolet.opacity(0.16), radius: 14, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onHistory) {
                HStack(spacing: 9) {
                    Image("you-icon-feather-stat")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .opacity(0.72)

                    Text(AnkyLocalization.ui("History"))
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ankyInk)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.72))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, recentSessions.isEmpty ? 10 : 8)

            if recentSessions.isEmpty {
                Text(AnkyLocalization.ui("Your first page is waiting."))
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft)
                    .padding(.bottom, 2)
            } else {
                // Each row opens its entry directly — the header alone
                // leads to the full archive.
                let visibleSessions = Array(recentSessions.prefix(5))
                ForEach(Array(visibleSessions.enumerated()), id: \.element.hash) { offset, session in
                    Button {
                        onOpenEntry(session)
                    } label: {
                        HistoryPreviewRow(
                            session: session,
                            thumbnail: SessionLevelArt.thumbnail(
                                forLevel: sessionLevels[session.hash] ?? levelProgress.level
                            )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if offset < visibleSessions.count - 1 {
                        LazureDivider()
                            .padding(.leading, 46)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.ankyPaper.opacity(0.86),
                            Color.ankyPaperDeep.opacity(0.62),
                            Color.ankyPaper.opacity(0.56),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.ankyGold.opacity(0.18), lineWidth: 0.7)
                )
        }
        .shadow(color: Color.ankyViolet.opacity(0.14), radius: 18, y: 6)
    }

    private var header: some View {
        HStack {
            if let writerName = WritingAnchorStore().writerName {
                HStack(spacing: 10) {
                    if let avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.ankyGold.opacity(0.45), lineWidth: 0.8))
                    }

                    Text(writerName)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ankyInk)
                }
            }
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(width: 38, height: 38)
                    .background(Color.ankyPaper.opacity(0.6), in: Circle())
                    .overlay(Circle().strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("Settings"))
        }
    }

    // MARK: State

    private func refreshEverything() {
        refreshSignal()
        refreshLevel()
    }

    private func refreshSignal() {
        let now = Date()
        let sessions = SessionIndexStore().load()
        recentSessions = sessions
        sessionLevels = SessionLevelArt.levels(for: sessions)
        signal = SignalCalculator.snapshot(
            screenTimeState: screenTime.state,
            unlockState: UnlockStateStore().load(),
            events: WriteBeforeScrollEventLogStore().load(),
            sessionDays: sessions.map(\.createdAt)
        )
        quickPassesRemaining = QuickPassStore().remainingPasses(now: now)
        dailyTargetMinutes = DailyTargetStore().effectiveTargetMinutes(now: now)
        let calendar = Calendar.current
        let writtenTodayMs = sessions
            .filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
            .reduce(Int64(0)) { $0 + $1.durationMs }
        targetMetToday = writtenTodayMs >= DailyTargetStore().effectiveTargetMs(now: now)
    }

    private func refreshLevel() {
        let store = LevelProgressStore()
        store.backfillIfNeeded(from: SessionIndexStore().load())
        // Adopted / updated writers land at their true level, no ceremony
        // crawl through the shared static paintings.
        store.reconcileCeremonyPointerIfNeeded()
        // The free tier presents the boundary — level 8 serenely
        // complete — while the counter underneath keeps every second.
        let entitled = entitlements.isEntitledForGating
        levelProgress = store.presentedProgress(entitled: entitled)
        atBoundary = store.isAtBoundary(entitled: entitled)
        ceremonyOwed = store.owedCeremonyLevel != nil && !atBoundary

        let assetStore = PaintingAssetStore()
        assetStore.installStarterIfNeeded()

        // Past level 8 the painting is custom and summoned by ritual. The
        // owed custom level whose canvas doesn't exist yet waits with the
        // invitation — never the previous painting stuck at a false 100%.
        if entitled,
           let owed = store.owedCeremonyLevel,
           owed > LevelProgressStore.freeBoundaryLevel,
           assetStore.installedPackage(forLevel: owed) == nil {
            needsRitual = true
            ritualLevel = owed
            isSummoningPainting = store.phase(forLevel: owed) != .accumulating
            package = nil
            revealAssets = nil
            theme = .fallback
            displayedProgress = 0
            return
        }
        needsRitual = false

        // The painting for the level the writer is IN; if it isn't installed
        // (yet), fall back to the newest one we have.
        let installed = assetStore.installedPackage(forLevel: levelProgress.level)
            ?? assetStore.installedLevels().last.flatMap { assetStore.installedPackage(forLevel: $0) }
        if package != installed {
            package = installed
            revealAssets = installed.flatMap(PaintingRevealAssets.init)
            theme = LevelTheme(package: installed)
        }
        displayedProgress = paintingProgress
    }

    /// The reveal progress of the displayed painting. A painting behind the
    /// writer's current level is complete; the current level's reveals by
    /// percent within the level.
    private var paintingProgress: Double {
        guard let package else { return 0 }
        if package.level < levelProgress.level { return 1 }
        return levelProgress.percent
    }

    /// Only a centered, on-screen frame is worth remembering — the pager
    /// slides this page off-screen when the journey card is up.
    private static func reportFramePosition(_ rect: CGRect) {
        guard abs(rect.midX - UIScreen.main.bounds.midX) < 2,
              rect.minY > 0,
              rect.maxY < UIScreen.main.bounds.height else {
            return
        }
        PaintingFramePosition.lastHomeGlobalRect = rect
    }

    // MARK: Post-session stroke beat

    /// Today's strokes arrive over ~2-3s, proportional to seconds written.
    private func playStrokeBeatIfOwed() {
        let pending = LevelProgressStore().consumePendingStrokeSeconds()
        guard pending > 0, revealAssets != nil else { return }
        strokeBeatSeconds = pending

        let target = paintingProgress
        let delta = min(Double(pending) / Double(max(1, levelProgress.secondsRequired)), target)
        displayedProgress = max(0, target - delta)

        // Proportional: a 12-minute session visibly paints more than one
        // sentence — longer sessions get the full three seconds.
        let duration = min(3.0, 1.2 + Double(pending) / 240.0)
        withAnimation(.easeInOut(duration: duration)) {
            displayedProgress = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            strokeBeatSeconds = 0
        }
    }

    private func skipStrokeBeat() {
        strokeBeatSeconds = 0
        withAnimation(.easeOut(duration: 0.2)) {
            displayedProgress = paintingProgress
        }
    }
}

private struct HistoryPreviewRow: View {
    let session: SessionSummary
    let thumbnail: UIImage?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d  ·  h:mm a"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            thumbnailView

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateFormatter.string(from: session.createdAt))
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.78))
                    .lineLimit(1)

                Text(session.preview)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 0) {
                Text(AnkyDuration.clock(session.durationMs))
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInk)
                    .monospacedDigit()
                Text(AnkyLocalization.ui("mins"))
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.76))
            }
            .frame(width: 42, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ankyInkSoft.opacity(0.72))
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.ankyGold.opacity(0.28), lineWidth: 0.7))
        } else {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.ankyGoldLight.opacity(0.52),
                            Color.ankyViolet.opacity(0.42),
                            Color.ankyInk.opacity(0.18),
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 28
                    )
                )
                .frame(width: 34, height: 34)
                .overlay(
                    AnkySunGlyph(size: 16, color: .ankyPaper.opacity(0.88))
                        .frame(width: 16, height: 16)
                )
        }
    }
}

/// Which level each session was written in, and that level's painting as a
/// small thumbnail — the art that was on the easel at the moment of the
/// writing. Levels are derived by replaying the sessions in order and
/// accumulating seconds, exactly like the level curve does.
@MainActor
enum SessionLevelArt {
    private static var thumbnailCache: [Int: UIImage] = [:]

    static func levels(for sessions: [SessionSummary]) -> [String: Int] {
        levels(entries: sessions.map { ($0.hash, $0.createdAt, $0.durationMs) })
    }

    static func levels(forArtifacts artifacts: [SavedAnky]) -> [String: Int] {
        levels(entries: artifacts.map { ($0.hash, $0.createdAt, $0.durationMs) })
    }

    private static func levels(entries: [(hash: String, createdAt: Date, durationMs: Int64)]) -> [String: Int] {
        var totalSeconds = 0
        var byHash: [String: Int] = [:]
        for entry in entries.sorted(by: { $0.createdAt < $1.createdAt }) {
            byHash[entry.hash] = AnkyLevel.progress(forTotalSeconds: totalSeconds).level
            totalSeconds += Int(entry.durationMs / 1000)
        }
        return byHash
    }

    /// The nearest installed painting at or below the level — the starter
    /// level-1 package is always installed, so this only misses when no
    /// package exists at all.
    static func thumbnail(forLevel level: Int) -> UIImage? {
        let store = PaintingAssetStore()
        let installed = store.installedLevels()
        guard let resolved = installed.filter({ $0 <= level }).max() ?? installed.min() else {
            return nil
        }
        if let cached = thumbnailCache[resolved] {
            return cached
        }
        guard let package = store.installedPackage(forLevel: resolved),
              let thumbnail = downsampledImage(at: package.finalURL, maxPixel: 120) else {
            return nil
        }
        thumbnailCache[resolved] = thumbnail
        return thumbnail
    }

    /// CGImageSource thumbnail decode — the full painting is 1254² and has
    /// no business being decoded per row.
    private static func downsampledImage(at url: URL, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Phase-3 §2: the pending moment at the boundary. The level-2 painting is
/// complete and stays theirs; the *next* canvas waits under the veil, one
/// tap from the paywall. Serene, never broken — the bar behind reads 100%.
private struct BoundaryCeremonyVeilView: View {
    @ObservedObject var entitlements: EntitlementStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsPaywall = false

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                VeiledFeature(
                    surface: "ceremony",
                    message: AnkyCopyRegistry.veilCeremony,
                    onTap: { showsPaywall = true }
                ) {
                    // The waiting canvas — the same breathing paper the
                    // entitled see while anky paints.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.ankyPaperDeep)
                        .aspectRatio(1, contentMode: .fit)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 44)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(AnkyLocalization.ui("not yet"))
                        .font(.ankyCaption)
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.85))
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.bottom, 44)
            }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallSheet(store: entitlements, origin: "ceremony")
        }
        .onChange(of: entitlements.verificationState) { state in
            if state.hasVerifiedPro {
                dismiss()
            }
        }
    }
}
