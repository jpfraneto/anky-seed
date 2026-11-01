//
//  LoomCarpet.swift
//  Anky
//
//  The carpet the writer weaves. The pattern is Anky at the loom, set as
//  cross-stitch on an 88 × 88 grid. It is woven the way cloth is woven:
//  from the bottom up, the shuttle crossing left, then right, then left.
//  Every character typed lays down a few stitches, so the people appear
//  first, then the loom, then Anky, then the eye, then the star.
//

import SwiftUI
import UIKit

enum LoomPalette {
    /// The night the carpets were stitched on.
    static let night = Color(.displayP3, red: 0.035, green: 0.043, blue: 0.118)
    static let nightDeep = Color(.displayP3, red: 0.020, green: 0.024, blue: 0.075)
    static let thread = Color(.displayP3, red: 0.953, green: 0.757, blue: 0.431)
    static let threadSoft = Color(.displayP3, red: 0.953, green: 0.757, blue: 0.431).opacity(0.62)
    static let threadFaint = Color(.displayP3, red: 0.953, green: 0.757, blue: 0.431).opacity(0.34)
}

/// The pattern, rendered once as stitched cloth.
struct LoomPattern {
    static let grid = 88
    static var stitchCount: Int { grid * grid }

    /// Renders every stitch for a carpet `side` points wide. Safe off the
    /// main thread.
    static func render(side: CGFloat, scale: CGFloat) -> UIImage? {
        guard let source = UIImage(named: "LoomCarpetSource")?.cgImage else { return nil }
        let n = grid
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let sampler = CGContext(
            data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        sampler.interpolationQuality = .high
        sampler.draw(source, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let raw = sampler.data else { return nil }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: n * n * 4)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let cell = side / CGFloat(n)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineWidth(max(0.6, cell * 0.27))
            let inset = cell * 0.17
            for row in 0..<n {
                for column in 0..<n {
                    // Bitmap memory runs top row first.
                    let i = (row * n + column) * 4
                    var r = CGFloat(pixels[i]) / 255
                    var g = CGFloat(pixels[i + 1]) / 255
                    var b = CGFloat(pixels[i + 2]) / 255
                    let luminance = 0.3 * r + 0.59 * g + 0.11 * b
                    // A hand's unevenness: each stitch a touch brighter or dimmer.
                    let jitter = 0.9 + 0.2 * CGFloat((row &* 73 &+ column &* 151) % 17) / 16
                    r = min(1, pow(r, 0.75) * 1.45 * jitter)
                    g = min(1, pow(g, 0.75) * 1.45 * jitter)
                    b = min(1, pow(b, 0.75) * 1.45 * jitter)
                    let alpha = 0.35 + 0.65 * min(1, luminance * 2.2)
                    cg.setStrokeColor(UIColor(displayP3Red: r, green: g, blue: b, alpha: alpha).cgColor)
                    let x = CGFloat(column) * cell
                    let y = CGFloat(row) * cell
                    cg.move(to: CGPoint(x: x + inset, y: y + inset))
                    cg.addLine(to: CGPoint(x: x + cell - inset, y: y + cell - inset))
                    cg.move(to: CGPoint(x: x + cell - inset, y: y + inset))
                    cg.addLine(to: CGPoint(x: x + inset, y: y + cell - inset))
                    cg.strokePath()
                }
            }
        }
    }

    /// Where the shuttle is after `woven` stitches, in unit coordinates.
    static func shuttle(after woven: Double) -> CGPoint {
        let n = Double(grid)
        let clamped = min(max(0, woven), n * n)
        let row = min(n - 1, floor(clamped / n))
        let along = clamped - row * n
        let leftToRight = Int(row) % 2 == 0
        let x = leftToRight ? along / n : 1 - along / n
        let y = 1 - (row + 0.5) / n
        return CGPoint(x: x, y: y)
    }
}

/// The woven part of the cloth: whole rows from the bottom, plus the row
/// the shuttle is crossing.
struct WovenRegion: Shape {
    var woven: Double

    var animatableData: Double {
        get { woven }
        set { woven = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let n = Double(LoomPattern.grid)
        let clamped = min(max(0, woven), n * n)
        let cell = rect.height / CGFloat(n)
        let fullRows = floor(clamped / n)
        let along = CGFloat(clamped - fullRows * n)
        var path = Path()
        if fullRows > 0 {
            let height = CGFloat(fullRows) * cell
            path.addRect(CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height))
        }
        if along > 0, fullRows < n {
            let y = rect.maxY - CGFloat(fullRows + 1) * cell
            let width = along * rect.width / CGFloat(n)
            let leftToRight = Int(fullRows) % 2 == 0
            let x = leftToRight ? rect.minX : rect.maxX - width
            path.addRect(CGRect(x: x, y: y, width: width, height: cell))
        }
        return path
    }
}

/// Each carpet size is stitched once per launch; the welcome's screens
/// share it, so the cloth never flickers between them.
@MainActor
private enum LoomClothCache {
    static var images: [Int: UIImage] = [:]
}

/// The loom itself: the warp strung and waiting, and the weft the writer
/// has laid across it.
struct LoomCarpetView: View {
    /// Stitches laid so far (0…stitchCount).
    let woven: Double
    /// The shuttle glows while it is moving.
    var weaving: Bool = false
    /// 0…1: how much of the warp has been strung (the loom being set up).
    var warpStrung: Double = 1

    @State private var cloth: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                warp(side: side)

                if let cloth {
                    Image(uiImage: cloth)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: side, height: side)
                        .mask(WovenRegion(woven: woven).frame(width: side, height: side))
                }

                if weaving, woven > 0, woven < Double(LoomPattern.stitchCount) {
                    let point = LoomPattern.shuttle(after: woven)
                    Circle()
                        .fill(LoomPalette.thread)
                        .frame(width: 5, height: 5)
                        .shadow(color: LoomPalette.thread.opacity(0.9), radius: 6)
                        .position(x: point.x * side, y: point.y * side)
                        .animation(.easeOut(duration: 0.3), value: woven)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: Int(side)) {
                guard side > 0 else { return }
                let key = Int(side * displayScale)
                if let cached = LoomClothCache.images[key] {
                    cloth = cached
                    return
                }
                let scale = displayScale
                let rendered = await Task.detached(priority: .userInitiated) {
                    LoomPattern.render(side: side, scale: scale)
                }.value
                LoomClothCache.images[key] = rendered
                cloth = rendered
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// One faint thread per column, strung from the top down.
    private func warp(side: CGFloat) -> some View {
        Canvas { context, size in
            let n = LoomPattern.grid
            let cell = size.width / CGFloat(n)
            let strung = CGFloat(min(1, max(0, warpStrung)))
            var path = Path()
            for column in stride(from: 0, to: n, by: 2) {
                // Threads drop in from the middle outwards.
                let distance = abs(CGFloat(column) - CGFloat(n) / 2) / (CGFloat(n) / 2)
                let local = min(1, max(0, (strung * 1.6) - distance * 0.6))
                guard local > 0 else { continue }
                let x = (CGFloat(column) + 0.5) * cell
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height * local))
            }
            context.stroke(path, with: .color(LoomPalette.thread.opacity(0.2)), lineWidth: 0.6)
        }
        .frame(width: side, height: side)
    }
}
