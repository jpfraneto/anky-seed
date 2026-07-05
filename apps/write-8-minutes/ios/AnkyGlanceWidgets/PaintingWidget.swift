import WidgetKit
import SwiftUI

/// Phase-2 §4: the 2×2 painting widget — the current level painting at its
/// true progress, pre-rendered by the app into the App Group. Thin gold
/// frame, warm glow, `lvl N` and spiral+pct in serif. Nothing else.
struct PaintingEntry: TimelineEntry {
    let date: Date
    let level: Int
    let percent: Int
    let image: UIImage?
    /// Phase-3 §5: the held-100% moment — the earned painting with the
    /// spiral and one truthful line, routing to the veiled ceremony.
    var isAtBoundary: Bool = false
}

struct PaintingProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaintingEntry {
        starterEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (PaintingEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PaintingEntry>) -> Void) {
        // The app reloads timelines on every seal/level-up; time alone never
        // changes the painting.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> PaintingEntry {
        guard let snapshot = GlanceSharedState.loadSnapshot(),
              let url = GlanceSharedState.imageURL(named: snapshot.imageFile),
              let image = UIImage(contentsOfFile: url.path) else {
            return starterEntry()
        }
        return PaintingEntry(
            date: Date(),
            level: snapshot.level,
            percent: snapshot.percent,
            image: image,
            isAtBoundary: snapshot.isAtBoundary ?? false
        )
    }

    /// The bundled "The Door" starter underdrawing — what a brand-new
    /// writer adds on day one, and the redacted/placeholder state.
    private func starterEntry() -> PaintingEntry {
        let url = Bundle.main.url(
            forResource: "underdrawing",
            withExtension: "png",
            subdirectory: "StarterPainting"
        )
        let image = url.flatMap { UIImage(contentsOfFile: $0.path) }
        return PaintingEntry(date: Date(), level: 1, percent: 0, image: image)
    }
}

struct PaintingWidgetView: View {
    let entry: PaintingEntry

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                Group {
                    if let image = entry.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        GlancePalette.paperDeep
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(GlancePalette.gold.opacity(0.85), lineWidth: 1)
                )
                .shadow(color: GlancePalette.goldLight.opacity(0.55), radius: 5)
            }

            if entry.isAtBoundary {
                // The boundary, truthfully: the completed painting they
                // earned, the spiral, and the waiting line. No countdown,
                // no percent that would never move.
                HStack(spacing: 4) {
                    Image(systemName: "hurricane")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(GlancePalette.gold)
                    Text(AnkyCopyRegistry.boundaryWidgetLine)
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(GlancePalette.ink)
            } else {
                HStack(spacing: 4) {
                    Text("lvl \(entry.level)")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                    Spacer()
                    Image(systemName: "hurricane")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(GlancePalette.gold)
                    Text("\(entry.percent)%")
                        .font(.system(size: 11, weight: .regular, design: .serif))
                }
                .foregroundStyle(GlancePalette.ink)
            }
        }
        .padding(10)
        .glanceBackground(GlancePalette.paper)
        .widgetURL(URL(string: entry.isAtBoundary ? "anky://painting" : "anky://write"))
    }
}

struct PaintingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AnkyPaintingWidget", provider: PaintingProvider()) { entry in
            PaintingWidgetView(entry: entry)
        }
        .configurationDisplayName("your painting")
        .description("the current painting at its true progress.")
        .supportedFamilies([.systemSmall])
    }
}

extension View {
    /// iOS 17 requires containerBackground; 16.1 still uses plain background.
    @ViewBuilder
    func glanceBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { color }
        } else {
            background(color)
        }
    }
}
