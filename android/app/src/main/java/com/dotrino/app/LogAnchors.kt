package com.dotrino.app

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import com.dotrino.sdk.LogAnchor
import com.dotrino.sdk.VaultNotice

/**
 * EL ANCLA DE LA BITÁCORA, guardada en este teléfono (vault ≥ 0.104.0).
 *
 * La bóveda sella cada pocas horas la cabeza de su bitácora y la manda, callada, a quien
 * aprueba. Este teléfono guarda la última de cada cuenta: si llega una con menos entradas, o
 * con las mismas y otra cabeza, alguien cortó o reescribió el final de la bitácora en esa
 * máquina, y eso es justo lo que la cadena sola no deja ver. Entonces se avisa, una vez por
 * ancla distinta, y la buena (la vieja) se queda guardada.
 */
object LogAnchors {
    private const val TAG = "LogAnchors"
    private const val PREFS = "log-anchors"

    /**
     * Compara el ancla más nueva de [notices] con la guardada de [accountId]. Devuelve el
     * veredicto de [LogAnchor.compare], o `null` si la bóveda no mandó ninguna.
     */
    fun check(ctx: Context, accountId: String, notices: List<VaultNotice>): String? {
        val next = LogAnchor.latest(notices) ?: return null
        val seq = next.logSeq ?: return null
        val head = next.head ?: return null
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val kept = prefs.getString(accountId, null)?.split('|')
        val verdict = LogAnchor.compare(kept?.getOrNull(0)?.toLongOrNull(), kept?.getOrNull(1), seq, head)
        if (LogAnchor.isAlarm(verdict)) {
            val alarmKey = "alarm:$accountId"
            val incoming = "$seq|$head"
            if (prefs.getString(alarmKey, null) != incoming) {
                Log.w(TAG, "account $accountId: log anchor $verdict (kept ${kept?.getOrNull(0)}, got $seq)")
                prefs.edit().putString(alarmKey, incoming).apply()
                notifyCut(ctx)
            }
        } else if (verdict != LogAnchor.SAME) {
            prefs.edit().putString(accountId, "$seq|$head").apply()
        }
        return verdict
    }

    private fun notifyCut(ctx: Context) {
        PushService.ensureChannel(ctx)
        val body = ctx.getString(R.string.notif_log_cut_body)
        val open = Intent(ctx, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP }
        val pi = PendingIntent.getActivity(ctx, 3, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(ctx, PushService.CHANNEL)
            .setSmallIcon(R.drawable.ic_vault)
            .setContentTitle(ctx.getString(R.string.notif_log_cut_title))
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        try { (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(1003, n) } catch (_: SecurityException) {}
    }
}
