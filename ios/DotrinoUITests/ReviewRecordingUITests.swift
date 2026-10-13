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

    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private let nick = "Review Demo"
    private func tab(_ i: Int) { app.tabBars.buttons.element(boundBy: i).tap() }

    /// THE TAKE. Launch, create a profile, sign in to the demo account, approve a request, look at
    /// the vault, delete the profile, deny a request, sign out. It only ever touches what it made:
    /// the profile called "Review Demo" and the account that appears after signing in.
    func testTake() throws {
        try XCTSkipUnless(step == "take")
        continueAfterFailure = false
        let address = try XCTUnwrap(env["REVIEW_ADDRESS"]), password = try XCTUnwrap(env["DEMO_PASSWORD"])
        app.launch()
        pause(5)
        english()
        web.swipeUp(velocity: .slow); pause(2); web.swipeDown(velocity: .slow); pause(1)

        // Requests before signing in: the accounts this phone already has are left alone.
        tab(3); pause(3)
        let en = app.buttons["lang-en"]; if en.waitForExistence(timeout: 5) { en.tap() }
        pause(3)
        let before = accountIds()

        // Registration: a profile is a key made on the phone. No email, no password.
        tab(1); profileReady()
        openMenu()
        link("Create profile").tap()
        let name = web.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 15)); pause(2)
        name.tap(); name.typeText(nick); pause(1)
        web.buttons["Create the profile"].tap()
        profileReady(); pause(3)
        dump("created")

        // Sign in with the demo account.
        openMenu()
        link("Sign in").tap()
        let addr = web.textFields.firstMatch, pass = web.secureTextFields.firstMatch
        XCTAssertTrue(pass.waitForExistence(timeout: 15)); pause(2)
        addr.tap(); addr.typeText(address)
        XCTAssertEqual(addr.value as? String, address)
        pass.tap(); pass.typeText(password); pause(1)
        web.staticTexts["Sign in with your password"].tap(); pause(1)   // puts the keyboard away
        web.switches.firstMatch.tap(); pause(1)
        web.buttons["Sign in"].tap()
        profileReady(timeout: 60); pause(4)
        dump("signed-in")

        // Requests: the demo account is the one that was not there before.
        tab(3); pause(3)
        let demo = try XCTUnwrap(newAccount(before, timeout: 40), "the demo account did not show up in Requests")
        dump("requests")
        try answer(demo, "approve", timeout: 220); pause(5)

        // The vault of the account in use.
        tab(2); pause(6); english(); pause(3)
        web.swipeUp(velocity: .slow); pause(3); web.swipeDown(velocity: .slow); pause(1)
        dump("vault")

        // Account deletion: the profile created above goes, with everything in it.
        tab(1); profileReady(); pause(2)
        try deleteProfile(); pause(3)

        // The other answer.
        tab(3); pause(3)
        try answer(demo, "deny", timeout: 220); pause(5)

        // Sign out: the demo account leaves this phone.
        tab(1); profileReady(); pause(2)
        try signOut(); pause(6)
        tab(3); pause(5)
        dump("end")
        XCTAssertFalse(accountIds().contains(demo), "the demo account is still on the phone")
        continueAfterFailure = true
        XCTFail("keep the recording")
    }

    /// Undo what a take left behind if it stopped half way.
    func testCleanup() throws {
        try XCTSkipUnless(step == "cleanup")
        app.launch(); pause(5)
        tab(1); profileReady(); pause(2)
        if rowDelete() != nil { try deleteProfile(); pause(3) }
        openMenu(); dump("menu")
        let out = signOutControl()
        if out.exists { out.tap(); pause(6) } else { web.staticTexts["Your profile"].firstMatch.tap() }
        tab(3); pause(5); dump("end")
        XCTFail("keep the recording")
    }

    private func profileReady(timeout: TimeInterval = 25) {
        XCTAssertTrue(web.staticTexts["Your profile"].waitForExistence(timeout: timeout), "profile page")
    }

    private func accountIds() -> Set<String> {
        let q = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'account-'"))
        return Set(q.allElementsBoundByIndex.map { String($0.identifier.dropFirst("account-".count)) })
    }

    private func newAccount(_ before: Set<String>, timeout: TimeInterval) -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            let fresh = accountIds().subtracting(before)
            if fresh.count == 1 { return fresh.first }
            XCTAssertTrue(fresh.isEmpty, "more than one new account: \(fresh)")
            pause(2)
        }
        return nil
    }

    /// Taps Approve or Deny on a request of THAT account and no other: the button has to sit
    /// between that account's heading and the next one.
    private func answer(_ account: String, _ what: String, timeout: TimeInterval) throws {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            let heads = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'account-'")).allElementsBoundByIndex
            let mine = heads.filter { $0.identifier == "account-\(account)" }.map { $0.frame.minY }.min()
            if let top = mine {
                let next = heads.filter { $0.identifier != "account-\(account)" && $0.frame.minY > top }.map { $0.frame.minY }.min() ?? .greatestFiniteMagnitude
                let buttons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", what + "-")).allElementsBoundByIndex
                if let b = buttons.first(where: { $0.frame.minY > top && $0.frame.minY < next }) {
                    // Below the fold: bring it up and look again (the frames move).
                    if !b.isHittable { app.swipeUp(velocity: .slow); pause(2); continue }
                    pause(3)   // long enough to read the request in the recording
                    b.tap()
                    return
                }
            } else { app.swipeDown(velocity: .slow) }
            pause(2)
        }
        XCTFail("no request to \(what) in the demo account")
    }

    /// The Delete button on the row of the profile this test created, or nil.
    private func rowDelete() -> XCUIElement? {
        let names = web.staticTexts.matching(NSPredicate(format: "label == %@", nick)).allElementsBoundByIndex
        let dels = web.buttons.matching(NSPredicate(format: "label == 'Delete'")).allElementsBoundByIndex
        var found: [XCUIElement] = []
        for d in dels where names.contains(where: { abs($0.frame.midY - d.frame.midY) < 22 && $0.frame.width > 0 }) { found.append(d) }
        return found.count == 1 ? found[0] : nil
    }

    private func deleteProfile() throws {
        let list = web.staticTexts["Your profiles"].firstMatch
        for _ in 0..<6 where !list.isHittable { web.swipeUp(velocity: .slow); pause(1) }
        web.swipeUp(velocity: .slow); pause(2)
        let del = try XCTUnwrap(rowDelete(), "the row of \(nick) was not found: nothing is deleted")
        del.tap(); pause(3)
        dump("delete-ask")
        XCTAssertTrue(web.staticTexts["Delete this account from this device?"].exists, "not the question for a profile that is not in use")
        web.buttons["Yes, delete it"].tap(); pause(3)
        XCTAssertNil(rowDelete())
    }

    private func signOutControl() -> XCUIElement {
        web.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Sign out' AND (elementType == %d OR elementType == %d)",
                                                           XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.link.rawValue)).firstMatch
    }

    private func signOut() throws {
        web.swipeDown(); web.swipeDown(); pause(1)
        openMenu()
        let out = signOutControl()
        XCTAssertTrue(out.waitForExistence(timeout: 5), "no Sign out in the menu")
        out.tap()
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
