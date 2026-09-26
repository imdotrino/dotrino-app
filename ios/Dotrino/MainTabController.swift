import Combine
import os
import SwiftUI
import UIKit
import WebKit

/// La app de Dotrino: una cáscara nativa sobre las mismas páginas del ecosistema. El pilar de
/// identidad (iframe id.dotrino.com) corre dentro del WKWebView igual que en un navegador,
/// con sus llaves en el Secure Enclave (IdentityKeysBridge). Pedidos es nativo.
///
/// Un solo WebView y cuatro pestañas: Inicio (dotrino.com), Perfil, Bóveda y Pedidos. La
/// pestaña marcada sigue a la página que se ve; los enlaces fuera de *.dotrino.com van a Safari.
final class MainTabController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    static let home = URL(string: "https://dotrino.com/")!
    static let profile = URL(string: "https://profile.dotrino.com/")!
    static let vault = URL(string: "https://vault.dotrino.com/vault")!
    /// Los pedidos en la web. El `#ring` le dice a la página que se llegó por el aviso (ver
    /// MainActivity.kt); va en el `#fragment`, que no llega al servidor.
    static let approvalsWeb = URL(string: "https://vault.dotrino.com/approvals#ring")!
    /// Donde se conecta una cuenta: el emparejamiento normal de la consola. Dentro de la app la
    /// identidad crea su llave en el enclave, así que esa misma llave tiene el perfil y aprueba
    /// en Pedidos: no hay un alta «nativa» aparte.
    static let addAccount = URL(string: "https://vault.dotrino.com/d")!

    static func isInside(_ url: URL) -> Bool {
        guard url.scheme == "https", let h = url.host else { return false }
        return h == "dotrino.com" || h.hasSuffix(".dotrino.com")
    }

    private enum Tab: Int { case home, profile, vault, approvals }

    private var web: WKWebView!
    private let tabs = UITabBar()
    private let offline = UIStackView()
    private let model = ApprovalsModel()
    private var approvalsHost: UIHostingController<ApprovalsView>!
    /// Pedidos: barra de Dotrino nativa + la lista (ApprovalsView), en un contenedor.
    private let approvalsBox = UIView()
    private var langSub: AnyCancellable?
    private lazy var items: [UITabBarItem] = [
        UITabBarItem(title: L("tab_home"), image: UIImage(systemName: "house"), tag: Tab.home.rawValue),
        UITabBarItem(title: L("tab_profile"), image: UIImage(systemName: "person.crop.circle"), tag: Tab.profile.rawValue),
        UITabBarItem(title: L("tab_vault"), image: UIImage(systemName: "lock.shield"), tag: Tab.vault.rawValue),
        UITabBarItem(title: L("tab_approvals"), image: UIImage(systemName: "bell"), tag: Tab.approvals.rawValue),
    ]

    private var approvalsVisible: Bool { !approvalsBox.isHidden }

    override func viewDidLoad() {
        super.viewDidLoad()
        let bg = UIColor(Palette.bg)
        view.backgroundColor = bg

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // IndexedDB persistente: identidad y store
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.applicationNameForUserAgent = "DotrinoApp/\(Self.version)"
        // Lo que la página ve como `window.DotrinoNative` (solo en *.dotrino.com): así sabe que
        // corre dentro de la app. Sin push todavía en iOS, `pushToken()` es null.
        cfg.userContentController.addUserScript(WKUserScript(source: """
            if (/(^|\\.)dotrino\\.com$/.test(location.hostname)) {
              window.DotrinoNative = { platform: function () { return 'ios' }, version: function () { return '\(Self.version)' }, pushToken: function () { return null } }
            }
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        IdentityKeysBridge.install(cfg)
        #if DEBUG
        ConsoleBridge.install(cfg)
        #endif

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = bg
        #if DEBUG
        web.isInspectable = true
        #endif

        approvalsHost = UIHostingController(rootView: ApprovalsView(
            model: model,
            onAddAccount: { [weak self] in self?.hideApprovals(); self?.open(url: Self.addAccount) },
            onOpenWeb: { [weak self] in self?.hideApprovals(); self?.open(url: Self.approvalsWeb) },
            onOpen: { [weak self] url in self?.hideApprovals(); self?.open(url: url) }))
        approvalsHost.view.backgroundColor = bg
        approvalsBox.backgroundColor = bg
        approvalsBox.isHidden = true
        addChild(approvalsHost)
        approvalsHost.view.translatesAutoresizingMaskIntoConstraints = false
        approvalsBox.addSubview(approvalsHost.view)
        NSLayoutConstraint.activate([
            approvalsHost.view.topAnchor.constraint(equalTo: approvalsBox.topAnchor),
            approvalsHost.view.bottomAnchor.constraint(equalTo: approvalsBox.bottomAnchor),
            approvalsHost.view.leadingAnchor.constraint(equalTo: approvalsBox.leadingAnchor),
            approvalsHost.view.trailingAnchor.constraint(equalTo: approvalsBox.trailingAnchor),
        ])
        // Los títulos de las pestañas siguen al idioma elegido en la barra.
        langSub = AppLang.shared.$code.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.retitleTabs() }

        tabs.items = items
        tabs.delegate = self
        let look = UITabBarAppearance()
        look.configureWithOpaqueBackground()
        look.backgroundColor = UIColor(Palette.card)
        tabs.standardAppearance = look
        tabs.scrollEdgeAppearance = look
        tabs.tintColor = UIColor(Palette.accent)
        tabs.unselectedItemTintColor = UIColor(Palette.muted)
        tabs.selectedItem = items[0]

        buildOffline()

        for v in [web!, approvalsBox, offline, tabs] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        approvalsHost.didMove(toParent: self)
        for v in [web!, approvalsBox] {
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                v.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                v.bottomAnchor.constraint(equalTo: tabs.topAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            offline.centerXAnchor.constraint(equalTo: web.centerXAnchor),
            offline.centerYAnchor.constraint(equalTo: web.centerYAnchor),
            offline.widthAnchor.constraint(lessThanOrEqualTo: web.widthAnchor, constant: -48),
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabs.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            // The app went to the background: sockets closed, nothing left running.
            MainActor.assumeIsolated { self?.model.stop() }
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.approvalsVisible == true { self?.model.start() } }
        }

        web.load(URLRequest(url: Self.home))
    }

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    private func buildOffline() {
        let label = UILabel()
        label.text = L("offline")
        label.textColor = UIColor(Palette.fg)
        label.numberOfLines = 0
        label.textAlignment = .center
        var bc = UIButton.Configuration.filled()
        bc.title = L("retry")
        bc.baseBackgroundColor = UIColor(Palette.accent)
        let retry = UIButton(configuration: bc, primaryAction: UIAction { [weak self] _ in
            self?.offline.isHidden = true
            self?.web.reload()
        })
        offline.axis = .vertical
        offline.spacing = 16
        offline.alignment = .center
        offline.addArrangedSubview(label)
        offline.addArrangedSubview(retry)
        offline.isHidden = true
    }

    /// Abre un enlace del ecosistema. Los de `/approvals` van a los Pedidos NATIVOS si este
    /// teléfono ya aprueba en alguna cuenta; si no, a la página de siempre.
    func open(url: URL) {
        if url.host == "vault.dotrino.com", url.path.hasPrefix("/approvals"), model.accountsCount() > 0 {
            select(.approvals)
            showApprovals()
            return
        }
        hideApprovals()
        web.load(URLRequest(url: url))
    }

    func openApprovalsTab() {
        select(.approvals)
        showApprovals()
    }

    private func showApprovals() {
        approvalsBox.isHidden = false
        offline.isHidden = true
        model.start()
    }

    private func hideApprovals() {
        approvalsBox.isHidden = true
        model.stop()
    }

    private func select(_ t: Tab) { tabs.selectedItem = items[t.rawValue] }

    /// Los títulos de las pestañas siguen al idioma elegido en la barra.
    private func retitleTabs() {
        for (i, k) in ["tab_home", "tab_profile", "tab_vault", "tab_approvals"].enumerated() { items[i].title = L(k) }
    }

    /// La pestaña marcada sigue a la página que se está viendo.
    private func syncTab(_ url: URL?) {
        guard let url, let h = url.host, !approvalsVisible else { return }
        // La ruta importa: `/approvals` y `/vault` viven en el MISMO host.
        if h == "profile.dotrino.com" { select(.profile) }
        else if h == "vault.dotrino.com" { select(url.path.hasPrefix("/approvals") ? .approvals : .vault) }
        else if h == "dotrino.com" { select(.home) }
    }

    // MARK: WKNavigationDelegate

    // Fuera del ecosistema → Safari. Los iframes (la identidad) se cargan donde estén.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame ?? true else {
            decisionHandler(.allow); return
        }
        if Self.isInside(url) || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            decisionHandler(.allow)
        } else {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        offline.isHidden = true
        syncTab(webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        log.warning("page did not load: \(e.localizedDescription, privacy: .public)")
        offline.isHidden = approvalsVisible
    }

    // MARK: WKUIDelegate

    // Cámara (QR de emparejamiento) solo para el ecosistema.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let inside = origin.protocol == "https" && (origin.host == "dotrino.com" || origin.host.hasSuffix(".dotrino.com"))
        decisionHandler(inside ? .prompt : .deny)
    }

    // window.open → la misma vista (o Safari si es de fuera).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if Self.isInside(url) { web.load(URLRequest(url: url)) } else { UIApplication.shared.open(url) }
        }
        return nil
    }
}

extension MainTabController: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        // Pedidos es SIEMPRE la pantalla nativa. Sin cuentas todavía, ella misma lo dice y
        // ofrece las dos salidas: añadir una, o ver los pedidos en la web.
        switch Tab(rawValue: item.tag) {
        case .approvals?: showApprovals()
        case .profile?: open(url: Self.profile)
        case .vault?: open(url: Self.vault)
        default: open(url: Self.home)
        }
    }
}

#if DEBUG
/// LA CONSOLA DE LA PÁGINA, AL REGISTRO DEL SISTEMA (`log stream --predicate 'subsystem ==
/// "com.dotrino.app"'`). Sin esto una cáscara WebView es indiagnosticable. Solo en DEBUG: en
/// un build de release los mensajes de la página no deben acabar en el registro del sistema.
final class ConsoleBridge: NSObject, WKScriptMessageHandler {
    private static let web = Logger(subsystem: "com.dotrino.app", category: "web")

    static func install(_ cfg: WKWebViewConfiguration) {
        cfg.userContentController.addUserScript(WKUserScript(source: """
            (function () {
              var h = window.webkit.messageHandlers.dotrinoConsole
              ;['log', 'info', 'warn', 'error'].forEach(function (lvl) {
                var orig = console[lvl]
                console[lvl] = function () {
                  try { h.postMessage(lvl + ' ' + location.host + ' ' + Array.prototype.map.call(arguments, function (a) {
                    try { return typeof a === 'string' ? a : (a instanceof Error ? a.stack || String(a) : JSON.stringify(a)) } catch (_) { return String(a) }
                  }).join(' ')) } catch (_) {}
                  return orig.apply(console, arguments)
                }
              })
              window.addEventListener('error', function (e) { try { h.postMessage('error ' + location.host + ' ' + e.message + ' (' + e.filename + ':' + e.lineno + ')') } catch (_) {} })
              window.addEventListener('unhandledrejection', function (e) { try { h.postMessage('error ' + location.host + ' unhandled: ' + ((e.reason && (e.reason.stack || e.reason.message)) || e.reason)) } catch (_) {} })
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        cfg.userContentController.add(ConsoleBridge(), name: "dotrinoConsole")
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        Self.web.notice("[web] \(String(describing: message.body), privacy: .public)")
    }
}
#endif
