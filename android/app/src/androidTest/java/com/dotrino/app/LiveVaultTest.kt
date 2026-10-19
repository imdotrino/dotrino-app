package com.dotrino.app

import android.content.Intent
import android.net.Uri
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.android.material.bottomnavigation.BottomNavigationView
import org.json.JSONTokener
import org.junit.Assert.assertNotNull
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The app against a REAL vault, end to end — the Android twin of `LiveVaultUITests.swift`: it opens
 * the vault's invite, hands the six digits to the vault, and approves a write and a key request in
 * Requests. Every message the app sends to the vault goes binary (dotrino-native ≥ 0.42.0), so this
 * is what says the vault understands it.
 *
 * Inside the app's process and not with uiautomator: the Requests screen never goes idle (the
 * «expires in» countdown ticks every second), and uiautomator gives up on a screen that does not.
 *
 * The code goes to the vault side through the log (`dotrino-live: code 123456`), which the smoke
 * reads with `adb logcat`: the app does not allow cleartext HTTP, and a test is no reason to open it.
 *
 * Run by `smoke:native-app` of dotrino-test, which starts the vault and passes:
 *   adb shell am instrument -w -e invite <link> com.dotrino.app.test/androidx.test.runner.AndroidJUnitRunner
 */
@RunWith(AndroidJUnit4::class)
class LiveVaultTest {
    private val args = InstrumentationRegistry.getArguments()

    @Test fun addsAVaultAndApprovesItsRequests() {
        val invite = args.getString("invite")
        assumeTrue("pass -e invite (smoke:native-app of dotrino-test)", invite != null)
        val open = Intent(Intent.ACTION_VIEW, Uri.parse(invite)).setClass(InstrumentationRegistry.getInstrumentation().targetContext, MainActivity::class.java)
        ActivityScenario.launch<MainActivity>(open).use { sc ->
            // The six digits, from the line the pairing page shows for the computer's vault.
            val code = poll(90, "the pairing page did not show the code") {
                Regex("""dotrino-vault approve (\d{6})""").find(pageText(sc))?.groupValues?.get(1)
            }
            Log.i("dotrino-live", "code $code")
            // The page says the device is in when it shows the `caps` line with its ID: only then
            // does the account reach Requests.
            poll(90, "the pairing page did not finish") {
                Regex("""dotrino-vault caps [0-9A-F]{4}-[0-9A-F]{4}""").find(pageText(sc))?.value
            }

            sc.onActivity { it.findViewById<BottomNavigationView>(R.id.nav).selectedItemId = R.id.nav_approvals }
            // A write first, then the key request the vault side asks for once the write is stored.
            val first = approveOne(sc, null)
            approveOne(sc, first)
        }
    }

    /** Taps Approve on a request whose text is not [skip]; returns that text. */
    private fun approveOne(sc: ActivityScenario<MainActivity>, skip: String?): String = poll(150, "no request to approve (after: $skip)") {
        var done: String? = null
        sc.onActivity { a ->
            for (b in views(a.findViewById(R.id.approvalsList)).filter { it.id == R.id.approve && it.isShown && it.isEnabled }) {
                val card = b.parent?.parent as? ViewGroup ?: continue
                val who = views(card).filterIsInstance<TextView>().firstOrNull { it.id == R.id.who }?.text?.toString() ?: continue
                if (who == skip) continue
                b.performClick(); done = who; break
            }
        }
        done
    }

    private fun views(v: View): List<View> = listOf(v) + ((v as? ViewGroup)?.let { g -> (0 until g.childCount).flatMap { views(g.getChildAt(it)) } } ?: emptyList())

    private fun pageText(sc: ActivityScenario<MainActivity>): String {
        val latch = CountDownLatch(1)
        var text = ""
        sc.onActivity { a ->
            a.findViewById<WebView>(R.id.web).evaluateJavascript("document.body ? document.body.innerText : ''") { v ->
                text = runCatching { JSONTokener(v).nextValue() as? String }.getOrNull() ?: ""
                latch.countDown()
            }
        }
        latch.await(5, TimeUnit.SECONDS)
        return text
    }

    private fun <T> poll(seconds: Int, what: String, f: () -> T?): T {
        val end = System.currentTimeMillis() + seconds * 1000L
        while (System.currentTimeMillis() < end) {
            f()?.let { return it }
            Thread.sleep(1000)
        }
        assertNotNull(what, null)
        error(what)
    }
}
