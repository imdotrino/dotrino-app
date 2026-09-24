package com.dotrino.app

import android.content.Context
import android.util.Log
import com.dotrino.sdk.Account
import com.dotrino.sdk.AccountStore
import com.dotrino.sdk.Approval
import com.dotrino.sdk.Grant
import com.dotrino.sdk.KeystoreKeys
import com.dotrino.sdk.ProxyConnection
import com.dotrino.sdk.VaultClient
import com.dotrino.sdk.VaultError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.jsonPrimitive
import java.util.concurrent.ConcurrentHashMap

/**
 * The native approvals, account by account. While the screen is visible each account keeps
 * ONE connection open to its proxy, identified with its own key, so a new request arrives
 * live (the vault's `approval` notice) instead of waiting for a poll.
 *
 * WHAT A REQUEST LIST CAN BE REPLACED BY. Only by a newer answer from THAT account's vault.
 * A late answer to an older question is dropped (`seq`), a failed refresh keeps what was on
 * screen and says it failed, and one account never touches another's list. That is what
 * made requests show for a second and vanish on the web.
 */
class ApprovalsModel(context: Context) {
    companion object {
        private const val TAG = "dotrino-approvals"
        const val POLL_MS = 15_000L
        const val CANNOT_APPROVE = "cannot-approve"
        const val NO_REPLY = "vault-no-reply"
        const val NOT_CONNECTED = "not-connected"
    }

    sealed interface Status {
        data object Connecting : Status
        data object Live : Status
        data class Failed(val reason: String) : Status
    }

    data class AccountState(
        val account: Account,
        val status: Status = Status.Connecting,
        val items: List<Approval> = emptyList(),
        val grants: List<Grant> = emptyList(),
        /** When the lists were last confirmed by the vault; null = never yet. */
        val confirmedAt: Long? = null,
        /** Requests being answered right now: their buttons stay disabled. */
        val busy: Set<String> = emptySet(),
        /** The last thing that went wrong answering or refreshing, said on screen. */
        val error: String? = null,
    )

    private val app = context.applicationContext
    private val store = AccountStore(app)
    private val _state = MutableStateFlow<Map<String, AccountState>>(emptyMap())
    val state: StateFlow<Map<String, AccountState>> = _state

    private var scope: CoroutineScope? = null
    private val sessions = ConcurrentHashMap<String, Pair<ProxyConnection, VaultClient>>()
    /** Accounts with a refresh in flight, and those asked to refresh again when it ends. */
    private val inflight = ConcurrentHashMap.newKeySet<String>()
    private val again = ConcurrentHashMap.newKeySet<String>()

    /** Opens a session per account. Called when the screen becomes visible. */
    fun start() {
        if (scope != null) return
        val s = CoroutineScope(SupervisorJob() + Dispatchers.IO).also { scope = it }
        val accounts = try { store.list() } catch (e: Exception) {
            Log.e(TAG, "could not read the accounts file", e)
            _state.value = emptyMap(); return
        }
        _state.value = accounts.associate { it.id to (_state.value[it.id]?.copy(account = it, status = Status.Connecting) ?: AccountState(it)) }
        for (a in accounts) s.launch { session(a) }
        // Safety net: a notice lost on the way should not leave a request unseen.
        s.launch { while (isActive) { delay(POLL_MS); refreshAll() } }
    }

    /** Closes every session. Called when the screen is no longer visible. */
    fun stop() {
        scope?.cancel(); scope = null
        sessions.values.forEach { runCatching { it.first.close() } }
        sessions.clear()
    }

    fun accountsCount(): Int = try { store.list().size } catch (_: Exception) { 0 }

    /** Keeps an account connected: on a dropped socket it reconnects with a growing wait. */
    private suspend fun session(a0: Account) {
        var wait = 1_000L
        while (scope?.isActive == true) {
            // Removed from this phone: its session ends here, it does not keep retrying with keys that are gone.
            val a = _state.value[a0.id]?.account ?: return
            try {
                val keys = KeystoreKeys.open(a.id)
                val conn = ProxyConnection(a.proxy)
                conn.connect()
                conn.identify(keys)
                val vc = VaultClient(a, keys, conn) { renewed ->
                    store.save(renewed)
                    set(renewed.id) { it.copy(account = renewed) }
                }
                conn.onMessage { m ->
                    // The vault's «there is a request» notice: refresh THIS account now.
                    if (m.payload["type"]?.jsonPrimitive?.content == VaultClient.ADMIN_EVENT) {
                        Log.i(TAG, "account ${a.deviceId}: notice from the vault at ${System.currentTimeMillis()}")
                        scope?.launch { refresh(a.id) }
                    }
                }
                sessions[a.id] = conn to vc
                set(a.id) { it.copy(status = Status.Live) }
                wait = 1_000L
                refresh(a.id)
                while (conn.closed == null && scope?.isActive == true) delay(500)
                set(a.id) { it.copy(status = Status.Failed(conn.closed ?: "closed")) }
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) {
                Log.w(TAG, "account ${a.deviceId}: ${e.message}")
                set(a.id) { it.copy(status = Status.Failed(e.message ?: e.javaClass.simpleName)) }
            } finally { sessions.remove(a.id)?.first?.let { runCatching { it.close() } } }
            delay(wait); wait = (wait * 2).coerceAtMost(30_000L)
        }
    }

