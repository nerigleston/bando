import AppKit
import BandoCore
import SwiftUI

/// Botão "Claude Code ⌄" do cabeçalho: troca agente, provider ou modelo
/// mantendo a sessão (worktree, branch e histórico).
struct AgentSwitcher: View {
    @Environment(AppModel.self) private var model
    let session: Session
    @State private var open = false

    var body: some View {
        let p = model.palette
        let name = model.config?.agents[session.agent]?.name ?? session.agent
        let provider = session.provider.flatMap { model.config?.providers[$0]?.name }
        Button { open.toggle() } label: {
            HStack(spacing: 4) {
                Text(provider.map { "\(name) · \($0)" } ?? name).font(.system(size: 12.5)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(p.secondary)
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(open ? p.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor()
        .help("Trocar agente, provider ou modelo")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            AgentSwitcherPanel(session: session) { open = false }
                .environment(model)
                .environment(\.palette, p)
        }
    }
}

struct AgentSwitcherPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let session: Session
    let close: () -> Void
    @State private var agent = ""
    @State private var provider = "default"
    @State private var modelName = ""

    @State private var showOthers = false
    @State private var filter = ""
    @State private var handoff: HandoffMode = .summary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Agente").font(.system(size: 11, weight: .bold)).foregroundStyle(p.secondary)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            // Só os instalados à vista; os outros ficam recolhidos e com busca.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(installed, id: \.agent.id) { a in
                        AgentOption(item: a, selected: a.agent.id == agent, current: a.agent.id == session.agent) {
                            agent = a.agent.id; fixProvider()
                        }
                    }
                    if !notInstalled.isEmpty {
                        Button { withAnimation(.easeOut(duration: 0.15)) { showOthers.toggle() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showOthers ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold))
                                Text("Instalar outros agentes (\(notInstalled.count))").font(.system(size: 12))
                                Spacer()
                            }
                            .foregroundStyle(p.secondary)
                            .padding(.horizontal, 14).frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).pointerCursor()
                        if showOthers {
                            TextField("Buscar agente", text: $filter)
                                .textFieldStyle(.roundedBorder).font(.system(size: 12))
                                .padding(.horizontal, 12).padding(.bottom, 4)
                            ForEach(notInstalled.filter { filter.isEmpty || $0.agent.name.localizedCaseInsensitiveContains(filter) }, id: \.agent.id) { a in
                                AgentOption(item: a, selected: false, current: false) { install(a.agent) }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: showOthers ? 340 : CGFloat(installed.count) * 38 + 34)
            Rectangle().fill(p.border).frame(height: 1).padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 8) {
                Picker("Provider", selection: $provider) {
                    ForEach(providers) { Text($0.name).tag($0.id) }
                }
                TextField("Modelo (opcional)", text: $modelName,
                          prompt: Text(model.config?.providers[provider]?.models.first ?? "padrão do agente"))
                if agent != session.agent {
                    Picker("Levar para o novo agente", selection: $handoff) {
                        ForEach(HandoffMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Text(note).font(.system(size: 11)).foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancelar", action: close)
                    Button(agent == session.agent ? "Reiniciar com esta configuração" : "Trocar para \(model.config?.agents[agent]?.name ?? agent)") {
                        apply()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!changed)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(width: 340)
        .onAppear {
            agent = session.agent
            provider = session.provider ?? "default"
            modelName = session.model ?? ""
            handoff = model.handoffDefault
        }
    }

    var installed: [AgentAvailability] { agents.filter { $0.isInstalled || $0.agent.id == session.agent } }
    var notInstalled: [AgentAvailability] { agents.filter { !$0.isInstalled && $0.agent.id != session.agent } }

    var agents: [AgentAvailability] {
        let current = model.availability[session.agent]
        let rest = model.availability.values.filter { $0.agent.id != session.agent && $0.agent.id != "shell" }
            .sorted { ($0.isInstalled ? 0 : 1, $0.agent.name) < ($1.isInstalled ? 0 : 1, $1.agent.name) }
        return (current.map { [$0] } ?? []) + rest
    }

    var providers: [ProviderDefinition] {
        (model.config?.providers(for: agent) ?? [])
            .sorted { ($0.id == "default" ? 0 : 1, $0.name) < ($1.id == "default" ? 0 : 1, $1.name) }
    }

    var changed: Bool {
        agent != session.agent || provider != (session.provider ?? "default") || modelName != (session.model ?? "")
    }

    var note: String {
        if agent == session.agent {
            return "Mesmo agente: reinicia retomando a mesma conversa, agora com o provider e o modelo escolhidos."
        }
        switch handoff {
        case .summary: return "O agente atual escreve .bando/handoff.md (comandos, decisões, pendências) e o novo começa lendo esse arquivo. O texto do pedido fica em Ajustes > Geral."
        case .transcript: return "O Bando exporta a conversa inteira para .bando/handoff.md (só a partir do Claude Code) e o novo agente começa lendo."
        case .none: return "O novo agente começa só com a tarefa original e o código como está."
        }
    }

    func fixProvider() {
        if !providers.contains(where: { $0.id == provider }) { provider = "default" }
    }

    func apply() {
        let id = session.id, a = agent
        let prov = provider == "default" ? nil : provider
        let m = modelName.isEmpty ? nil : modelName
        close()
        model.swapAgent(id, agent: a, provider: prov, model: m, handoff: a == session.agent ? .none : handoff)
    }

    /// Instala num Terminal à parte, com o comando do preset à vista.
    func install(_ a: AgentDefinition) {
        guard let cmd = a.install else { return }
        close()
        let script = "tell application \"Terminal\" to do script \"\(cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
        NSApp.activate()
    }
}

struct AgentOption: View {
    @Environment(\.palette) private var p
    let item: AgentAvailability
    let selected: Bool
    let current: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    .opacity(selected ? 1 : 0).foregroundStyle(.green).frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.agent.name + (current ? "  (atual)" : "")).font(.system(size: 13))
                        .foregroundStyle(item.isInstalled ? p.text : p.tertiary)
                    Text(item.isInstalled ? (item.version ?? "instalado") : "Não instalado")
                        .font(.system(size: 11)).foregroundStyle(p.tertiary).lineLimit(1)
                }
                Spacer()
                if !item.isInstalled && item.agent.install != nil {
                    Text("Instalar").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().strokeBorder(p.border))
                }
            }
            .padding(.horizontal, 10).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? p.hover : .clear))
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerCursor()
    }
}

