import SwiftUI

#if DEBUG
/// DEBUG authoring mode for the 96-day journey positions.
///
/// Shows the full stacked eight-kingdom map. Tap the days IN ORDER, day 0
/// (bottom of primordia) through day 95 (rising above poiesis): for each
/// kingdom, its 8 painted stepping stones first, then the 4 threshold spots
/// in the misty seam toward the next kingdom. Undo, clear, copy the JSON to
/// the clipboard, and drop it into `Anky/JourneyKingdoms/` as
/// `journey_positions.json`. Author once.
struct TileAuthoringView: View {
    @State private var days: [JourneyDay] = []
    @State private var didCopy = false
    @ObservedObject private var atlas = JourneyKingdomAtlas.shared
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { container in
            let width = container.size.width
            let geometry = JourneyMapGeometry(imageSide: width)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                ScrollView(showsIndicators: true) {
                    mapContent(width: width, geometry: geometry)
                        .frame(width: width, height: geometry.totalHeight)
                }

                controls
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(Color.ankyInk.ignoresSafeArea())
    }

    // MARK: Map

    private func mapContent(width: CGFloat, geometry: JourneyMapGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<JourneySojourn.kingdomCount, id: \.self) { index in
                paintingLayer(index, width: width, geometry: geometry)
            }

            // Placed days so far, numbered.
            ForEach(days) { day in
                marker(for: day, width: width)
                    .position(geometry.point(for: day))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            place(at: location, geometry: geometry, width: width)
        }
    }

    private func paintingLayer(_ index: Int, width: CGFloat, geometry: JourneyMapGeometry) -> some View {
        let top = geometry.imageTop(index)
        return Group {
            if let image = atlas.images[index] {
                Image(uiImage: image).resizable()
            } else {
                Color.ankyPaperDeep
                    .onAppear {
                        atlas.requestImage(
                            at: index,
                            maxPixelSize: Int(width * displayScale)
                        )
                    }
            }
        }
        .frame(width: width, height: width)
        .position(x: width / 2, y: top + width / 2)
    }

    private func marker(for day: JourneyDay, width: CGFloat) -> some View {
        Text("\(day.index)")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.ankyInk)
            .frame(width: 17, height: 17)
            .background(
                day.kind == .tile
                    ? Color.ankyGoldLight.opacity(0.92)
                    : Color.ankyApricot.opacity(0.92),
                in: day.kind == .tile
                    ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    : AnyShape(Circle())
            )
    }

    // MARK: Placement

    /// The next expected day, derived purely from how many are placed.
    private var nextIndex: Int { days.count }
    private var nextKingdom: Int { nextIndex / JourneySojourn.daysPerKingdom }
    private var nextKind: JourneyDayKind {
        nextIndex % JourneySojourn.daysPerKingdom < JourneySojourn.tilesPerKingdom
            ? .tile : .threshold
    }

    private func place(at location: CGPoint, geometry: JourneyMapGeometry, width: CGFloat) {
        guard nextIndex < JourneySojourn.totalDays else { return }
        let kingdom = nextKingdom
        let kind = nextKind

        // Which painting owns the position: a tile belongs to its kingdom's
        // image; a threshold to the bottom mist-band of the NEXT kingdom's
        // image (after poiesis it stays in image 8, rising at the top). In
        // the seam overlap two images contain the point — prefer the home,
        // fall back to whichever actually contains the tap.
        let home = kind == .tile
            ? kingdom
            : min(kingdom + 1, JourneySojourn.kingdomCount - 1)
        let candidates = geometry.imageIndices(containing: location.y)
        let image = candidates.contains(home)
            ? home
            : (candidates.max() ?? home)

        let normalizedX = (location.x / width).rounded(toPlaces: 4)
        let normalizedY = ((location.y - geometry.imageTop(image)) / width).rounded(toPlaces: 4)
        days.append(
            JourneyDay(
                index: nextIndex,
                kind: kind,
                kingdomIndex: kingdom,
                imageIndex: image,
                x: Double(normalizedX),
                y: Double(min(1, max(0, normalizedY)))
            )
        )
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Text(
                nextIndex < JourneySojourn.totalDays
                    ? "\(days.count)/\(JourneySojourn.totalDays) · next: day \(nextIndex) — \(nextKind.rawValue) (kingdom \(nextKingdom + 1))"
                    : "all \(JourneySojourn.totalDays) placed — copy the JSON"
            )
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.ankyPaper)
            Spacer()
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button("undo") { _ = days.popLast() }
            Button("clear") { days.removeAll() }
            Button("load bundled") { days = JourneyPositions.load() }
            Spacer()
            Button(didCopy ? "copied ✓" : "copy JSON") { copyJSON() }
                .fontWeight(.semibold)
        }
        .font(.system(size: 13, design: .monospaced))
        .foregroundStyle(Color.ankyGoldLight)
        .buttonStyle(.plain)
    }

    private func copyJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(
            JourneyPositions.PositionsFile(version: 1, days: days)
        ) else { return }
        UIPasteboard.general.string = String(decoding: data, as: UTF8.self)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { didCopy = false }
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let factor = pow(10, CGFloat(places))
        return (self * factor).rounded() / factor
    }
}
#endif
