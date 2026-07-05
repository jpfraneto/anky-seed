import Foundation
import UIKit

/// One kingdom of the 88-day pilgrimage.
///
/// Architecture: ONE background painting per kingdom (square, tile path baked
/// into the artwork, ideally WITHOUT Anky so the sprite can move), one
/// transparent Anky sprite, one JSON of 88 normalized tile positions authored
/// via TileAuthoringView. No per-day image variants, ever.
///
/// POIESIS ASSET SPEC (per kingdom):
/// - `kingdomN.png`: 2048×2048, the landscape with an empty translucent
///   88-tile stepping-stone path baked in, no character.
/// - a matching Anky sprite cut from the same scene (lighting/palette match),
///   transparent PNG — used at tile `currentDay`, walking on day completion.
/// The bundled kingdom1 is a cleaned crop of the reference mockup: it still
/// carries a baked Anky, so `hasBakedCharacter` hides the sprite until the
/// real art lands.
struct JourneyKingdom {
    let index: Int
    let imageName: String
    /// True while the placeholder art (with Anky painted in) is in use.
    let hasBakedCharacter: Bool

    static let current = JourneyKingdom(
        index: 1,
        imageName: "kingdom1",
        hasBakedCharacter: true
    )

    var backgroundImage: UIImage? {
        guard let url = Bundle.main.url(
            forResource: imageName,
            withExtension: "png",
            subdirectory: "JourneyKingdoms"
        ) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

struct JourneyTilePosition: Codable, Equatable {
    let x: Double
    let y: Double
}

enum JourneyTilePositions {
    private struct TileFile: Codable {
        let kingdom: Int
        let tiles: [JourneyTilePosition]
    }

    /// The 88 normalized positions for a kingdom, authored once via
    /// TileAuthoringView and bundled as JSON.
    static func load(kingdom: Int, bundle: Bundle = .main) -> [JourneyTilePosition] {
        guard
            let url = bundle.url(
                forResource: "journey-tiles-kingdom\(kingdom)",
                withExtension: "json",
                subdirectory: "JourneyKingdoms"
            ),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(TileFile.self, from: data)
        else {
            return []
        }
        return file.tiles
    }
}

/// The pilgrimage calendar: 88 days, one tile per day the writer showed up.
/// No streak semantics — a missed day simply means the next tile lights
/// tomorrow. Nothing resets, nothing is lost.
enum JourneyProgress {
    static let totalDays = 88
    private static let celebratedKey = "anky.journey.celebratedTileCount.v1"

    /// Days (distinct local calendar days) with at least one sealed session.
    static func completedDays(
        summaries: [SessionSummary],
        calendar: Calendar = .current
    ) -> Int {
        let days = Set(summaries.map { calendar.startOfDay(for: $0.createdAt) })
        return min(totalDays, days.count)
    }

    /// The last tile count whose bloom/walk was celebrated on this device.
    static func celebratedCount(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: celebratedKey)
    }

    static func markCelebrated(_ count: Int, defaults: UserDefaults = .standard) {
        defaults.set(count, forKey: celebratedKey)
    }
}
