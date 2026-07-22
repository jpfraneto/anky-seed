import SwiftUI
import UIKit

/// The nine beat layers of the animatic, stacked in story order. Each beat is
/// an aspect-filled still with a linear Ken Burns move; crossfades come from
/// each layer fading in over the one below, and the 8.6s time cut is the one
/// layer whose opacity switches with no animation at all (fade_in_ms == 0 —
/// intentional and non-negotiable).
struct AnimaticStage: View {
    let timeline: AnimaticTimeline
    let frames: AnimaticFrameStore
    /// Beats whose start time has passed, set by the driver. A beat animates
    /// its own fade and zoom the moment it enters this set.
    let startedBeats: Set<Int>
    /// Beat 3's revealed fraction, stepped by the driver.
    let carveFraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // The ground beneath the first fade-in: near-black, so the
                // opening frame breathes out of darkness, not out of paper.
                Color(.displayP3, red: 0.04, green: 0.03, blue: 0.05)
                ForEach(timeline.beats, id: \.n) { beat in
                    beatLayer(beat, size: geo.size)
                }
            }
            .clipped()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func beatLayer(_ beat: AnimaticTimeline.Beat, size: CGSize) -> some View {
        let started = startedBeats.contains(beat.n)
        Group {
            if beat.isCarveReveal {
                CarveRevealView(
                    pre: frames.image("03a_carve_pre"),
                    post: frames.image("03b_carve_post"),
                    revealFraction: carveFraction,
                    containerSize: size
                )
            } else {
                filledImage(frames.image(beat.asset), size: size)
            }
        }
        .scaleEffect(
            started ? beat.kenburns.scale_to : beat.kenburns.scale_from,
            anchor: beat.kenburns.unitAnchor
        )
        // The zoom runs the beat's length plus a 600ms tail so it never
        // visibly stops before the next beat has fully covered it.
        .animation(.linear(duration: beat.durationSeconds + 0.6), value: started)
        .opacity(started ? 1 : 0)
        .animation(
            beat.fade_in_ms == 0 ? nil : .linear(duration: Double(beat.fade_in_ms) / 1000),
            value: started
        )
    }

    private func filledImage(_ image: UIImage, size: CGSize) -> some View {
        let display = CarveRevealView.coverSize(image: image.size, in: size)
        return Image(uiImage: image)
            .resizable()
            .frame(width: display.width, height: display.height)
            .frame(width: size.width, height: size.height)
            .position(x: size.width / 2, y: size.height / 2)
    }
}
