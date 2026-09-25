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
import com.dotrino.sdk.Crypto
import com.dotrino.sdk.Delegation
import com.dotrino.sdk.KeystoreKeys
import com.dotrino.sdk.ProxyConnection
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
import java.util.UUID

/**
 * `window.DotrinoIdentityKeys` — the identity of the WebView (the `id.dotrino.com` iframe)
 * keeps its keys in THIS phone's Keystore instead of IndexedDB. One key per account: the
 * same one that approves on the native Requests screen, so the phone is ONE device in the
 * record, with its profile and its approvals (owner, 2026-09-25). The JS side is
 * `dotrino-identity/vault/externalKeys.js`.
 *
 * The private halves never leave the Keystore: the page asks to sign bytes or to agree an
 * ECDH secret, and that is all it can do.
 *
 * ONLY `https://id.dotrino.com` sees the object — in any frame, because the identity is an
 * iframe inside every page — via `addWebMessageListener`, which checks the origin of each
 * frame. A `@JavascriptInterface` would be visible to any page in the WebView. That origin is
 * the identity itself: it can already sign as you with its own keys, so the bridge gives it
 * nothing it did not have.
 *
 * Protocol: the page posts `{ id, method, params }` as JSON; the answer comes back as
 * `{ id, result }` or `{ id, error, code }`.
 */
object IdentityKeysBridge {
    private const val TAG = "dotrino-identity-keys"
    const val ORIGIN = "https://id.dotrino.com"
    private val json = Json { ignoreUnknownKeys = true }
    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** An error the page can act on: it goes back with its `code`. */
    class BridgeError(message: String, val code: String) : Exception(message)

    fun install(web: WebView, context: Context) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            Log.w(TAG, "this WebView cannot restrict a bridge by origin: the identity keeps its keys in the WebView"); return
        }
        WebViewCompat.addWebMessageListener(web, "DotrinoIdentityKeys", setOf(ORIGIN)) { _, message, origin, _, reply ->
            // Belt and braces: the rule already filters, but a wrong origin must never get an answer.
            if (origin.toString() != ORIGIN) return@addWebMessageListener
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
                buildJsonObject {
                    put("id", id); put("error", e.message ?: e.javaClass.simpleName)
                    put("code", (e as? BridgeError)?.code ?: "native-error")
                }
            }
            // The reply proxy must be used on the thread that created it (the UI thread).
            android.os.Handler(android.os.Looper.getMainLooper()).post { reply.postMessage(out.toString()) }
        }
    }

    /** The key [kid], or the error the page shows: no other key is ever made in its place. */
    private fun keys(kid: String): KeystoreKeys {
        if (!KeystoreKeys.exists(kid)) throw BridgeError("that key is not on this phone", "native-key-gone")
        return KeystoreKeys.open(kid)
    }

    private fun call(ctx: Context, method: String?, p: JsonObject): JsonObject = when (method) {
        "create" -> {
            val kid = UUID.randomUUID().toString()
            val k = KeystoreKeys.create(kid)
            buildJsonObject { put("kid", kid); put("publickey", k.publickey); put("encPub", k.encPub) }
        }
        "open" -> {
            val kid = p.str("kid"); val k = keys(kid)
            buildJsonObject { put("kid", kid); put("publickey", k.publickey); put("encPub", k.encPub) }
        }
        "sign" -> buildJsonObject { put("signature", keys(p.str("kid")).signBytes(Crypto.fromB64(p.str("data")))) }
        "deriveBits" -> buildJsonObject {
            put("bits", Crypto.b64(keys(p.str("kid")).agree(Crypto.publicKeyOf(p.str("peer")))))
        }
        "save" -> {
            // After pairing: the native Requests screen gets the account, with the SAME paper.
            val kid = p.str("kid"); val k = keys(kid)
            val cert = p["cert"] as? JsonObject ?: throw IllegalArgumentException("save: missing cert")
            val vault = p.str("vault")
            Delegation.check(cert, vault, k.publickey, null)?.let { throw BridgeError("the paper does not check out: $it", "bad-paper") }
            val account = Account(
                id = kid, name = (p["name"]?.jsonPrimitive?.content).orEmpty().ifBlank { Delegation.keyLabel(vault) },
                profileId = p["profileId"]?.jsonPrimitive?.content, vault = vault,
                proxy = p.str("proxy"), cert = cert, deviceId = Delegation.keyLabel(k.publickey),
            )
            AccountStore(ctx).save(account)
            PushService.savedToken(ctx)?.let { t -> io.launch { registerPush(account, t) } }
            buildJsonObject { put("deviceId", account.deviceId) }
        }
        "remove" -> {
            // The identity removed that profile: its key and its native account go with it.
            AccountStore(ctx).remove(p.str("kid"))
            buildJsonObject { put("ok", true) }
        }
        else -> throw IllegalArgumentException("unknown method: $method")
    }

    /** The phone's FCM token under this account's key: the vault's ring reaches it. */
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
