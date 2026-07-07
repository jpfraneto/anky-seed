import SwiftUI

/// The 96-tile journey map is one uniform grid baked into the artwork.
/// Tile i -> row i/10, col i%10. Rows 0-8 are full; row 9 has cols 0-5.
/// Row 0 = red kingdom band at the top.
enum JourneyGrid {
    static let totalTiles = 96

    static let x0: CGFloat = 0.1354
    static let dx: CGFloat = 0.0807
    static let y0: CGFloat = 0.1295
    static let dy: CGFloat = 0.0780

    /// Normalized (0-1) center of tile `index` in the square artwork.
    static func anchor(for index: Int) -> CGPoint? {
        guard (0..<totalTiles).contains(index) else { return nil }
        return CGPoint(
            x: x0 + dx * CGFloat(index % 10),
            y: y0 + dy * CGFloat(index / 10)
        )
    }

    /// Position in a square container of side `side` (.scaledToFit).
    static func position(for index: Int, side: CGFloat) -> CGPoint? {
        anchor(for: index).map { CGPoint(x: $0.x * side, y: $0.y * side) }
    }
}

/// Page two of the main pager: the writing journey.
///
/// The journey is now a single baked 96-tile painting. Each sealed writing day
/// paints one tile in row-major order, making progress legible at a glance.
struct JourneyCardView: View {
    let side: CGFloat
    /// Beneath the paywall veil, progress is hidden until the journey opens.
    var heldAtFirstTile = false

    @StateObject private var state = JourneyState()
    @State private var writtenDayIndices: Set<Int> = []
    @State private var missedDayIndices: Set<Int> = []
    @State private var currentJourneyDay = 1
    @State private var minutesWritten = 0
    @State private var writingsCount = 0

    private var completedTileCount: Int {
        heldAtFirstTile ? 0 : writtenDayIndices.count
    }

    private var latestWrittenIndex: Int? {
        writtenDayIndices.max()
    }

    var body: some View {
        ZStack {
            Image("journey-map")
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)

            tileLayer
            mapChrome

            #if DEBUG
            debugControls
            #endif
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.ankyGold.opacity(0.45), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Writing journey, day \(currentJourneyDay) of \(JourneyGrid.totalTiles), \(completedTileCount) writing days")
        .onAppear(perform: refresh)
    }

    private var tileLayer: some View {
        ZStack {
            ForEach(Array(missedDayIndices).sorted(), id: \.self) { index in
                if let point = JourneyGrid.position(for: index, side: side) {
                    JourneyPaintedTile(side: side, style: .missed, isCurrent: false)
                        .position(point)
                }
            }

            ForEach(Array(writtenDayIndices).sorted(), id: \.self) { index in
                if let point = JourneyGrid.position(for: index, side: side) {
                    JourneyPaintedTile(
                        side: side,
                        style: .written,
                        isCurrent: index == latestWrittenIndex
                    )
                    .position(point)
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
                }
            }
        }
        .frame(width: side, height: side)
        .animation(.easeOut(duration: 0.35), value: completedTileCount)
        .allowsHitTesting(false)
    }

