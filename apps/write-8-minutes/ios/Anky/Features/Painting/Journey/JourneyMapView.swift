import SwiftUI

/// Page two of the main pager: the 88-day pilgrimage through a kingdom.
///
/// One background painting, procedural gilded tiles for completed days, the
/// Anky sprite on the current tile. Day-completion choreography: the new
/// tile blooms in (~2 glow pulses), then Anky walks to it along the path.
/// No streak number, no flame — the lit tiles already say everything.
struct JourneyMapView: View {
    let side: CGFloat
    /// Phase-3 §3: beneath the journey veil, Anky waits at tile 1. Progress
    /// keeps accruing in the stores; the walked path renders the moment the
    /// journey opens. Also skips the celebration choreography so a veiled
    /// map never consumes a tile bloom.
    var heldAtFirstTile = false

    @State private var kingdom = JourneyKingdom.current
    @State private var tiles: [JourneyTilePosition] = []
    @State private var completedDays = 0
    @State private var bloomingTileIndex: Int?
    @State private var bloomPulse: Double = 0
    @State private var walkProgress: Double = 1 // 0→1 along the last segment

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background

            GeometryReader { geometry in
                let size = geometry.size

                // Gilding: one warm procedural tile per completed day,
                // clipped to the footprint, .plusLighter over the watercolor.
                ForEach(0..<min(completedDays, tiles.count), id: \.self) { index in
                    litTile(at: index, in: size)
                }

                if !kingdom.hasBakedCharacter, let spot = spritePosition(in: size) {
                    AnkySpriteView(
                        sequence: walkProgress < 1 ? .walkRight : .idleFront,
                        size: size.height * 0.14
                    )
                    // Feet on the tile: nudge the sprite up half its height.
                    .position(x: spot.x, y: spot.y - size.height * 0.055)
                }
            }

            Text("day \(min(completedDays + 1, JourneyProgress.totalDays)) of \(JourneyProgress.totalDays)")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInk.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.ankyPaper.opacity(0.6), in: Capsule())
                .padding(12)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.ankyGold.opacity(0.5), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
        .onAppear(perform: refresh)
    }

    private var background: some View {
        Group {
            if let image = kingdom.backgroundImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // No kingdom art yet: a quiet pastel land under a pale sky.
                LinearGradient(
                    colors: [.ankyApricot.opacity(0.5), .ankyPaperDeep, .ankySage.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func litTile(at index: Int, in size: CGSize) -> some View {
        let tile = tiles[index]
        // Sized so 88 tiles sit shoulder-to-shoulder along the path without
        // fusing; re-tune per kingdom once the real art is authored.
        let tileSide = size.width * 0.036
        let isBlooming = bloomingTileIndex == index
        let angle = pathAngle(at: index)

        return RoundedRectangle(cornerRadius: tileSide * 0.24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.ankyGoldLight.opacity(0.95), Color.ankyGold.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: tileSide, height: tileSide * 0.82)
            .rotationEffect(angle)
            // Gilding over watercolor. If a kingdom palette ever fights
            // .plusLighter, fall back to .screen here.
            .blendMode(.plusLighter)
            .shadow(color: Color.ankyGold.opacity(0.55), radius: tileSide * 0.35)
            .scaleEffect(isBlooming ? 1 + bloomPulse * 0.35 : 1)
            .opacity(isBlooming ? 0.55 + bloomPulse * 0.45 : 1)
            .position(
                x: size.width * tile.x,
                y: size.height * tile.y
            )
    }

    /// Tiles sit along the path; each leans into the local tangent.
    private func pathAngle(at index: Int) -> Angle {
        guard tiles.count > 1 else { return .zero }
        let ahead = tiles[min(index + 1, tiles.count - 1)]
        let behind = tiles[max(index - 1, 0)]
        return .radians(atan2(ahead.y - behind.y, ahead.x - behind.x) * 0.5)
    }

    private func spritePosition(in size: CGSize) -> CGPoint? {
        guard !tiles.isEmpty else { return nil }
        let currentIndex = max(0, min(completedDays, tiles.count) - 1)
        let current = tiles[currentIndex]
        guard walkProgress < 1, currentIndex > 0 else {
            return CGPoint(x: size.width * current.x, y: size.height * current.y)
        }
        let previous = tiles[currentIndex - 1]
        let x = previous.x + (current.x - previous.x) * walkProgress
        let y = previous.y + (current.y - previous.y) * walkProgress
        return CGPoint(x: size.width * x, y: size.height * y)
    }

    // MARK: State

    private func refresh() {
        if tiles.isEmpty {
            tiles = JourneyTilePositions.load(kingdom: kingdom.index)
        }
        if heldAtFirstTile {
            completedDays = 0
            walkProgress = 1
            return
        }
        completedDays = JourneyProgress.completedDays(summaries: SessionIndexStore().load())
        celebrateNewTileIfNeeded()
    }

    /// The daily reward moment on this page: bloom, then walk. Ceremonial,
    /// not game-y — two slow pulses and one unhurried stride.
    private func celebrateNewTileIfNeeded() {
        let celebrated = JourneyProgress.celebratedCount()
        guard completedDays > celebrated, completedDays > 0, !tiles.isEmpty else {
            return
        }
        JourneyProgress.markCelebrated(completedDays)

        let newIndex = min(completedDays, tiles.count) - 1
        bloomingTileIndex = newIndex
        bloomPulse = 0
        // Two glow pulses (~2s), then the walk (~1.4s).
        withAnimation(.easeInOut(duration: 0.55).repeatCount(4, autoreverses: true)) {
            bloomPulse = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            bloomingTileIndex = nil
            bloomPulse = 0
            guard newIndex > 0 else { return }
            walkProgress = 0
            withAnimation(.easeInOut(duration: 1.4)) {
                walkProgress = 1
            }
        }
    }
}