/// Ações da sessão, num lugar só: o menu nativo (clique direito) e o menu
/// próprio do botão "⋯" usam a mesma lista.
struct SessionAction: Identifiable {
    enum Kind { case normal, destructive, separator, dependency }
    let id: String
    var title = ""
    var symbol = ""
    var kind: Kind = .normal
    var run: () -> Void = {}

    static func separator(_ id: String) -> SessionAction { SessionAction(id: id, kind: .separator) }

    @MainActor
    static func list(for session: Session, model: AppModel) -> [SessionAction] {
        let id = session.id
        var items: [SessionAction] = []
        if session.status.isLive {
            items.append(.init(id: "stop", title: "Parar sessão", symbol: "stop.circle", kind: .destructive) { model.stopSession(id) })
        } else {
            items.append(.init(id: "resume", title: "Retomar sessão", symbol: "play.circle") { model.resumeSession(id) })
        }
        items.append(.init(id: "pin", title: session.pinned ? "Desafixar" : "Fixar no topo", symbol: session.pinned ? "pin.slash" : "pin") {
            let v = !session.pinned; model.run("Fixar") { try $0.setPinned(id, v) }
        })
        items.append(.init(id: "rename", title: "Renomear…", symbol: "pencil") { model.renaming = session })
        items.append(.separator("s1"))
        items.append(.init(id: "term", title: "Novo terminal neste worktree", symbol: "terminal") {
            model.runReturning("Novo terminal") { try $0.newTerminal(id) }
        })
        items.append(.init(id: "fork", title: "Fork da sessão", symbol: "arrow.triangle.branch") {
            model.runReturning("Fork") { try $0.fork(id) }
        })
        items.append(.init(id: "dep", title: "Depende de", symbol: "link", kind: .dependency))
        items.append(.separator("s2"))
        let inGrid = model.gridMode && model.gridSessions.contains { $0.id == id }
        items.append(inGrid
            ? .init(id: "grid", title: "Tirar da grade", symbol: "square.grid.2x2") { model.removeFromGrid(id) }
            : .init(id: "grid", title: "Adicionar à grade", symbol: "square.grid.2x2") { model.showInGrid(id) })
        items.append(.init(id: "alone", title: "Abrir só esta", symbol: "arrow.up.left.and.arrow.down.right") { model.openAlone(id) })
        items.append(.init(id: "hide", title: session.hidden ? "Mostrar na lateral" : "Esconder da lateral", symbol: session.hidden ? "eye" : "eye.slash") {
            let v = !session.hidden; model.run("Esconder") { try $0.setHidden(id, v) }
        })
        items.append(.separator("s3"))
        items.append(.init(id: "finder", title: "Mostrar no Finder", symbol: "folder") { model.reveal(session) })
        items.append(.init(id: "copyid", title: "Copiar ID da sessão", symbol: "number") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(id, forType: .string)
        })
        items.append(.init(id: "copypath", title: "Copiar caminho do worktree", symbol: "doc.on.doc") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(session.worktreePath, forType: .string)
        })
        items.append(.separator("s4"))
        items.append(.init(id: "delete", title: "Apagar sessão e worktree…", symbol: "trash", kind: .destructive) { model.deleteSession(id) })
        return items
    }
}

