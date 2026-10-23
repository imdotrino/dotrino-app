import DotrinoNative
import XCTest

/// EL BLUETOOTH EN VIVO, contra un PC de verdad cerca (dotrino-proxy-client/docs/bluetooth.md).
/// Se salta si no se le pasa con quién: `TEST_RUNNER_BLE_EXPECT` (la invitación que el PC
/// anuncia) y `TEST_RUNNER_BLE_PEER` (el token del PC en el proxio). Va alojada en la app porque
/// CoreBluetooth exige el permiso de Bluetooth de una app.
final class BleLiveTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    private func ready() async throws -> BluetoothDirect {
        let bt = BluetoothDirect()
        bt.onLog = { print("[ble] \($0)") }
        bt.start()
        for _ in 0..<150 where !bt.available { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertTrue(bt.available, "Bluetooth is off or not allowed for the app")
        return bt
    }

    /// Lo que el PC anuncia (`kind: pair`) se encuentra sin proxio.
    func testDiscoversTheInvitationAnnouncedNearby() async throws {
        guard let want = env["BLE_EXPECT"] else { throw XCTSkip("needs TEST_RUNNER_BLE_EXPECT (a PC announcing nearby)") }
        let bt = try await ready()
        defer { bt.stop() }
        let found = try await bt.discover(kind: "pair", timeout: 20)
        XCTAssertTrue(found.contains(want), "found: \(found)")
    }

    /// El primer mensaje sale por el proxio, el canal sube a Bluetooth, y el eco vuelve por él.
    func testChannelGoesOverBluetooth() async throws {
        guard let peer = env["BLE_PEER"] else { throw XCTSkip("needs TEST_RUNNER_BLE_PEER (the PC's token)") }
        let bt = try await ready()
        defer { bt.stop() }
        let conn = try ProxyConnection("wss://proxy.dotrino.com")
        _ = try await conn.connect()
        conn.useDirect(DirectLadder(webrtc: nil, bluetooth: bt))
        let lock = NSLock()
        var got: [JSON] = []
        _ = conn.onMessage { inc in lock.withLock { got.append(inc.payload) } }

        try conn.sendToOrUpgrade(peer, ["n": 1])
        for _ in 0..<300 where !bt.isOpen(peer) { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertTrue(bt.isOpen(peer), "the Bluetooth channel did not open")
        XCTAssertEqual(conn.routeOf(peer), "bluetooth")

        try conn.sendToOrUpgrade(peer, ["n": 2])
        var echo: JSON?
        for _ in 0..<100 {
            echo = lock.withLock { got.first { $0["echo"]?.int == 2 } }
            if echo != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(echo?["via"]?.string, "bluetooth", "the PC said the second message came by: \(String(describing: echo))")
        conn.close()
    }
}
