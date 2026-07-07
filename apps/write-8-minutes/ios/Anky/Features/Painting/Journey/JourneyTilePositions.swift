import Foundation
import SwiftUI
import ImageIO
import UIKit

/// The 96-day sojourn: 8 kingdom paintings stacked into one continuous
/// vertical world, primordia at the bottom, poiesis at the top. Each kingdom
/// holds 12 days — 8 stepping-stone "tile" days baked into its painting and
/// 4 "threshold" days in the misty seam toward the next kingdom. The
/// tile/threshold distinction is INTERNAL ONLY: no screen ever names a
/// kingdom, a threshold, or a crossing. The map just gets lighter.
enum JourneySojourn {
    static let kingdomCount = 8
    static let tilesPerKingdom = 8
    static let thresholdsPerKingdom = 4
    static let daysPerKingdom = tilesPerKingdom + thresholdsPerKingdom
    static let totalDays = kingdomCount * daysPerKingdom // 96
}

enum JourneyDayKind: String, Codable {
    case tile
    case threshold
}

/// One day of the sojourn, pinned to a normalized position inside one of the
/// eight paintings. Threshold days may sit in the bottom mist-band of the
/// NEXT kingdom's image (the seam belongs to the crossing); after poiesis
/// they rise into the light at the top of image 8 — hence `imageIndex` is
/// stored separately from `kingdomIndex`.
struct JourneyDay: Codable, Equatable, Identifiable {
    let index: Int          // 0...95, walked bottom-to-top
    let kind: JourneyDayKind
    let kingdomIndex: Int   // 0...7, which kingdom's 12-day span owns the day
    let imageIndex: Int     // 0...7, which painting the position is authored in
    let x: Double           // normalized within that painting
    let y: Double

    var id: Int { index }

    private enum CodingKeys: String, CodingKey {
        case index, kind
        case kingdomIndex = "kingdom"
        case imageIndex = "image"
        case x, y
    }
}

/// Loader for the authored positions (journey_positions.json, produced by
/// TileAuthoringView and bundled in JourneyKingdoms/). Fails loudly in DEBUG
/// so a missing or malformed file can never ship silently.
enum JourneyPositions {
    struct PositionsFile: Codable {
        let version: Int
        let days: [JourneyDay]
    }

    static func load(bundle: Bundle = .main) -> [JourneyDay] {
        guard let url = bundle.url(
            forResource: "journey_positions",
            withExtension: "json",
            subdirectory: "JourneyKingdoms"
        ) else {
            return failLoudly("journey_positions.json missing from JourneyKingdoms")
        }
        guard
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(PositionsFile.self, from: data)
        else {
            return failLoudly("journey_positions.json unreadable")
        }
        let days = file.days.sorted { $0.index < $1.index }
        guard
            days.count == JourneySojourn.totalDays,
            days.enumerated().allSatisfy({ offset, day in
                day.index == offset
                    && (0..<JourneySojourn.kingdomCount).contains(day.imageIndex)
                    && (0..<JourneySojourn.kingdomCount).contains(day.kingdomIndex)
            })
        else {
            return failLoudly("journey_positions.json must hold days 0...95 with valid indices")
        }
        return days
    }

    private static func failLoudly(_ message: String) -> [JourneyDay] {
        #if DEBUG
        fatalError(message)
        #else
        return []
        #endif
    }
}

/// The geometry of the stacked world. Every painting renders square at the
/// card's width; adjacent paintings overlap by 4% of their height so the
/// misty seams melt into each other. Image 0 (primordia) sits at the BOTTOM
/// of the scroll content, image 7 (poiesis) at the top.
struct JourneyMapGeometry: Equatable {
    let imageSide: CGFloat

    static let seamOverlapFraction: CGFloat = 0.04

    var overlap: CGFloat { imageSide * Self.seamOverlapFraction }
    var totalHeight: CGFloat {
        imageSide * CGFloat(JourneySojourn.kingdomCount)
            - overlap * CGFloat(JourneySojourn.kingdomCount - 1)
    }

    /// Distance from the top of the scroll content to the top of a painting.
    func imageTop(_ imageIndex: Int) -> CGFloat {
        CGFloat(JourneySojourn.kingdomCount - 1 - imageIndex) * (imageSide - overlap)
    }

    /// A day's position in scroll-content coordinates.
    func point(for day: JourneyDay) -> CGPoint {
        CGPoint(
            x: imageSide * CGFloat(day.x),
            y: imageTop(day.imageIndex) + imageSide * CGFloat(day.y)
        )
    }

    /// Which paintings contain a content-space y. In the seam overlap two do.
    func imageIndices(containing mapY: CGFloat) -> [Int] {
        (0..<JourneySojourn.kingdomCount).filter { index in
            let top = imageTop(index)
            return mapY >= top && mapY <= top + imageSide
        }
    }
}

/// Decoded kingdom paintings, downsampled once to at most ~2x the card's
/// pixel width and kept for the app's lifetime (eight stills; the scroll
/// only ever composites, never re-decodes).
@MainActor
final class JourneyKingdomAtlas: ObservableObject {
    static let shared = JourneyKingdomAtlas()

