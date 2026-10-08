package com.dotrino.app

import android.content.Context
import com.dotrino.sdk.Approval
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive

/**
 * WHAT A REQUEST IS ASKING FOR, in one line. The same text in the Requests screen and in the
 * system notice, so the notice says the why and never disagrees with what the screen shows.
 */
object RequestText {
    private const val VAULT_PRODUCT = "@dotrino/vaultd"

    fun who(a: Approval): String =
        if (a.label.isNotBlank()) "${a.label} (${a.deviceId})" else a.deviceId

    fun title(ctx: Context, a: Approval): String = when (a.kind) {
        // Someone asks to install a new version: the vault itself (no `product`, or its own), or
        // a device that runs something else (an agent from npm) and says which with `ctx.product`.
        "update" -> {
            val version = a.ctx?.get("version")?.jsonPrimitive?.content ?: "?"
            val product = a.ctx?.get("product")?.jsonPrimitive?.content
            if (product.isNullOrBlank() || product == VAULT_PRODUCT) ctx.getString(R.string.req_update, version)
            else ctx.getString(R.string.req_update_device, who(a), version)
        }
        "write" -> ctx.getString(R.string.req_writes, who(a), a.ns)
        // The password vault: which FIELDS it wants to read (vaultd ≥ 0.136.0), never the entry.
        "passwords" -> ctx.getString(R.string.req_passwords, who(a))
        // An INCIDENT (vaultd ≥ 0.142.0): a device failed the terminal code of `ns` (the reporter) three times. Block or ignore.
        "incident" -> ctx.getString(R.string.req_incident, who(a), reporter(a))
        else -> ctx.getString(R.string.req_asks, who(a), a.ns)
    }

    /** Who reported the incident: its label and id, or just the id (`ns`). */
    fun reporter(a: Approval): String {
        val label = a.ctx?.get("reporterLabel")?.jsonPrimitive?.content
        return if (!label.isNullOrBlank()) "$label (${a.ns})" else a.ns
    }

    /** «Fields: password, 2FA code» for a password request; null when it says none. */
    fun fields(ctx: Context, a: Approval): String? {
        val list = (a.ctx?.get("fields") as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content } ?: return null
        if (list.isEmpty()) return null
        return ctx.getString(R.string.req_fields, list.joinToString(", ") { fieldName(ctx, it) })
    }

    private fun fieldName(ctx: Context, f: String): String = when (f) {
        "password" -> ctx.getString(R.string.field_password)
        "totp" -> ctx.getString(R.string.field_totp)
        "passkey", "webauthn" -> ctx.getString(R.string.field_passkey)
        "notes" -> ctx.getString(R.string.field_notes)
        else -> f
    }
}
