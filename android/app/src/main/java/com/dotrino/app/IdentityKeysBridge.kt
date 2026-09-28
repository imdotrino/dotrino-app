package com.dotrino.app

import android.content.Context
import android.util.Log
import android.webkit.WebView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.dotrino.sdk.Account
import com.dotrino.sdk.IdentityClient
import com.dotrino.sdk.ProxyConnection
import com.dotrino.sdk.RemoteAccounts
import com.dotrino.sdk.RemoteKeys
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** ONE connection to the identity app per process (dotrino-native/docs/DISENO.md §2.2). */
object Identity {
    @Volatile private var client: IdentityClient? = null
    fun get(ctx: Context): IdentityClient = client ?: synchronized(this) { client ?: IdentityClient(ctx).also { client = it } }
}

/**
 * `window.DotrinoIdentityKeys` — the identity of the WebView (the `id.dotrino.com` iframe) uses
 * the keys AND the storage of the IDENTITY APP (`com.dotrino.identity`): one profile for every
 * page and every Dotrino app on the phone. This bridge only relays: each `{ id, method, params }`
 * goes to the identity app as it came, and its answer comes back as it went.
 *
 * ONLY `https://id.dotrino.com` sees the object, via `addWebMessageListener`, which checks the
 * origin of each frame. That origin is the identity itself: the bridge gives it nothing it
 * did not have.
 */
object IdentityKeysBridge {
    private const val TAG = "dotrino-identity-keys"
    const val ORIGIN = "https://id.dotrino.com"
    private val json = Json { ignoreUnknownKeys = true }
    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun install(web: WebView, context: Context) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) ||
            !WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            Log.w(TAG, "this WebView cannot restrict a bridge by origin: the identity keeps its keys in the WebView"); return
        }
        WebViewCompat.addWebMessageListener(web, "DotrinoIdentityKeys", setOf(ORIGIN)) { _, message, origin, _, reply ->
            // Belt and braces: the rule already filters, but a wrong origin must never get an answer.
            if (origin.toString() != ORIGIN) return@addWebMessageListener
            handle(context.applicationContext, message, reply)
        }
        // The storage is the identity app's too (`dotrino-identity/vault/nativeStore.js`).
        WebViewCompat.addDocumentStartJavaScript(web, "if (window.DotrinoIdentityKeys) window.DotrinoIdentityKeys.storage = true", setOf(ORIGIN))
    }

    private fun handle(ctx: Context, message: WebMessageCompat, reply: JavaScriptReplyProxy) {
        val req = try { json.parseToJsonElement(message.data ?: "").jsonObject } catch (_: Exception) { return }
        val id = req["id"]?.jsonPrimitive?.content ?: return
        val method = req["method"]?.jsonPrimitive?.content ?: return
        val params = req["params"] as? JsonObject ?: JsonObject(emptyMap())
        io.launch {
            val out = try {
                val r = Identity.get(ctx).raw(method, params)
                // After pairing, this phone's FCM token under the new account's key: the vault's ring reaches it.
                if (method == "save" && r["error"] == null) PushService.savedToken(ctx)?.let { t ->
                    params["kid"]?.jsonPrimitive?.content?.let { kid -> registerPush(ctx, kid, t) }
                }
                JsonObject(r + ("id" to kotlinx.serialization.json.JsonPrimitive(id)))
            } catch (e: IdentityClient.IdentityError) {
                Log.w(TAG, "$method: ${e.message}")
                buildJsonObject { put("id", id); put("error", e.message ?: e.code); put("code", e.code) }
            } catch (e: Exception) {
                Log.w(TAG, "$method: ${e.message}")
                buildJsonObject { put("id", id); put("error", e.message ?: e.javaClass.simpleName); put("code", "native-error") }
            }
            // The reply proxy must be used on the thread that created it (the UI thread).
            android.os.Handler(android.os.Looper.getMainLooper()).post { reply.postMessage(out.toString()) }
        }
    }

    private suspend fun registerPush(ctx: Context, kid: String, token: String) {
        val a = runCatching { RemoteAccounts.list(Identity.get(ctx)).firstOrNull { it.id == kid } }.getOrNull() ?: return
        registerPush(ctx, a, token)
    }

    /** The phone's FCM token under this account's key: the vault's ring reaches it. */
    suspend fun registerPush(ctx: Context, account: Account, token: String) {
        val conn = ProxyConnection(account.proxy)
        try {
            conn.connect()
            conn.registerPushToken(RemoteKeys.open(Identity.get(ctx), account.id), token)
        } catch (e: Exception) {
            Log.w(TAG, "push for ${account.deviceId} not registered: ${e.message}")
        } finally { conn.close() }
    }

    /** On start and on a new token: every account registers it again (cheap, and a lost registration heals). */
    fun registerAll(ctx: Context, token: String) {
        io.launch {
            val accounts = try { RemoteAccounts.list(Identity.get(ctx)) } catch (e: Exception) { Log.w(TAG, "accounts: ${e.message}"); return@launch }
            accounts.forEach { registerPush(ctx, it, token) }
        }
    }
}
