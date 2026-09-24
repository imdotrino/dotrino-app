package com.dotrino.app

import android.content.Context
import android.util.Log
import android.webkit.WebView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.dotrino.sdk.Account
import com.dotrino.sdk.AccountStore
import com.dotrino.sdk.Delegation
import com.dotrino.sdk.KeystoreKeys
import com.dotrino.sdk.ProxyConnection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * `window.DotrinoNativeKeys` — how the vault console ENROLS this phone's native key for an
 * account. Everything else (listing, approving) is native and never goes through here.
 *
 * Three locks, because a key that can approve is worth stealing:
 * 1. ONLY `https://vault.dotrino.com` sees the object (`addWebMessageListener` checks the
 *    origin of every frame; a `@JavascriptInterface` would be visible to any subdomain).
 * 2. The key only signs during ITS enrolment, and only an `op:'enroll'` body. The page can
 *    never make it sign an approval.
 * 3. The paper handed back is checked here (signed by that vault, for this key) before the
 *    account is saved.
 *
 * Protocol: the page posts `{ id, method, params }` as JSON; the answer comes back as
 * `{ id, result }` or `{ id, error }`.
 */
object NativeKeysBridge {
    private const val TAG = "dotrino-native-keys"
    const val ORIGIN = "https://vault.dotrino.com"
    private val json = Json { ignoreUnknownKeys = true }
    private val enrolling = ConcurrentHashMap.newKeySet<String>()
    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun install(web: WebView, context: Context) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            Log.w(TAG, "this WebView cannot restrict a bridge by origin: native enrolment is off"); return
        }
        WebViewCompat.addWebMessageListener(web, "DotrinoNativeKeys", setOf(ORIGIN)) { _, message, origin, isMainFrame, reply ->
            // Belt and braces: the rule already filters, but a wrong origin must never get an answer.
            if (origin.toString() != ORIGIN || !isMainFrame) return@addWebMessageListener
            handle(context.applicationContext, message, reply)
        }
    }

    private fun handle(ctx: Context, message: WebMessageCompat, reply: JavaScriptReplyProxy) {
        val req = try { json.parseToJsonElement(message.data ?: "").jsonObject } catch (_: Exception) { return }
        val id = req["id"]?.jsonPrimitive?.content ?: return
        val p = req["params"] as? JsonObject ?: JsonObject(emptyMap())
        io.launch {
            val out = try {
                buildJsonObject { put("id", id); put("result", call(ctx, req["method"]?.jsonPrimitive?.content, p)) }
            } catch (e: Exception) {
                Log.w(TAG, "${req["method"]}: ${e.message}")
                buildJsonObject { put("id", id); put("error", e.message ?: e.javaClass.simpleName) }
            }
            // The reply proxy must be used on the thread that created it (the UI thread).
            android.os.Handler(android.os.Looper.getMainLooper()).post { reply.postMessage(out.toString()) }
        }
    }

    private fun call(ctx: Context, method: String?, p: JsonObject): JsonObject = when (method) {
        "begin" -> {
            val kid = UUID.randomUUID().toString()
            val k = KeystoreKeys.create(kid)
            enrolling.add(kid)
            buildJsonObject { put("id", kid); put("publickey", k.publickey); put("encPub", k.encPub) }
        }
        "sign" -> {
            val kid = p.str("id")
            check(kid in enrolling) { "this key is not being enrolled" }
            val text = p.str("text")
            val op = try { json.parseToJsonElement(text).jsonObject["op"]?.jsonPrimitive?.content } catch (_: Exception) { null }
            check(op == "enroll") { "this key only signs its enrolment" }
            buildJsonObject { put("signature", KeystoreKeys.open(kid).sign(text)) }
        }
        "save" -> {
            val kid = p.str("id")
            check(kid in enrolling) { "this key is not being enrolled" }
            val keys = KeystoreKeys.open(kid)
            val cert = p["cert"] as? JsonObject ?: throw IllegalArgumentException("save: missing cert")
            val vault = p.str("vault")
            Delegation.check(cert, vault, keys.publickey, null)?.let { throw IllegalStateException("the paper does not check out: $it") }
            val account = Account(
                id = kid, name = (p["name"]?.jsonPrimitive?.content).orEmpty().ifBlank { Delegation.keyLabel(vault) },
                profileId = (p["profileId"]?.jsonPrimitive?.content), vault = vault,
                proxy = p.str("proxy"), cert = cert, deviceId = Delegation.keyLabel(keys.publickey),
            )
            AccountStore(ctx).save(account)
            enrolling.remove(kid)
            PushService.savedToken(ctx)?.let { t -> io.launch { registerPush(account, t) } }
            buildJsonObject { put("deviceId", account.deviceId) }
        }
        "discard" -> {
            val kid = p.str("id")
            if (enrolling.remove(kid)) KeystoreKeys.delete(kid)
            buildJsonObject { put("ok", true) }
        }
        "accounts" -> buildJsonObject {
            put("items", buildJsonArray {
                AccountStore(ctx).list().forEach { a -> add(buildJsonObject { put("name", a.name); put("vault", a.vault); put("deviceId", a.deviceId) }) }
            })
        }
        else -> throw IllegalArgumentException("unknown method: $method")
    }

    /** The phone's FCM token under this account's native key: the vault's ring reaches it. */
    suspend fun registerPush(account: Account, token: String) {
        val conn = ProxyConnection(account.proxy)
        try {
            conn.connect()
            conn.registerPushToken(KeystoreKeys.open(account.id), token)
        } catch (e: Exception) {
            Log.w(TAG, "push for ${account.deviceId} not registered: ${e.message}")
        } finally { conn.close() }
    }

    /** On start and on a new token: every account registers it again (cheap, and a lost registration heals). */
    fun registerAll(ctx: Context, token: String) {
        io.launch {
            val accounts = try { AccountStore(ctx).list() } catch (e: Exception) { Log.e(TAG, "accounts unreadable", e); return@launch }
            accounts.forEach { registerPush(it, token) }
        }
    }

    private fun JsonObject.str(k: String): String = this[k]?.jsonPrimitive?.content ?: throw IllegalArgumentException("missing $k")

}
