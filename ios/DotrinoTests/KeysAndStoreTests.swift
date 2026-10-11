import XCTest
import CryptoKit
import DotrinoNative

/// The keys and the accounts file against the real Keychain (these run hosted in the app,
/// which is what gives them one). In the simulator the keys are software ones — the enclave
/// path is only compiled for a device.
final class KeysAndStoreTests: XCTestCase {
    private let id = "test-\(UUID().uuidString)"

    override func tearDown() { EnclaveKeys.delete(id) }

    func testCreateOpenSignAgreeDelete() throws {
        let k = try EnclaveKeys.create(id)
        XCTAssertThrowsError(try EnclaveKeys.create(id), "never overwrites an existing pair")
        let again = try EnclaveKeys.open(id)
        XCTAssertEqual(k.publickey, again.publickey)
        XCTAssertEqual(k.encPub, again.encPub)

        let data: JSON = ["op": "x", "ts": 1]
        XCTAssertTrue(Crypto.verify(publickey: k.publickey, data: data, signature: try again.sign(Canonical.stringify(data))))

        let other = try EnclaveKeys.create(id + "-b")
        defer { EnclaveKeys.delete(id + "-b") }
        let ab = try k.agree(Crypto.agreementKey(jwk: other.encPub))
        let ba = try other.agree(Crypto.agreementKey(jwk: k.encPub))
        XCTAssertEqual(ab, ba)
        XCTAssertEqual(ab.count, 32)

        EnclaveKeys.delete(id)
        XCTAssertFalse(EnclaveKeys.exists(id))
        XCTAssertThrowsError(try EnclaveKeys.open(id))
    }

    /// The key a vault hands over at sign-in (user and password): kept sealed, used like any other.
    func testImportedKeysSignAgreeAndGoWithTheAccount() throws {
        defer { PhoneKeys.delete(id) }
        func b64u(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let s = P256.Signing.PrivateKey(), e = P256.KeyAgreement.PrivateKey(), other = P256.Signing.PrivateKey()
        let publickey = Crypto.jwk(raw: s.publicKey.rawRepresentation), encPub = Crypto.jwk(raw: e.publicKey.rawRepresentation)
        let sign: JSON = ["kty": "EC", "crv": "P-256", "d": .string(b64u(s.rawRepresentation))]
        let enc: JSON = ["kty": "EC", "crv": "P-256", "d": .string(b64u(e.rawRepresentation))]

        XCTAssertThrowsError(try ImportedKeys.import(id, sign: sign, enc: enc, publickey: Crypto.jwk(raw: other.publicKey.rawRepresentation), encPub: encPub),
                             "a private key that is not the pair of its public one is refused")
        XCTAssertFalse(PhoneKeys.exists(id))

        try ImportedKeys.import(id, sign: sign, enc: enc, publickey: publickey, encPub: encPub)
        let k = try PhoneKeys.open(id)   // reopened from the Keychain, as after a restart
        XCTAssertEqual(k.publickey, publickey)
        XCTAssertEqual(k.encPub, encPub)
        let data: JSON = ["op": "x", "ts": 1]
        XCTAssertTrue(Crypto.verify(publickey: publickey, data: data, signature: try k.sign(Canonical.stringify(data))))
        let peer = P256.KeyAgreement.PrivateKey()
        XCTAssertEqual(try k.agree(peer.publicKey), try peer.sharedSecretFromKeyAgreement(with: e.publicKey).withUnsafeBytes { Data($0) })

        PhoneKeys.delete(id)
        XCTAssertFalse(PhoneKeys.exists(id))
    }

    func testAccountsRoundTripEncrypted() throws {
        let store = AccountStore()
        let before = try store.list()
        let k = try EnclaveKeys.create(id)
        let a = Account(id: id, name: "Prueba ñ", profileId: nil, vault: k.publickey, proxy: "wss://proxy.dotrino.com",
                        cert: ["iss": .string(k.publickey), "seq": 3], deviceId: try Delegation.keyLabel(k.publickey))
        try store.save(a)
        XCTAssertEqual(try store.list().first { $0.id == id }, a)
        try store.remove(id)
        XCTAssertEqual(try store.list(), before)
        XCTAssertFalse(EnclaveKeys.exists(id), "removing the account deletes its keys")
    }
}

final class IdentityStoreTests: XCTestCase {
    func testWhatOnePageSavesTheNextSees() throws {
        let k = "kv:test-\(UUID().uuidString)"
        try IdentityStore.shared.set(k, #"["p1"]"#)
        XCTAssertEqual(try IdentityStore().all()[k], #"["p1"]"#, "a fresh instance reads it from the sealed file")
        try IdentityStore.shared.remove(k)
        XCTAssertNil(try IdentityStore().all()[k])
    }
}
