import UIKit
import WebKit

/// La barra de Dotrino encima de la pantalla nativa de Pedidos: el MISMO `<dotrino-topbar>`
/// de las páginas (CONVENCIONES §5: la barra no se re-arma a mano), en un WKWebView propio.
///
/// Sin el botón de perfil (dueño, 2026-09-26): Pedidos es de TODAS las cuentas a la vez, no
/// de un perfil. La franja mide lo que mide la barra, y se agranda a toda la pantalla solo
/// mientras la moneda de apoyo tiene su ventana abierta. Los enlaces no navegan aquí: los
/// del ecosistema van a la vista principal y los de fuera a Safari.
final class TopbarView: UIView, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    /// Un enlace del ecosistema pulsado en la barra.
    var onOpen: ((URL) -> Void)?
    /// El idioma elegido en la barra (o el que resolvió al cargar).
    var onLang: ((String) -> Void)?
    /// Cuánto debe medir la franja; quien la coloca ajusta su altura.
    var onHeight: ((CGFloat, Bool) -> Void)?

    private var web: WKWebView!
    private var loaded = false

    private static let html = """
    <!doctype html><html><head>
    <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
    <style>html,body{margin:0;background:transparent;color-scheme:dark}</style>
    <script type="module" src="https://cdn.jsdelivr.net/npm/@dotrino/topbar@0.12/+esm"></script>
    </head><body>
    <dotrino-topbar brand="Dotrino" icon="https://dotrino.com/icons/icon-192.png" brand-href="https://dotrino.com/" no-back
      support-repo="imdotrino/dotrino-app" support-discord="https://discord.gg/D648uq7cth"></dotrino-topbar>
    <script>
      var h = window.webkit.messageHandlers.dotrinoTopbar
      var bar = document.querySelector('dotrino-topbar')
      var open = false
      function size () { h.postMessage({ height: Math.ceil(bar.getBoundingClientRect().height), open: open }) }
      new ResizeObserver(size).observe(bar)
      document.addEventListener('cc-support-open', function () { open = true; size() })
      document.addEventListener('cc-support-close', function () { open = false; size() })
      document.addEventListener('dotrino-lang', function (e) { h.postMessage({ lang: e.detail.lang }) })
      customElements.whenDefined('dotrino-topbar').then(function () { h.postMessage({ lang: bar.lang }); size() })
    </script>
    </body></html>
    """

    override init(frame: CGRect) {
        super.init(frame: frame)
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.userContentController.add(WeakHandler(self), name: "dotrinoTopbar")
        web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = self
        web.uiDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: topAnchor), web.bottomAnchor.constraint(equalTo: bottomAnchor),
            web.leadingAnchor.constraint(equalTo: leadingAnchor), web.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Se carga la primera vez que se enseña: en el origen de dotrino.com, así comparte con
    /// esa página el idioma guardado (`dotrino.lang`).
    func loadIfNeeded() {
        if loaded { return }
        loaded = true
        web.loadHTMLString(Self.html, baseURL: URL(string: "https://dotrino.com/")!)
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let o = message.body as? [String: Any] else { return }
        if let l = o["lang"] as? String, l == "es" || l == "en" { onLang?(l) }
        if let h = o["height"] as? NSNumber { onHeight?(CGFloat(truncating: h), (o["open"] as? Bool) ?? false) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // La carga de la propia barra pasa; cualquier enlace pulsado sale de aquí.
        guard action.navigationType == .linkActivated, let url = action.request.url else { decisionHandler(.allow); return }
        route(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { route(url) }
        return nil
    }

    private func route(_ url: URL) {
        if MainTabController.isInside(url) { onOpen?(url) } else { UIApplication.shared.open(url) }
    }
}

/// `WKUserContentController` retiene a su manejador: sin esto la barra no se liberaría nunca.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}
