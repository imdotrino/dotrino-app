import DotrinoNative
import DotrinoNativeUI
import Foundation

/// THE RING of Requests on iOS: APNs straight from the proxy (no Firebase). Every vault account
/// on this phone registers the token under ITS device key — that is who the vault writes to — so
/// a request queued while the app is closed rings the phone. The same as Android's
/// `IdentityKeysBridge.registerAll` (Android) with FCM.
///
/// What arrives is an alert with no content: the proxy sends only `DOTRINO_RING_TITLE` /
/// `DOTRINO_RING_BODY`, and the text comes from Localizable.strings.
enum Push {
    private static let lock = NSLock()
    private static var token: SealedSession.PushToken?

    /// Apple gave (or rotated) the token: every account registers it again (cheap, and a lost
    /// registration heals on the next launch).
    static func tokenArrived(_ t: SealedSession.PushToken) {
        lock.withLock { token = t }
        let accounts: [Account]
        do { accounts = try AccountStore.shared.list() } catch {
            log.warning("push: could not read the accounts: \(String(describing: error), privacy: .public)")
            return
        }
        for a in accounts { Task.detached { await register(a, t) } }
    }

    /// A new account (just paired): registered at once if the token is already known.
    static func accountAdded(_ a: Account) {
        guard let t = lock.withLock({ token }) else { return }
        Task.detached { await register(a, t) }
    }

    private static func register(_ a: Account, _ t: SealedSession.PushToken) async {
        do {
            let keys = try EnclaveKeys.open(a.id)
            let c = try ProxyConnection(a.proxy, app: "vault")   // the approver app: its rings and its queue
            defer { c.close() }
            try await c.connect()
            try await c.registerApnsTokenAs(keys.publickey, token: t.token, topic: t.topic, env: t.env) { try keys.sign(Canonical.stringify($0)) }
            log.info("push: registered for \(a.deviceId, privacy: .public) (\(t.env, privacy: .public))")
        } catch {
            log.warning("push for \(a.deviceId, privacy: .public) not registered: \(String(describing: error), privacy: .public)")
        }
    }
}
