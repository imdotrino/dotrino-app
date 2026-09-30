package com.dotrino.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import android.util.Log
import com.dotrino.sdk.Account
import com.dotrino.sdk.Approval
import com.dotrino.sdk.ProxyConnection
import com.dotrino.sdk.RemoteAccounts
import com.dotrino.sdk.RemoteKeys
import com.dotrino.sdk.VaultClient
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

/**
 * El TIMBRE. El proxio manda por FCM un `{ type: 'ring' }` sin contenido cuando la bóveda
 * tiene algo para este aparato (un pedido de claves, una firma SSH). Google no ve nada más.
 *
 * EL AVISO DICE EL PORQUÉ (dueño, 2026-09-30: «es importante que se sepa el porqué de la
 * notificación»). Al llegar el timbre se bajan los pedidos aquí, en el teléfono, por el
 * mismo camino que la pantalla de Pedidos, y el aviso dice qué se pide («proxy1 pide tus
 * claves de proxy»). Con un tope: si en 8 s no hay respuesta, sale el aviso de siempre. En la
 * pantalla de bloqueo se ve solo el genérico: el motivo nombra aparatos y cajones.
 */
class PushService : FirebaseMessagingService() {

    companion object {
        // Mudo: el trino lo toca DotrinoRing (uno al azar). Reemplaza al viejo «vault», que
        // sonaba con el tono del sistema y no se puede cambiar una vez creado.
        const val CHANNEL = "vault_trino"
        private const val PREFS = "push"
        private const val KEY_TOKEN = "fcmToken"

        fun savedToken(ctx: Context): String? = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TOKEN, null)

        fun ensureChannel(ctx: Context) {
            com.dotrino.sdk.DotrinoRing.channel(ctx, CHANNEL, ctx.getString(R.string.channel_vault), replaces = "vault")
        }

        /**
         * El aviso. Con [pending] dice qué se pide: uno solo, su motivo como título; varios,
         * cuántos y el más reciente. Sin él (no se pudo preguntar a tiempo), el genérico.
         */
        fun notifyRequest(ctx: Context, pending: List<Approval>? = null) {
            ensureChannel(ctx)
            val open = Intent(ctx, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse(MainActivity.APPROVALS)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pi = PendingIntent.getActivity(ctx, 1, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            fun base() = NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(R.drawable.ic_vault)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setAutoCancel(true)
                .setContentIntent(pi)
            val generic = base().setContentTitle(ctx.getString(R.string.notif_title)).setContentText(ctx.getString(R.string.notif_body)).build()
            val n = if (pending.isNullOrEmpty()) generic else {
                val newest = pending.maxBy { it.exp }
                val (title, text) = if (pending.size == 1) RequestText.title(ctx, newest) to ctx.getString(R.string.notif_tap)
                    else ctx.getString(R.string.notif_many, pending.size) to RequestText.title(ctx, newest)
                base().setContentTitle(title).setContentText(text)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                    // El motivo nombra aparatos y cajones: con el teléfono bloqueado, el genérico.
                    .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                    .setPublicVersion(generic)
                    .build()
            }
            try { (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(1001, n) } catch (_: SecurityException) {}
        }

        /**
         * Los pedidos vivos de todas las cuentas de este teléfono, preguntando a cada bóveda. Si
         * la bóveda renueva el papel de una cuenta mientras tanto, SE GUARDA: emitir uno nuevo
         * retira el anterior, y perderlo dejaría la cuenta con un papel que ya no vale.
         */
        suspend fun pendingRequests(ctx: Context): List<Approval> {
            val identity = Identity.get(ctx.applicationContext)
            val accounts = RemoteAccounts.list(identity)
            return coroutineScope {
                accounts.map { a -> async { runCatching { ofAccount(identity, a) }.onFailure { Log.w(TAG, "ring: ${a.deviceId}: ${it.message}") }.getOrDefault(emptyList()) } }
                    .awaitAll().flatten()
            }
        }

        private suspend fun ofAccount(identity: com.dotrino.sdk.IdentityClient, a: Account): List<Approval> {
            val keys = RemoteKeys.open(identity, a.id)
            val conn = ProxyConnection(a.proxy)
            var renewed: Account? = null
            try {
                conn.connect()
                conn.identify(keys)
                return VaultClient(a, keys, conn) { renewed = it }.approvals()
            } finally {
                conn.close()
                renewed?.let { runCatching { RemoteAccounts.save(identity, it) }.onFailure { e -> Log.e(TAG, "ring: could not save the renewed paper: ${e.message}") } }
            }
        }

        private const val TAG = "dotrino-push"
    }

    override fun onNewToken(token: String) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_TOKEN, token).apply()
        MainActivity.current?.pushTokenChanged(token) ?: IdentityKeysBridge.registerAll(this, token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // Con los Pedidos a la vista, se refrescan ahí y sobra el aviso del sistema.
        if (MainActivity.current?.onRing() == true) return
        // El timbre no trae nada: el porqué se pregunta aquí, en el teléfono. Este método corre
        // fuera del hilo principal y Android le da unos segundos; con 8 s de tope, lo que no
        // llegue a tiempo sale como el aviso genérico.
        val pending = runBlocking { withTimeoutOrNull(8_000) { runCatching { pendingRequests(this@PushService) }.getOrNull() } }
        notifyRequest(this, pending)
    }
}
