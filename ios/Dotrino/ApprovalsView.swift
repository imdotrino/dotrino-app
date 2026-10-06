import DotrinoNative
import DotrinoNativeUI
import SwiftUI

/// Colores de la app: los del ecosistema (`DotrinoPalette`) más los de estado de Pedidos.
enum Palette {
    static let bg = DotrinoPalette.bg
    static let accent = DotrinoPalette.accent
    static let fg = DotrinoPalette.fg
    static let muted = DotrinoPalette.muted
    static let card = DotrinoPalette.card
    static let warn = Color(hex: 0xFFD98A)
    static let ok = Color(hex: 0x7FE0A8)
    static let bad = Color(hex: 0xFF9AA2)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A text of the app in the language chosen in the topbar (`DotrinoLang`), with `%1$@`-style arguments.
func L(_ key: String, _ args: CVarArg...) -> String {
    let f = DotrinoLang.shared.text(key)
    return args.isEmpty ? f : String(format: f, arguments: args)
}

/// `L` with the arguments as an array, the shape `RequestText` takes.
func Lt(_ key: String, _ args: [CVarArg]) -> String {
    let f = DotrinoLang.shared.text(key)
    return args.isEmpty ? f : String(format: f, arguments: args)
}

/// The native «Requests» tab. One section per account with its NAME always on top, then its
/// requests, then what is approved for now. Nothing here goes through the WebView.
struct ApprovalsView: View {
    @ObservedObject var model: ApprovalsModel
    /// Cambiar de idioma en la barra vuelve a pintar la pantalla.
    @ObservedObject var lang = DotrinoLang.shared
    let onAddAccount: () -> Void
    let onOpenWeb: () -> Void
    /// Un enlace del ecosistema pulsado en la barra.
    let onOpen: (URL) -> Void
    @State private var removing: ApprovalsModel.AccountState?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            content(now: Int64(ctx.date.timeIntervalSince1970 * 1000))
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // La barra del ecosistema (dotrino-native). Sus enlaces a *.dotrino.com se abren
            // DENTRO de la app, como toda página del ecosistema; el resto (Ko-fi, Discord), fuera.
            DotrinoTopbar(repo: "imdotrino/dotrino-app", showProfile: false) // Pedidos is of EVERY profile of the phone
                .environment(\.openURL, OpenURLAction { url in
                    guard let h = url.host, h == "dotrino.com" || h.hasSuffix(".dotrino.com") else { return .systemAction }
                    onOpen(url); return .handled
                })
        }
        .background(Palette.bg.ignoresSafeArea())
        .alert(item: $removing) { st in
            Alert(title: Text(L("remove_confirm", st.account.name)),
                  primaryButton: .destructive(Text(L("remove_account"))) { model.remove(st.account.id) },
                  secondaryButton: .cancel(Text(L("cancel"))))
        }
    }

    // A FIXED order (the one they were added in): an account that jumps up or down when a
    // request arrives or is answered is exactly how you lose track of which one is which.
    private var ordered: [ApprovalsModel.AccountState] { model.state.values.sorted { $0.account.addedAt < $1.account.addedAt } }

    @ViewBuilder
    private func content(now: Int64) -> some View {
        List {
            if let e = model.storeError {
                note(L("err_accounts_file", e), color: Palette.bad)
            } else if model.state.isEmpty {
                note(L("no_accounts"))
                action(L("add_account"), onAddAccount)
                action(L("open_web"), onOpenWeb)
            } else {
                ForEach(ordered, id: \.account.id) { st in
                    Section {
                        header(st)
                        ForEach(st.items) { a in request(st, a, now: now) }
                        if st.items.isEmpty && st.confirmedAt != nil { note(L("none")) }
                        if !st.grants.isEmpty {
                            note(L("grants_title"))
                            ForEach(st.grants) { g in grant(st, g, now: now) }
                        }
                    }
                }
                if model.state.values.contains(where: { !$0.items.isEmpty }) { note(L("warn"), color: Palette.warn) }
                if model.state.values.contains(where: { $0.items.contains { $0.kind == "read" } }) { note(L("grant_hint")) }
                if model.state.values.contains(where: { $0.items.contains { $0.kind == "passwords" } }) { note(L("passwords_hint")) }
                action(L("add_account"), onAddAccount)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { model.refreshAll(); try? await Task.sleep(nanoseconds: 600_000_000) }
    }

    private func note(_ text: String, color: Color = Palette.muted) -> some View {
        Text(text).font(.footnote).foregroundColor(color).listRowBackground(Color.clear)
    }

    private func action(_ label: String, _ run: @escaping () -> Void) -> some View {
        Button(label, action: run)
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent).tint(Palette.accent)
            .listRowBackground(Color.clear)
    }

    private func header(_ st: ApprovalsModel.AccountState) -> some View {
        let (text, base): (String, Color) = {
            switch st.status {
            case .live: return (L("acct_live"), Palette.ok)
            case .connecting: return (L("acct_connecting"), Palette.muted)
            case .failed(let r): return (L("acct_failed", r), Palette.bad)
            }
        }()
        // Connected to the proxy is not «all good»: if the vault is not answering, the dot says so too.
        let dot = (st.error ?? st.notice) != nil && base == Palette.ok ? Palette.warn : base
        return VStack(alignment: .leading, spacing: 4) {
            Text(st.account.name).font(.headline).foregroundColor(Palette.fg)
            Text(L("acct_phone", st.account.deviceId)).font(.caption).foregroundColor(Palette.muted)
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(text).font(.caption).foregroundColor(Palette.muted)
            }
            if let e = errorText(st) { Text(e).font(.caption).foregroundColor(Palette.bad).textSelection(.enabled) }
        }
        .padding(.vertical, 4)
        .listRowBackground(Palette.card)
        .contentShape(Rectangle())
        .onLongPressGesture { removing = st }
        .accessibilityIdentifier("account-\(st.account.deviceId)")
    }

    /// Approving hands out keys, so the phone asks «is it you?» first (Face ID, Touch ID or the
    /// passcode). Denying does not: it takes nothing out. Without a passcode there is nothing to
    /// confirm with, and the request is NOT approved — the screen says why.
    @MainActor private func approve(_ accountId: String, _ requestId: String, _ title: String) async {
        let outcome = await Presence.confirm(L("presence_reason", title))
        if outcome == .confirmed { model.approve(accountId, requestId) }
        else if let m = Presence.message(outcome) { model.say(accountId, m) }
    }

    private func errorText(_ st: ApprovalsModel.AccountState) -> String? {
        switch st.notice ?? st.error {
        case nil: return nil
        case ApprovalsModel.cannotApprove?: return L("err_cannot_approve")
        case ApprovalsModel.noReply?: return L("err_no_reply")
        case ApprovalsModel.notConnected?: return L("err_not_connected")
        case let e?: return e
        }
    }

    private func request(_ st: ApprovalsModel.AccountState, _ a: Approval, now: Int64) -> some View {
        let ctx = a.ctx
        let title = RequestText.title(a, Lt)
        var detail = ""
        var sub: (String, Color)?
        if a.kind == "passwords" {
            detail = RequestText.fields(a, Lt) ?? ""
        } else if a.kind == "update" {
            if let from = ctx?["from"]?.string { detail = L("req_update_from", from) }
            sub = (L("req_update_verified"), Palette.muted)
        } else if a.kind == "write", let ctx {
            detail = L("req_keys", (ctx["keys"]?.array ?? []).compactMap { $0.string }.joined(separator: ", "))
        } else if let ctx {
            detail = L("req_cmd", commandOf(ctx))
            let proc = ctx["verified"]?.string == "proc"
            sub = (L("req_cwd", ctx["cwd"]?.string ?? "?") + " · " + L(proc ? "req_proc" : "req_declared"), proc ? Palette.muted : Palette.warn)
        } else if let err = a.ctxError {
            detail = L("req_cmderr", err)
        } else {
            detail = L("req_nocmd")
        }
        let busy = st.busy.contains(a.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundColor(Palette.fg)
            if !detail.isEmpty { Text(detail).font(.system(.footnote, design: .monospaced)).foregroundColor(Palette.fg).textSelection(.enabled) }
            if let sub { Text(sub.0).font(.caption).foregroundColor(sub.1) }
            Text(L("req_left", left(a.exp - now))).font(.caption).foregroundColor(Palette.muted)
            HStack {
                // Disabled, never hidden, while the answer travels.
                Button(L("deny")) { model.deny(st.account.id, a.id) }
                    .buttonStyle(.bordered).tint(Palette.bad).disabled(busy)
                    .accessibilityIdentifier("deny-\(a.id)")
                Spacer()
                Button(L("approve")) { Task { await approve(st.account.id, a.id, title) } }
                    .buttonStyle(.borderedProminent).tint(Palette.accent).disabled(busy)
                    .accessibilityIdentifier("approve-\(a.id)")
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Palette.card)
    }

    private func grant(_ st: ApprovalsModel.AccountState, _ g: Grant, now: Int64) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(g.ctx.map(commandOf) ?? g.ns).font(.system(.footnote, design: .monospaced)).foregroundColor(Palette.fg)
                Text("\(g.ns) · " + L("grant_sub", left(g.exp - now), Int32(clamping: g.uses))).font(.caption).foregroundColor(Palette.muted)
            }
            Spacer()
            Button(L("grant_revoke")) { model.revokeGrant(st.account.id, g.id) }
                .buttonStyle(.bordered).disabled(st.busy.contains(g.id))
        }
        .listRowBackground(Palette.card)
    }

    private func left(_ ms: Int64) -> String {
        if ms <= 0 { return L("req_expired") }
        let t = ms / 1000
        if t >= 3600 { return "\(t / 3600) h \((t % 3600) / 60) min" }
        if t >= 60 { return String(format: "%ld:%02ld", Int(t / 60), Int(t % 60)) }
        return "\(t) s"
    }

    /// Same text as `apvCmd` in the web console: `argv` joined, or the executable, and `…` when cut.
    private func commandOf(_ ctx: JSON) -> String {
        let argv = (ctx["argv"]?.array ?? []).compactMap { $0.string }
        let base = argv.isEmpty ? (ctx["exe"]?.string ?? "") : argv.joined(separator: " ")
        let cut = ctx["truncated"]?.bool == true || ctx["truncated"]?.string == "true"
        return base + (cut ? " …" : "")
    }
}

extension ApprovalsModel.AccountState: Identifiable {
    var id: String { account.id }
}
