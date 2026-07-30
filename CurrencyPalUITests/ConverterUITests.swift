import XCTest

/// Drives the real app in the simulator: typing, keyboard dismissal, list edits.
/// These cover the things unit tests cannot — focus, the decimal keypad, navigation.
final class ConverterUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Fresh in-memory store per case — otherwise a currency added by one test
        // leaks into the next one and the assertions drift.
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func amountField(_ currency: String) -> XCUIElement {
        app.textFields["\(currency) amount"]
    }

    /// Amounts are shown with the simulator locale's decimal separator, which may
    /// be a comma — `Double(_:)` only accepts a period.
    private func numericValue(_ element: XCUIElement) -> Double? {
        guard let raw = element.value as? String, !raw.isEmpty else { return nil }
        return Double(raw.replacingOccurrences(of: ",", with: "."))
    }

    /// Rates arrive over the network on first launch; wait for a converted value.
    @discardableResult
    private func waitForRates(timeout: TimeInterval = 25) -> Bool {
        let eur = amountField("Euro")
        XCTAssertTrue(eur.waitForExistence(timeout: 10), "EUR row never appeared")

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = numericValue(eur), value > 0 { return true }
            usleep(300_000)
        }
        return false
    }

    func testRatesLoadAndConvert() {
        XCTAssertTrue(waitForRates(), "No converted EUR value after launch")

        let usd = amountField("US Dollar")
        XCTAssertEqual(usd.value as? String, "1", "USD should start at 1")
    }

    /// The decimal keypad has no return key — without an explicit Done button
    /// the keyboard cannot be dismissed and covers half the list.
    func testKeyboardCanBeDismissed() {
        waitForRates()

        let eur = amountField("Euro")
        eur.tap()

        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "No Done button above the keyboard")

        doneButton.tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 2), "Keyboard did not dismiss")
    }

    /// Typing in any row must recalculate the others — this is the core interaction.
    func testTypingInAnyRowRecalculatesOthers() {
        waitForRates()

        let eur = amountField("Euro")
        let usd = amountField("US Dollar")

        eur.tap()
        eur.typeText("100")

        // The first keystroke replaces the previous value, so EUR reads exactly what was typed.
        XCTAssertEqual(eur.value as? String, "100", "EUR field did not take the typed value")

        let deadline = Date().addingTimeInterval(5)
        var converted: Double?
        while Date() < deadline {
            converted = numericValue(usd)
            if let value = converted, value != 1 { break }
            usleep(200_000)
        }

        guard let usdValue = converted else {
            return XCTFail("USD shows a non-numeric value: \(usd.value ?? "nil")")
        }
        // 100 EUR is worth far more than the 1 USD the row started at.
        XCTAssertGreaterThan(usdValue, 1, "USD did not recalculate from EUR input")
    }

    /// Keystrokes must not lag behind input — the old build ran two SwiftData
    /// queries per currency per keystroke.
    func testTypingStaysResponsive() {
        waitForRates()

        let eur = amountField("Euro")
        eur.tap()

        let start = Date()
        eur.typeText("123456")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(eur.value as? String, "123456", "Dropped keystrokes while typing")
        XCTAssertLessThan(elapsed, 6.0, "Typing six digits took \(elapsed)s")
    }

    func testAddAndRemoveCurrency() {
        waitForRates()

        app.buttons["Add currency"].tap()

        let swissFranc = app.buttons["currency-CHF"]
        XCTAssertTrue(
            swissFranc.waitForExistence(timeout: 5),
            "Add-currency sheet did not list CHF. Hierarchy:\n\(app.debugDescription)"
        )

        // The sheet animates in — tapping before it settles fails as "not hittable".
        let deadline = Date().addingTimeInterval(5)
        while !swissFranc.isHittable && Date() < deadline {
            usleep(200_000)
        }
        swissFranc.tap()

        let chf = amountField("Swiss Franc")
        XCTAssertTrue(chf.waitForExistence(timeout: 5), "CHF row was not added")

        // And back out again: swipe-to-delete removes the row.
        chf.swipeLeft()
        let deleteButton = app.buttons["Delete"].firstMatch
        if deleteButton.waitForExistence(timeout: 3) {
            deleteButton.tap()
            XCTAssertFalse(chf.waitForExistence(timeout: 3), "CHF row was not removed")
        }
    }

    func testChartOpensFromRow() {
        waitForRates()

        app.buttons["Euro chart"].firstMatch.tap()

        XCTAssertTrue(
            app.navigationBars["USD / EUR"].waitForExistence(timeout: 10),
            "Chart screen did not open"
        )

        // A chart that renders only "No Data" is the failure this guards against.
        XCTAssertTrue(
            app.staticTexts["Current Rate"].waitForExistence(timeout: 20),
            "Chart opened but never produced data"
        )
        XCTAssertTrue(app.staticTexts["30d Change"].exists, "Chart is missing its stats")
        XCTAssertFalse(app.staticTexts["No Data"].exists, "Chart shows No Data for USD/EUR")
    }

    /// Tapping the row that is currently active must not open a self-referential pair.
    func testChartForActiveRowUsesADifferentBase() {
        waitForRates()

        app.buttons["US Dollar chart"].firstMatch.tap()

        XCTAssertTrue(
            app.navigationBars["EUR / USD"].waitForExistence(timeout: 10),
            "USD row should chart against EUR, not against itself"
        )
    }

    /// Crypto history comes from a different provider than fiat — worth its own case.
    func testCryptoChartLoads() {
        waitForRates()

        app.buttons["Bitcoin chart"].firstMatch.tap()

        XCTAssertTrue(
            app.navigationBars["USD / BTC"].waitForExistence(timeout: 10),
            "Bitcoin chart did not open"
        )
        XCTAssertTrue(
            app.staticTexts["Current Rate"].waitForExistence(timeout: 25),
            "Bitcoin chart never produced data"
        )
    }

    /// Frankfurter has no ruble series; the screen must say so instead of spinning.
    func testUnsupportedPairExplainsItself() {
        waitForRates()

        app.buttons["Russian Ruble chart"].firstMatch.tap()

        XCTAssertTrue(
            app.navigationBars["USD / RUB"].waitForExistence(timeout: 10),
            "Ruble chart did not open"
        )

        let hasData = app.staticTexts["Current Rate"].waitForExistence(timeout: 25)
        let explainsAbsence = app.staticTexts["No Data"].exists
        XCTAssertTrue(hasData || explainsAbsence, "Ruble chart neither loaded nor explained itself")
    }
}