/// Menu nativo (clique direito), com os mesmos ícones.
struct SessionContextMenu: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        ForEach(SessionAction.list(for: session, model: model)) { item in
            switch item.kind {
            case .separator: Divider()
            case .dependency:
                Menu { DependencyItems(session: session) } label: { Label(item.title, systemImage: item.symbol) }
            case .destructive:
                Button(role: .destructive, action: item.run) { Label(item.title, systemImage: item.symbol) }
            case .normal:
                Button(action: item.run) { Label(item.title, systemImage: item.symbol) }
            }
        }
    }
}

struct DependencyItems: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var candidates: [Session] {
        model.sessions.filter { $0.id != session.id && ($0.status.isLive || $0.status == .queued) }
    }

    var body: some View {
        Button("Nenhuma") { let id = session.id; model.run("Dependência") { try $0.setDependency(id, parent: nil) } }
        Divider()
        ForEach(candidates) { other in
            Button((session.dependsOn == other.id ? "✓ " : "") + other.name) {
                let id = session.id, parent = other.id
                model.run("Dependência") { try $0.setDependency(id, parent: parent) }
            }
        }
    }
}

/// Botão "⋯" com o menu próprio do Bando (visual do tema, ícones, ações
/// perigosas em vermelho), no lugar do menu padrão do macOS.
struct SessionActionsButton: View {
    @Environment(AppModel.self) private var model
    let session: Session
    var size: CGFloat = 14
    @State private var open = false

    var body: some View {
        let p = model.palette
        Button { open.toggle() } label: {
            Image(systemName: "ellipsis").font(.system(size: size, weight: .semibold)).foregroundStyle(p.secondary)
                .frame(width: size + 14, height: size + 12)
                .background(RoundedRectangle(cornerRadius: 6).fill(open ? p.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor()
        .help("Mais ações")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            SessionActionsPanel(session: session) { open = false }
                .environment(model)
                .environment(\.palette, p)
        }
    }
}

struct SessionActionsPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let session: Session
    let close: () -> Void
    @State private var showDependency = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(StateColor.dot(session.status) ?? p.tertiary).frame(width: 7, height: 7)
                Text(session.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(StateColor.label(session.status)).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.tertiary)
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 8)
            Rectangle().fill(p.border).frame(height: 1).padding(.horizontal, 6).padding(.bottom, 4)
            ForEach(SessionAction.list(for: session, model: model)) { item in
                switch item.kind {
                case .separator:
                    Rectangle().fill(p.border).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 6)
                case .dependency:
                    ActionItem(symbol: item.symbol, title: item.title, color: p.text,
                               trailing: showDependency ? "chevron.down" : "chevron.right") {
                        withAnimation(.easeOut(duration: 0.15)) { showDependency.toggle() }
                    }
                    if showDependency { dependencyList }
                default:
                    ActionItem(symbol: item.symbol, title: item.title,
                               color: item.kind == .destructive ? StateColor.failed : p.text) {
                        close(); item.run()
                    }
                }
            }
        }
        .padding(6)
        .frame(width: 270)
        .background(p.card)
    }

    var dependencyList: some View {
        let candidates = model.sessions.filter { $0.id != session.id && ($0.status.isLive || $0.status == .queued) }
        return VStack(alignment: .leading, spacing: 0) {
            ActionItem(symbol: session.dependsOn == nil ? "checkmark" : "", title: "Nenhuma", color: p.secondary) {
                close(); let id = session.id; model.run("Dependência") { try $0.setDependency(id, parent: nil) }
            }
            ForEach(candidates) { other in
                ActionItem(symbol: session.dependsOn == other.id ? "checkmark" : "", title: other.name, color: p.secondary) {
                    close(); let id = session.id, parent = other.id
                    model.run("Dependência") { try $0.setDependency(id, parent: parent) }
                }
            }
        }
        .padding(.leading, 18)
    }
}

/// Linha do menu próprio: ícone de 14 pt, texto de 13 pt, fundo no hover.
struct ActionItem: View {
    @Environment(\.palette) private var p
    let symbol: String
    let title: String
    let color: Color
    var trailing: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol.isEmpty ? "circle" : symbol).font(.system(size: 14))
                    .foregroundStyle(color == p.text ? (hovering ? p.text : p.secondary) : color)
                    .opacity(symbol.isEmpty ? 0 : 1).frame(width: 18)
                Text(title).font(.system(size: 13)).lineLimit(1).foregroundStyle(color)
                Spacer(minLength: 6)
                if let trailing { Image(systemName: trailing).font(.system(size: 10, weight: .semibold)).foregroundStyle(p.tertiary) }
            }
            .padding(.horizontal, 8).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? p.accent.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerCursor()
    }
}

struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Renomear sessão").font(.system(size: 14, weight: .semibold))
            TextField("Nome", text: $name).textFieldStyle(.roundedBorder).onSubmit(save)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Salvar", action: save).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { name = session.name }
    }

    func save() {
        let id = session.id, n = name
        model.run("Renomear") { try $0.rename(id, to: n) }
        dismiss()
    }
}
