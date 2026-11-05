package com.dotrino.app

import org.junit.Assert.assertEquals
import org.junit.Test

/** A device is named with its alias AND its id wherever the app shows it. */
class RequestTextTest {
    @Test fun aliasAndIdBoth() {
        assertEquals("portátil (AB12-CD34)", RequestText.named("portátil", "AB12-CD34"))
    }

    @Test fun withoutAliasOnlyTheId() {
        assertEquals("AB12-CD34", RequestText.named("", "AB12-CD34"))
        assertEquals("AB12-CD34", RequestText.named(null, "AB12-CD34"))
        assertEquals("AB12-CD34", RequestText.named("  ", "AB12-CD34"))
    }

    @Test fun theNotificationSaysWhichProfile() {
        val names = mapOf("r1" to "Personal", "r2" to "Cepi", "r3" to "Personal", "r4" to "")
        assertEquals("Personal", RequestText.profilesOf(listOf("r1"), names))
        assertEquals("Personal, Cepi", RequestText.profilesOf(listOf("r1", "r2", "r3"), names))
        assertEquals(null, RequestText.profilesOf(listOf("x", "r4"), names))
    }
}
