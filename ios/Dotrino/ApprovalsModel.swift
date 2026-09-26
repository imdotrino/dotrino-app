import DotrinoNative
import Foundation
import os

let log = Logger(subsystem: "com.dotrino.app", category: "approvals")

/// The native approvals, account by account. While the screen is visible each account keeps
/// ONE connection open to its proxy, identified with its own key, so a new request arrives
/// live (the vault's notice) instead of waiting for a poll.
///
/// WHAT A REQUEST LIST CAN BE REPLACED BY. Only by a newer answer from THAT account's vault.
/// One refresh in flight per account, a failed refresh keeps what was on screen and says it
/// failed, and one account never touches another's list. That is what made requests show for
/// a second and vanish on the web. (Same model as Android's `ApprovalsModel.kt`.)
@MainActor
final class ApprovalsModel: ObservableObject {
    static let pollSeconds: UInt64 = 15
    static let cannotApprove = "cannot-approve"
    static let noReply = "vault-no-reply"
    static let notConnected = "not-connected"

    enum Status: Equatable {
        case connecting
        case live
        case failed(String)
    }

    struct AccountState: Equatable {
        var account: Account
        var status: Status = .connecting
        var items: [Approval] = []
        var grants: [Grant] = []
        /// When the lists were last confirmed by the vault; nil = never yet.
        var confirmedAt: Int64?
        /// Requests being answered right now: their buttons stay disabled.
        var busy: Set<String> = []
        /// The last thing that went wrong answering or refreshing, said on screen.
        var error: String?
    }

    @Published private(set) var state: [String: AccountState] = [:]
    /// The accounts file exists and does not open: said, never shown as «no accounts».
    @Published private(set) var storeError: String?

    private let store = AccountStore.shared
    private var running = false
    private var tasks: [Task<Void, Never>] = []
    private var sessions: [String: (conn: ProxyConnection, vault: VaultClient)] = [:]
    /// Accounts with a refresh in flight, and those asked to refresh again when it ends.
    private var inflight = Set<String>()
    private var again = Set<String>()

