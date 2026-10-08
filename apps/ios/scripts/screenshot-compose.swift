#!/usr/bin/env swift
//
//  screenshot-compose.swift
//  Anky — turns raw simulator captures into App Store marketing frames.
//
//  Deliberately dependency-free: CoreGraphics draws, CoreText sets the
//  headline, ImageIO writes the PNG. Everything it needs ships with macOS, so
//  the pipeline has nothing to install, pin, or keep up to date.
//
//  Each frame is the app's own paper and ink: a headline in the brand serif,
//  centered over the capture held in a drawn phone — see `Layout` below.
//
//  Usage:
//    swift screenshot-compose.swift <root> [--font "Fraunces72pt-Regular"]
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

// MARK: - Layout

/// The frame is the app's own surface: paper, ink, the brand serif, and the
/// capture held in a drawn phone. Nothing else competes with the screen.
enum Layout {
    /// 6.9-inch portrait, the native size an iPhone 16 Pro Max simulator emits.
    static let canvas = CGSize(width: 1320, height: 2868)

    /// AnkyLazure.swift: ankyPaper and ankyInk.
    static let background = CGColor(red: 0.965, green: 0.937, blue: 0.894, alpha: 1)
    static let ink = CGColor(red: 0.239, green: 0.216, blue: 0.310, alpha: 1)

    // The phone. Proportions follow an iPhone 16 Pro Max: a 440pt-wide display
    // with ~62pt corners, a thin black border, a titanium band around it.
    static let screenWidth: CGFloat = 968
    static let screenTop: CGFloat = 610
    static let screenCornerRadius: CGFloat = screenWidth * 62.0 / 440.0
    static let bezel: CGFloat = 21
    static let band: CGFloat = 7

    // The headline, centered in the space above the phone.
    static let headlineSize: CGFloat = 112
    static let minimumHeadlineSize: CGFloat = 70
    static let headlineLineHeight: CGFloat = 1.16
    static let headlineSideMargin: CGFloat = 96
    static let headlineZoneTop: CGFloat = 150
    static let headlineZoneBottomGap: CGFloat = 96
}

// MARK: - Fonts

/// Latin gets Fraunces, the face the app itself is set in. Devanagari and Han
/// need their own, because Fraunces has no glyphs for them and CoreText would
/// silently substitute something arbitrary.
enum FontPicker {
    static var latinCandidates = ["Fraunces72pt-Regular", "NewYork-Regular", "Georgia"]
    static let devanagariCandidates = ["KohinoorDevanagari-Medium", "Kohinoor Devanagari Medium",
                                       "DevanagariSangamMN", "Devanagari Sangam MN"]
    static let hanCandidates = ["STSongti-SC-Bold", "Songti SC Bold",
                                "PingFangSC-Medium", "PingFang SC Medium"]

