import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Renders one painting package at a reveal progress.
///
/// iOS 17+: the Metal `paintingReveal` layer shader over the underdrawing —
/// 60fps, animatable, wet-edged. iOS 16: a Core Image `CIBlendWithMask`
/// composite re-rendered at discrete steps and crossfaded (no wet edge).
struct PaintingRevealCanvas: View {
    let assets: PaintingRevealAssets
    var progress: Double

    var body: some View {
        if #available(iOS 17, *) {
            ShaderRevealView(assets: assets, progress: progress)
        } else {
            FallbackRevealView(assets: assets, progress: progress)
        }
    }
}

/// The decoded images of one package, loaded once and shared by every
/// surface that shows the painting (main page, ceremony, gallery).
final class PaintingRevealAssets {
    let package: PaintingPackage
    let underdrawing: UIImage
    let final: UIImage
    let revealMap: UIImage

    init?(package: PaintingPackage) {
        guard
            let underdrawing = UIImage(contentsOfFile: package.underdrawingURL.path),
            let final = UIImage(contentsOfFile: package.finalURL.path),
            let revealMap = UIImage(contentsOfFile: package.revealMapURL.path)
        else {
            return nil
        }
        self.package = package
        self.underdrawing = underdrawing
        self.final = final
        self.revealMap = revealMap
    }
}

// MARK: - iOS 17 Metal path

@available(iOS 17, *)
private struct ShaderRevealView: View {
    let assets: PaintingRevealAssets
    var progress: Double

    var body: some View {
        AnimatableShaderReveal(assets: assets, progress: progress)
    }
}

@available(iOS 17, *)
private struct AnimatableShaderReveal: View, Animatable {
    let assets: PaintingRevealAssets
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        // RenderBox permits one texture argument per shader, so the reveal
        // composites as a stack: underdrawing below, final above with its
        // alpha driven by the reveal map + progress.
        ZStack {
            Image(uiImage: assets.underdrawing)
                .resizable()
            Image(uiImage: assets.final)
                .resizable()
                .layerEffect(
                    ShaderLibrary.paintingRevealMask(
                        .image(Image(uiImage: assets.revealMap)),
                        .boundingRect,
                        .float(Float(progress)),
                        .float(0.012) // wet-edge feather in map units
                    ),
                    maxSampleOffset: .zero
                )
        }
    }
}

// MARK: - iOS 16 Core Image fallback

private struct FallbackRevealView: View {
    let assets: PaintingRevealAssets
    var progress: Double

    @State private var rendered: UIImage?
    @State private var renderedStep = -1

    private var step: Int {
        Int((progress * 100).rounded())
    }

    var body: some View {
        ZStack {
            Image(uiImage: assets.underdrawing)
                .resizable()
            if let rendered {
                Image(uiImage: rendered)
                    .resizable()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .onAppear { renderIfNeeded() }
        .onChange(of: step) { _ in renderIfNeeded() }
    }

    private func renderIfNeeded() {
        let currentStep = step
        guard currentStep != renderedStep else { return }
        renderedStep = currentStep
        let renderer = FallbackRevealRenderer.shared
        let assets = assets
        Task.detached(priority: .userInitiated) {
            let image = renderer.render(assets: assets, progress: Double(currentStep) / 100)
            await MainActor.run {
                if renderedStep == currentStep {
                    rendered = image
                }
            }
        }
    }
}

/// Thresholds the reveal map at `progress` and blends final over underdrawing.
final class FallbackRevealRenderer {
    static let shared = FallbackRevealRenderer()

    private let context = CIContext(options: [.cacheIntermediates: false])

    func render(assets: PaintingRevealAssets, progress: Double) -> UIImage? {
        guard
            let finalCI = CIImage(image: assets.final),
            let underCI = CIImage(image: assets.underdrawing),
            let mapCI = CIImage(image: assets.revealMap)
        else {
            return nil
        }

        // mask = clamp((progress - map) * gain): white where paint arrived.
        let gain: CGFloat = 60
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = mapCI
        matrix.rVector = CIVector(x: -gain, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: -gain, y: 0, z: 0, w: 0)
        matrix.bVector = CIVector(x: -gain, y: 0, z: 0, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        let bias = CGFloat(progress) * gain
        matrix.biasVector = CIVector(x: bias, y: bias, z: bias, w: 1)
        guard let mask = matrix.outputImage?.clamped(to: mapCI.extent) else {
            return nil
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = finalCI
        blend.backgroundImage = underCI.transformed(
            by: scaleTransform(from: underCI.extent, to: finalCI.extent)
        )
        blend.maskImage = mask.transformed(
            by: scaleTransform(from: mapCI.extent, to: finalCI.extent)
        )

        guard
            let output = blend.outputImage,
            let cgImage = context.createCGImage(output, from: finalCI.extent)
        else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func scaleTransform(from: CGRect, to: CGRect) -> CGAffineTransform {
        guard from.width > 0, from.height > 0 else { return .identity }
        return CGAffineTransform(
            scaleX: to.width / from.width,
            y: to.height / from.height
        )
    }
}
