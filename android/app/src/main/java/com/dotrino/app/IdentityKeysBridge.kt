package com.dotrino.app

import android.content.Context
import android.util.Log
import android.webkit.WebView
import com.dotrino.sdk.Account
import com.dotrino.sdk.IdentityClient
import com.dotrino.sdk.ProxyConnection
import com.dotrino.sdk.RemoteAccounts
import com.dotrino.sdk.RemoteKeys
import com.dotrino.sdk.ui.IdentityWebBridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.jsonPrimitive

/** ONE connection to the identity app per process (dotrino-native/docs/DISENO.md §2.2). */
object Identity {
    fun get(ctx: Context): IdentityClient = IdentityClient.shared(ctx)
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
    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * The bridge is `dotrino-native`'s ([IdentityWebBridge]), the same one every app uses; what
     * is only this app's is what follows a pairing: its push token under the new account.
     */
    fun install(web: WebView, context: Context) {
        val ctx = context.applicationContext
        IdentityWebBridge.install(web, ctx) { method, params, _ ->
            if (method == "save") PushService.savedToken(ctx)?.let { t ->
                params["kid"]?.jsonPrimitive?.content?.let { kid -> registerPush(ctx, kid, t) }
            }
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
