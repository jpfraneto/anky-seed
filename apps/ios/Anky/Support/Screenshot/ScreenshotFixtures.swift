//
//  ScreenshotFixtures.swift
//  Anky — the content the marketing screenshots are made of.
//
//  One bundled JSON holds every locale's writings, reflection, archive column
//  and headlines. It is generated from the per-locale sources in
//  `AppStoreScreenshots/fixtures/` by `scripts/assemble-screenshot-fixtures.rb`
//  — edit those, not this bundle.
//
//  Everything here is authored copy, not translated copy: each locale's
//  writing was written in that language, so the screenshots read like someone
//  actually sat down and wrote in it. Nothing in this file is production
//  localization; it never reaches a writer's screen outside screenshot mode.
//
#if DEBUG
import Foundation

struct ScreenshotFixtureBundle: Decodable {
    let version: Int
    let scenes: [String]
    let locales: [String: ScreenshotLocaleFixture]
}

struct ScreenshotLocaleFixture: Decodable {
    struct Writing: Decodable {
        let elapsedMs: Int64
        let text: String
    }

    struct Feature: Decodable {
        let date: Date
        let text: String
        let reflection: String
    }

    struct ArchiveEntry: Decodable {
        let date: Date
        let text: String
        let reflected: Bool
    }

    let appLocale: String
    let appStoreLocale: String
    let languageName: String
    let simulatorLanguage: String
    let simulatorLocale: String
    let keyboards: [String]
    let headlines: [String: String]
    let ritual: Writing
    let simplicity: Writing
    let feature: Feature
    let archive: [ArchiveEntry]
}

enum ScreenshotFixtures {

    enum LoadError: LocalizedError {
        case missingBundleResource
        case undecodable(String)
        case unknownLocale(String, available: [String])

        var errorDescription: String? {
            switch self {
            case .missingBundleResource:
                return "ScreenshotFixtures.json is not in the app bundle — check the Resources build phase."
            case .undecodable(let detail):
                return "ScreenshotFixtures.json could not be decoded: \(detail)"
            case .unknownLocale(let code, let available):
                return "No fixture for locale '\(code)'. Available: \(available.sorted().joined(separator: ", "))."
            }
        }
    }

    private static var cached: ScreenshotFixtureBundle?

    static func bundleContents() throws -> ScreenshotFixtureBundle {
        if let cached { return cached }
        guard let url = Bundle.main.url(forResource: "ScreenshotFixtures", withExtension: "json") else {
            throw LoadError.missingBundleResource
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode(ScreenshotFixtureBundle.self, from: try Data(contentsOf: url))
            cached = decoded
            return decoded
        } catch {
            throw LoadError.undecodable(String(describing: error))
        }
    }

    /// The fixture for one locale. Falls back from a regional code to its
    /// language (`es-419` → `es`) but never to English: a silent English
    /// screenshot filed under another locale is the exact defect this whole
    /// pipeline exists to prevent.
    static func locale(_ code: String) throws -> ScreenshotLocaleFixture {
        let contents = try bundleContents()
        if let exact = contents.locales[code] { return exact }
        let base = code.split(separator: "-").first.map(String.init) ?? code
        if let byLanguage = contents.locales[base] { return byLanguage }
        if let byPrefix = contents.locales.first(where: { $0.key.hasPrefix(base + "-") })?.value {
            return byPrefix
        }
        throw LoadError.unknownLocale(code, available: Array(contents.locales.keys))
    }
}
#endif
