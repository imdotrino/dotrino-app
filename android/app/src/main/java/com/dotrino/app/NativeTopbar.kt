package com.dotrino.app

import android.content.Intent
import android.net.Uri
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.ContextCompat
import androidx.core.os.LocaleListCompat
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import com.google.android.material.button.MaterialButtonToggleGroup

/**
 * La barra de Dotrino en la pantalla NATIVA de Pedidos: lo mismo que `<dotrino-topbar>`
 * (marca, ES/EN y la moneda de apoyo), hecho en nativo porque la pestaña es nativa (dueño,
 * 2026-09-26). Sin botón de perfil: Pedidos es de todas las cuentas a la vez.
 *
 * El idioma va por los idiomas POR APP de AppCompat: cambia los textos nativos de toda la app
 * y queda guardado. La actividad se recrea, y MainActivity vuelve a abrir Pedidos.
 */
class NativeTopbar(private val activity: AppCompatActivity, root: View, private val onOpen: (Uri) -> Unit) {
    companion object {
        private val KOFI = Uri.parse("https://ko-fi.com/dotrino")
        private val DISCORD = Uri.parse("https://discord.gg/D648uq7cth")
        private val ISSUES = Uri.parse("https://github.com/imdotrino/dotrino-app/issues")
        private const val HOME = "https://dotrino.com/"
    }

    init {
        root.findViewById<View>(R.id.topbarBrand).setOnClickListener { onOpen(Uri.parse(HOME)) }
        root.findViewById<MaterialButtonToggleGroup>(R.id.topbarLang).apply {
            check(if (current() == "en") R.id.langEn else R.id.langEs)
            addOnButtonCheckedListener { _, id, checked -> if (checked) setLang(if (id == R.id.langEn) "en" else "es") }
        }
        root.findViewById<View>(R.id.topbarCoin).setOnClickListener { showSupport() }
    }

    /** El idioma en uso: el elegido en la app o, si no se eligió, el del sistema. */
    private fun current(): String {
        val chosen = AppCompatDelegate.getApplicationLocales()
        val tag = if (!chosen.isEmpty) chosen[0]?.language else activity.resources.configuration.locales[0].language
        return if (tag == "en") "en" else "es"
    }

    private fun setLang(l: String) {
        if (l == current()) return
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(l))
    }

    /** Lo que abre la moneda: los mismos textos y destinos que el modal de `<dotrino-support>`. */
    private fun showSupport() {
        val sheet = BottomSheetDialog(activity)
        val dp = activity.resources.displayMetrics.density
        val pad = (24 * dp).toInt()
        val col = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(pad, pad, pad, pad)
            setBackgroundColor(ContextCompat.getColor(activity, R.color.bg))
        }
        col.addView(ImageView(activity).apply {
            setImageResource(R.drawable.coin)
            layoutParams = LinearLayout.LayoutParams((72 * dp).toInt(), (72 * dp).toInt())
        })
        fun text(id: Int, size: Float, color: Int, bold: Boolean = false) = TextView(activity).apply {
            setText(id); textSize = size; gravity = Gravity.CENTER
            setTextColor(ContextCompat.getColor(activity, color))
            if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
        }
        col.addView(text(R.string.support_heading, 20f, R.color.fg, bold = true))
        col.addView(text(R.string.support_message, 15f, R.color.muted))
        fun button(label: Int, outlined: Boolean, run: () -> Unit) = MaterialButton(
            activity, null, if (outlined) com.google.android.material.R.attr.materialButtonOutlinedStyle else com.google.android.material.R.attr.materialButtonStyle
        ).apply {
            setText(label)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            setOnClickListener { run() }
        }
        val out = { u: Uri -> activity.startActivity(Intent(Intent.ACTION_VIEW, u)) }
        col.addView(button(R.string.support_donate, false) { out(KOFI) })
        col.addView(button(R.string.support_discord, true) { out(DISCORD) })
        col.addView(button(R.string.support_bug, true) { out(ISSUES) })
        col.addView(button(R.string.support_share, true) {
            activity.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, HOME), null))
        })
        col.addView(button(R.string.support_close, true) { sheet.dismiss() })
        sheet.setContentView(col)
        sheet.show()
    }
}
