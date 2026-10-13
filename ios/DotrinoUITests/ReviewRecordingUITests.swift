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
        let menu = profileButton()
        if menu.waitForExistence(timeout: 5) { menu.tap(); pause(2); dump("menu") }
        app.tabBars.buttons.element(boundBy: 3).tap()
        pause(6)
        dump("requests")
        XCTFail("keep the recording")
    }

    private func profileButton() -> XCUIElement {
        let web = app.webViews.firstMatch
        for label in ["Mi perfil", "My profile"] {
            let b = web.buttons[label]
            if b.exists { return b }
        }
        return web.buttons["Mi perfil"]
    }

    private func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }

    private func dump(_ name: String) {
        print("=== TREE \(name) ===\n\(app.debugDescription)\n=== END \(name) ===")
    }
}
