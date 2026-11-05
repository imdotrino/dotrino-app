import DotrinoNative
import XCTest
@testable import Dotrino

/// The «Last 24 hours» lines of Requests (`MoveText`). Same as Android's `MoveTextTest.kt`: the
/// words come from a table here, what is tested is which are picked and how they are put together.
final class MoveTextTests: XCTestCase {
    private let es: [String: String] = [
        "move_the_vault": "La bóveda",
        "move_asks": "%1$@ pidió las claves de %2$@",
        "move_writes": "%1$@ quiso guardar variables en %2$@",
        "move_reveals": "%1$@ pidió ver una variable de %2$@",
        "move_passwords": "%@ pidió una contraseña",
        "move_update": "%@ pidió actualizarse",
        "move_incident": "Incidente de seguridad de %@",
        "move_approved": "aprobado", "move_denied": "denegado", "move_blocked": "bloqueado",
        "move_ignored": "ignorado", "move_withdrawn": "retirado", "move_expired": "caducó sin respuesta",
        "move_by": "por %@",
        "move_contested": "Dos aparatos respondieron a la misma invitación de emparejar y se canceló.",
        "notif_delivered_passwords_title": "%@ se llevó una contraseña",
        "notif_delivered_secrets_title": "%1$@ se llevó las claves de %2$@",
        "notif_updated_title": "Tu bóveda se actualizó",
        "notif_updated_device_title": "%@ se actualizó",
        "notif_needs_root_title": "Tu bóveda tiene una actualización pendiente",
        "notif_needs_root_device_title": "%@ tiene una actualización pendiente",
    ]
    private func t(_ key: String, _ args: [CVarArg]) -> String { String(format: es[key]!, arguments: args) }

    private func answered(_ outcome: String, kind: String = "read", by: String? = "EF56-7890", byLabel: String? = "teléfono") -> VaultNotice {
        VaultNotice(id: "a", ev: "answered", version: "", from: "", ts: 1, deviceId: "AB12-CD34", label: "portátil",
                    ns: "claude", kind: kind, outcome: outcome, by: by, byLabel: byLabel)
    }

    func testAnApprovedRequestSaysWhoAskedWhatAndWhoApprovedWithAliasAndId() {
        XCTAssertEqual(MoveText.text(answered("approved"), t), "portátil (AB12-CD34) pidió las claves de claude: aprobado por teléfono (EF56-7890)")
    }

    func testAnExpiredRequestWasAnsweredByNobody() {
        XCTAssertEqual(MoveText.text(answered("expired", by: nil, byLabel: nil), t), "portátil (AB12-CD34) pidió las claves de claude: caducó sin respuesta")
    }

    func testAnApproverWithoutAliasIsNamedByItsId() {
        XCTAssertEqual(MoveText.text(answered("denied", kind: "write", byLabel: ""), t), "portátil (AB12-CD34) quiso guardar variables en claude: denegado por EF56-7890")
    }

    func testEachKindAndOutcomeHasItsWords() {
        XCTAssertEqual(MoveText.text(answered("withdrawn", kind: "passwords"), t), "portátil (AB12-CD34) pidió una contraseña: retirado por teléfono (EF56-7890)")
        XCTAssertEqual(MoveText.text(answered("ignored", kind: "reveal"), t), "portátil (AB12-CD34) pidió ver una variable de claude: ignorado por teléfono (EF56-7890)")
        XCTAssertEqual(MoveText.text(answered("blocked", kind: "incident"), t), "Incidente de seguridad de portátil (AB12-CD34): bloqueado por teléfono (EF56-7890)")
    }

    func testWhatAnUnattendedDeviceTookUsesTheWordsOfTheSystemNotice() {
        let n = VaultNotice(id: "d", ev: "delivered", version: "", from: "", ts: 1, deviceId: "AB12-CD34", label: "servidor", ns: "claude", kind: "secrets")
        XCTAssertEqual(MoveText.text(n, t), "servidor (AB12-CD34) se llevó las claves de claude")
    }

    func testAnUpdateSaysWhoAndToWhichVersion() {
        XCTAssertEqual(MoveText.text(VaultNotice(id: "u", ev: "updated", version: "0.193.0", from: "", ts: 1), t), "Tu bóveda se actualizó (0.193.0)")
        let agent = VaultNotice(id: "u", ev: "update-needs-root", version: "1.2.3", from: "", ts: 1, product: "@dotrino/terminal-agent", deviceId: "AB12-CD34", label: "portátil")
        XCTAssertEqual(MoveText.text(agent, t), "portátil (AB12-CD34) tiene una actualización pendiente (1.2.3)")
    }

    func testTheLogAnchorIsNotShown() {
        XCTAssertFalse(MoveText.shown(VaultNotice(id: "l", ev: "log-anchor", version: "", from: "", ts: 1)))
    }

    func testADeviceIsNamedWithAliasAndId() {
        XCTAssertEqual(RequestText.named("portátil", "AB12-CD34"), "portátil (AB12-CD34)")
        XCTAssertEqual(RequestText.named("", "AB12-CD34"), "AB12-CD34")
        XCTAssertEqual(RequestText.named(nil, "AB12-CD34"), "AB12-CD34")
    }
}
