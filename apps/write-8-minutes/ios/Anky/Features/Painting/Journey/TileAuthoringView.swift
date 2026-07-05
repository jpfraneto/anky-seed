import SwiftUI

#if DEBUG
/// DEBUG authoring mode for kingdom tile paths.
///
/// Show the kingdom painting, tap the 88 tiles in order, copy the JSON to
/// the clipboard, and drop it into `Anky/JourneyKingdoms/` as
/// `journey-tiles-kingdom{N}.json`. Author once per kingdom.
struct TileAuthoringView: View {
    @State private var kingdom = JourneyKingdom.current
    @State private var points: [JourneyTilePosition] = []
    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 14) {
            Text("tap the \(JourneyProgress.totalDays) tiles in order · \(points.count) placed")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.ankyInk)

            GeometryReader { geometry in
                let size = geometry.size

                ZStack {
                    if let image = kingdom.backgroundImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    } else {
                        Color.ankyPaperDeep
                    }

                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.ankyInk)
                            .frame(width: 18, height: 18)
                            .background(Color.ankyGoldLight.opacity(0.9), in: Circle())
                            .position(x: size.width * point.x, y: size.height * point.y)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard points.count < JourneyProgress.totalDays else { return }
                    let normalizedX = Double(location.x / size.width)
                    let normalizedY = Double(location.y / size.height)
                    points.append(
                        JourneyTilePosition(
                            x: (normalizedX * 10_000).rounded() / 10_000,
                            y: (normalizedY * 10_000).rounded() / 10_000
                        )
                    )
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 12) {
                Button("undo") {
                    _ = points.popLast()
                }
                Button("clear") {
                    points.removeAll()
                }
                Spacer()
                Button(didCopy ? "copied ✓" : "copy JSON") {
                    copyJSON()
                }
                .fontWeight(.semibold)
            }
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(Color.ankyInk)
        }
        .padding(18)
        .background(LazureWall(mood: .dawn).ignoresSafeArea())
    }

    private func copyJSON() {
        struct TileFile: Encodable {
            let kingdom: Int
            let tiles: [JourneyTilePosition]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(TileFile(kingdom: kingdom.index, tiles: points)) else {
            return
        }
        UIPasteboard.general.string = String(decoding: data, as: UTF8.self)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { didCopy = false }
    }
}
#endif
