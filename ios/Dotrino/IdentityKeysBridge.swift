import DotrinoNative
import Foundation
import WebKit

/// `window.DotrinoIdentityKeys` — the identity of the WebView (the `id.dotrino.com` iframe)
/// keeps its keys in THIS phone's Secure Enclave instead of IndexedDB. One key per account:
/// the same one that approves on the native Requests screen, so the phone is ONE device in the
/// record, with its profile and its approvals. The JS side is
/// `dotrino-identity/vault/externalKeys.js`; this is the iOS twin of `IdentityKeysBridge.kt`.
///
/// The private halves never leave the enclave: the page asks to sign bytes or to agree an ECDH
/// secret, and that is all it can do.
///
/// ONLY `https://id.dotrino.com` gets an answer — in any frame, because the identity is an
/// iframe inside every page. WebKit shows `window.webkit.messageHandlers` to every frame, so
/// the check is HERE, on the frame's security origin, for every message. That origin is the
/// identity itself: it can already sign as you with its own keys, so the bridge gives it
/// nothing it did not have.
///
/// Protocol: the page posts `{ id, method, params }` as JSON; the answer comes back as
/// `{ id, result }` or `{ id, error, code }`. The shim below gives the page the same
/// `{ postMessage, onmessage }` port Android's `addWebMessageListener` gives.
final class IdentityKeysBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let name = "dotrinoIdentityKeys"
    static let origin = (proto: "https", host: "id.dotrino.com")

    struct BridgeError: Error, CustomStringConvertible {
        let description: String
        let code: String
    }

    /// Injected at document start in every frame; it only does something in the identity's.
    static let shim = """
    (function () {
      if (location.origin !== 'https://id.dotrino.com') return
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(name)
      if (!h) return
      var port = {
        onmessage: null,
        postMessage: function (s) {
          h.postMessage(s).then(function (r) {
            if (port.onmessage) port.onmessage({ data: r })
          }, function (e) {
            var id = null
            try { id = JSON.parse(s).id } catch (_) {}
            if (port.onmessage) port.onmessage({ data: JSON.stringify({ id: id, error: String((e && e.message) || e), code: 'native-error' }) })
          })
        }
      }
      Object.defineProperty(window, 'DotrinoIdentityKeys', { value: port })
    })();
    """

    static func install(_ cfg: WKWebViewConfiguration) {
        cfg.userContentController.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        cfg.userContentController.addScriptMessageHandler(IdentityKeysBridge(), contentWorld: .page, name: name)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let o = message.frameInfo.securityOrigin
        // A wrong origin gets nothing but a bare rejection (WebKit wants every reply handler
        // called once): no key, no result, no hint of what exists.
        guard o.protocol == Self.origin.proto, o.host == Self.origin.host, o.port == 0 else { replyHandler(nil, "forbidden"); return }
        guard let text = message.body as? String, let req = try? JSON.parse(text), let id = req["id"]?.string else {
            replyHandler(nil, "bad request"); return
        }
        let method = req["method"]?.string
        let params = req["params"] ?? [:]
        Task.detached {
            let out: JSON
            do {
                out = ["id": .string(id), "result": try Self.call(method, params)]
            } catch {
                log.warning("identity keys \(method ?? "?", privacy: .public): \(String(describing: error), privacy: .public)")
                out = ["id": .string(id), "error": .string(String(describing: error)),
                       "code": .string((error as? BridgeError)?.code ?? "native-error")]
            }
            await MainActor.run { replyHandler(out.text, nil) }
        }
    }

    /// The key [kid], or the error the page shows: no other key is ever made in its place.
    private static func keys(_ kid: String) throws -> EnclaveKeys {
        guard EnclaveKeys.exists(kid) else { throw BridgeError(description: "that key is not on this phone", code: "native-key-gone") }
        return try EnclaveKeys.open(kid)
    }

    private static func str(_ p: JSON, _ k: String) throws -> String {
        guard let v = p[k]?.string else { throw BridgeError(description: "missing \(k)", code: "native-bad-request") }
        return v
    }

    private static func call(_ method: String?, _ p: JSON) throws -> JSON {
        switch method {
        case "create":
            let kid = UUID().uuidString.lowercased()
            let k = try EnclaveKeys.create(kid)
            return ["kid": .string(kid), "publickey": .string(k.publickey), "encPub": .string(k.encPub)]
        case "open":
            let kid = try str(p, "kid")
            let k = try keys(kid)
            return ["kid": .string(kid), "publickey": .string(k.publickey), "encPub": .string(k.encPub)]
        case "sign":
            return ["signature": .string(try keys(str(p, "kid")).signBytes(Crypto.fromB64(str(p, "data"))))]
        case "deriveBits":
            let bits = try keys(str(p, "kid")).agree(Crypto.agreementKey(jwk: str(p, "peer")))
            return ["bits": .string(Crypto.b64(bits))]
        case "save":
            // After pairing: the native Requests screen gets the account, with the SAME paper.
            let kid = try str(p, "kid")
            let k = try keys(kid)
            guard let cert = p["cert"], cert.object != nil else { throw BridgeError(description: "save: missing cert", code: "native-bad-request") }
            let vault = try str(p, "vault")
            if let why = Delegation.check(cert, vault: vault, sub: k.publickey, expectedScope: nil) {
                throw BridgeError(description: "the paper does not check out: \(why)", code: "bad-paper")
            }
            let name = p["name"]?.string ?? ""
            let account = Account(id: kid, name: name.isEmpty ? try Delegation.keyLabel(vault) : name,
                                  profileId: p["profileId"]?.string, vault: vault, proxy: try str(p, "proxy"),
                                  cert: cert, deviceId: try Delegation.keyLabel(k.publickey))
            try AccountStore.shared.save(account)
            return ["deviceId": .string(account.deviceId)]
        case "remove":
            // The identity removed that profile: its key and its native account go with it.
            try AccountStore.shared.remove(str(p, "kid"))
            return ["ok": true]
        default:
            throw BridgeError(description: "unknown method: \(method ?? "nil")", code: "native-bad-request")
        }
    }
}
