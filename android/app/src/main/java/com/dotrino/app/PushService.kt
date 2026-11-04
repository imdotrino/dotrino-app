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
import com.dotrino.sdk.ApprovalsAnswer
import com.dotrino.sdk.ProxyConnection
import com.dotrino.sdk.RemoteAccounts
import com.dotrino.sdk.RemoteKeys
import com.dotrino.sdk.VaultClient
import com.dotrino.sdk.VaultNotice
import com.dotrino.sdk.VaultRing
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
        private const val KEY_SHOWN = "shownNotices"
        private const val EV_UPDATED = "updated"
        private const val EV_NEEDS_ROOT = "update-needs-root"
        private const val EV_DELIVERED = "delivered"

        fun savedToken(ctx: Context): String? = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TOKEN, null)

        fun ensureChannel(ctx: Context) {
            com.dotrino.sdk.DotrinoRing.channel(ctx, CHANNEL, ctx.getString(R.string.channel_vault), replaces = "vault")
        }

        /**
         * El aviso. Con [pending] dice qué se pide: uno solo, su motivo como título; varios,
         * cuántos y el más reciente. Sin él (no se pudo preguntar a tiempo), el genérico.
         */
        fun notifyRequest(ctx: Context, pending: List<Approval>? = null, again: Boolean = false) {
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
                // The SAME ring completing its list (another account answered later) does not sound twice.
                .setOnlyAlertOnce(again)
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
         * LA BÓVEDA (O UN APARATO DEL ACTA) SE ACTUALIZÓ, o tiene una versión que no puede
         * instalar sola (vaultd ≥ 0.147.0). No pide nada: lo cuenta. Va en su propio aviso, para no pisar el de un pedido que siga esperando.
         */
        fun notifyUpdated(ctx: Context, notice: VaultNotice) {
            if (notice.ev == EV_DELIVERED) return notifyDelivered(ctx, notice)
            ensureChannel(ctx)
            // QUIÉN: la bóveda, o un aparato del acta (un agente) que se nombra por su etiqueta
            // o su ID. QUÉ: ya se actualizó, o hay una versión que no puede instalar sola
            // porque necesita permisos de administrador (`update-needs-root`).
            val device = notice.device
            val needsRoot = notice.ev == EV_NEEDS_ROOT
            val title = when {
                needsRoot && device != null -> ctx.getString(R.string.notif_needs_root_device_title, device)
                needsRoot -> ctx.getString(R.string.notif_needs_root_title)
                device != null -> ctx.getString(R.string.notif_updated_device_title, device)
                else -> ctx.getString(R.string.notif_updated_title)
            }
            val body = ctx.getString(if (needsRoot) R.string.notif_needs_root_body else R.string.notif_updated_body, notice.version)
            val open = Intent(ctx, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP }
            val pi = PendingIntent.getActivity(ctx, 2, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val n = NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(R.drawable.ic_vault)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            try { (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(1002, n) } catch (_: SecurityException) {}
        }

        /**
         * UN APARATO DESATENDIDO SE LLEVÓ CLAVES O UNA CONTRASEÑA (vaultd ≥ 0.190.0). No pidió
         * permiso porque tiene `unattended`; esto lo cuenta. Nada que aprobar: abre la app.
         */
        fun notifyDelivered(ctx: Context, notice: VaultNotice) {
            ensureChannel(ctx)
            val who = notice.device ?: "?"
            val title = if (notice.kind == "passwords") ctx.getString(R.string.notif_delivered_passwords_title, who)
                else ctx.getString(R.string.notif_delivered_secrets_title, who, notice.ns ?: "?")
            val body = ctx.getString(R.string.notif_delivered_body)
            val open = Intent(ctx, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP }
            val pi = PendingIntent.getActivity(ctx, 3, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val generic = NotificationCompat.Builder(ctx, CHANNEL).setSmallIcon(R.drawable.ic_vault)
                .setContentTitle(ctx.getString(R.string.notif_delivered_generic)).build()
            val n = NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(R.drawable.ic_vault)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setPublicVersion(generic)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            try { (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(1003, n) } catch (_: SecurityException) {}
        }

        /**
         * EL ASUNTO SELLADO DEL TIMBRE (vaultd ≥ 0.190.0): lo abre la llave de alguna cuenta de
         * este teléfono, sin red. `null` si no vino o no es para ninguna (cuenta que ya no está).
         */
        suspend fun ringSubject(ctx: Context, sealed: String?): kotlinx.serialization.json.JsonObject? {
            if (sealed.isNullOrBlank()) return null
            val identity = Identity.get(ctx.applicationContext)
            for (a in RemoteAccounts.list(identity)) {
                val keys = runCatching { RemoteKeys.open(identity, a.id) }.getOrNull() ?: continue
                VaultRing.open(sealed, keys)?.let { return it }
            }
            return null
        }

        /** Apunta un aviso como ya enseñado (lo contó el asunto), sin olvidar los demás. */
        fun markShown(ctx: Context, id: String) {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val shown = prefs.getStringSet(KEY_SHOWN, emptySet()) ?: emptySet()
            prefs.edit().putStringSet(KEY_SHOWN, shown + id).apply()
        }

        /**
         * De los avisos que trae la bóveda, el más reciente de los que esta app sabe contar y
         * que este teléfono todavía NO enseñó, o `null`. Los que vienen quedan apuntados como
         * enseñados (y solo esos: uno que la bóveda ya dejó de mandar no hace falta
         * recordarlo), así un timbre posterior no repite la misma noticia.
         */
        fun freshUpdate(ctx: Context, notices: List<VaultNotice>): VaultNotice? {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val shown = prefs.getStringSet(KEY_SHOWN, emptySet()) ?: emptySet()
            val known = notices.filter { it.ev == EV_UPDATED || it.ev == EV_NEEDS_ROOT || it.ev == EV_DELIVERED }
            val fresh = known.filter { it.id !in shown }.maxByOrNull { it.ts }
            if (known.isNotEmpty()) prefs.edit().putStringSet(KEY_SHOWN, known.map { it.id }.toSet()).apply()
            return fresh
        }

        /**
         * Los pedidos vivos y los avisos de todas las cuentas de este teléfono, preguntando a
         * cada bóveda. Si la bóveda renueva el papel de una cuenta mientras tanto, SE GUARDA:
         * emitir uno nuevo retira el anterior, y perderlo dejaría la cuenta con un papel que ya
         * no vale.
         */
        suspend fun pendingRequests(ctx: Context, onAccount: (ApprovalsAnswer) -> Unit = {}): ApprovalsAnswer {
            val identity = Identity.get(ctx.applicationContext)
            val accounts = RemoteAccounts.list(identity)
            val all = coroutineScope {
                accounts.map { a -> async {
                    runCatching { ofAccount(ctx, identity, a) }.onFailure { Log.w(TAG, "ring: ${a.deviceId}: ${it.message}") }.getOrNull()?.also(onAccount)
                } }.awaitAll().filterNotNull()
            }
            return ApprovalsAnswer(all.flatMap { it.items }, all.flatMap { it.notices })
        }

        private suspend fun ofAccount(ctx: Context, identity: com.dotrino.sdk.IdentityClient, a: Account): ApprovalsAnswer {
            val keys = RemoteKeys.open(identity, a.id)
            val conn = ProxyConnection(a.proxy, "vault")   // the approver app: its rings and its queue
            var renewed: Account? = null
            try {
                conn.connect()
                conn.identify(keys)
                // A ring just got here, so this phone does receive them: say so (see ApprovalsModel.notifiable).
                val answer = VaultClient(a, keys, conn) { renewed = it }.approvalsWithNotices(notify = true)
                runCatching { LogAnchors.check(ctx, a.id, answer.notices) }.onFailure { Log.w(TAG, "log anchor: ${it.message}") }
                return answer
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
        // AS SOON AS ONE ACCOUNT HAS A REQUEST, IT IS SAID: waiting for every account meant
        // waiting for the slowest — one whose vault no longer answers took the whole 8 s
        // (measured 2026-10-16: 7 s late on an emulator with old accounts).
        val seen = java.util.concurrent.ConcurrentLinkedQueue<Approval>()
        var shown = false
        // EL ASUNTO, ANTES QUE NADA (dueño, 2026-11-04: «que al menos tengan asunto, para ver
        // quién solicita qué»). Viene sellado a este teléfono en el timbre y se abre sin red: el
        // aviso dice el porqué aunque la bóveda tarde. La lista, que llega después, manda.
        val subject = runBlocking { withTimeoutOrNull(3_000) { runCatching { ringSubject(this@PushService, message.data["sealed"]) }.getOrNull() } }
        subject?.let { VaultRing.approval(it) }?.let { a -> synchronized(seen) { seen.add(a); notifyRequest(this, seen.toList()); shown = true } }
        val subjectNotice = subject?.let { VaultRing.notice(it) }
        if (subjectNotice != null) { notifyUpdated(this, subjectNotice); markShown(this, subjectNotice.id) }
        val early: (ApprovalsAnswer) -> Unit = { a ->
            if (a.items.isNotEmpty()) synchronized(seen) {
                // El pedido del asunto es el mismo que trae la lista: no se cuenta dos veces.
                val ids = a.items.map { it.id }.toSet(); seen.removeAll { it.id in ids }
                seen.addAll(a.items); notifyRequest(this, seen.toList(), again = shown); shown = true
            }
        }
        val answer = runBlocking { withTimeoutOrNull(8_000) { runCatching { pendingRequests(this@PushService, early) }.getOrNull() } }
        // SIN PEDIDOS Y CON UNA NOTICIA NUEVA: el timbre era para contarla («tu bóveda se
        // actualizó»), no para pedir nada. Con pedidos, mandan los pedidos, como siempre.
        // A RING THAT NO ACCOUNT EXPLAINS may be for one that is no longer on this phone: the
        // proxy is told which ones are left, so that one stops ringing.
        if (answer != null && answer.items.isEmpty() && answer.notices.isEmpty()) IdentityKeysBridge.prunePushSoon(this)
        val updated = answer?.let { freshUpdate(this, it.notices) }
        if (answer != null && answer.items.isEmpty() && updated != null) notifyUpdated(this, updated)
        else if (answer?.items?.isNotEmpty() == true) notifyRequest(this, answer.items, again = shown)
        // «TU BÓVEDA TIENE UN PEDIDO» SOLO SI PUEDE HABERLO. Antes salía también cuando la lista
        // llegaba VACÍA —un timbre de «se actualizó» ya contado, o de un aviso que esta app no
        // sabe pintar—, y el dueño veía pedidos de aprobación de aparatos con `unattended` que
        // no habían pedido nada (2026-11-04). Ahora el genérico es solo para «no pude preguntar»
        // (sin respuesta a tiempo) y sin asunto que lo explique.
        else if (answer == null && !shown && subjectNotice == null) notifyRequest(this, null)
    }
}
