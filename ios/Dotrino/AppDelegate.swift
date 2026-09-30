import DotrinoNative
import DotrinoNativeUI
import UIKit
import UserNotifications

/// La app de Dotrino en iOS: la misma cáscara que en Android — las páginas del ecosistema
/// dentro de un WKWebView, con la identidad firmando con la llave del Secure Enclave, y la
/// pestaña Pedidos nativa.
///
/// El timbre de Pedidos va por APNs, directo desde el proxio (`Push`): con la app cerrada, un
/// pedido de la bóveda enseña un aviso sin contenido; con Pedidos a la vista, se refresca ahí.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Antes que nada: las llaves y el almacén van a los grupos del equipo, los mismos para
        // todas las apps de Dotrino del teléfono. Sin los grupos en la firma no se sigue.
        do {
            try SharedStorage.share(keychainAccessGroup: "P7G853375S.com.dotrino.shared", appGroup: "group.com.dotrino")
        } catch {
            preconditionFailure("shared storage: \(error)")
        }
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = MainTabController()
        window?.makeKeyAndVisible()
        // After pairing, the new account gets this phone's push token (the bridge is dotrino-native's).
        IdentityWebBridge.onSaved = { Push.accountAdded($0) }
        UNUserNotificationCenter.current().delegate = self
        DotrinoPush.register()
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

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Push.tokenArrived(DotrinoPush.token(deviceToken))
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.warning("APNs registration failed: \(String(describing: error), privacy: .public)")
    }

    /// A ring with the app open: with Requests on screen it refreshes there and the banner is not
    /// needed (like Android's `onRing`); anywhere else, the banner shows.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        let tabs = window?.rootViewController as? MainTabController
        done(tabs?.onRing() == true ? [] : [.banner, .sound])
    }

    /// Tapping the ring opens Requests.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        (window?.rootViewController as? MainTabController)?.openApprovalsTab()
        done()
    }

    /// Enlaces del ecosistema: se abren dentro de la app (cuando haya enlaces universales).
    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let url = userActivity.webpageURL, MainTabController.isInside(url) else { return false }
        (window?.rootViewController as? MainTabController)?.open(url: url)
        return true
    }
}
