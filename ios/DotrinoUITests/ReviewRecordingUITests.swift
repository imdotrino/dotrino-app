import XCTest

/// Drives the INSTALLED app (by bundle id, not a build of this project) on a physical iPhone and
/// lets Xcode record the screen: the recording App Review asks for (Guideline 2.1).
///
///   TEST_RUNNER_REVIEW_STEP=look xcodebuild -project Dotrino.xcodeproj -scheme DotrinoUITests \
///     -destination 'platform=iOS,name=Dotrino Phone' -allowProvisioningUpdates test
///
/// Every test ends in a failure on purpose: Xcode only keeps the recording of a failed test.
final class ReviewRecordingUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.dotrino.app")
    private var step: String { ProcessInfo.processInfo.environment["REVIEW_STEP"] ?? "look" }

    override func setUp() { continueAfterFailure = true }

    /// Read-only: what is on the phone right now. Touches nothing but the tabs and the menu.
    func testLook() throws {
        try XCTSkipUnless(step == "look")
        app.launch()
        pause(6)
        dump("home")
        app.tabBars.buttons.element(boundBy: 1).tap()
        pause(8)
        dump("profile")
        openMenu(); dump("menu")
        app.tabBars.buttons.element(boundBy: 3).tap()
        pause(6)
        dump("requests")
        XCTFail("keep the recording")
    }

    /// Read-only: the create and sign-in pages, without sending either form.
    func testProbe() throws {
        try XCTSkipUnless(step == "probe")
        app.launch()
        pause(5)
        english()
        app.tabBars.buttons.element(boundBy: 1).tap()
        pause(7)
        english()
        openMenu(); dump("menu")
        link("Create profile").tap()
        pause(5); dump("create")
        web.buttons["Cancel"].tap()
        pause(6)
        openMenu()
        link("Sign in").tap()
        pause(5); dump("login")
        app.tabBars.buttons.element(boundBy: 2).tap()
        pause(8); dump("vault")
        XCTFail("keep the recording")
    }

    private var web: XCUIElement { app.webViews.firstMatch }

    /// The pages remember the language per site: each one is switched the first time it shows.
    private func english() {
        let en = web.buttons["EN"]
        if en.waitForExistence(timeout: 8) { en.tap(); pause(3) }
    }

    private func openMenu() {
        let b = web.otherElements.matching(NSPredicate(format: "label IN %@", ["My profile", "Mi perfil"])).firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 10), "profile button")
        b.tap()
        pause(2)
    }

    private func link(_ text: String) -> XCUIElement {
        web.links.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }

    private func dump(_ name: String) {
        print("=== TREE \(name) ===\n\(app.debugDescription)\n=== END \(name) ===")
    }
}
