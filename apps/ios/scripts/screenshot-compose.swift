#!/usr/bin/env swift
//
//  screenshot-compose.swift
//  Anky — turns raw simulator captures into App Store marketing frames.
//
//  Deliberately dependency-free: CoreGraphics draws, CoreText sets the
//  headline, ImageIO writes the PNG. Everything it needs ships with macOS, so
//  the pipeline has nothing to install, pin, or keep up to date.
//
//  The layout is measured from Anky's five existing screenshots (1242x2688)
//  and scaled to the 6.9-inch canvas — see `Layout` below for the numbers and
//  where each came from.
//
//  Usage:
//    swift screenshot-compose.swift <root> [--font "Noteworthy Bold"]
//
//  <root> is AppStoreScreenshots/. Reads raw/<locale>/NN-scene.png plus
//  locales.json and fixtures/, writes final/<locale>/NN-scene.png,
//  contact/<locale>.png and manifest.json.
//
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - Layout, measured from the reference set

enum Layout {
    /// 6.9-inch portrait, the native size an iPhone 16 Pro Max simulator emits.
    static let canvas = CGSize(width: 1320, height: 2868)
    /// The reference screenshots were 1242x2688; every measurement below is
    /// the reference value times this.
    static let referenceScale: CGFloat = canvas.width / 1242.0

    /// Sampled from the reference background, which is flat across all five.
    static let background = CGColor(red: 243/255, green: 208/255, blue: 102/255, alpha: 1)
    static let ink = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

    static let sideMargin: CGFloat = 178.0 * referenceScale        // 189
    static let headlineTop: CGFloat = 176.0 * referenceScale       // 187
    static let captureTop: CGFloat = 545.0 * referenceScale        // 579
    static let captureWidth: CGFloat = 886.0 * referenceScale      // 942
    /// The reference cards are plain rectangles; measured corner radius was
    /// under 5px, i.e. none. Kept square deliberately.
    static let captureCornerRadius: CGFloat = 0.0

    static let headlineSize: CGFloat = 118.0 * referenceScale
    static let headlineLineHeight: CGFloat = 1.30
    /// Never let a long localized line run into the margin: the compositor
    /// shrinks the face a little rather than clipping or rewrapping badly.
    static let minimumHeadlineSize: CGFloat = 76.0 * referenceScale
    /// The headline must never reach the capture.
    static let headlineBottomGuard: CGFloat = 24.0 * referenceScale
}

// MARK: - Fonts

/// Latin gets the marketing face; Devanagari and Han need their own, because
/// a handwriting face has no glyphs for them and CoreText would silently
/// substitute something arbitrary.
enum FontPicker {
    static var latinCandidates = ["Noteworthy Bold", "Noteworthy-Bold"]
    static let devanagariCandidates = ["Kohinoor Devanagari Semibold", "KohinoorDevanagari-Semibold",
                                       "Devanagari Sangam MN Bold", "DevanagariSangamMN-Bold"]
    static let hanCandidates = ["PingFang SC Semibold", "PingFangSC-Semibold",
                                "Heiti SC Medium", "STHeitiSC-Medium"]

    static func font(for locale: String, size: CGFloat) throws -> CTFont {
        let candidates: [String]
        switch locale {
        case "hi": candidates = devanagariCandidates
        case let l where l.hasPrefix("zh"): candidates = hanCandidates
        default: candidates = latinCandidates
        }
        for name in candidates {
            if let font = NSFont(name: name, size: size) {
                return font as CTFont
            }
        }
        throw Failure("No headline font installed for '\(locale)'. Tried: \(candidates.joined(separator: ", ")).")
    }
}

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Drawing

struct Composer {
    let locale: String
    let headline: String

    /// Lays the headline out at the largest size that fits the content width,
    /// honoring the fixture's explicit line breaks.
    private func lines(at size: CGFloat) throws -> [(CTLine, CGFloat)] {
        let font = try FontPicker.font(for: locale, size: size)
        return headline.components(separatedBy: "\n").map { text in
            let attributed = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor.black
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            return (line, CGFloat(width))
        }
    }

    private func fittedSize(maxWidth: CGFloat) throws -> CGFloat {
        var size = Layout.headlineSize
        while size > Layout.minimumHeadlineSize {
            let widest = try lines(at: size).map(\.1).max() ?? 0
            if widest <= maxWidth { return size }
            size -= 2
        }
        return Layout.minimumHeadlineSize
    }

