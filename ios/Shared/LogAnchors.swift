import DotrinoNative
import Foundation
import UserNotifications

/// EL ANCLA DE LA BITÁCORA, guardada en este teléfono (vault ≥ 0.104.0). Igual que `LogAnchors.kt`.
///
/// La bóveda sella cada pocas horas la cabeza de su bitácora y la manda, callada, a quien
/// aprueba. Este teléfono guarda la última de cada cuenta: si llega una con menos entradas, o
/// con las mismas y otra cabeza, alguien cortó o reescribió el final de la bitácora en esa
/// máquina, y eso es justo lo que la cadena sola no deja ver. Entonces se avisa, una vez por
/// ancla distinta, y la buena (la vieja) se queda guardada. En el grupo de la app, para que la
/// app y la extensión de avisos vean lo mismo.
enum LogAnchors {
    private static let defaults = UserDefaults(suiteName: "group.com.dotrino")
    private static let prefix = "log-anchor:"

    /// Compara el ancla más nueva de `notices` con la guardada de `accountId`. `nil` si no vino ninguna.
    @discardableResult
    static func check(accountId: String, notices: [VaultNotice]) -> LogAnchor.Verdict? {
        guard let defaults, let next = LogAnchor.latest(notices), let seq = next.logSeq, let head = next.head else { return nil }
        let kept = defaults.string(forKey: prefix + accountId)?.split(separator: "|").map(String.init)
        let verdict = LogAnchor.compare(lastSeq: kept?.first.flatMap { Int64($0) }, lastHead: kept?.dropFirst().first, seq: seq, head: head)
        let incoming = "\(seq)|\(head)"
        if verdict.isAlarm {
            let alarmKey = prefix + "alarm:" + accountId
            if defaults.string(forKey: alarmKey) != incoming {
                defaults.set(incoming, forKey: alarmKey)
                notifyCut()
            }
        } else if verdict != .same {
            defaults.set(incoming, forKey: prefix + accountId)
        }
        return verdict
    }

    private static func notifyCut() {
        let c = UNMutableNotificationContent()
        c.title = NSLocalizedString("notif_log_cut_title", comment: "")
        c.body = NSLocalizedString("notif_log_cut_body", comment: "")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "log-cut", content: c, trigger: nil))
    }
}
