import XCTest

/// Drives the app through the states we ship as App Store screenshots and attaches
/// each frame to the test result. Run on a 6.9" device; extract with:
///   xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Store listing is en-US, so the frames must not show a comma decimal.
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForRates(timeout: TimeInterval = 30) {
        let eur = app.textFields["Euro amount"]
        XCTAssertTrue(eur.waitForExistence(timeout: 15))

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let value = eur.value as? String ?? ""
            if !value.isEmpty, value != "0", value != "—", Double(value) != nil { return }
            usleep(300_000)
        }
        XCTFail("Rates never loaded")
    }

    func testCaptureStoreScreenshots() {
        waitForRates()
        capture("01-converter")

        // 2 — typing in a non-pivot row, keyboard visible, everything recalculated
        let eur = app.textFields["Euro amount"]
        eur.tap()
        eur.typeText("250")
        usleep(800_000)
        capture("02-typing")
        app.buttons["Done"].tap()
        usleep(400_000)

        // 3 — 30-day chart with stats
        app.buttons["Euro chart"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Current Rate"].waitForExistence(timeout: 30), "Chart had no data")
        usleep(600_000)
        capture("03-chart")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        usleep(600_000)

        // 4 — the currency picker, showing the breadth of the list
        app.buttons["Add currency"].tap()
        XCTAssertTrue(app.buttons["currency-CHF"].waitForExistence(timeout: 5))
        usleep(700_000)
        capture("04-add-currency")
    }
}