    func compose(capture: CGImage) throws -> CGImage {
        let width = Int(Layout.canvas.width)
        let height = Int(Layout.canvas.height)
        // noneSkipLast: the App Store rejects screenshots with an alpha
        // channel, and this is what keeps one from ever existing.
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Failure("Could not create the drawing context.") }

        context.setFillColor(Layout.background)
        context.fill(CGRect(origin: .zero, size: Layout.canvas))

        let contentWidth = Layout.canvas.width - Layout.sideMargin * 2
        let size = try fittedSize(maxWidth: contentWidth)
        let laid = try lines(at: size)
        let lineHeight = size * Layout.headlineLineHeight

        // CoreGraphics origin is bottom-left; the layout is specified from the
        // top, so every y is flipped once, here. The first baseline uses the
        // font's real ascent — using the point size instead sits the block low.
        let font = try FontPicker.font(for: locale, size: size)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        var baseline = Layout.canvas.height - Layout.headlineTop - ascent
        for (line, _) in laid {
            context.textPosition = CGPoint(x: Layout.sideMargin, y: baseline)
            CTLineDraw(line, context)
            baseline -= lineHeight
        }

        let headlineBottom = Layout.headlineTop + ascent + descent
            + CGFloat(laid.count - 1) * lineHeight
        guard headlineBottom + Layout.headlineBottomGuard <= Layout.captureTop else {
            throw Failure("Headline overruns the capture (bottom \(Int(headlineBottom)) vs top \(Int(Layout.captureTop))). Shorten the line or add a break.")
        }

        let captureHeight = Layout.captureWidth * CGFloat(capture.height) / CGFloat(capture.width)
        let captureRect = CGRect(
            x: (Layout.canvas.width - Layout.captureWidth) / 2,
            y: Layout.canvas.height - Layout.captureTop - captureHeight,
            width: Layout.captureWidth,
            height: captureHeight
        )
        guard captureRect.minY >= 0 else {
            throw Failure("The capture is taller than the canvas allows — is the raw screenshot the right device?")
        }
        context.saveGState()
        if Layout.captureCornerRadius > 0 {
            let path = CGPath(roundedRect: captureRect,
                              cornerWidth: Layout.captureCornerRadius,
                              cornerHeight: Layout.captureCornerRadius, transform: nil)
            context.addPath(path)
            context.clip()
        }
        context.interpolationQuality = .high
        context.draw(capture, in: captureRect)
        context.restoreGState()

        guard let image = context.makeImage() else { throw Failure("Could not render the frame.") }
        return image
    }
}

// MARK: - IO

func readImage(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw Failure("Could not read \(url.lastPathComponent).")
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw Failure("Could not open \(url.path) for writing.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw Failure("Could not finalize \(url.path).")
    }
}

/// The App Store's two hard rules, checked on the bytes we actually wrote.
func validate(_ url: URL) throws -> (width: Int, height: Int, hasAlpha: Bool) {
    let image = try readImage(url)
    let info = image.alphaInfo
    let hasAlpha = !(info == .none || info == .noneSkipLast || info == .noneSkipFirst)
    guard image.width == Int(Layout.canvas.width), image.height == Int(Layout.canvas.height) else {
        throw Failure("\(url.lastPathComponent) is \(image.width)x\(image.height); expected \(Int(Layout.canvas.width))x\(Int(Layout.canvas.height)).")
    }
    guard !hasAlpha else { throw Failure("\(url.lastPathComponent) has an alpha channel.") }
    return (image.width, image.height, hasAlpha)
}

/// Five frames side by side, so a locale can be judged as a set rather than
/// one image at a time.
func contactSheet(_ images: [CGImage], to url: URL) throws {
    let thumbWidth: CGFloat = 520.0
    let gutter: CGFloat = 28.0
    let thumbHeight = thumbWidth * Layout.canvas.height / Layout.canvas.width
    let width = Int(thumbWidth * CGFloat(images.count) + gutter * CGFloat(images.count + 1))
    let height = Int(thumbHeight + gutter * 2)
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw Failure("Could not create the contact sheet context.")
    }
    context.setFillColor(CGColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    context.interpolationQuality = .high
    for (index, image) in images.enumerated() {
        let x = gutter + CGFloat(index) * (thumbWidth + gutter)
        context.draw(image, in: CGRect(x: x, y: gutter, width: thumbWidth, height: thumbHeight))
    }
    guard let sheet = context.makeImage() else { throw Failure("Could not render the contact sheet.") }
    try writePNG(sheet, to: url)
}

