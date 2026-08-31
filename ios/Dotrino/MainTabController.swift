import UIKit
import WebKit

/// Un solo WebView y tres pestañas: Inicio (dotrino.com), Perfil y Bóveda. La pestaña
/// marcada sigue a la página que se ve; los enlaces fuera de *.dotrino.com salen a Safari.
class MainTabController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    static let home = URL(string: "https://dotrino.com/")!
    static let profile = URL(string: "https://profile.dotrino.com/")!
    static let vault = URL(string: "https://vault.dotrino.com/vault")!
    /// A donde apunta el aviso: los pedidos, separados de la administración.
    static let approvals = URL(string: "https://vault.dotrino.com/approvals")!
    static func isInside(_ url: URL) -> Bool {
        guard let h = url.host else { return false }
        return h == "dotrino.com" || h.hasSuffix(".dotrino.com")
    }

    private var web: WKWebView!
    private let tabs = UITabBar()
    private let items = [
        UITabBarItem(title: NSLocalizedString("tab_home", comment: ""), image: UIImage(systemName: "house"), tag: 0),
        UITabBarItem(title: NSLocalizedString("tab_profile", comment: ""), image: UIImage(systemName: "person"), tag: 1),
        UITabBarItem(title: NSLocalizedString("tab_vault", comment: ""), image: UIImage(systemName: "lock"), tag: 2)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.043, green: 0.07, blue: 0.125, alpha: 1)
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // IndexedDB persistente: identidad y store
        cfg.allowsInlineMediaPlayback = true
        cfg.applicationNameForUserAgent = "DotrinoApp/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")"
        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = view.backgroundColor

        tabs.items = items
        tabs.delegate = self
        tabs.barTintColor = view.backgroundColor
        tabs.tintColor = UIColor(red: 0.31, green: 0.55, blue: 1, alpha: 1)

        [web, tabs].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: tabs.topAnchor),
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabs.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        open(url: Self.home)
    }

    func open(url: URL) { web.load(URLRequest(url: url)) }

    // Fuera del ecosistema → Safari.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame ?? true else { decisionHandler(.allow); return }
        if Self.isInside(url) || url.scheme == "about" { decisionHandler(.allow) } else { UIApplication.shared.open(url); decisionHandler(.cancel) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let h = webView.url?.host else { return }
        let tag = h == "profile.dotrino.com" ? 1 : h == "vault.dotrino.com" ? 2 : h == "dotrino.com" ? 0 : -1
        if tag >= 0 { tabs.selectedItem = items[tag] }
    }

    // Cámara (QR de emparejamiento) solo para el ecosistema.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.hasSuffix("dotrino.com") ? .grant : .deny)
    }

    // window.open → misma vista.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { if Self.isInside(url) { web.load(URLRequest(url: url)) } else { UIApplication.shared.open(url) } }
        return nil
    }
}

extension MainTabController: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        switch item.tag { case 1: open(url: Self.profile); case 2: open(url: Self.vault); default: open(url: Self.home) }
    }
}
