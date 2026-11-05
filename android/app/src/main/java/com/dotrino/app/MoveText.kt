package com.dotrino.app

import android.content.Context
import com.dotrino.sdk.VaultNotice
import java.text.DateFormat
import java.util.Date

/**
 * WHAT HAPPENED IN THE LAST 24 HOURS, one line per notice (vaultd ≥ 0.193.0 for closed requests).
 *
 * The owner, 2026-11-05: «the notices arrive but when I open them in the app there is no trace of
 * anything». A request that was answered or expired left the list, and the ring that had already
 * sounded had nothing behind it. The vault keeps a notice for 24 h; this turns it into a line.
 *
 * Devices are named with ALIAS AND ID («laptop (AB12-CD34)», `VaultNotice.device` / `approver`),
 * and the words of the system notices are reused where there is one (delivered, updated), so the
 * screen and the notice never tell two different stories.
 *
 * The text is built from a [Strings] and not from a `Context`, so it is tested on the JVM.
 */
object MoveText {
    /** Where the words come from: the app's resources, or a table in a test. */
    fun interface Strings { fun get(id: Int, vararg args: Any): String }

    fun of(ctx: Context) = Strings { id, args -> ctx.getString(id, *args) }

    /** Notices that say nothing to a person (the log anchor is checked, not shown). */
    fun shown(n: VaultNotice) = n.ev != "log-anchor"

    fun line(ctx: Context, n: VaultNotice): String =
        DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(n.ts)) + " · " + text(of(ctx), n)

    fun text(s: Strings, n: VaultNotice): String = when (n.ev) {
        "answered" -> {
            val w = n.device ?: s.get(R.string.move_the_vault); val ns = n.ns ?: "?"
            val what = when (n.kind) {
                "write" -> s.get(R.string.move_writes, w, ns)
                "reveal" -> s.get(R.string.move_reveals, w, ns)
                "passwords" -> s.get(R.string.move_passwords, w)
                "update" -> s.get(R.string.move_update, w)
                "incident" -> s.get(R.string.move_incident, w)
                else -> s.get(R.string.move_asks, w, ns)
            }
            val how = when (n.outcome) {
                "approved" -> s.get(R.string.move_approved)
                "denied" -> s.get(R.string.move_denied)
                "blocked" -> s.get(R.string.move_blocked)
                "ignored" -> s.get(R.string.move_ignored)
                "withdrawn" -> s.get(R.string.move_withdrawn)
                "expired" -> s.get(R.string.move_expired)
                else -> n.outcome ?: "?"
            }
            val by = n.approver?.let { " " + s.get(R.string.move_by, it) } ?: ""
            "$what: $how$by"
        }
        "delivered" -> {
            val w = n.device ?: "?"
            if (n.kind == "passwords") s.get(R.string.notif_delivered_passwords_title, w)
            else s.get(R.string.notif_delivered_secrets_title, w, n.ns ?: "?")
        }
        "updated" -> (n.device?.let { s.get(R.string.notif_updated_device_title, it) } ?: s.get(R.string.notif_updated_title)) + " (${n.version})"
        "update-needs-root" -> (n.device?.let { s.get(R.string.notif_needs_root_device_title, it) } ?: s.get(R.string.notif_needs_root_title)) + " (${n.version})"
        "pairing-contested" -> s.get(R.string.move_contested)
        else -> n.ev
    }
}
