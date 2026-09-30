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
    fun who(a: Approval): String =
        if (a.label.isNotBlank()) "${a.label} (${a.deviceId})" else a.deviceId

    fun title(ctx: Context, a: Approval): String = when (a.kind) {
        // The vault itself asks to install a new version (vaultd ≥ 0.130.0).
        "update" -> ctx.getString(R.string.req_update, a.ctx?.get("version")?.jsonPrimitive?.content ?: "?")
        "write" -> ctx.getString(R.string.req_writes, who(a), a.ns)
        // The password vault: which FIELDS it wants to read (vaultd ≥ 0.136.0), never the entry.
        "passwords" -> ctx.getString(R.string.req_passwords, who(a))
        else -> ctx.getString(R.string.req_asks, who(a), a.ns)
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
