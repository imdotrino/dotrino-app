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
}
