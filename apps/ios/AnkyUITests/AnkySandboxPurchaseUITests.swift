import XCTest

/// Real-device, sandbox-only: subscribe through Apple's sheet, see the
/// entitlement in Settings, restore it, and get a reflection from the
/// production server (which checks the subscription itself).
/// Requires a Sandbox Apple Account signed in on the device. No real money.
final class AnkySandboxPurchaseUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testSubscribeRestoreAndReflect() throws {
        endAndDeleteOpenSession()

        // Settings › Subscription.
        openSettings()
        let alreadySubscribed = app.staticTexts["Subscribed"].waitForExistence(timeout: 8)
        if !alreadySubscribed {
            app.buttons["Subscribe"].firstMatch.tap()
            let subscribe = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Subscribe for'")).firstMatch
            XCTAssertTrue(subscribe.waitForExistence(timeout: 20), "paywall shows the StoreKit price")
            attach("paywall")
            subscribe.tap()
            confirmAppleSheet()
            XCTAssertTrue(
                app.staticTexts["Welcome. Anky is open."].waitForExistence(timeout: 60)
                    || app.staticTexts["You're subscribed. Thank you for keeping Anky alive."].waitForExistence(timeout: 5),
                "the purchase activates the entitlement"
            )
            attach("purchased")
            sleep(2)
            if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        }
        XCTAssertTrue(app.staticTexts["Subscribed"].waitForExistence(timeout: 15), "Settings shows Subscribed")

        // Restore.
        app.buttons["Restore purchases"].firstMatch.tap()
        confirmAppleSheet(timeout: 10)
        XCTAssertTrue(app.staticTexts["Your subscription is restored."].waitForExistence(timeout: 40), "restore finds it")
        attach("restored")

        // Close settings and ask for a reflection on a fresh writing.
        app.swipeDown(velocity: .fast)
        sleep(1)
        // Settings opened from the drawer: the drawer is still out.
        if app.buttons["New session"].waitForExistence(timeout: 3) {
            app.buttons["New session"].tap()
            sleep(1)
        }
        app.buttons["Write"].firstMatch.tap()
        sleep(2)
        app.textViews.firstMatch.tap()
        sleep(1)
        app.typeText("i walked to the corner store and back and noticed how quiet my mind gets when my feet move. i want more of that quiet in my days")
        sleep(10) // the 8 second rule seals the passage
        app.buttons["More"].firstMatch.tap()
        app.buttons["Reflect with Anky"].firstMatch.tap()
        let send = app.buttons["Send and reflect"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "subscribers see the consent, not the paywall")
        send.tap()
        let failed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'subscription yet' OR label CONTAINS 'didn' OR label CONTAINS 'offline'")).firstMatch
        // Either a real reflection (the consent heading gives way to the
        // reflection's title) or an honest failure line. Never a placeholder.
        let consent = app.staticTexts["Ask Anky to reflect"]
        let placeholder = app.staticTexts["mirror unavailable"]
        var outcome = "timeout"
        for _ in 0..<120 {
            if placeholder.exists { outcome = "placeholder"; break }
            if failed.exists { outcome = "honest failure: \(failed.label)"; break }
            if !consent.exists, !send.exists { outcome = "reflection"; break }
            sleep(1)
        }
        attach("reflection")
        print("REFLECTION OUTCOME: \(outcome)")
        XCTAssertNotEqual(outcome, "placeholder", "a placeholder must never be shown as a reflection")
        XCTAssertNotEqual(outcome, "timeout")

        // Leave the phone as it was.
        app.buttons["Close"].firstMatch.tap()
        sleep(1)
        endAndDeleteOpenSession()
    }

    private func endAndDeleteOpenSession() {
        guard app.buttons["End session"].waitForExistence(timeout: 3) else { return }
        app.buttons["End session"].firstMatch.tap()
        if app.alerts.buttons["End session"].waitForExistence(timeout: 3) {
            app.alerts.buttons["End session"].tap()
        }
        let delete = app.buttons["Delete this session"]
        if delete.waitForExistence(timeout: 5) {
            delete.tap()
            if app.alerts.buttons["Delete"].waitForExistence(timeout: 3) { app.alerts.buttons["Delete"].tap() }
        }
    }

    private func openSettings() {
        let settings = app.buttons["Settings"]
        // A sheet may still be animating away; retry until the drawer opens.
        for _ in 0..<5 where !settings.exists {
            let menu = app.buttons["Your memories"].firstMatch
            if menu.waitForExistence(timeout: 5) { menu.tap() }
            _ = settings.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(settings.exists, "drawer opened")
        settings.tap()
    }

    /// Taps through Apple's purchase / sign-in confirmation sheets.
    private func confirmAppleSheet(timeout: TimeInterval = 45) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var tapped = false
            for label in ["Subscribe", "Confirm", "Purchase", "Buy", "OK", "Continue", "Done"] {
                let button = springboard.buttons[label]
                if button.exists, button.isHittable {
                    button.tap()
                    tapped = true
                    break
                }
            }
            if !tapped {
                if app.staticTexts["Welcome. Anky is open."].exists
                    || app.staticTexts["Your subscription is restored."].exists
                    || app.staticTexts["You're subscribed. Thank you for keeping Anky alive."].exists {
                    return
                }
            }
            sleep(1)
        }
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
