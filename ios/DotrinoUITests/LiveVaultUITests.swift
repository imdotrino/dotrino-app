import XCTest

/// The app against a REAL vault, end to end: it adds the vault's account by pasting its invite,
/// hands the six digits to the vault, and approves a write and a key request in Requests. Every
/// message the app sends to the vault goes binary (dotrino-native ≥ 0.42.0), so this is what says
/// the vault understands it — a vault that does not would never answer and nothing would show.
///
/// The vault side is `dotrino-native/test-vectors/e2e-live.mjs` (in a dotrino-test box); a small
/// HTTP server next to it takes the code (`CODE_URL?c=123456`). Simulator only: it adds an account
/// that points to a throwaway vault.
///
///   TEST_RUNNER_LIVE_INVITE=<invite-A.txt> TEST_RUNNER_LIVE_CODE_URL=http://<ip>:8778/code \
///     xcodebuild -project Dotrino.xcodeproj -scheme DotrinoUITests \
///     -destination 'platform=iOS Simulator,id=<udid>' -only-testing:DotrinoUITests/LiveVaultUITests test
final class LiveVaultUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.dotrino.app")
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var web: XCUIElement { app.webViews.firstMatch }

    func testAddsAVaultAndApprovesItsRequests() throws {
        let invite = try XCTUnwrap(env["LIVE_INVITE"], "set TEST_RUNNER_LIVE_INVITE")
        let codeUrl = try XCTUnwrap(env["LIVE_CODE_URL"], "set TEST_RUNNER_LIVE_CODE_URL")
        app.launch()
        tab(3)
        pause(3)
        let before = accountIds()

        // Add account → the vault's /d page → paste the invite.
        let add = app.buttons.matching(NSPredicate(format: "label IN %@", ["Add account", "Añadir cuenta"])).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "no Add account button")
        add.tap()
        let paste = web.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Paste the code", "Pegar el código"])).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 30), "the pairing page did not show")
        paste.tap()
        pause(1)
        let field = web.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no field to paste the invite")
        field.tap()
        field.typeText(invite)
        web.buttons.matching(NSPredicate(format: "label IN %@", ["Connect", "Conectar"])).firstMatch.tap()

        // The six digits, from the line the page shows for the computer's vault.
        let line = web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'dotrino-vault approve'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 60), "the page did not show the code")
        let code = try XCTUnwrap(line.label.split(separator: " ").last.map(String.init))
        XCTAssertEqual(code.count, 6, "not a code: \(line.label)")
        try get("\(codeUrl)?c=\(code)")

        // Requests: the new account, a write to approve and then a key request.
        tab(3)
        let acct = try XCTUnwrap(newAccount(before, timeout: 90), "the vault's account did not show up in Requests")
        try answer(acct, timeout: 120)
        pause(4)
        try answer(acct, timeout: 120)
        pause(4)
    }

    private func tab(_ i: Int) { app.tabBars.buttons.element(boundBy: i).tap() }

    private func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }

    private func get(_ url: String) throws {
        let done = expectation(description: "code delivered")
        var status = 0
        URLSession.shared.dataTask(with: try XCTUnwrap(URL(string: url))) { _, r, _ in
            status = (r as? HTTPURLResponse)?.statusCode ?? 0
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 15)
        XCTAssertEqual(status, 200, "the code did not reach the vault side")
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
            pause(2)
        }
        return nil
    }

    /// Taps Approve on the first request of THAT account: the button has to sit between that
    /// account's heading and the next one.
    private func answer(_ account: String, timeout: TimeInterval) throws {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            let heads = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'account-'")).allElementsBoundByIndex
            if let top = heads.filter({ $0.identifier == "account-\(account)" }).map({ $0.frame.minY }).min() {
                let next = heads.filter { $0.identifier != "account-\(account)" && $0.frame.minY > top }.map { $0.frame.minY }.min() ?? .greatestFiniteMagnitude
                let buttons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'approve-'")).allElementsBoundByIndex
                if let b = buttons.first(where: { $0.frame.minY > top && $0.frame.minY < next && $0.isEnabled }) {
                    if !b.isHittable { app.swipeUp(velocity: .slow); pause(1); continue }
                    b.tap()
                    return
                }
            }
            pause(2)
        }
        XCTFail("no request to approve in the account \(account)")
    }
}
