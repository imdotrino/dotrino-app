package com.dotrino.app

import com.dotrino.sdk.VaultNotice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The «Last 24 hours» lines of Requests (`MoveText`). The words come from a table here instead
 * of the resources: what is tested is which words are picked and how they are put together.
 */
class MoveTextTest {
    private val es = mapOf(
        R.string.move_the_vault to "La bóveda",
        R.string.move_asks to "%1\$s pidió las claves de %2\$s",
        R.string.move_writes to "%1\$s quiso guardar variables en %2\$s",
        R.string.move_reveals to "%1\$s pidió ver una variable de %2\$s",
        R.string.move_passwords to "%1\$s pidió una contraseña",
        R.string.move_update to "%1\$s pidió actualizarse",
        R.string.move_incident to "Incidente de seguridad de %1\$s",
        R.string.move_approved to "aprobado",
        R.string.move_denied to "denegado",
        R.string.move_blocked to "bloqueado",
        R.string.move_ignored to "ignorado",
        R.string.move_withdrawn to "retirado",
        R.string.move_expired to "caducó sin respuesta",
        R.string.move_by to "por %1\$s",
        R.string.move_contested to "Dos aparatos respondieron a la misma invitación de emparejar y se canceló.",
        R.string.notif_delivered_passwords_title to "%1\$s se llevó una contraseña",
        R.string.notif_delivered_secrets_title to "%1\$s se llevó las claves de %2\$s",
        R.string.notif_updated_title to "Tu bóveda se actualizó",
        R.string.notif_updated_device_title to "%1\$s se actualizó",
        R.string.notif_needs_root_title to "Tu bóveda tiene una actualización pendiente",
        R.string.notif_needs_root_device_title to "%1\$s tiene una actualización pendiente",
    )
    private val words = MoveText.Strings { id, args -> String.format(es[id] ?: error("missing string $id"), *args) }

    private fun answered(outcome: String, kind: String = "read", by: String? = "EF56-7890", byLabel: String? = "teléfono") =
        VaultNotice(id = "a", ev = "answered", version = "", from = "", ts = 1, ns = "claude", kind = kind,
            deviceId = "AB12-CD34", label = "portátil", outcome = outcome, by = by, byLabel = byLabel)

    @Test fun anApprovedRequestSaysWhoAskedWhatAndWhoApprovedWithAliasAndId() {
        assertEquals("portátil (AB12-CD34) pidió las claves de claude: aprobado por teléfono (EF56-7890)",
            MoveText.text(words, answered("approved")))
    }

    @Test fun anExpiredRequestWasAnsweredByNobody() {
        assertEquals("portátil (AB12-CD34) pidió las claves de claude: caducó sin respuesta",
            MoveText.text(words, answered("expired", by = null, byLabel = null)))
    }

    @Test fun anApproverWithoutAliasIsNamedByItsId() {
        assertEquals("portátil (AB12-CD34) quiso guardar variables en claude: denegado por EF56-7890",
            MoveText.text(words, answered("denied", kind = "write", byLabel = "")))
    }

    @Test fun eachKindAndOutcomeHasItsWords() {
        assertEquals("portátil (AB12-CD34) pidió una contraseña: retirado por teléfono (EF56-7890)", MoveText.text(words, answered("withdrawn", kind = "passwords")))
        assertEquals("portátil (AB12-CD34) pidió ver una variable de claude: ignorado por teléfono (EF56-7890)", MoveText.text(words, answered("ignored", kind = "reveal")))
        assertEquals("Incidente de seguridad de portátil (AB12-CD34): bloqueado por teléfono (EF56-7890)", MoveText.text(words, answered("blocked", kind = "incident")))
        assertEquals("portátil (AB12-CD34) pidió actualizarse: aprobado por teléfono (EF56-7890)", MoveText.text(words, answered("approved", kind = "update")))
    }

    @Test fun whatAnUnattendedDeviceTookUsesTheWordsOfTheSystemNotice() {
        val secrets = VaultNotice(id = "d", ev = "delivered", version = "", from = "", ts = 1, kind = "secrets", ns = "claude", deviceId = "AB12-CD34", label = "servidor")
        assertEquals("servidor (AB12-CD34) se llevó las claves de claude", MoveText.text(words, secrets))
        assertEquals("servidor (AB12-CD34) se llevó una contraseña", MoveText.text(words, secrets.copy(kind = "passwords")))
    }

    @Test fun anUpdateSaysWhoAndToWhichVersion() {
        val vault = VaultNotice(id = "u", ev = "updated", version = "0.193.0", from = "0.192.1", ts = 1)
        assertEquals("Tu bóveda se actualizó (0.193.0)", MoveText.text(words, vault))
        val agent = vault.copy(product = "@dotrino/terminal-agent", deviceId = "AB12-CD34", label = "portátil", version = "1.2.3")
        assertEquals("portátil (AB12-CD34) se actualizó (1.2.3)", MoveText.text(words, agent))
        assertEquals("portátil (AB12-CD34) tiene una actualización pendiente (1.2.3)", MoveText.text(words, agent.copy(ev = "update-needs-root")))
    }

    @Test fun theLogAnchorIsNotShown() {
        assertFalse(MoveText.shown(VaultNotice(id = "l", ev = "log-anchor", version = "", from = "", ts = 1)))
        assertTrue(MoveText.shown(answered("approved")))
    }
}
