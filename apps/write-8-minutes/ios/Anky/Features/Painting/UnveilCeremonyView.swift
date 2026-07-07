import SwiftUI

/// The level-up ceremony.
///
/// The frame never moves — PaintingFrameMetrics places it exactly where the
/// main screen holds it; the world darkens and blooms around it. Sequence:
/// final strokes → held breath → candlelit aubergine → WELCOME TO LEVEL {N}
/// → the 8-second glimpse (bloom, breath, recede) → ghost Begin → drain.
struct UnveilCeremonyView: View {
    let level: Int
    let coordinator: LevelPaintingCoordinator
    let onFinished: () -> Void

    private enum Beat {
        case finalStrokes
        case heldBreath
        case darkening
        case title
        case waitingForGlimpse
        case glimpseBloom
        case glimpseHold
        case glimpseRecede
        case begin
        case drain
    }

    @State private var beat: Beat = .finalStrokes
    @State private var completedAssets: PaintingRevealAssets?
    @State private var completedTitle = ""
    @State private var glimpseAssets: PaintingRevealAssets?
    @State private var completedProgress: Double = 0.72
    @State private var glimpseProgress: Double = 0
    @State private var darkness: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var beginOpacity: Double = 0
    @State private var glowOvershoot: Double = 0
    @State private var contentOpacity: Double = 1
    @State private var theme = LevelTheme.fallback
    @State private var generationExcerpts: [String] = []

