import SwiftUI

/// La barra de Dotrino en la pantalla NATIVA de Pedidos: lo mismo que `<dotrino-topbar>`
/// (marca, ES/EN y la moneda de apoyo), hecho en nativo porque la pestaña es nativa (dueño,
/// 2026-09-26). Sin botón de perfil: Pedidos es de todas las cuentas a la vez.
struct TopBar: View {
    @ObservedObject var lang = AppLang.shared
    /// Un enlace del ecosistema pulsado en la barra (la marca lleva a dotrino.com).
    let onOpen: (URL) -> Void
    @State private var support = false

    var body: some View {
        HStack(spacing: 10) {
            Button { onOpen(URL(string: "https://dotrino.com/")!) } label: {
                HStack(spacing: 8) {
                    Image("Brand").resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Dotrino").font(.headline).foregroundColor(Palette.fg)
                }
            }
            .accessibilityIdentifier("topbar-brand")
            Spacer()
            // Las DOS opciones siempre a la vista, la activa resaltada (CONVENCIONES §9).
            HStack(spacing: 0) {
                ForEach(["es", "en"], id: \.self) { l in
                    Button(l.uppercased()) { lang.set(l) }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundColor(lang.code == l ? Palette.bg : Palette.muted)
                        .background(lang.code == l ? Palette.accent : Color.clear)
                        .accessibilityIdentifier("lang-\(l)")
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Palette.muted.opacity(0.4)))
            Button { support = true } label: {
                Image("Coin").resizable().frame(width: 34, height: 34)
            }
            .accessibilityLabel(L("support_cta"))
            .accessibilityIdentifier("support-coin")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Palette.card)
        .sheet(isPresented: $support) { SupportSheet(onClose: { support = false }) }
    }
}

/// Lo que abre la moneda: los mismos textos y destinos que el modal de `<dotrino-support>`.
private struct SupportSheet: View {
    let onClose: () -> Void
    private static let kofi = URL(string: "https://ko-fi.com/dotrino")!
    private static let discord = URL(string: "https://discord.gg/D648uq7cth")!
    private static let issues = URL(string: "https://github.com/imdotrino/dotrino-app/issues")!
    private static let home = URL(string: "https://dotrino.com/")!

    var body: some View {
        VStack(spacing: 14) {
            Image("Coin").resizable().frame(width: 72, height: 72)
            Text(L("support_heading")).font(.title3.weight(.bold)).foregroundColor(Palette.fg)
            Text(L("support_message")).font(.callout).foregroundColor(Palette.muted).multilineTextAlignment(.center)
            Link(L("support_donate"), destination: Self.kofi)
                .frame(maxWidth: .infinity).padding(12).background(Palette.accent).foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 10) {
                Link(L("support_discord"), destination: Self.discord).frame(maxWidth: .infinity)
                Link(L("support_bug"), destination: Self.issues).frame(maxWidth: .infinity)
            }
            .font(.footnote).foregroundColor(Palette.accent)
            ShareLink(item: Self.home) { Label(L("support_share"), systemImage: "square.and.arrow.up") }
                .foregroundColor(Palette.accent)
            Button(L("support_close"), action: onClose).foregroundColor(Palette.muted)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
