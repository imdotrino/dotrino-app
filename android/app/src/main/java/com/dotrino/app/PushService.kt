package com.dotrino.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * El TIMBRE. El proxio manda por FCM un `{ type: 'ring' }` sin contenido cuando la bóveda
 * tiene algo para este aparato (un pedido de claves, una firma SSH). Aquí solo se muestra
 * el aviso del sistema; tocarlo abre Pedidos, que baja el detalle por el proxio. El token
 * de FCM se registra bajo la llave del aparato desde la página (MainActivity lo inyecta).
 */
class PushService : FirebaseMessagingService() {

    companion object {
        const val CHANNEL = "vault"
        private const val PREFS = "push"
        private const val KEY_TOKEN = "fcmToken"

        fun savedToken(ctx: Context): String? = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TOKEN, null)

        fun ensureChannel(ctx: Context) {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(NotificationChannel(CHANNEL, ctx.getString(R.string.channel_vault), NotificationManager.IMPORTANCE_HIGH))
            }
        }

        fun notifyRequest(ctx: Context) {
            ensureChannel(ctx)
            val open = Intent(ctx, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse(MainActivity.APPROVALS)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pi = PendingIntent.getActivity(ctx, 1, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val n = NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(R.drawable.ic_vault)
                .setContentTitle(ctx.getString(R.string.notif_title))
                .setContentText(ctx.getString(R.string.notif_body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            try { (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(1001, n) } catch (_: SecurityException) {}
        }
    }

    override fun onNewToken(token: String) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_TOKEN, token).apply()
        MainActivity.current?.pushTokenChanged(token) ?: IdentityKeysBridge.registerAll(this, token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // Con los Pedidos a la vista, se refrescan ahí y sobra el aviso del sistema.
        if (MainActivity.current?.onRing() == true) return
        // Venga lo que venga (ring o futuro), el aviso es el mismo: no hay contenido que mostrar.
        notifyRequest(this)
    }
}