    var body: some View {
        GeometryReader { geometry in
            let frame = PaintingFrameMetrics.frameRect(in: geometry.size)

            ZStack {
                // The room: warm paper below, living aubergine darkness above.
                LazureWall(mood: theme.wallMood)
                aubergineDarkness
                    .opacity(darkness)

                if beat == .waitingForGlimpse {
                    PaintingGenerationWaitView(excerpts: generationExcerpts)
                        .transition(.opacity)
                }

                // The never-moving frame.
                Group {
                    if showsGlimpsePainting, let glimpseAssets {
                        PaintingView(
                            assets: glimpseAssets,
                            progress: glimpseProgress,
                            glowTint: theme.glowTint,
                            glowStrength: 1 + glowOvershoot
                        )
                    } else if let completedAssets {
                        PaintingView(
                            assets: completedAssets,
                            progress: completedProgress,
                            glowTint: theme.glowTint,
                            glowStrength: 1 + glowOvershoot
                        )
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

                ceremonyText(frame: frame, containerSize: geometry.size)
                    .opacity(titleOpacity * contentOpacity)

                beginButton(frame: frame, containerSize: geometry.size)
                    .opacity(beginOpacity * contentOpacity)
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: start)
    }

    private var showsGlimpsePainting: Bool {
        switch beat {
        case .glimpseBloom, .glimpseHold, .glimpseRecede, .begin, .drain:
            return glimpseAssets != nil
        default:
            return false
        }
    }

    /// Candlelit aubergine breathing into burnt umber — never pure black.
    private var aubergineDarkness: some View {
        ZStack {
            Color(.displayP3, red: 0.16, green: 0.10, blue: 0.17) // deep aubergine
            RadialGradient(
                colors: [
                    Color(.displayP3, red: 0.32, green: 0.18, blue: 0.10).opacity(0.55), // burnt umber warmth
                    Color.clear,
                ],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
        }
    }

    private func ceremonyText(frame: CGRect, containerSize: CGSize) -> some View {
        VStack(spacing: 14) {
            Text("WELCOME TO LEVEL \(level)")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .tracking(6)
                .foregroundStyle(Color.ankyGold)

            if !completedTitle.isEmpty {
                Text("“\(completedTitle)” — painted from \(AnkyLevel.thresholdSeconds(forLevel: level).formatted()) seconds of your writing.")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyPaperDeep.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .position(x: containerSize.width / 2, y: frame.maxY + 64)
    }

    private func beginButton(frame: CGRect, containerSize: CGSize) -> some View {
        Button {
            drainAndFinish()
        } label: {
            Text("Begin")
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(Color.ankyGoldLight)
                .padding(.horizontal, 38)
                .padding(.vertical, 12)
                .background(
                    Capsule().strokeBorder(Color.ankyGold.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .position(x: containerSize.width / 2, y: frame.maxY + 140)
    }

    // MARK: The sequence

    private func start() {
        let packages = coordinator.ceremonyPackages(forLevel: level)
        completedAssets = packages.completed.flatMap(PaintingRevealAssets.init)
        completedTitle = packages.completed?.title ?? ""
        glimpseAssets = packages.glimpse.flatMap(PaintingRevealAssets.init)
        generationExcerpts = coordinator.paintingGenerationExcerpts()
        theme = LevelTheme(package: packages.glimpse ?? packages.completed)

        // 1. The final strokes land. The painting view is inserted in this
        // same render pass, so the animation must start one tick later —
        // otherwise SwiftUI materializes it directly at the end value.
        completedProgress = 0.72
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: CeremonyTiming.finalStrokesSeconds)) {
                completedProgress = 1
            }
        }
        after(CeremonyTiming.finalStrokesSeconds) {
            beat = .heldBreath
            after(CeremonyTiming.heldBreathSeconds) {
                beat = .darkening
                withAnimation(.easeInOut(duration: CeremonyTiming.darkeningSeconds)) {
                    darkness = 1
                }
                after(CeremonyTiming.darkeningSeconds) {
                    beat = .title
                    withAnimation(.easeIn(duration: CeremonyTiming.titleFadeSeconds)) {
                        titleOpacity = 1
                    }
                    after(CeremonyTiming.titleFadeSeconds) {
                        beginGlimpse()
                    }
                }
            }
        }
    }

    private func beginGlimpse() {
        if glimpseAssets != nil {
            playGlimpse()
            return
        }
        // The writer outran generation: the darkness simply breathes longer.
        beat = .waitingForGlimpse
        Task {
            if let package = await coordinator.waitForCeremonyPackage(level: level) {
                glimpseAssets = PaintingRevealAssets(package: package)
                theme = LevelTheme(package: package)
            }
            playGlimpse()
        }
    }

    private func playGlimpse() {
        guard glimpseAssets != nil else {
            // Generation is still breathing; don't hold the writer hostage —
            // the glimpse will be waiting on the main painting instead.
            showBegin()
            return
        }
        // The glimpse painting enters this render pass at 0; the 8-second
        // bloom starts on the next tick so the insertion doesn't swallow it.
        beat = .glimpseBloom
        glimpseProgress = 0
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: CeremonyTiming.glimpseBloomSeconds)) {
                glimpseProgress = 1
            }
        }
        after(CeremonyTiming.glimpseBloomSeconds) {
            beat = .glimpseHold
            after(CeremonyTiming.glimpseHoldSeconds) {
                beat = .glimpseRecede
                withAnimation(.easeInOut(duration: CeremonyTiming.glimpseRecedeSeconds)) {
                    glimpseProgress = 0
                }
                // Begin fades in during the recede — anky shows you where
                // you're going; you earn it back stroke by stroke.
                showBegin()
            }
        }
    }

    private func showBegin() {
        beat = .begin
        withAnimation(.easeIn(duration: CeremonyTiming.beginFadeSeconds)) {
            beginOpacity = 1
        }
    }

    private func drainAndFinish() {
        beat = .drain
        coordinator.markCeremonyShown(level)
        withAnimation(.easeOut(duration: 0.6)) {
            contentOpacity = 0
        }
        // Pigment bleeds outward into the room: the glow overshoots in the
        // palette, then settles as the darkness lifts.
        withAnimation(.easeInOut(duration: CeremonyTiming.drainSeconds * 0.45)) {
            glowOvershoot = 1.6
        }
        withAnimation(.easeInOut(duration: CeremonyTiming.drainSeconds).delay(CeremonyTiming.drainSeconds * 0.25)) {
            glowOvershoot = 0
            darkness = 0
        }
        after(CeremonyTiming.drainSeconds) {
            onFinished()
        }
    }

    private func after(_ seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
}

private struct PaintingGenerationWaitView: View {
    let excerpts: [String]

    var body: some View {
        ZStack {
            WatercolorVeilView(register: .aubergine)

            VStack(spacing: 18) {
                Spacer(minLength: 0)

                Text("Anky is painting...")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(Color.ankyGoldLight)

                if !excerpts.isEmpty {
                    VStack(spacing: 12) {
                        Text("from your writing")
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                            .textCase(.uppercase)
                            .tracking(2.8)
                            .foregroundStyle(Color.ankyGold.opacity(0.78))

                        VStack(spacing: 10) {
                            ForEach(Array(excerpts.prefix(3).enumerated()), id: \.offset) { index, excerpt in
                                Text("“\(excerpt)”")
                                    .font(.system(size: index == 0 ? 17 : 15, weight: .regular, design: .serif))
                                    .foregroundStyle(Color.ankyPaperDeep.opacity(index == 0 ? 0.92 : 0.72))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, index == 0 ? 15 : 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.ankyInk.opacity(index == 0 ? 0.18 : 0.10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .strokeBorder(Color.ankyGold.opacity(index == 0 ? 0.28 : 0.16), lineWidth: 0.6)
                                            )
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: 360)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 56)
        }
        .allowsHitTesting(false)
    }
}