    /// Views observe this directly, so a painting appears the moment its
    /// decode lands — keyed by image index (0 = primordia … 7 = poiesis).
    @Published private(set) var images: [Int: UIImage] = [:]
    private var inFlight: Set<Int> = []

    static func url(forImage index: Int, bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: "kingdom\(index + 1)",
            withExtension: "png",
            subdirectory: "JourneyKingdoms"
        )
    }

    /// Kicks a background decode if needed. Safe to call every scroll frame —
    /// dedupes in-flight work and never re-decodes.
    func requestImage(at index: Int, maxPixelSize: Int) {
        guard images[index] == nil, !inFlight.contains(index) else { return }
        guard let url = Self.url(forImage: index) else {
            #if DEBUG
            fatalError("kingdom\(index + 1).png missing from JourneyKingdoms")
            #else
            return
            #endif
        }
        inFlight.insert(index)
        Task.detached(priority: .userInitiated) {
            let image = Self.downsample(url: url, maxPixelSize: maxPixelSize)
            await MainActor.run {
                self.inFlight.remove(index)
                if let image {
                    self.images[index] = image
                }
            }
        }
    }

    nonisolated private static func downsample(url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// The observable heart of the journey card. Everything derives from the
/// session index (the app's store of record for sealed writing) — a day
/// counts when it holds at least one sealed session, and nothing ever
/// resets: a missed day just means the next light comes tomorrow.
@MainActor
final class JourneyState: ObservableObject {
    @Published private(set) var completedDays = 0     // distinct writing days
    @Published private(set) var currentJourneyDay = 1  // day since first writing, 1...96
    @Published private(set) var writtenDayIndices: Set<Int> = []
    @Published private(set) var missedDayIndices: Set<Int> = []
    @Published private(set) var minutesWritten = 0
    @Published private(set) var writingsCount = 0
    @Published private(set) var streakDays = 0

    private static let celebratedKey = "anky.journey.celebratedDayCount.v2"
    #if DEBUG
    private static let debugExtraDaysKey = "anky.journey.debugExtraDays"
    #endif

    /// The day Anky stands on: the most recently lit one (day 0 before any
    /// writing — the sprite waits on the first unlit stone).
    var currentDayIndex: Int {
        max(0, min(completedDays, JourneySojourn.totalDays) - 1)
    }

    func refresh(
        summaries: [SessionSummary]? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let sessions = summaries ?? SessionIndexStore().load()
        let sessionDays = Set(sessions.map { calendar.startOfDay(for: $0.createdAt) })

        var writtenIndices = Set<Int>()
        var missedIndices = Set<Int>()
        if let firstDay = sessionDays.min() {
            let today = calendar.startOfDay(for: now)
            let elapsedDays = calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0
            currentJourneyDay = min(JourneySojourn.totalDays, max(1, elapsedDays + 1))
            for index in 0..<currentJourneyDay {
                guard let day = calendar.date(byAdding: .day, value: index, to: firstDay) else { continue }
                if sessionDays.contains(day) {
                    writtenIndices.insert(index)
                } else {
                    missedIndices.insert(index)
                }
            }
        } else {
            currentJourneyDay = 1
        }

        #if DEBUG
        let debugExtraDays = UserDefaults.standard.integer(forKey: Self.debugExtraDaysKey)
        if debugExtraDays > 0 {
            for index in currentJourneyDay..<min(JourneySojourn.totalDays, currentJourneyDay + debugExtraDays) {
                writtenIndices.insert(index)
            }
            currentJourneyDay = min(JourneySojourn.totalDays, currentJourneyDay + debugExtraDays)
        }
        #endif
        writtenDayIndices = writtenIndices.filter { (0..<JourneySojourn.totalDays).contains($0) }
        missedDayIndices = missedIndices.filter { (0..<currentJourneyDay).contains($0) }
        completedDays = min(JourneySojourn.totalDays, writtenDayIndices.count)

        minutesWritten = Int(sessions.reduce(Int64(0)) { $0 + $1.durationMs } / 60_000)
        writingsCount = sessions.count
        streakDays = Self.streak(sessionDays: sessionDays, now: now, calendar: calendar)
    }

    /// Consecutive written days ending today or yesterday (a day in progress
    /// doesn't break its own streak).
    private static func streak(sessionDays: Set<Date>, now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        var cursor = sessionDays.contains(today)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var count = 0
        while sessionDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    // MARK: Celebration ledger (bloom + walk shown once per new day)

    func celebratedCount(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: Self.celebratedKey)
    }

    func markCelebrated(_ count: Int, defaults: UserDefaults = .standard) {
        defaults.set(count, forKey: Self.celebratedKey)
    }

    #if DEBUG
    /// Debug-only: pretend one more day was written, so the bloom + walk
    /// choreography and seam scrolling can be tested without waiting a day.
    func debugAdvanceDay() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Self.debugExtraDaysKey) + 1, forKey: Self.debugExtraDaysKey)
        refresh()
    }

    func debugResetJourney() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.debugExtraDaysKey)
        defaults.removeObject(forKey: Self.celebratedKey)
        refresh()
    }
    #endif
}
