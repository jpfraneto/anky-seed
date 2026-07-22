import SwiftUI
import UIKit

/// Beat 3: the knife carves "anky" stroke by stroke. Two identical plates —
/// the word cloned out below, the carved word above — with the top plate
/// masked by a rectangle whose width steps through the timeline's reveal
/// fractions. The fractions are of IMAGE width, so both plates are laid out
/// at their explicit aspect-fill size and the mask lives in that same image
/// space; outside the word region the plates are identical, making the
/// full-height sweep invisible except where the letters live.
struct CarveRevealView: View {
    let pre: UIImage
    let post: UIImage
    /// Revealed fraction of the image width, animated by the driver through
    /// the halting carve steps — the anky protocol rhythm applied to a knife.
    let revealFraction: CGFloat
    let containerSize: CGSize

    var body: some View {
        let display = Self.coverSize(image: pre.size, in: containerSize)
        ZStack {
            Image(uiImage: pre)
                .resizable()
                .frame(width: display.width, height: display.height)
            Image(uiImage: post)
                .resizable()
                .frame(width: display.width, height: display.height)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: display.width * revealFraction, height: display.height)
                        .frame(width: display.width, alignment: .leading)
                }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .position(x: containerSize.width / 2, y: containerSize.height / 2)
    }

    static func coverSize(image: CGSize, in container: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return container }
        let scale = max(container.width / image.width, container.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}
