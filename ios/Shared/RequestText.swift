import DotrinoNative
import Foundation

/// WHAT A REQUEST IS ASKING FOR, in one line. The same text in the Requests screen and in the
/// notification (the service extension), so the notice says the why and never disagrees with
/// what the screen shows. `t` translates a key with its arguments: the app passes its `L`
/// (the in-app language), the extension the system's.
enum RequestText {
    typealias T = (_ key: String, _ args: [CVarArg]) -> String

    static func who(_ a: Approval) -> String {
        a.label.isEmpty ? a.deviceId : "\(a.label) (\(a.deviceId))"
    }

    static func title(_ a: Approval, _ t: T) -> String {
        switch a.kind {
        // The vault itself asks to install a new version (vaultd ≥ 0.130.0).
        case "update": return t("req_update", [a.ctx?["version"]?.string ?? "?"])
        case "write": return t("req_writes", [who(a), a.ns])
        // The password vault: which FIELDS it wants to read (vaultd ≥ 0.136.0), never the entry.
        case "passwords": return t("req_passwords", [who(a)])
        // An INCIDENT (vaultd ≥ 0.142.0): a device failed the terminal code of `ns` (the reporter) three times. Block or ignore.
        case "incident": return t("req_incident", [who(a), reporter(a)])
        default: return t("req_asks", [who(a), a.ns])
        }
    }

    /// Who reported the incident: its label and id, or just the id (`ns`).
    static func reporter(_ a: Approval) -> String {
        if let label = a.ctx?["reporterLabel"]?.string, !label.isEmpty { return "\(label) (\(a.ns))" }
        return a.ns
    }

    /// «Fields: password, 2FA code» for a password request; nil when it names none.
    static func fields(_ a: Approval, _ t: T) -> String? {
        let list = (a.ctx?["fields"]?.array ?? []).compactMap { $0.string }
        if list.isEmpty { return nil }
        return t("req_fields", [list.map { fieldName($0, t) }.joined(separator: ", ")])
    }

    private static func fieldName(_ f: String, _ t: T) -> String {
        switch f {
        case "password": return t("field_password", [])
        case "totp": return t("field_totp", [])
        case "passkey", "webauthn": return t("field_passkey", [])
        case "notes": return t("field_notes", [])
        default: return f
        }
    }
}