    /// Opens a session per account. Called when the screen becomes visible.
    func start() {
        if running { return }
        running = true
        let accounts: [Account]
        do {
            accounts = try store.list()
            storeError = nil
        } catch {
            log.error("could not read the accounts file: \(String(describing: error), privacy: .public)")
            storeError = String(describing: error)
            state = [:]
            return
        }
        state = Dictionary(uniqueKeysWithValues: accounts.map { a in
            var st = state[a.id] ?? AccountState(account: a)
            st.account = a
            st.status = .connecting
            return (a.id, st)
        })
        for a in accounts { tasks.append(Task { await self.session(a.id) }) }
        // Safety net: a notice lost on the way should not leave a request unseen.
        tasks.append(Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollSeconds * 1_000_000_000)
                if Task.isCancelled { return }
                self.refreshAll()
            }
        })
    }

    /// Closes every session. Called when the screen is no longer visible.
    func stop() {
        running = false
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        sessions.values.forEach { $0.conn.close() }
        sessions.removeAll()
    }

    func accountsCount() -> Int { (try? store.list().count) ?? 0 }

    /// Keeps an account connected: on a dropped socket it reconnects with a growing wait.
    private func session(_ id: String) async {
        var wait: UInt64 = 1
        while running && !Task.isCancelled {
            // Removed from this phone: its session ends here, it does not keep retrying with keys that are gone.
            guard let a = state[id]?.account else { return }
            var conn: ProxyConnection?
            do {
                let keys = try EnclaveKeys.open(a.id)
                let c = try ProxyConnection(a.proxy)
                conn = c
                try await c.connect()
                try await c.identify(keys)
                let vc = VaultClient(account: a, keys: keys, conn: c) { renewed in
                    Task { @MainActor in
                        do { try self.store.save(renewed) } catch {
                            log.error("could not save the renewed paper: \(String(describing: error), privacy: .public)")
                        }
                        self.set(renewed.id) { $0.account = renewed }
                    }
                }
                _ = c.onMessage { m in
                    // The vault's «there is a request» notice: refresh THIS account now.
                    if m.payload["type"]?.string == VaultClient.adminEvent {
                        Task { @MainActor in
                            log.info("account \(a.deviceId, privacy: .public): notice from the vault")
                            await self.refresh(id)
                        }
                    }
                }
                sessions[id] = (c, vc)
                set(id) { $0.status = .live }
                wait = 1
                await refresh(id)
                while c.closed == nil && running && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                set(id) { $0.status = .failed(c.closed ?? "closed") }
            } catch {
                log.warning("account \(a.deviceId, privacy: .public): \(String(describing: error), privacy: .public)")
                set(id) { $0.status = .failed(String(describing: error)) }
            }
            sessions[id] = nil
            conn?.close()
            if !running || Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            wait = min(wait * 2, 30)
        }
    }

    func refreshAll() {
        for id in state.keys { Task { await refresh(id) } }
    }

    /// ONE question in flight per account. A refresh asked while another is running is not
    /// sent in parallel: it runs once more when the current one ends. So answers can never
    /// arrive out of order, and a failure is never thrown away for being «old».
    func refresh(_ id: String) async {
        if inflight.contains(id) { again.insert(id); return }
        inflight.insert(id)
        defer { inflight.remove(id) }
        repeat {
            again.remove(id)
            guard let vc = sessions[id]?.vault else { return }
            do {
                let items = try await vc.approvals()
                let grants = (try? await vc.grants()) ?? state[id]?.grants ?? []
                let before = state[id].map { Set($0.items.map(\.id)) }
                set(id) {
                    $0.items = items; $0.grants = grants; $0.confirmedAt = nowMs(); $0.error = nil
                }
                if before != Set(items.map(\.id)) {
                    log.info("account \(self.state[id]?.account.deviceId ?? "?", privacy: .public): \(items.count) request(s)")
                }
            } catch {
                log.warning("refresh \(self.state[id]?.account.deviceId ?? "?", privacy: .public): \(String(describing: error), privacy: .public)")
                // What was on screen STAYS: failing to refresh is not «there are no requests».
                set(id) { $0.error = Self.messageOf(error) }
            }
        } while again.contains(id)
    }

    func approve(_ accountId: String, _ requestId: String) { answer(accountId, requestId) { try await $0.approve(requestId) } }
    func deny(_ accountId: String, _ requestId: String) { answer(accountId, requestId) { try await $0.deny(requestId) } }
    func revokeGrant(_ accountId: String, _ grantId: String) { answer(accountId, grantId) { try await $0.revokeGrant(grantId) } }

    private func answer(_ accountId: String, _ key: String, _ op: @escaping (VaultClient) async throws -> Void) {
        guard running else { return }
        guard let vc = sessions[accountId]?.vault else { set(accountId) { $0.error = Self.notConnected }; return }
        set(accountId) { $0.busy.insert(key); $0.error = nil }
        Task {
            do {
                try await op(vc)
                // Answered: it leaves the list NOW, and the vault's list confirms it next.
                set(accountId) { st in
                    st.items.removeAll { $0.id == key }
                    st.grants.removeAll { $0.id == key }
                }
            } catch {
                set(accountId) { $0.error = Self.messageOf(error) }
            }
            set(accountId) { $0.busy.remove(key) }
            await refresh(accountId)
        }
    }

    /// `cannot-approve` is the one the screen translates and explains (the record does not let
    /// this key approve yet: `+aprueba` is missing). Anything else is shown as the vault or the
    /// network said it: it is what someone will paste in an issue.
    private static func messageOf(_ e: Error) -> String {
        if let v = e as? VaultError {
            if v.code == "acta" || v.code == VaultClient.noApprove { return cannotApprove }
            if v.code == "vault-no-reply" { return noReply }
        }
        return String(describing: e)
    }

    private func set(_ id: String, _ f: (inout AccountState) -> Void) {
        guard var st = state[id] else { return }
        f(&st)
        state[id] = st
    }

    /// Removes an account from this phone: its keys go with it. It stays in the vault's record until revoked there.
    func remove(_ accountId: String) {
        do { try store.remove(accountId) } catch {
            set(accountId) { $0.error = String(describing: error) }
            return
        }
        sessions.removeValue(forKey: accountId)?.conn.close()
        state[accountId] = nil
    }
}