// MARK: - Driver

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: screenshot-compose.swift <AppStoreScreenshots dir> [--font NAME]\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1])
if let fontIndex = arguments.firstIndex(of: "--font"), fontIndex + 1 < arguments.count {
    FontPicker.latinCandidates = [arguments[fontIndex + 1]] + FontPicker.latinCandidates
}

struct LocaleRow: Decodable {
    let appLocale: String
    let appStoreLocale: String
    let languageName: String
}
struct LocaleManifest: Decodable { let locales: [LocaleRow] }

let sceneOrder = ["ritual", "simplicity", "reflection", "archive", "recording"]

do {
    let manifestData = try Data(contentsOf: root.appendingPathComponent("locales.json"))
    let manifest = try JSONDecoder().decode(LocaleManifest.self, from: manifestData)

    var records: [[String: Any]] = []
    var failures: [String] = []
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let device = ProcessInfo.processInfo.environment["ANKY_SCREENSHOT_DEVICE"] ?? "unknown simulator"

    for row in manifest.locales {
        let fixtureURL = root.appendingPathComponent("fixtures/\(row.appLocale).json")
        let fixture = try JSONSerialization.jsonObject(with: try Data(contentsOf: fixtureURL)) as? [String: Any] ?? [:]
        let headlines = fixture["headlines"] as? [String: String] ?? [:]

        var composed: [CGImage] = []
        for (index, scene) in sceneOrder.enumerated() {
            let name = String(format: "%02d-%@.png", index + 1, scene)
            let rawURL = root.appendingPathComponent("raw/\(row.appStoreLocale)/\(name)")
            let finalURL = root.appendingPathComponent("final/\(row.appStoreLocale)/\(name)")

            guard FileManager.default.fileExists(atPath: rawURL.path) else {
                failures.append("\(row.appStoreLocale)/\(name): no raw capture")
                records.append(["locale": row.appStoreLocale, "languageName": row.languageName,
                                "scene": scene, "file": name, "success": false,
                                "error": "missing raw capture", "generatedAt": timestamp])
                continue
            }
            guard let headline = headlines[scene] else {
                failures.append("\(row.appStoreLocale)/\(name): no headline in fixture")
                records.append(["locale": row.appStoreLocale, "languageName": row.languageName,
                                "scene": scene, "file": name, "success": false,
                                "error": "missing headline", "generatedAt": timestamp])
                continue
            }

            do {
                let capture = try readImage(rawURL)
                let frame = try Composer(locale: row.appLocale, headline: headline).compose(capture: capture)
                try writePNG(frame, to: finalURL)
                let checked = try validate(finalURL)
                composed.append(frame)
                records.append([
                    "locale": row.appStoreLocale,
                    "appLocale": row.appLocale,
                    "languageName": row.languageName,
                    "scene": scene,
                    "file": "final/\(row.appStoreLocale)/\(name)",
                    "headline": headline.replacingOccurrences(of: "\n", with: " "),
                    "width": checked.width,
                    "height": checked.height,
                    "format": "png",
                    "hasAlpha": checked.hasAlpha,
                    "sourceDevice": device,
                    "generatedAt": timestamp,
                    "success": true
                ])
                print("  ✓ \(row.appStoreLocale)/\(name)")
            } catch {
                failures.append("\(row.appStoreLocale)/\(name): \(error.localizedDescription)")
                records.append(["locale": row.appStoreLocale, "languageName": row.languageName,
                                "scene": scene, "file": name, "success": false,
                                "error": error.localizedDescription, "generatedAt": timestamp])
                print("  ✗ \(row.appStoreLocale)/\(name): \(error.localizedDescription)")
            }
        }

        if composed.count == sceneOrder.count {
            try contactSheet(composed, to: root.appendingPathComponent("contact/\(row.appStoreLocale).png"))
        } else if !composed.isEmpty {
            failures.append("\(row.appStoreLocale): only \(composed.count) of \(sceneOrder.count) scenes composed")
        }
    }

    let manifestOut: [String: Any] = [
        "generatedAt": timestamp,
        "canvas": ["width": Int(Layout.canvas.width), "height": Int(Layout.canvas.height)],
        "sourceDevice": device,
        "screenshots": records,
        "failures": failures
    ]
    let data = try JSONSerialization.data(withJSONObject: manifestOut, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: root.appendingPathComponent("manifest.json"))

    if failures.isEmpty {
        print("composed \(records.count) images")
    } else {
        FileHandle.standardError.write(Data(("compositor failures:\n  " + failures.joined(separator: "\n  ") + "\n").utf8))
        exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("compositor error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
