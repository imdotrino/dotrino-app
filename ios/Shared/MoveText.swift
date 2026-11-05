import DotrinoNative
import Foundation

/// WHAT HAPPENED IN THE LAST 24 HOURS, one line per notice (vaultd ≥ 0.193.0 for closed requests).
/// Same as Android's `MoveText.kt`.
///
/// The owner, 2026-11-05: «the notices arrive but when I open them in the app there is no trace of
/// anything». A request that was answered or expired left the list, and the ring that had already
/// sounded had nothing behind it. The vault keeps a notice for 24 h; this turns it into a line.
///
/// Devices are named with ALIAS AND ID («laptop (AB12-CD34)», `VaultNotice.device` / `approver`),
/// and the words of the system notices are reused where there is one (delivered, updated).
enum MoveText {
    /// Notices that say nothing to a person (the log anchor is checked, not shown).
    static func shown(_ n: VaultNotice) -> Bool { n.ev != "log-anchor" }

    static func text(_ n: VaultNotice, _ t: RequestText.T) -> String {
        switch n.ev {
        case "answered":
            let w = n.device ?? t("move_the_vault", []); let ns = n.ns ?? "?"
            let what: String
            switch n.kind {
            case "write": what = t("move_writes", [w, ns])
            case "reveal": what = t("move_reveals", [w, ns])
            case "passwords": what = t("move_passwords", [w])
            case "update": what = t("move_update", [w])
            case "incident": what = t("move_incident", [w])
            default: what = t("move_asks", [w, ns])
            }
            let outcomes = ["approved", "denied", "blocked", "ignored", "withdrawn", "expired"]
            let how = n.outcome.flatMap { outcomes.contains($0) ? t("move_" + $0, []) : $0 } ?? "?"
            let by = n.approver.map { " " + t("move_by", [$0]) } ?? ""
            return "\(what): \(how)\(by)"
        case "delivered":
            let w = n.device ?? "?"
            return n.kind == "passwords" ? t("notif_delivered_passwords_title", [w]) : t("notif_delivered_secrets_title", [w, n.ns ?? "?"])
        case "updated":
            return (n.device.map { t("notif_updated_device_title", [$0]) } ?? t("notif_updated_title", [])) + " (\(n.version))"
        case "update-needs-root":
            return (n.device.map { t("notif_needs_root_device_title", [$0]) } ?? t("notif_needs_root_title", [])) + " (\(n.version))"
        case "pairing-contested":
            return t("move_contested", [])
        default:
            return n.ev
        }
    }
}
