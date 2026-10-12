import DotrinoNative
import Foundation
import os

/// THE RINGS OF AN ACCOUNT THAT IS NO LONGER HERE (owner, 2026-10-12). Removing an account
/// deletes its key, so nothing can sign a `push-unsubscribe` for it and the proxy kept ringing
/// this phone with its requests. Here the phone tells the proxy which accounts it STILL has and
/// the proxy drops the rest of the subscriptions of this push token (`push-prune`, proxy ≥ 1.4.7).
///
/// It runs when an account is removed, when the app gets its token (every launch) and when a
/// ring arrives that no account explains — that last one from the notification extension, which
/// is why the token is kept in the App Group.
enum PushPrune {
    private static let log = Logger(subsystem: "com.dotrino.app", category: "push")
    private static let defaults = UserDefaults(suiteName: "group.com.dotrino")
    /// Per app: the group is shared by every Dotrino app and each has its own token.
    private static let key = "pushToken.com.dotrino.app"

    private static let proxiesKey = "pushProxies.com.dotrino.app"

    static func remember(_ token: String) { defaults?.set(token, forKey: key) }

    /// Every proxy this phone subscribed at is remembered: once the last account of a proxy is
    /// removed, nothing else says where its subscription was.
    static func registered(at proxy: String) {
        let known = defaults?.stringArray(forKey: proxiesKey) ?? []
        if !known.contains(proxy) { defaults?.set(known + [proxy], forKey: proxiesKey) }
    }

    static func run() async {
        let extra = defaults?.stringArray(forKey: proxiesKey) ?? []
        guard let token = defaults?.string(forKey: key) else { return }
        // Without the full list of what is left there is nothing to say: a guess would drop
        // the rings of an account that is still here (a locked phone cannot open its keys).
        var keep: [String] = []
        let accounts: [Account]
        do {
            accounts = try AccountStore.shared.list()
            for a in accounts { keep.append(try PhoneKeys.open(a.id).publickey) }
        } catch {
            log.warning("push prune skipped, could not read the accounts: \(String(describing: error), privacy: .public)")
            return
        }
        for proxy in Set(accounts.map(\.proxy) + extra) {
            do {
                let c = try ProxyConnection(proxy, app: "vault")
                defer { c.close() }
                try await c.connect()
                let n = try await c.prunePush(token: token, keep: keep)
                if n > 0 { log.info("push: \(n, privacy: .public) subscription(s) of removed accounts dropped at \(proxy, privacy: .public)") }
            } catch {
                log.warning("push prune at \(proxy, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
