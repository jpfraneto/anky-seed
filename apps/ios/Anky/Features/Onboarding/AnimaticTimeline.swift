import Foundation
import SwiftUI
import UIKit

/// The approved cut, decoded from the bundled TIMELINE.json. The JSON is the
/// single source of truth — numbers are never transcribed into code, so the
/// cut can be tuned without a code change (implementation pack rule).
struct AnimaticTimeline: Decodable {
    struct Meta: Decodable {
        let total_ms: Int
        let story_ms: Int
    }

    struct KenBurns: Decodable {
        let scale_from: CGFloat
        let scale_to: CGFloat
        let anchor: [CGFloat]

        var unitAnchor: UnitPoint {
            UnitPoint(x: anchor.first ?? 0.5, y: anchor.count > 1 ? anchor[1] : 0.5)
        }
    }

    struct Beat: Decodable {
        let n: Int
        let asset: String
        let start_ms: Int
        let end_ms: Int
        let fade_in_ms: Int
        let kenburns: KenBurns
        let special: String?

        var isCarveReveal: Bool { special == "carve_reveal" }
        var durationSeconds: Double { Double(end_ms - start_ms) / 1000 }
    }

    struct CarveStep: Decodable {
        let t_ms: Int
        let reveal_to: CGFloat
    }

    struct CarveReveal: Decodable {
        let steps: [CarveStep]
        let stroke_ease_ms: Int
    }

    struct Handoff: Decodable {
        let lazure_dissolve_start_ms: Int
        let lazure_dissolve_duration_ms: Int
        let typing_start_ms: Int
        let question: String
        let per_char_delays_ms: [Int]
        let keyboard_rise_delay_after_typing_ms: Int
    }

    let meta: Meta
    let beats: [Beat]
    let carve_reveal: CarveReveal
    let handoff: Handoff

    /// The quiet skip affordance appears here (implementation pack §6).
    var skipAppearsAtMs: Int { 3000 }

    static func load(bundle: Bundle = .main) -> AnimaticTimeline? {
        guard let url = bundle.url(forResource: "TIMELINE", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(AnimaticTimeline.self, from: data)
    }
}

/// The nine approved frames, decoded before t0 so the first frame renders
/// instantly on cold launch. The opening frame is prepared synchronously —
/// it must be on screen within 300ms — and the rest decode off-main.
final class AnimaticFrameStore {
    private var images: [String: UIImage] = [:]

    init(openingAsset: String = "01_blank_geshtu") {
        if let first = UIImage(named: openingAsset) {
            images[openingAsset] = first.preparingForDisplay() ?? first
        }
        let remaining = [
            "02_hands_cradle", "03a_carve_pre", "03b_carve_post",
            "04_ancient_writing", "05_recognition", "06_gift_carving",
            "07_offering", "08_pushin"
        ]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for name in remaining {
                guard let image = UIImage(named: name) else { continue }
                let prepared = image.preparingForDisplay() ?? image
                DispatchQueue.main.async {
                    self?.images[name] = prepared
                }
            }
        }
    }

    func image(_ name: String) -> UIImage {
        if let prepared = images[name] {
            return prepared
        }
        // Decode-on-demand fallback: correctness over the preload guarantee.
        let image = UIImage(named: name) ?? UIImage()
        images[name] = image
        return image
    }
}
