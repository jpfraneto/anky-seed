import XCTest

/// Real-device checks for what the simulator cannot prove: camera capture,
/// and voice that keeps recording while the app is in the background (the
/// same audio background mode a locked phone in a pocket relies on).
///
/// Run on a connected, unlocked iPhone:
///   xcodebuild test -project Anky.xcodeproj -scheme Anky \
///     -destination id=<device> -only-testing:AnkyUITests -allowProvisioningUpdates
///
/// The test cleans up after itself: the session it creates is deleted.
final class AnkyDeviceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Permission prompts (camera, microphone, notifications) are accepted.
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow", "OK", "Allow While Using App"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
    }

    func testCameraAndBackgroundVoiceInOneSession() throws {
        // A session left open by an earlier run is ended first.
        if app.buttons["End session"].waitForExistence(timeout: 3) {
            endSessionAndCloseMemory(deleting: true)
        }

        // 1. Camera.
        let record = app.buttons["Record"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10), "threshold shows Record")
        record.tap()
        let start = app.buttons["Start recording"]
        for _ in 0..<10 where !(start.exists && start.isEnabled) {
            app.tap() // lets the interruption monitor answer permission prompts
            sleep(1)
        }
        XCTAssertTrue(start.isEnabled, "camera preview is running")
        start.tap()
        sleep(6)
        attach("camera-recording")
        app.buttons["Stop and save"].tap()
        sleep(3)

        // 2. Voice, then background for 25 seconds.
        app.buttons["Talk"].firstMatch.tap()
        let voiceStart = app.buttons["Start recording"]
        XCTAssertTrue(voiceStart.waitForExistence(timeout: 5))
        voiceStart.tap()
        sleep(2)
        app.tap()
        attach("voice-recording")
        XCUIDevice.shared.press(.home)
        sleep(25)
        app.activate()
        let stop = app.buttons["Stop and save"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "still recording after the background")
        stop.tap()
        sleep(3)

        // 3. The memory holds both, and the voice covers the background time.
        app.buttons["End session"].firstMatch.tap()
        app.alerts.buttons["End session"].tap()
        let video = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Video ·'")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10), "memory lists the video")
        let voice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Voice ·'")).firstMatch
        XCTAssertTrue(voice.exists, "memory lists the voice recording")
        attach("memory")
        let seconds = Self.seconds(in: voice.label)
        XCTAssertGreaterThanOrEqual(seconds, 25, "voice kept recording in the background (\(voice.label))")
        XCTAssertGreaterThanOrEqual(Self.seconds(in: video.label), 4, "video has real length (\(video.label))")

        // 4. Clean up.
        deleteOpenMemory()
    }

    private func endSessionAndCloseMemory(deleting: Bool) {
        app.buttons["End session"].firstMatch.tap()
        if app.alerts.buttons["End session"].waitForExistence(timeout: 3) {
            app.alerts.buttons["End session"].tap()
        }
        if deleting, app.buttons["Delete this session"].waitForExistence(timeout: 5) {
            deleteOpenMemory()
        } else if app.buttons["Done"].exists {
            app.buttons["Done"].tap()
        }
    }

    private func deleteOpenMemory() {
        let delete = app.buttons["Delete this session"]
        guard delete.waitForExistence(timeout: 5) else { return }
        delete.tap()
        if app.alerts.buttons["Delete"].waitForExistence(timeout: 3) {
            app.alerts.buttons["Delete"].tap()
        }
    }

    /// "Voice · 0:27" → 27
    static func seconds(in label: String) -> Int {
        guard let clock = label.components(separatedBy: "· ").last else { return 0 }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
