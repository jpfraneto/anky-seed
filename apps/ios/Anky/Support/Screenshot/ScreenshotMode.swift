//
//  ScreenshotMode.swift
//  Anky — deterministic App Store screenshot staging.
//
//  Marketing screenshots have to show the real app in a real state, and the
//  same state every single time, in every language. This is the switch that
//  makes that possible: a launch-argument-only mode that seeds the app's own
//  stores with fixture content, parks the world on one scene, and then tells
//  the capture script — through a file, not a guess — that the frame is ready.
//
//  Three guarantees, in order of importance:
//
//  1. It cannot run in a shipping build. The whole file is `#if DEBUG`, and
//     even in a debug build nothing happens unless an explicit launch
//     argument asks for it. An ordinary launch — debug or release — never
//     touches a line of this.
//  2. It never guesses. Every scene loads from `ScreenshotFixtures.json`;
//     a missing locale or scene is a hard failure written to the signal file,
//     not a silently empty screen.
//  3. It is not UI automation. Nothing here types, taps, or waits on a
//     hittable element. State goes in through the same stores the app writes
//     to itself, which means the capture exercises the real read paths.
//
#if DEBUG
import Foundation

enum ScreenshotMode {

    /// The five canonical marketing scenes, in App Store order.
    enum Scene: String, CaseIterable {
        case ritual
        case simplicity
        case reflection
        case archive
        case recording

        /// Zero-padded so the App Store ordering is obvious on disk.
        var fileNumber: String {
            guard let index = Scene.allCases.firstIndex(of: self) else { return "00" }
            return String(format: "%02d", index + 1)
        }
    }

    // MARK: - Activation

    /// Launch arguments (`-KEY VALUE`) land in UserDefaults' argument domain;
    /// environment variables are honored too so the mode works under both
    /// `simctl launch` and an Xcode scheme.
    private static func value(_ key: String) -> String? {
        if let argument = UserDefaults.standard.string(forKey: key), !argument.isEmpty {
            return argument
        }
        if let environment = ProcessInfo.processInfo.environment[key], !environment.isEmpty {
            return environment
        }
        return nil
    }

    /// True only when the launch explicitly asked for screenshot staging.
    static var isActive: Bool {
        guard let raw = value("ANKY_SCREENSHOT_MODE")?.lowercased() else { return false }
        return raw == "yes" || raw == "1" || raw == "true"
    }

    /// The scene this launch is staging. Nil (with the mode on) is a failure,
    /// not a default — a screenshot of the wrong surface is worse than none.
    static var scene: Scene? {
        value("ANKY_SCREENSHOT_SCENE").flatMap(Scene.init(rawValue:))
    }

    /// The fixture locale, e.g. `en`, `es`, `zh-Hans`. Falls back to the app's
    /// own resolved language so a locale-less launch still shows real copy.
    static var localeCode: String {
        if let explicit = value("ANKY_SCREENSHOT_LOCALE") { return explicit }
        return Bundle.main.preferredLocalizations.first ?? "en"
    }

    // MARK: - The ready signal

    /// Where the capture script looks. Written exactly once per launch, after
    /// the scene has been composed and the run loop has had frames to settle.
    /// The script polls for this instead of sleeping a hopeful two seconds.
    static var signalURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("anky-screenshot-signal.json")
    }

    static func clearSignal() {
        try? FileManager.default.removeItem(at: signalURL)
    }

    static func signalReady(scene: Scene, locale: String, detail: [String: String] = [:]) {
        write(["status": "ready", "scene": scene.rawValue, "locale": locale].merging(detail) { current, _ in current })
    }

    /// Loud failure. The script treats any non-"ready" status as fatal for
    /// that locale/scene pair rather than capturing whatever happens to be on
    /// screen.
    static func signalFailure(_ reason: String) {
        write([
            "status": "failed",
            "scene": scene?.rawValue ?? "unknown",
            "locale": localeCode,
            "reason": reason
        ])
        NSLog("[anky-screenshot] FAILED: %@", reason)
    }

    private static func write(_ payload: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            return
        }
        try? data.write(to: signalURL, options: [.atomic])
    }
}
#endif
