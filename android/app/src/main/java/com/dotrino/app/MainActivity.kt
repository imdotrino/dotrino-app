package com.dotrino.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.util.Log
import android.os.Build
import android.os.Bundle
import android.view.View
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import com.google.firebase.messaging.FirebaseMessaging
import android.webkit.PermissionRequest
import android.webkit.ValueCallback
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.bottomnavigation.BottomNavigationView

/**
 * La app de Dotrino: una cáscara nativa sobre las mismas páginas del ecosistema. El
 * pilar de identidad (iframe id.dotrino.com) corre dentro del WebView igual que en un
 * navegador, así que los perfiles son los de siempre (multiperfil incluido) y no hay
 * nada que reescribir del lado web. Lo nativo es lo que el navegador no da: el aviso del
 * sistema que despierta la app (push) y, más adelante, el llavero para la llave SSH.
 */
class MainActivity : AppCompatActivity() {

    companion object {
        const val TAG = "dotrino-app"
        const val HOME = "https://dotrino.com/"
        const val PROFILE = "https://profile.dotrino.com/"
        const val VAULT = "https://vault.dotrino.com/vault"
        /**
         * A donde apunta el aviso: los pedidos, separados de la administración.
         *
         * El `#ring` NO es decoración: le dice a la página que se llegó por el timbre y no
         * a mano. Con varios perfiles en el mismo teléfono, el pedido es de UNO de ellos y
         * puede no ser el activo — sin esa marca la página abría con el perfil que hubiera
         * y enseñaba «este aparato no aprueba pedidos», que es falso y además desorienta.
         * Con la marca, si hay exactamente un perfil conectado a una bóveda, salta a él.
         *
         * Y va en el `#fragment` a propósito: no llega al servidor (CLAUDE.md, §SEO).
         */
        const val APPROVALS = "https://vault.dotrino.com/approvals#ring"
        /** Hosts que se navegan DENTRO de la app; el resto sale al navegador. */
        val INSIDE = Regex("""^([a-z0-9-]+\.)*dotrino\.com$""")
        /**
         * Donde se conecta una cuenta: el emparejamiento normal de la consola. Dentro de la app
         * la identidad crea su llave en el Keystore (IdentityKeysBridge), así que esa misma
         * llave tiene el perfil y aprueba en Pedidos: no hay un alta «nativa» aparte.
         */
        const val ADD_ACCOUNT = "https://vault.dotrino.com/d"
        private const val STATE_APPROVALS = "approvalsVisible"
        /** La Activity viva, para que el servicio de push le avise de un token nuevo. */
        var current: MainActivity? = null
    }

    /** Lo que la página ve como `window.DotrinoNative` (solo en *.dotrino.com). */
    inner class NativeBridge {
        @JavascriptInterface fun pushToken(): String? = PushService.savedToken(this@MainActivity)
        @JavascriptInterface fun platform(): String = "android"
        @JavascriptInterface fun version(): String = BuildConfig.VERSION_NAME
    }

    /**
     * Llegó un timbre. Si la pantalla de Pedidos está a la vista, se refresca ahí mismo y no
     * hace falta aviso del sistema: devuelve `true`.
     */
    fun onRing(): Boolean {
        var handled = false
        val latch = java.util.concurrent.CountDownLatch(1)
        runOnUiThread { handled = approvals.visible && resumed; if (handled) approvals.ring(); latch.countDown() }
        latch.await(2, java.util.concurrent.TimeUnit.SECONDS)
        return handled
    }

    /** Token nuevo de FCM → la página lo registra bajo la llave del aparato, y cada cuenta nativa también. */
    fun pushTokenChanged(token: String) {
        IdentityKeysBridge.registerAll(this, token)
        runOnUiThread {
            val js = "window.dispatchEvent(new CustomEvent('dotrino-native-push-token',{detail:{kind:'fcm',token:'" + token.replace("'", "") + "'}}))"
            web.evaluateJavascript(js, null)
        }
    }