    /// Fraunces ships inside the app, not with macOS; make it available to
    /// this process from the repo.
    static func registerBundledFonts(iosRoot: URL) {
        let fonts = iosRoot.appendingPathComponent("Anky/Fonts")
        let files = (try? FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

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

    /// Lays the headline out at a given size, honoring the fixture's explicit
    /// line breaks.
    private func lines(at size: CGFloat) throws -> [(CTLine, CGFloat)] {
        let font = try FontPicker.font(for: locale, size: size)
        return headline.components(separatedBy: "\n").map { text in
            let attributed = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor(cgColor: Layout.ink) ?? .black,
                .kern: -size * 0.012
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            return (line, CGFloat(width))
        }
    }

    /// The largest size at which the widest line still fits.
    private func fittedSize(maxWidth: CGFloat) throws -> CGFloat {
        var size = Layout.headlineSize
        while size > Layout.minimumHeadlineSize {
            let widest = try lines(at: size).map(\.1).max() ?? 0
            if widest <= maxWidth { return size }
            size -= 2
        }
        return Layout.minimumHeadlineSize
    }

    private func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    func compose(capture: CGImage) throws -> CGImage {
        let canvas = Layout.canvas
        // noneSkipLast: the App Store rejects screenshots with an alpha
        // channel, and this is what keeps one from ever existing.
        guard let context = CGContext(
            data: nil, width: Int(canvas.width), height: Int(canvas.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Failure("Could not create the drawing context.") }

        context.setFillColor(Layout.background)
        context.fill(CGRect(origin: .zero, size: canvas))

        // CoreGraphics origin is bottom-left; the layout is specified from
        // the top, so every rect is flipped once, here.
        func fromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: x, y: canvas.height - y - height, width: width, height: height)
        }

        // MARK: The phone

        let screenHeight = Layout.screenWidth * CGFloat(capture.height) / CGFloat(capture.width)
        let screen = fromTop(
            x: (canvas.width - Layout.screenWidth) / 2,
            y: Layout.screenTop,
            width: Layout.screenWidth,
            height: screenHeight
        )
        let body = screen.insetBy(dx: -Layout.bezel, dy: -Layout.bezel)
        let shell = body.insetBy(dx: -Layout.band, dy: -Layout.band)
        guard shell.minY >= 40 else {
            throw Failure("The capture is taller than the canvas allows — is the raw screenshot the right device?")
        }
        let bodyRadius = Layout.screenCornerRadius + Layout.bezel
        let shellRadius = bodyRadius + Layout.band
        let titanium = [
            CGColor(red: 0.80, green: 0.78, blue: 0.75, alpha: 1),
            CGColor(red: 0.56, green: 0.54, blue: 0.52, alpha: 1),
            CGColor(red: 0.74, green: 0.72, blue: 0.69, alpha: 1)
        ]

        // Side buttons first, so the band overlaps their inner halves.
        // (edge: -1 leading / +1 trailing; start and length as shares of height.)
        let buttons: [(edge: CGFloat, start: CGFloat, length: CGFloat)] = [
            (-1, 0.150, 0.034),   // action
            (-1, 0.215, 0.066),   // volume up
            (-1, 0.300, 0.066),   // volume down
            (1, 0.255, 0.105)     // side button
        ]
        context.setFillColor(titanium[1])
        for button in buttons {
            let height = shell.height * button.length
            let top = shell.maxY - shell.height * button.start - height
            let x = button.edge < 0 ? shell.minX - 5 : shell.maxX - 7
            context.addPath(rounded(CGRect(x: x, y: top, width: 12, height: height), 4))
            context.fillPath()
        }

        // The shell casts the only shadow in the frame.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -34),
            blur: 90,
            color: CGColor(red: 0.239, green: 0.216, blue: 0.310, alpha: 0.26)
        )
        context.setFillColor(titanium[1])
        context.addPath(rounded(shell, shellRadius))
        context.fillPath()
        context.restoreGState()

        // Titanium band: light catching the top and bottom edges.
        context.saveGState()
        context.addPath(rounded(shell, shellRadius))
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: titanium as CFArray,
            locations: [0, 0.5, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: shell.minX, y: shell.maxY),
                end: CGPoint(x: shell.maxX, y: shell.minY),
                options: []
            )
        }
        context.restoreGState()

        context.setFillColor(CGColor(red: 0.035, green: 0.035, blue: 0.045, alpha: 1))
        context.addPath(rounded(body, bodyRadius))
        context.fillPath()

        context.saveGState()
        context.addPath(rounded(screen, Layout.screenCornerRadius))
        context.clip()
        context.interpolationQuality = .high
        context.draw(capture, in: screen)
        context.restoreGState()

        // MARK: The headline

        let maxWidth = canvas.width - Layout.headlineSideMargin * 2
        let size = try fittedSize(maxWidth: maxWidth)
        let laid = try lines(at: size)
        let font = try FontPicker.font(for: locale, size: size)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let lineHeight = size * Layout.headlineLineHeight
        let blockHeight = ascent + descent + CGFloat(laid.count - 1) * lineHeight

        let zoneTop = Layout.headlineZoneTop
        let zoneBottom = Layout.screenTop - Layout.bezel - Layout.band - Layout.headlineZoneBottomGap
        guard blockHeight <= zoneBottom - zoneTop else {
            throw Failure("Headline does not fit above the phone (\(Int(blockHeight)) vs \(Int(zoneBottom - zoneTop))). Shorten the line or drop a break.")
        }
        // Centered in its zone, so one line and two lines both sit balanced.
        let blockTop = zoneTop + (zoneBottom - zoneTop - blockHeight) / 2
        var baseline = canvas.height - blockTop - ascent
        for (line, width) in laid {
            context.textPosition = CGPoint(x: (canvas.width - width) / 2, y: baseline)
            CTLineDraw(line, context)
            baseline -= lineHeight
        }

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
// <root> is apps/ios/AppStoreScreenshots; the app's fonts live beside it.
FontPicker.registerBundledFonts(iosRoot: root.deletingLastPathComponent())
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
