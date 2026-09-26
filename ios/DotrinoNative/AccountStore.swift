import CryptoKit
import Foundation

/// An account this phone approves for natively: which vault, through which proxy, and the
/// paper (`cert`) the vault gave to this device's key. No secret in here — the keys live in
/// the Secure Enclave under [id].
public struct Account: Equatable, Sendable {
    public let id: String
    public let name: String
    public let profileId: String?
    public let vault: String
    public let proxy: String
    public var cert: JSON
    public let deviceId: String
    public let addedAt: Int64

    public init(id: String, name: String, profileId: String?, vault: String, proxy: String, cert: JSON, deviceId: String, addedAt: Int64 = nowMs()) {
        self.id = id; self.name = name; self.profileId = profileId; self.vault = vault
        self.proxy = proxy; self.cert = cert; self.deviceId = deviceId; self.addedAt = addedAt
    }

    var json: JSON {
        var o: [String: JSON] = ["id": .string(id), "name": .string(name), "vault": .string(vault), "proxy": .string(proxy),
                                 "cert": cert, "deviceId": .string(deviceId), "addedAt": .int(addedAt)]
        if let profileId { o["profileId"] = .string(profileId) }
        return .object(o)
    }

    init(json o: JSON) throws {
        guard let id = o["id"]?.string, let name = o["name"]?.string, let vault = o["vault"]?.string,
              let proxy = o["proxy"]?.string, let cert = o["cert"], cert.object != nil, let deviceId = o["deviceId"]?.string
        else { throw CryptoError("accounts file: an account is missing fields") }
        self.init(id: id, name: name, profileId: o["profileId"]?.string, vault: vault, proxy: proxy, cert: cert,
                  deviceId: deviceId, addedAt: o["addedAt"]?.int ?? 0)
    }
}

/// The accounts this phone approves for, on disk. Nothing secret is stored (vault key, proxy,
/// paper, name), but the list of vaults a person belongs to is theirs, so the file is
/// encrypted with an AES key kept in the Keychain, only on this device.
///
/// A file that exists but does not open is an ERROR, not an empty list: treating it as
/// «no accounts» would silently make the phone stop approving.
public final class AccountStore: @unchecked Sendable {
    public static let shared = AccountStore()
    private static let keyAlias = "dotrino.accounts"
    private let lock = NSLock()
    private let file: URL

    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("dotrino-accounts.bin")
    }

    private func key() throws -> SymmetricKey {
        if let d = try Keychain.get(Self.keyAlias) { return SymmetricKey(data: d) }
        let k = SymmetricKey(size: .bits256)
        try Keychain.add(Self.keyAlias, k.withUnsafeBytes { Data($0) })
        return k
    }

    public func list() throws -> [Account] {
        lock.lock(); defer { lock.unlock() }
        return try read()
    }

    private func read() throws -> [Account] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let raw = try Data(contentsOf: file)
        guard raw.count > 28 else { throw CryptoError("accounts file is truncated") }
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: raw), using: key())
        guard let arr = try JSON.parse(plain).array else { throw CryptoError("accounts file is not a list") }
        return try arr.map(Account.init(json:))
    }

    private func write(_ accounts: [Account]) throws {
        let body = Data(JSON.array(accounts.map(\.json)).text.utf8)
        guard let sealed = try AES.GCM.seal(body, using: key()).combined else { throw CryptoError("could not seal the accounts file") }
        // Atomic: a half-written file must never replace a good one.
        try sealed.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Adds or replaces the account with the same [Account.id].
    public func save(_ a: Account) throws {
        lock.lock(); defer { lock.unlock() }
        try write(read().filter { $0.id != a.id } + [a])
    }

    public func remove(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        try write(read().filter { $0.id != id })
        EnclaveKeys.delete(id)
    }
}