    private var mapChrome: some View {
        VStack(spacing: 0) {
            HStack {
                Text("day \(currentJourneyDay) of \(JourneyGrid.totalTiles)")
                    .font(.system(size: max(13, side * 0.040), weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ankyInk.opacity(0.88))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.ankyPaper.opacity(0.58), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.ankyGold.opacity(0.35), lineWidth: 0.6))
                Spacer()
            }
            Spacer()
            HStack {
                statPill(icon: .sun, text: "\(minutesWritten) mins written")
                Spacer()
                statPill(icon: .feather, text: "\(writingsCount) writings")
            }
        }
        .padding(10)
        .allowsHitTesting(false)
    }

    private func statPill(icon: JourneyStatIcon, text: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.ankyPaper.opacity(0.68))
                    .overlay(Circle().strokeBorder(Color.ankyGold.opacity(0.42), lineWidth: 0.7))

                switch icon {
                case .sun:
                    AnkySunGlyph(size: side * 0.044, color: .ankyInk.opacity(0.72))
                        .frame(width: side * 0.044, height: side * 0.044)
                case .feather:
                    Image("you-icon-feather-stat")
                        .resizable()
                        .scaledToFit()
                        .frame(width: side * 0.036, height: side * 0.036)
                        .opacity(0.72)
                }
            }
            .frame(width: side * 0.074, height: side * 0.074)

            Text(text)
                .font(.system(size: max(12, side * 0.038), weight: .medium, design: .serif))
                .foregroundStyle(Color.ankyInk.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(Color.ankyPaper.opacity(0.42), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.ankyGold.opacity(0.30), lineWidth: 0.6))
    }

    private func refresh() {
        state.refresh()
        if heldAtFirstTile {
            writtenDayIndices = []
            missedDayIndices = []
            currentJourneyDay = 1
            minutesWritten = 0
            writingsCount = 0
        } else {
            writtenDayIndices = state.writtenDayIndices
            missedDayIndices = state.missedDayIndices
            currentJourneyDay = state.currentJourneyDay
            minutesWritten = state.minutesWritten
            writingsCount = state.writingsCount
        }
    }

    #if DEBUG
    private var debugControls: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Spacer()
                Button("+1d") {
                    state.debugAdvanceDay()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        refresh()
                    }
                }
                Button("↺") {
                    state.debugResetJourney()
                    withAnimation(.easeOut(duration: 0.25)) {
                        refresh()
                    }
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.ankyPaper.opacity(0.86))
            .buttonStyle(.plain)
            .padding(12)
        }
    }
    #endif
}

private enum JourneyTilePaintStyle {
    case written
    case missed
}

private enum JourneyStatIcon {
    case sun
    case feather
}

private struct JourneyPaintedTile: View {
    let side: CGFloat
    let style: JourneyTilePaintStyle
    let isCurrent: Bool

    @State private var pulses = false

    private var tileSide: CGFloat { side * 0.058 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: tileSide * 0.20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: fillColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: tileSide * 0.20, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: max(1, tileSide * 0.030))
                )
                .shadow(color: shadowColor, radius: tileSide * (isCurrent ? 0.22 : 0.12))
                .frame(width: tileSide, height: tileSide)

            if style == .written, isCurrent {
                AnkySunGlyph(size: tileSide * 0.42, color: .ankyInk.opacity(0.58))
                    .frame(width: tileSide * 0.42, height: tileSide * 0.42)
                    .opacity(0.65)
            }
        }
        .blendMode(style == .written ? .plusLighter : .multiply)
        .opacity(style == .missed ? 0.44 : 1)
        .scaleEffect(isCurrent && pulses ? 1.05 : 1)
        .animation(
            isCurrent
                ? .easeInOut(duration: 2.0).repeatForever(autoreverses: true)
                : .default,
            value: pulses
        )
        .onAppear {
            pulses = isCurrent
        }
        .onChange(of: isCurrent) { current in
            pulses = current
        }
    }

    private var fillColors: [Color] {
        switch style {
        case .written:
            [
                Color.ankyPaper.opacity(0.72),
                Color.ankyGoldLight.opacity(0.88),
                Color.ankyGold.opacity(0.76),
            ]
        case .missed:
            [
                Color(red: 0.64, green: 0.20, blue: 0.16).opacity(0.34),
                Color(red: 0.48, green: 0.12, blue: 0.12).opacity(0.30),
            ]
        }
    }

    private var strokeColor: Color {
        switch style {
        case .written:
            Color.ankyGoldLight.opacity(0.82)
        case .missed:
            Color(red: 0.52, green: 0.16, blue: 0.12).opacity(0.28)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .written:
            Color.ankyGold.opacity(isCurrent ? 0.72 : 0.40)
        case .missed:
            Color(red: 0.40, green: 0.10, blue: 0.08).opacity(0.18)
        }
    }
}
