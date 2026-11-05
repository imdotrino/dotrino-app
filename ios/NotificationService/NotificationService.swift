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
        // EL ASUNTO, ANTES QUE NADA (dueño, 2026-11-04: «que al menos tengan asunto, para ver
        // quién solicita qué»). Viene sellado a este teléfono en el timbre (vaultd ≥ 0.190.0) y
        // se abre sin red: la alerta dice el porqué aunque la bóveda no conteste a tiempo.
        // DE QUÉ CUENTA ES (dueño, 2026-11-05: «las notificaciones llevan el nombre del perfil,
        // deberían»): un teléfono aprueba por varias cuentas, y la alerta no decía de cuál. Va en
        // el subtítulo: el id del pedido o del aviso → el nombre de la cuenta que lo abrió.
        let opened = Self.subject(request.content.userInfo["sealed"] as? String)
        let subject = opened?.0
        if let (s, name) = opened {
            Self.apply(s, to: c)
            c.subtitle = name
        }
        Task {
            let (items, notices, answered, names) = await Self.pending()
            // A RING THAT NO ACCOUNT EXPLAINS may be for one that is no longer on this phone:
            // the proxy is told which ones are left, so that one stops ringing.
            if answered, items.isEmpty, notices.isEmpty { await PushPrune.run() }
            // SIN PEDIDOS Y CON UNA NOTICIA NUEVA: el timbre era para contarla («tu bóveda se
            // actualizó», o tiene una versión que no puede instalar sola; vaultd ≥ 0.147.0), no para pedir nada. Con pedidos, mandan los pedidos.
            if let n = subject.flatMap(VaultRing.notice) { Self.markShown(n.id) }
            let updated = Self.freshUpdate(notices)
            if items.isEmpty, let updated {
                Self.describe(updated, into: c)
                c.subtitle = RequestText.profilesOf([updated.id], names) ?? ""
            } else if !items.isEmpty, let newest = items.max(by: { $0.exp < $1.exp }) {
                c.subtitle = RequestText.profilesOf(items.map(\.id), names) ?? 
                if items.count == 1 {
                    c.title = RequestText.title(newest, Self.t)
                    c.body = Self.t("notif_tap", [])
                } else {
                    c.title = Self.t("notif_many", [items.count])
                    c.body = RequestText.title(newest, Self.t)
                }
            } else if answered, subject == nil {
                // NO HAY PEDIDO: la bóveda contestó y no pide nada (un aviso ya contado, o uno que
                // esta app no sabe pintar). iOS no deja callar la alerta, pero sí dejar de decir
                // «tu bóveda tiene un pedido» cuando no lo hay (2026-11-04: avisos de pedidos de
                // aparatos con `unattended` que no habían pedido nada).
                c.title = Self.t("notif_nothing_title", [])
                c.body = Self.t("notif_nothing_body", [])
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

    static let evNeedsRoot = "update-needs-root"

    /// El asunto sellado del timbre, abierto con la llave de alguna cuenta de este teléfono.
    /// Y el nombre de esa cuenta, que va en el subtítulo.
    static func subject(_ sealed: String?) -> (JSON, String)? {
        guard let sealed, !sealed.isEmpty, let accounts = try? AccountStore.shared.list() else { return nil }
        for a in accounts {
            guard let keys = try? PhoneKeys.open(a.id) else { continue }
            if let s = VaultRing.open(sealed, keys: keys) { return (s, a.name) }
        }
        return nil
    }

    /// Lo que dice el asunto, en la alerta: el pedido, o el aviso.
    static func apply(_ s: JSON, to c: UNMutableNotificationContent) {
        if let a = VaultRing.approval(s) {
            c.title = RequestText.title(a, t)
            c.body = t("notif_tap", [])
        } else if let n = VaultRing.notice(s) {
            describe(n, into: c)
        }
    }

    /// Un aviso en la alerta. QUIÉN: la bóveda, o un aparato del acta que se nombra por su
    /// etiqueta o su ID. QUÉ: se actualizó, necesita permisos de administrador, o (`delivered`)
    /// un aparato desatendido se llevó claves sin pedir —porque lo tiene concedido—.
    static func describe(_ n: VaultNotice, into c: UNMutableNotificationContent) {
        if n.ev == "delivered" {
            let who = n.device ?? "?"
            c.title = n.kind == "passwords" ? t("notif_delivered_passwords_title", [who])
                : t("notif_delivered_secrets_title", [who, n.ns ?? "?"])
            c.body = t("notif_delivered_body", [])
            return
        }
        let base = n.ev == evNeedsRoot ? "notif_needs_root" : "notif_updated"
        c.title = n.device.map { t(base + "_device_title", [$0]) } ?? t(base + "_title", [])
        c.body = t(base + "_body", [n.version])
    }

    /// Apunta un aviso como ya enseñado (lo contó el asunto), sin olvidar los demás.
    static func markShown(_ id: String, defaults: UserDefaults = .standard) {
        let key = "shownNotices"
        let shown = defaults.stringArray(forKey: key) ?? []
        if !shown.contains(id) { defaults.set(shown + [id], forKey: key) }
    }

    /// De los avisos que trae la bóveda, el más reciente de los que esta app sabe contar y que
    /// este teléfono todavía NO enseñó, o `nil`. Los que vienen quedan apuntados como enseñados (y solo esos), así un
    /// timbre posterior no repite la misma noticia.
    static func freshUpdate(_ notices: [VaultNotice], defaults: UserDefaults = .standard) -> VaultNotice? {
        let key = "shownNotices"
        let shown = Set(defaults.stringArray(forKey: key) ?? [])
        let updated = notices.filter { $0.ev == "updated" || $0.ev == evNeedsRoot || $0.ev == "delivered" }
        let fresh = updated.filter { !shown.contains($0.id) }.max(by: { $0.ts < $1.ts })
        if !updated.isEmpty { defaults.set(updated.map(\.id), forKey: key) }
        return fresh
    }

    /// Los pedidos vivos y los avisos de todas las cuentas del teléfono. Si la bóveda renueva el
    /// papel de una cuenta mientras tanto, SE GUARDA: emitir uno nuevo retira el anterior.
    /// `answered`: alguna bóveda contestó. Sin eso, una lista vacía es «no pude preguntar».
    /// `names`: de qué cuenta es cada pedido y cada aviso (id → nombre), para el subtítulo.
    static func pending() async -> ([Approval], [VaultNotice], Bool, [String: String]) {
        guard let accounts = try? AccountStore.shared.list() else { return ([], [], false, [:]) }
        return await withTaskGroup(of: ([Approval], [VaultNotice], Bool, [String: String]).self) { group in
            for a in accounts {
                group.addTask {
                    do {
                        let keys = try PhoneKeys.open(a.id)
                        let c = try ProxyConnection(a.proxy, app: "vault")   // the approver app: its rings and its queue
                        defer { c.close() }
                        try await c.connect()
                        try await c.identify(keys)
                        let vc = VaultClient(account: a, keys: keys, conn: c) { renewed in
                            try? AccountStore.shared.save(renewed)
                        }
                        // A ring just got here, so this phone does receive them: say so.
                        let r = try await vc.approvalsWithNotices(notify: true)
                        LogAnchors.check(accountId: a.id, notices: r.notices)
                        var names: [String: String] = [:]
                        for i in r.items { names[i.id] = a.name }
                        for n in r.notices { names[n.id] = a.name }
                        return (r.items, r.notices, true, names)
                    } catch { return ([], [], false, [:]) }
                }
            }
            var all: ([Approval], [VaultNotice], Bool, [String: String]) = ([], [], false, [:])
            for await r in group { all.0 += r.0; all.1 += r.1; all.2 = all.2 || r.2; all.3.merge(r.3) { a, _ in a } }
            return all
        }
    }
}
