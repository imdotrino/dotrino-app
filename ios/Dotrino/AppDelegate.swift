import UIKit
import UserNotifications

/// La app de Dotrino en iOS: la misma cáscara que en Android — las páginas del ecosistema
/// dentro de un WKWebView (el pilar de identidad corre ahí, con sus perfiles), y lo nativo
/// es el aviso del sistema (APNs) que despierta la app cuando la bóveda tiene un pedido.
@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?
    /// Token de APNs; la bóveda lo recibe por el proxio para poder «timbrar» este aparato.
    static var pushToken: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = MainTabController()
        window?.makeKeyAndVisible()

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted { DispatchQueue.main.async { application.registerForRemoteNotifications() } }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AppDelegate.pushToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .dotrinoPushToken, object: nil)
    }

    /// Un timbre (sin contenido) → abrir Pedidos. El detalle lo trae la página por el proxio.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        (window?.rootViewController as? MainTabController)?.open(url: MainTabController.vault)
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Enlaces universales del ecosistema: se abren dentro de la app.
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let url = userActivity.webpageURL, MainTabController.isInside(url) else { return false }
        (window?.rootViewController as? MainTabController)?.open(url: url)
        return true
    }
}

extension Notification.Name { static let dotrinoPushToken = Notification.Name("dotrinoPushToken") }
