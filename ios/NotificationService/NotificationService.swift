import DotrinoNative
import Foundation
import UserNotifications

/// EL AVISO DICE EL PORQUÉ (dueño, 2026-09-30: «es importante que se sepa el porqué de la
/// notificación»). El proxio manda por APNs un timbre sin contenido —Apple no ve nada— con
/// `mutable-content`, así que iOS despierta esta extensión antes de enseñarlo. Aquí se bajan
/// los pedidos de cada cuenta del teléfono, por el mismo camino que la pantalla de Pedidos, y
/// la alerta pasa a decir qué se pide («proxy1 pide tus claves de proxy»).
///
/// Si no se puede preguntar —teléfono bloqueado (las llaves del chip no se usan así), sin red,
/// o iOS corta el tiempo—, queda la alerta de siempre. Nunca se inventa un motivo.
final class NotificationService: UNNotificationServiceExtension {
    private let lock = NSLock()
    private var deliver: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler handler: @escaping (UNNotificationContent) -> Void) {
        let c = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        lock.withLock { deliver = handler; content = c }
        Task {
            let items = await Self.pending()
            if !items.isEmpty, let newest = items.max(by: { $0.exp < $1.exp }) {
                if items.count == 1 {
                    c.title = RequestText.title(newest, Self.t)
                    c.body = Self.t("notif_tap", [])
                } else {
                    c.title = Self.t("notif_many", [items.count])
                    c.body = RequestText.title(newest, Self.t)
                }
            }
            self.finish()
        }
    }

    /// iOS avisa de que se acaba el tiempo: sale lo que haya (la alerta de siempre si no llegó nada).
    override func serviceExtensionTimeWillExpire() { finish() }

    /// Entrega UNA vez: lo pueden pedir a la vez el fin de la consulta y el fin del tiempo.
    private func finish() {
        let (d, c) = lock.withLock { () -> (((UNNotificationContent) -> Void)?, UNMutableNotificationContent?) in
            let r = (deliver, content); deliver = nil; return r
        }
        if let d, let c { d(c) }
    }

    /// Los textos con el idioma del sistema (esta extensión no ve la preferencia de la app).
    static func t(_ key: String, _ args: [CVarArg]) -> String {
        let f = NSLocalizedString(key, comment: "")
        return args.isEmpty ? f : String(format: f, arguments: args)
    }

    /// Los pedidos vivos de todas las cuentas del teléfono. Si la bóveda renueva el papel de una
    /// cuenta mientras tanto, SE GUARDA: emitir uno nuevo retira el anterior.
    static func pending() async -> [Approval] {
        guard let accounts = try? AccountStore.shared.list() else { return [] }
        return await withTaskGroup(of: [Approval].self) { group in
            for a in accounts {
                group.addTask {
                    do {
                        let keys = try EnclaveKeys.open(a.id)
                        let c = try ProxyConnection(a.proxy, app: "vault")   // the approver app: its rings and its queue
                        defer { c.close() }
                        try await c.connect()
                        try await c.identify(keys)
                        let vc = VaultClient(account: a, keys: keys, conn: c) { renewed in
                            try? AccountStore.shared.save(renewed)
                        }
                        return try await vc.approvals()
                    } catch { return [] }
                }
            }
            var all: [Approval] = []
            for await items in group { all += items }
            return all
        }
    }
}
