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
            // The identity removed a profile and its account went with it: its rings stop.
            if (method == "remove") prunePush(ctx)
        }
    }

    private suspend fun registerPush(ctx: Context, kid: String, token: String) {
        val a = runCatching { RemoteAccounts.list(Identity.get(ctx)).firstOrNull { it.id == kid } }.getOrNull() ?: return
        registerPush(ctx, a, token)
    }

    /** The phone's FCM token under this account's key: the vault's ring reaches it. */
    suspend fun registerPush(ctx: Context, account: Account, token: String) {
        val conn = ProxyConnection(account.proxy, "vault")   // ring THIS app, not messenger (same key)
        try {
            conn.connect()
            conn.registerPushToken(RemoteKeys.open(Identity.get(ctx), account.id), token)
            rememberProxy(ctx, account.proxy)
        } catch (e: Exception) {
            Log.w(TAG, "push for ${account.deviceId} not registered: ${e.message}")
        } finally { conn.close() }
    }

    /** On start and on a new token: every account registers it again (cheap, and a lost registration heals). */
    fun registerAll(ctx: Context, token: String) {
        io.launch {
            val accounts = try { RemoteAccounts.list(Identity.get(ctx)) } catch (e: Exception) { Log.w(TAG, "accounts: ${e.message}"); return@launch }
            accounts.forEach { registerPush(ctx, it, token) }
            // An account removed while the proxy could not be reached is still subscribed there.
            prunePush(ctx)
        }
    }

    private const val PREFS = "push"
    private const val KEY_PROXIES = "proxies"

    /**
     * Every proxy this phone subscribed at is remembered: once the last account of a proxy is
     * removed, nothing else says where its subscription was.
     */
    private fun rememberProxy(ctx: Context, proxy: String) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val known = prefs.getStringSet(KEY_PROXIES, emptySet()) ?: emptySet()
        if (proxy !in known) prefs.edit().putStringSet(KEY_PROXIES, known + proxy).apply()
    }

    /** [prunePush] from anywhere, without waiting for it. */
    fun prunePushSoon(ctx: Context) { val c = ctx.applicationContext; io.launch { prunePush(c) } }

    /**
     * THE RINGS OF AN ACCOUNT THAT IS NO LONGER HERE (owner, 2026-10-12). Removing an account
     * deletes its key, so nothing can sign a `push-unsubscribe` for it and the proxy kept ringing
     * this phone with its requests. Here the phone tells the proxy which accounts it STILL has
     * and the proxy drops the rest of the subscriptions of this token (`push-prune`, proxy ≥ 1.4.7).
     *
     * It runs when an account is removed, on every start, and when a ring arrives that no
     * account explains.
     */
    suspend fun prunePush(ctx: Context) {
        val token = PushService.savedToken(ctx) ?: return
        // Without the full list of what is left there is nothing to say: a guess would drop
        // the rings of an account that is still here.
        val accounts: List<Account>
        val keep: List<String>
        try {
            val identity = Identity.get(ctx)
            accounts = RemoteAccounts.list(identity)
            keep = accounts.map { RemoteKeys.open(identity, it.id).publickey }
        } catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (e: Exception) { Log.w(TAG, "push prune skipped, could not read the accounts: ${e.message}"); return }
        accounts.forEach { rememberProxy(ctx, it.proxy) }   // accounts from before this was remembered
        val proxies = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(KEY_PROXIES, emptySet()) ?: emptySet()
        for (proxy in proxies) {
            val conn = ProxyConnection(proxy, "vault")
            try {
                conn.connect()
                val n = conn.prunePush(token, keep)
                if (n > 0) Log.i(TAG, "push: $n subscription(s) of removed accounts dropped at $proxy")
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) { Log.w(TAG, "push prune at $proxy failed: ${e.message}") }
            finally { conn.close() }
        }
    }
}
