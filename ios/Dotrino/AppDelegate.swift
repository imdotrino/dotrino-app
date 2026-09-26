import UIKit

/// La app de Dotrino en iOS: la misma cáscara que en Android — las páginas del ecosistema
/// dentro de un WKWebView, con la identidad firmando con la llave del Secure Enclave, y la
/// pestaña Pedidos nativa.
///
/// Sin push todavía: el aviso del sistema (APNs) necesita una cuenta de Apple Developer y que
/// el proxio sepa timbrar por APNs. Hasta entonces Pedidos se entera en vivo mientras está a
/// la vista, como en Android con la pantalla abierta.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = MainTabController()
        window?.makeKeyAndVisible()
        #if DEBUG
        // Para capturas en el simulador: `simctl launch <sim> com.dotrino.app -approvals` abre Pedidos.
        if let i = CommandLine.arguments.firstIndex(of: "-openURL"), i + 1 < CommandLine.arguments.count,
           let url = URL(string: CommandLine.arguments[i + 1]) {
            DispatchQueue.main.async { (self.window?.rootViewController as? MainTabController)?.open(url: url) }
        }
        if CommandLine.arguments.contains("-approvals") {
            DispatchQueue.main.async { (self.window?.rootViewController as? MainTabController)?.openApprovalsTab() }
        }
        #endif
        return true
    }

    /// Enlaces del ecosistema: se abren dentro de la app (cuando haya enlaces universales).
    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let url = userActivity.webpageURL, MainTabController.isInside(url) else { return false }
        (window?.rootViewController as? MainTabController)?.open(url: url)
        return true
    }
}
