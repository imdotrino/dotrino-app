package com.dotrino.app

import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.dotrino.sdk.Approval
import com.dotrino.sdk.Grant
import com.google.android.material.button.MaterialButton
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive

/**
 * The native «Requests» tab. One section per account with its NAME always on top, then its
 * requests, then what is approved for now. Nothing here goes through the WebView.
 */
class ApprovalsScreen(
    private val activity: AppCompatActivity,
    private val swipe: SwipeRefreshLayout,
    list: RecyclerView,
    private val onAddAccount: () -> Unit,
    private val onOpenWeb: () -> Unit,
) {
    val model = ApprovalsModel(activity)
    private val adapter = Adapter()
    private var collect: Job? = null
    private val ticker = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() { adapter.tick(); ticker.postDelayed(this, 1000) }
    }

    init {
        list.layoutManager = LinearLayoutManager(activity)
        list.adapter = adapter
        list.itemAnimator = null   // rows are replaced in place; no fade that looks like «it vanished»
        swipe.setOnRefreshListener { model.refreshAll(); swipe.postDelayed({ swipe.isRefreshing = false }, 600) }
    }

    val visible: Boolean get() = swipe.visibility == View.VISIBLE

    fun show() {
        swipe.visibility = View.VISIBLE
        model.start()
        if (collect == null) collect = activity.lifecycleScope.launch { model.state.collect { adapter.submitList(rowsOf(it)) } }
        ticker.removeCallbacks(tick); ticker.post(tick)
    }

    fun hide() {
        swipe.visibility = View.GONE
        stop()
    }

    /** The app went to the background: sockets closed, nothing left running. */
    fun stop() {
        model.stop()
        collect?.cancel(); collect = null
        ticker.removeCallbacks(tick)
    }

    /** A push arrived while the screen is open: ask every vault now. */
    fun ring() { if (visible) model.refreshAll() }

    // ---------------------------------------------------------------- rows

    private sealed interface Row { val key: String }
    private data class Header(val st: ApprovalsModel.AccountState) : Row { override val key = "h:" + st.account.id }
    private data class Req(val accountId: String, val a: Approval, val busy: Boolean) : Row { override val key = "r:$accountId:${a.id}" }
    private data class Note(override val key: String, val text: String) : Row
    private data class GrantRow(val accountId: String, val g: Grant, val busy: Boolean) : Row { override val key = "g:$accountId:${g.id}" }
    private data class Action(override val key: String, val label: String, val onClick: () -> Unit) : Row {
        override fun equals(other: Any?) = other is Action && other.key == key && other.label == label
        override fun hashCode() = key.hashCode()
    }

    private fun s(id: Int, vararg args: Any) = activity.getString(id, *args)

    private fun rowsOf(m: Map<String, ApprovalsModel.AccountState>): List<Row> {
        val rows = mutableListOf<Row>()
        if (m.isEmpty()) {
            rows += Note("none-accounts", s(R.string.no_accounts))
            rows += Action("add", s(R.string.add_account), onAddAccount)
            rows += Action("web", s(R.string.open_web), onOpenWeb)
            return rows
        }
        // A FIXED order (the one they were added in): an account that jumps up or down when a
        // request arrives or is answered is exactly how you lose track of which one is which.
        val ordered = m.values.sortedBy { it.account.addedAt }
        var anyRead = false
        for (st in ordered) {
            val id = st.account.id
            rows += Header(st)
            for (a in st.items) { rows += Req(id, a, a.id in st.busy); if (a.kind == "read") anyRead = true }
            if (st.items.isEmpty() && st.confirmedAt != null) rows += Note("n:$id", s(R.string.none))
            if (st.grants.isNotEmpty()) {
                rows += Note("gt:$id", s(R.string.grants_title))
                st.grants.forEach { rows += GrantRow(id, it, it.id in st.busy) }
            }
        }
        if (m.values.any { it.items.isNotEmpty() }) rows += Note("warn", s(R.string.warn))
        if (anyRead) rows += Note("hint", s(R.string.grant_hint))
        rows += Action("add", s(R.string.add_account), onAddAccount)
        return rows
    }

    private fun left(ms: Long): String {
        if (ms <= 0) return s(R.string.req_expired)
        val t = ms / 1000
        return if (t >= 3600) "${t / 3600} h ${(t % 3600) / 60} min" else if (t >= 60) "${t / 60}:${"%02d".format(t % 60)}" else "$t s"
    }

    private fun errorText(st: ApprovalsModel.AccountState): String? = when (val e = st.error) {
        null -> null
        ApprovalsModel.CANNOT_APPROVE -> s(R.string.err_cannot_approve)
        ApprovalsModel.NO_REPLY -> s(R.string.err_no_reply)
        ApprovalsModel.NOT_CONNECTED -> s(R.string.err_not_connected)
        else -> e
    }

    private fun confirmRemove(st: ApprovalsModel.AccountState) {
        MaterialAlertDialogBuilder(activity)
            .setMessage(s(R.string.remove_confirm, st.account.name))
            .setNegativeButton(R.string.cancel, null)
            .setPositiveButton(R.string.remove_account) { _, _ -> model.remove(st.account.id) }
            .show()
    }

    private inner class Adapter : ListAdapter<Row, RecyclerView.ViewHolder>(object : DiffUtil.ItemCallback<Row>() {
        override fun areItemsTheSame(a: Row, b: Row) = a.key == b.key
        override fun areContentsTheSame(a: Row, b: Row) = a == b
    }) {
        fun tick() { currentList.forEachIndexed { i, r -> if (r is Req || r is GrantRow) notifyItemChanged(i, "tick") } }

        override fun getItemViewType(position: Int) = when (getItem(position)) {
            is Header -> 0; is Req -> 1; is Note -> 2; is GrantRow -> 3; is Action -> 4
        }

        override fun onCreateViewHolder(parent: ViewGroup, type: Int): RecyclerView.ViewHolder {
            val layout = when (type) { 0 -> R.layout.item_account; 1 -> R.layout.item_request; 2 -> R.layout.item_note; 3 -> R.layout.item_grant; else -> R.layout.item_action }
            return object : RecyclerView.ViewHolder(LayoutInflater.from(parent.context).inflate(layout, parent, false)) {}
        }

        override fun onBindViewHolder(h: RecyclerView.ViewHolder, position: Int, payloads: MutableList<Any>) {
            if (payloads.contains("tick")) { bindTime(h.itemView, getItem(position)); return }
            onBindViewHolder(h, position)
        }

        override fun onBindViewHolder(h: RecyclerView.ViewHolder, position: Int) {
            val v = h.itemView
            when (val r = getItem(position)) {
                is Header -> bindHeader(v, r.st)
                is Req -> bindReq(v, r)
                is Note -> (v as TextView).text = r.text
                is GrantRow -> bindGrant(v, r)
                is Action -> v.findViewById<MaterialButton>(R.id.button).apply { text = r.label; setOnClickListener { r.onClick() } }
            }
        }

        private fun bindHeader(v: View, st: ApprovalsModel.AccountState) {
            v.findViewById<TextView>(R.id.name).text = st.account.name
            v.findViewById<TextView>(R.id.device).text = s(R.string.acct_phone, st.account.deviceId)
            val (text, color) = when (val status = st.status) {
                ApprovalsModel.Status.Live -> s(R.string.acct_live) to R.color.ok
                ApprovalsModel.Status.Connecting -> s(R.string.acct_connecting) to R.color.muted
                is ApprovalsModel.Status.Failed -> s(R.string.acct_failed, status.reason) to R.color.bad
            }
            v.findViewById<TextView>(R.id.status).text = text
            // Connected to the proxy is not «all good»: if the vault is not answering, the dot says so too.
            val dot = if (st.error != null && color == R.color.ok) R.color.warn else color
            v.findViewById<View>(R.id.dot).background.setTint(ContextCompat.getColor(activity, dot))
            v.findViewById<TextView>(R.id.error).apply {
                val e = errorText(st); visibility = if (e == null) View.GONE else View.VISIBLE; this.text = e
            }
            v.setOnLongClickListener { confirmRemove(st); true }
        }

        private fun bindReq(v: View, r: Req) {
            val a = r.a
            val who = a.label.ifBlank { a.deviceId }.let { if (a.label.isNotBlank()) "$it (${a.deviceId})" else it }
            val detail = v.findViewById<TextView>(R.id.detail)
            val sub = v.findViewById<TextView>(R.id.sub)
            val ctx = a.ctx
            v.findViewById<TextView>(R.id.who).text = when (a.kind) {
                // The vault itself asks to install a new version (vaultd ≥ 0.130.0).
                "update" -> s(R.string.req_update, ctx?.get("version")?.jsonPrimitive?.content ?: "?")
                "write" -> s(R.string.req_writes, who, a.ns)
                else -> s(R.string.req_asks, who, a.ns)
            }
            when {
                a.kind == "update" -> {
                    val from = ctx?.get("from")?.jsonPrimitive?.content
                    detail.text = if (from != null) s(R.string.req_update_from, from) else ""
                    sub.visibility = View.VISIBLE; sub.text = s(R.string.req_update_verified)
                    sub.setTextColor(ContextCompat.getColor(activity, R.color.muted))
                }
                a.kind == "write" && ctx != null -> {
                    val keys = (ctx["keys"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content } ?: emptyList()
                    detail.text = s(R.string.req_keys, keys.joinToString(", ")); sub.visibility = View.GONE
                }
                ctx != null -> {
                    detail.text = s(R.string.req_cmd, commandOf(ctx))
                    val cwd = ctx["cwd"]?.jsonPrimitive?.content ?: "?"
                    val proc = ctx["verified"]?.jsonPrimitive?.content == "proc"
                    sub.visibility = View.VISIBLE
                    sub.text = s(R.string.req_cwd, cwd) + " · " + s(if (proc) R.string.req_proc else R.string.req_declared)
                    sub.setTextColor(ContextCompat.getColor(activity, if (proc) R.color.muted else R.color.warn))
                }
                a.ctxError != null -> { detail.text = s(R.string.req_cmderr, a.ctxError!!); sub.visibility = View.GONE }
                else -> { detail.text = s(R.string.req_nocmd); sub.visibility = View.GONE }
            }
            bindTime(v, r)
            // Disabled, never hidden, while the answer travels (memory: buttons are disabled, not removed).
            v.findViewById<MaterialButton>(R.id.approve).apply { isEnabled = !r.busy; setOnClickListener { model.approve(r.accountId, a.id) } }
            v.findViewById<MaterialButton>(R.id.deny).apply { isEnabled = !r.busy; setOnClickListener { model.deny(r.accountId, a.id) } }
        }

        private fun bindGrant(v: View, r: GrantRow) {
            v.findViewById<TextView>(R.id.what).text = r.g.ctx?.let { commandOf(it) } ?: r.g.ns
            bindTime(v, r)
            v.findViewById<MaterialButton>(R.id.revoke).apply { isEnabled = !r.busy; setOnClickListener { model.revokeGrant(r.accountId, r.g.id) } }
        }

        private fun bindTime(v: View, r: Row) {
            val now = System.currentTimeMillis()
            when (r) {
                is Req -> v.findViewById<TextView>(R.id.left).text = s(R.string.req_left, left(r.a.exp - now))
                is GrantRow -> v.findViewById<TextView>(R.id.sub).text =
                    "${r.g.ns} · " + s(R.string.grant_sub, left(r.g.exp - now), r.g.uses.toInt())
                else -> {}
            }
        }
    }

    /** Same text as `apvCmd` in the web console: `argv` joined, or the executable, and `…` when cut. */
    private fun commandOf(ctx: JsonObject): String {
        val argv = (ctx["argv"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }
        val base = if (!argv.isNullOrEmpty()) argv.joinToString(" ") else ctx["exe"]?.jsonPrimitive?.content ?: ""
        val cut = (ctx["truncated"] as? JsonPrimitive)?.content == "true"
        return base + if (cut) " …" else ""
    }
}