    fun refreshAll() { val s = scope ?: return; for (id in _state.value.keys) s.launch { refresh(id) } }

    /**
     * ONE question in flight per account. A refresh asked while another is running is not
     * sent in parallel: it runs once more when the current one ends. So answers can never
     * arrive out of order, and a failure is never thrown away for being «old» — which is
     * what happened before: against a vault that does not answer, every 15 s timeout was
     * overtaken by the next poll and discarded, and the screen said nothing at all.
     */
    private suspend fun refresh(id: String) {
        if (!inflight.add(id)) { again.add(id); return }
        try {
            do {
                again.remove(id)
                val vc = sessions[id]?.second ?: return
                try {
                    val items = vc.approvals()
                    val grants = runCatching { vc.grants() }.getOrElse { _state.value[id]?.grants ?: emptyList() }
                    val before = _state.value[id]?.items?.map { it.id }?.toSet()
                    set(id) { it.copy(items = items, grants = grants, confirmedAt = System.currentTimeMillis(), error = null) }
                    if (before != items.map { it.id }.toSet()) {
                        Log.i(TAG, "account ${_state.value[id]?.account?.deviceId}: ${items.size} request(s) [${items.joinToString(",") { it.id }}] at ${System.currentTimeMillis()}")
                    }
                } catch (e: kotlinx.coroutines.CancellationException) { throw e }
                catch (e: Exception) {
                    Log.w(TAG, "refresh ${_state.value[id]?.account?.deviceId}: ${e.message}")
                    // What was on screen STAYS: failing to refresh is not «there are no requests».
                    set(id) { it.copy(error = messageOf(e)) }
                }
            } while (id in again)
        } finally { inflight.remove(id) }
    }

    fun approve(accountId: String, requestId: String) = answer(accountId, requestId) { it.approve(requestId) }
    fun deny(accountId: String, requestId: String) = answer(accountId, requestId) { it.deny(requestId) }
    fun revokeGrant(accountId: String, grantId: String) = answer(accountId, grantId) { it.revokeGrant(grantId) }

    private fun answer(accountId: String, key: String, op: suspend (VaultClient) -> Unit) {
        val s = scope ?: return
        val vc = sessions[accountId]?.second ?: run { set(accountId) { it.copy(error = NOT_CONNECTED) }; return }
        set(accountId) { it.copy(busy = it.busy + key, error = null) }
        s.launch {
            try {
                op(vc)
                // Answered: it leaves the list NOW, and the vault's list confirms it next.
                set(accountId) { st -> st.copy(items = st.items.filter { it.id != key }, grants = st.grants.filter { it.id != key }) }
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) { set(accountId) { it.copy(error = messageOf(e)) } }
            finally {
                set(accountId) { it.copy(busy = it.busy - key) }
                refresh(accountId)
            }
        }
    }

    /**
     * `cannot-approve` is the one the screen translates and explains (the record does not let
     * this key approve yet: `+aprueba` is missing). Anything else is shown as the vault or the
     * network said it: it is what someone will paste in an issue.
     */
    private fun messageOf(e: Exception): String = when {
        e is VaultError && e.code == "acta" -> CANNOT_APPROVE
        e is VaultError && e.code == "vault-no-reply" -> NO_REPLY
        else -> e.message ?: e.javaClass.simpleName
    }

    private fun set(id: String, f: (AccountState) -> AccountState) {
        _state.update { m -> m[id]?.let { m + (id to f(it)) } ?: m }
    }

    /** Removes an account from this phone: its keys go with it. It stays in the vault's record until revoked there. */
    fun remove(accountId: String) {
        store.remove(accountId)
        sessions.remove(accountId)?.first?.let { runCatching { it.close() } }
        _state.update { it - accountId }
    }
}