    private lateinit var web: WebView
    private lateinit var nav: BottomNavigationView
    private lateinit var offline: LinearLayout
    private lateinit var approvals: ApprovalsScreen
    private var resumed = false
    private var fileChooser: ValueCallback<Array<Uri>>? = null
    private var pendingPermission: PermissionRequest? = null

    private val pickFile = registerForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris ->
        fileChooser?.onReceiveValue(uris.toTypedArray()); fileChooser = null
    }
    private val askCamera = registerForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        pendingPermission?.let { if (ok) it.grant(it.resources) else it.deny() }; pendingPermission = null
    }
    private val askNotifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        web = findViewById(R.id.web)
        nav = findViewById(R.id.nav)
        offline = findViewById(R.id.offline)
        findViewById<Button>(R.id.retry).setOnClickListener { offline.visibility = View.GONE; web.reload() }

        setupWebView()
        approvals = ApprovalsScreen(this, findViewById(R.id.approvalsBox), findViewById(R.id.approvals), findViewById(R.id.approvalsList),
            onAddAccount = { approvals.hide(); web.loadUrl(ADD_ACCOUNT) },
            onOpenWeb = { approvals.hide(); web.loadUrl(APPROVALS) })
        NativeTopbar(this, findViewById(R.id.topbar)) { u -> approvals.hide(); web.loadUrl(u.toString()); syncNav(u.toString()) }
        nav.setOnItemSelectedListener { item -> onTab(item.itemId); true }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // Volver desde Pedidos enseña la página que había debajo: la pestaña marcada la sigue.
                if (approvals.visible) { approvals.hide(); web.url?.let { syncNav(it) }; return }
                if (web.canGoBack()) web.goBack() else { isEnabled = false; onBackPressedDispatcher.onBackPressed() }
            }
        })

        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        current = this
        PushService.ensureChannel(this)
        // Pedir el token al arrancar: si ya existe no cambia, y si es nuevo la página lo registra.
        FirebaseMessaging.getInstance().token.addOnSuccessListener { t -> if (t != null) { getSharedPreferences("push", MODE_PRIVATE).edit().putString("fcmToken", t).apply(); pushTokenChanged(t) } }

        if (savedInstanceState == null) {
            if (!openIntent(intent)) web.loadUrl(HOME)
        } else {
            web.restoreState(savedInstanceState)
            // Cambiar el idioma en la barra de Pedidos recrea la actividad: se vuelve a Pedidos.
            if (savedInstanceState.getBoolean(STATE_APPROVALS)) { selectTab(R.id.nav_approvals); approvals.show() }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openIntent(intent)
    }

    /**
     * El aviso de un pedido (y el enlace a `/approvals`) abre los Pedidos NATIVOS si este
     * teléfono ya aprueba en nativo alguna cuenta; si no, la página de siempre.
     */
    private fun openIntent(intent: Intent?): Boolean {
        val u = intent?.data?.takeIf { it.host?.matches(INSIDE) == true } ?: return false
        if (u.host == "vault.dotrino.com" && u.path?.startsWith("/approvals") == true && approvals.model.accountsCount() > 0) {
            selectTab(R.id.nav_approvals); approvals.show(); return true
        }
        approvals.hide(); web.loadUrl(u.toString()); return true
    }

    private fun onTab(id: Int) {
        // Pedidos es SIEMPRE la pantalla nativa. Sin cuentas nativas todavía, ella misma lo
        // dice y ofrece las dos salidas: añadir una, o ver los pedidos en la web como antes.
        if (id == R.id.nav_approvals) { approvals.show(); return }
        approvals.hide()
        when (id) {
            R.id.nav_home -> web.loadUrl(HOME)
            R.id.nav_profile -> web.loadUrl(PROFILE)
            R.id.nav_vault -> web.loadUrl(VAULT)
        }
    }

    private fun selectTab(id: Int) {
        if (nav.selectedItemId == id) return
        nav.setOnItemSelectedListener(null); nav.selectedItemId = id
        nav.setOnItemSelectedListener { item -> onTab(item.itemId); true }
    }

    override fun onResume() { super.onResume(); resumed = true; if (approvals.visible) approvals.show() }
    override fun onPause() { resumed = false; super.onPause() }
    override fun onStop() { approvals.stop(); super.onStop() }

    override fun onDestroy() { if (current === this) current = null; super.onDestroy() }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        web.saveState(outState)
        outState.putBoolean(STATE_APPROVALS, approvals.visible)
    }

    private fun setupWebView() {
        with(web.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true            // IndexedDB / localStorage: el store y la identidad viven ahí
            databaseEnabled = true
            mediaPlaybackRequiresUserGesture = false
            allowFileAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            userAgentString = "$userAgentString DotrinoApp/${BuildConfig.VERSION_NAME}"
        }
        // El iframe de identidad (id.dotrino.com) es "tercero" para el WebView: sin esto no guarda nada.
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)
        // Puente nativo: solo lo ven las páginas del ecosistema (el WebView no navega fuera).
        web.addJavascriptInterface(NativeBridge(), "DotrinoNative")
        // Las llaves de la identidad (iframe id.dotrino.com) viven en el Keystore: una sola llave
        // por cuenta, la misma que aprueba en Pedidos. Solo lo ve ese origen.
        IdentityKeysBridge.install(web, this)

        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val host = request.url.host ?: return false
                if (host.matches(INSIDE)) return false
                // Fuera del ecosistema: el navegador del sistema, no esta cáscara.
                startActivity(Intent(Intent.ACTION_VIEW, request.url)); return true
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) offline.visibility = View.VISIBLE
            }
            override fun onPageFinished(view: WebView, url: String) {
                syncNav(url)
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(webView: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                fileChooser?.onReceiveValue(null)
                fileChooser = callback
                pickFile.launch(params.acceptTypes.firstOrNull()?.takeIf { it.isNotBlank() } ?: "*/*")
                return true
            }
            // Cámara (escanear el QR de emparejamiento): se pide el permiso del sistema y se concede al sitio.
            override fun onPermissionRequest(request: PermissionRequest) {
                if (request.origin.host?.matches(INSIDE) != true) { request.deny(); return }
                if (request.resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE) &&
                    ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                    pendingPermission = request; askCamera.launch(Manifest.permission.CAMERA)
                } else request.grant(request.resources)
            }
            /**
             * LA CONSOLA DE LA PÁGINA, A `logcat`.
             *
             * Sin esto una cáscara WebView es indiagnosticable: la página puede estar
             * gritando un error y desde fuera solo se ve una pantalla que no avanza. Pasó
             * con un emparejamiento que se quedaba en «hablando con tu bóveda» y no había
             * absolutamente nada que mirar.
             *
             * Solo en compilaciones de DEPURACIÓN: en una de release los mensajes de la
             * página acabarían en el registro del sistema, que lo lee cualquier app con
             * permiso, y ahí puede ir cualquier cosa.
             */
            override fun onConsoleMessage(m: ConsoleMessage): Boolean {
                if (!BuildConfig.DEBUG) return false
                val donde = "${m.sourceId()?.substringAfterLast('/') ?: "?"}:${m.lineNumber()}"
                val texto = "[web] ${m.message()}  ($donde)"
                when (m.messageLevel()) {
                    ConsoleMessage.MessageLevel.ERROR -> Log.e(TAG, texto)
                    ConsoleMessage.MessageLevel.WARNING -> Log.w(TAG, texto)
                    else -> Log.i(TAG, texto)
                }
                return true
            }
        }
    }

    /** La pestaña marcada sigue a la página que se está viendo. */
    private fun syncNav(url: String) {
        val u = Uri.parse(url)
        val host = u.host ?: return
        // La ruta importa: `/approvals` y `/vault` viven en el MISMO host, así que mirar
        // solo el host dejaba la campana sin marcar y encendía «Bóveda» estando en Pedidos.
        val id = when {
            host == "profile.dotrino.com" -> R.id.nav_profile
            host == "vault.dotrino.com" && u.path?.startsWith("/approvals") == true -> R.id.nav_approvals
            host == "vault.dotrino.com" -> R.id.nav_vault
            host == "dotrino.com" -> R.id.nav_home
            else -> return
        }
        if (approvals.visible) return
        selectTab(id)
    }
}
