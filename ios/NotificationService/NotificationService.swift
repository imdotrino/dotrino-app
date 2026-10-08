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
            let (items, notices) = await Self.pending()
            // SIN PEDIDOS Y CON UNA NOTICIA NUEVA: el timbre era para contarla («tu bóveda se
            // actualizó», vaultd ≥ 0.147.0), no para pedir nada. Con pedidos, mandan los pedidos.
            let updated = Self.freshUpdate(notices)
            if items.isEmpty, let updated {
                // La bóveda, o un aparato del acta (un agente) que se nombra por su etiqueta o su ID.
                c.title = updated.device.map { Self.t("notif_updated_device_title", [$0]) } ?? Self.t("notif_updated_title", [])
                c.body = Self.t("notif_updated_body", [updated.version])
            } else if !items.isEmpty, let newest = items.max(by: { $0.exp < $1.exp }) {
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

    /// De los avisos que trae la bóveda, el `updated` más reciente que este teléfono todavía NO
    /// enseñó, o `nil`. Los que vienen quedan apuntados como enseñados (y solo esos), así un
    /// timbre posterior no repite la misma noticia.
    static func freshUpdate(_ notices: [VaultNotice], defaults: UserDefaults = .standard) -> VaultNotice? {
        let key = "shownNotices"
        let shown = Set(defaults.stringArray(forKey: key) ?? [])
        let updated = notices.filter { $0.ev == "updated" }
        let fresh = updated.filter { !shown.contains($0.id) }.max(by: { $0.ts < $1.ts })
        if !updated.isEmpty { defaults.set(updated.map(\.id), forKey: key) }
        return fresh
    }

    /// Los pedidos vivos y los avisos de todas las cuentas del teléfono. Si la bóveda renueva el
    /// papel de una cuenta mientras tanto, SE GUARDA: emitir uno nuevo retira el anterior.
    static func pending() async -> ([Approval], [VaultNotice]) {
        guard let accounts = try? AccountStore.shared.list() else { return ([], []) }
        return await withTaskGroup(of: ([Approval], [VaultNotice]).self) { group in
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
                        // A ring just got here, so this phone does receive them: say so.
                        let r = try await vc.approvalsWithNotices(notify: true)
                        return (r.items, r.notices)
                    } catch { return ([], []) }
                }
            }
            var all: ([Approval], [VaultNotice]) = ([], [])
            for await r in group { all.0 += r.0; all.1 += r.1 }
            return all
        }
    }
}
