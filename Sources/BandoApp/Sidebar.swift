import BandoCore
import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var showFinished = false
    @State private var collapsed: Set<String> = []
    @State private var expandedStopped: Set<String> = []
    @State private var scrolledFromTop = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if model.sidebarMode == .projects {
                    ActionRow(symbol: "arrow.left", title: "Voltar às sessões", shortcut: nil) {
                        model.sidebarMode = .byProject
                        model.route = .sessions
                    }
                    NewProjectRow()
                } else {
                    ActionRow(symbol: "square.and.pencil", title: "Nova sessão", shortcut: "⌘N") { model.openComposer() }
                    ActionRow(symbol: "folder", title: "Projetos", shortcut: nil) { model.sidebarMode = .projects }
                    ActionRow(symbol: model.sidebarMode == .byProject ? "list.bullet" : "square.stack",
                              title: model.sidebarMode == .byProject ? "Agrupar por estado" : "Agrupar por projeto", shortcut: nil) {
                        model.sidebarMode = model.sidebarMode == .byProject ? .byStatus : .byProject
                    }
                }
            }
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)

            Rectangle().fill(scrolledFromTop ? p.border : .clear).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    switch model.sidebarMode {
                    case .byProject: byProject
                    case .byStatus: byStatus
                    case .projects: projectList
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(GeometryReader { g in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named("sidebar")).minY)
                })
            }
            .coordinateSpace(name: "sidebar")
            .onPreferenceChange(ScrollOffsetKey.self) { scrolledFromTop = $0 < -2 }
            .scrollIndicators(.never)
            .overlay {
                if model.sessions.filter({ !$0.hidden }).isEmpty && model.loadError == nil {
                    Text("Nenhuma sessão ativa").font(.system(size: 14)).foregroundStyle(p.secondary)
                }
            }

            footer
        }
    }

    // Por projeto (padrão): fixadas primeiro, depois cada projeto com sessões ativas.
    @ViewBuilder var byProject: some View {
        let visible = model.sessions.filter { !$0.hidden }
        let pinned = visible.filter(\.pinned)
        if !pinned.isEmpty {
            GroupHeader(title: "Fixadas", first: true, collapsed: collapsed.contains("_pinned")) { toggle("_pinned") }
            if !collapsed.contains("_pinned") { ForEach(pinned) { SessionRow(session: $0) } }
        }
        let groups = model.projects.compactMap { project -> (Project, [Session])? in
            let list = visible.filter { $0.projectId == project.id && !$0.pinned &&
                ($0.status.isLive || $0.status == .queued || $0.status == .error) }
                .sorted { ($0.status.urgency, $1.statusChangedAt) < ($1.status.urgency, $0.statusChangedAt) }
            return list.isEmpty && stopped(of: project.id).isEmpty ? nil : (project, list)
        }
        .sorted { ($0.1.map(\.status.urgency).min() ?? 9, $0.0.name) < ($1.1.map(\.status.urgency).min() ?? 9, $1.0.name) }
        ForEach(Array(groups.enumerated()), id: \.element.0.id) { i, g in
            GroupHeader(title: g.0.name, first: i == 0 && pinned.isEmpty, collapsed: collapsed.contains(g.0.id),
                        newSession: { model.openComposer(project: g.0.id) }) { toggle(g.0.id) }
            if !collapsed.contains(g.0.id) {
                ForEach(g.1) { SessionRow(session: $0, showProject: false) }
                StoppedToggle(project: g.0, expanded: expandedStopped.contains(g.0.id)) {
                    if expandedStopped.contains(g.0.id) { expandedStopped.remove(g.0.id) } else { expandedStopped.insert(g.0.id) }
                }
                if expandedStopped.contains(g.0.id) {
                    ForEach(stopped(of: g.0.id).prefix(30)) { SessionRow(session: $0, showProject: false) }
                }
            }
        }
    }

    func stopped(of projectId: String) -> [Session] {
        model.sessions.filter { $0.projectId == projectId && !$0.hidden && !$0.pinned && ($0.status == .stopped || $0.status == .exited) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Modo "Projetos": lista com contagem; clique abre a página do projeto.
    @ViewBuilder var projectList: some View {
        let counts = Dictionary(grouping: model.sessions, by: \.projectId).mapValues(\.count)
        ForEach(model.projects.sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }) { proj in
            ProjectRow(project: proj, count: counts[proj.id] ?? 0, selected: model.route == .project(proj.id)) {
                model.openProject(proj.id)
            }
        }
    }

    @ViewBuilder var byStatus: some View {
        ForEach(Array(model.groups.enumerated()), id: \.element.title) { i, group in
            GroupHeader(title: group.title, first: i == 0, collapsed: collapsed.contains(group.title)) { toggle(group.title) }
            if !collapsed.contains(group.title) { ForEach(group.sessions) { SessionRow(session: $0) } }
        }
        finished
    }

    @ViewBuilder var finished: some View {
        if !model.finishedSessions.isEmpty {
            GroupHeader(title: "Paradas e encerradas · \(model.finishedSessions.count)", first: false, collapsed: !showFinished) {
                showFinished.toggle()
            }
            if showFinished {
                ForEach(model.finishedSessions.prefix(80)) { SessionRow(session: $0) }
            }
        }
    }

    func toggle(_ key: String) {
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
    }

    var footer: some View {
        HStack(spacing: 2) {
            let waiting = model.counts.waiting
            if waiting > 0 {
                Button { model.selectNextWaiting() } label: {
                    Text("\(waiting) esperando").font(.system(size: 12)).foregroundStyle(StateColor.waiting)
                }
                .buttonStyle(.plain).pointerCursor().help("Ir para a próxima esperando você (⌘J)")
            } else {
                let live = model.sessions.filter(\.status.isLive).count
                Text("\(live) ativa\(live == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(p.secondary)
            }
            Spacer()
            IconButton(symbol: "square.grid.2x2", help: "Grade (⌥⌘G)") { model.toggleGrid() }
            IconButton(symbol: "arrow.clockwise", help: "Recarregar configuração") { Task { await model.reload() } }
        }
        .padding(.leading, 14).padding(.trailing, 8)
        .frame(height: 34)
        .overlay(alignment: .top) { Rectangle().fill(p.border).frame(height: 1) }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Cabeçalho de grupo: 12 pt negrito cinza; seta e "+" só no hover.
struct GroupHeader: View {
    @Environment(\.palette) private var p
    let title: String
    let first: Bool
    let collapsed: Bool
    var newSession: (() -> Void)? = nil
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(p.secondary).lineLimit(1)
            if hovering || collapsed {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(p.tertiary)
            }
            Spacer()
            if hovering, let newSession {
                Button(action: newSession) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(p.secondary)
                        .frame(width: 20, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointerCursor().help("Nova sessão neste projeto")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .padding(.top, first ? 0 : 14)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .pointerCursor()
        .onTapGesture(perform: toggle)
    }
}

struct ActionRow: View {
    @Environment(\.palette) private var p
    let symbol: String
    let title: String
    let shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(p.secondary).frame(width: 16)
                Text(title).font(.system(size: 14))
                Spacer()
                if let shortcut, hovering { Text(shortcut).font(.system(size: 11)).foregroundStyle(p.tertiary) }
            }
            .foregroundStyle(p.text)
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? p.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerCursor()
    }
}

/// Linha de sessão: título 14 pt (negrito se aberta), branch em 11 pt mono,
/// ponto de estado à direita; no hover o ponto vira "⋯".
struct SessionRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let session: Session
    var showProject = true
    @State private var hovering = false

    var isSelected: Bool { model.selection == session.id }
    var inGrid: Bool { model.gridMode && model.gridSessions.contains { $0.id == session.id } }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                    .lineLimit(1)
                if let line = secondLine {
                    Text(line.text)
                        .font(.system(size: 11, design: line.mono ? .monospaced : .default))
                        .foregroundStyle(line.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? p.selected : (hovering ? p.hover : .clear)))
        .overlay(alignment: .leading) {
            if inGrid { Capsule().fill(StateColor.working.opacity(0.6)).frame(width: 2, height: 14).offset(x: 2) }
        }
        .opacity(session.status == .queued ? (hovering ? 0.8 : 0.6) : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .pointerCursor()
        .onTapGesture(count: 2) { model.openAlone(session.id) }
        .onTapGesture { model.select(session.id) }
        .draggable(session.id)
        .contextMenu { SessionContextMenu(session: session) }
        .help(tooltip)
    }

    /// Segunda linha: a pergunta pendente (esperando), o erro, a fila, ou a branch.
    var secondLine: (text: String, mono: Bool, color: Color)? {
        switch session.status {
        case .waiting: return (session.statusDetail ?? "esperando você", false, StateColor.waiting)
        case .error: return (session.statusDetail ?? "falhou", false, StateColor.failed)
        case .queued: return ("na fila", false, p.secondary)
        default: break
        }
        var parts: [String] = []
        if showProject, let proj = model.project(session.projectId) { parts.append(proj.name) }
        if let b = session.branch { parts.append(b) }
        return parts.isEmpty ? nil : (parts.joined(separator: " · "), true, p.secondary)
    }

    @ViewBuilder var trailing: some View {
        if hovering {
            SessionActionsButton(session: session, size: 12)
        } else if let color = StateColor.dot(session.status) {
            Circle().fill(color).frame(width: 8, height: 8)
                .frame(width: 18)
        } else if session.status == .stopped {
            Image(systemName: "bolt.horizontal.circle").font(.system(size: 11)).foregroundStyle(p.tertiary).frame(width: 18)
        } else {
            Color.clear.frame(width: 18, height: 8)
        }
    }

    var tooltip: String {
        var lines = [session.name, session.status.label]
        if let proj = model.project(session.projectId) { lines.append(proj.name) }
        lines.append(session.worktreePath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        if let b = session.branch { lines.append(b) }
        lines.append([model.config?.agents[session.agent]?.name ?? session.agent, session.provider, session.model]
            .compactMap { $0 }.joined(separator: " · "))
        if let d = session.dependsOn, let parent = model.session(d) { lines.append("Depende de \(parent.name)") }
        return lines.joined(separator: "\n")
    }
}

struct SessionInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let s = model.selectedSession {
            Form {
                Section("Sessão") {
                    LabeledContent("Estado") { HStack { StatusIcon(status: s.status, size: 10); Text(s.status.label) } }
                    if let d = s.statusDetail { LabeledContent("Detalhe", value: d) }
                    LabeledContent("Agente", value: model.config?.agents[s.agent]?.name ?? s.agent)
                    LabeledContent("Provider", value: s.provider.flatMap { model.config?.providers[$0]?.name } ?? "login da CLI")
                    if let m = s.model { LabeledContent("Modelo", value: m) }
                    LabeledContent("Criada", value: s.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section("Código") {
                    if let proj = model.project(s.projectId) { LabeledContent("Projeto", value: proj.name) }
                    if let b = s.branch { LabeledContent("Branch", value: b) }
                    if let b = s.baseBranch { LabeledContent("Base", value: b) }
                    LabeledContent("Worktree") {
                        Text(s.worktreePath).lineLimit(3).truncationMode(.head).textSelection(.enabled)
                    }
                }
                if let prompt = s.prompt, !prompt.isEmpty {
                    Section("Tarefa") { Text(prompt).textSelection(.enabled) }
                }
                if let native = s.nativeId {
                    Section("Conversa do agente") { Text(native).font(.caption.monospaced()).textSelection(.enabled) }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("Nenhuma sessão", systemImage: "sidebar.right")
        }
    }
}


/// Linha "N paradas" dentro de cada projeto (recolhida por padrão).
struct StoppedToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let project: Project
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        let n = model.sessions.filter { $0.projectId == project.id && !$0.hidden && !$0.pinned && ($0.status == .stopped || $0.status == .exited) }.count
        if n > 0 {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                    Text("\(n) parada\(n == 1 ? "" : "s")").font(.system(size: 11.5))
                    Spacer()
                }
                .foregroundStyle(p.tertiary)
                .padding(.horizontal, 10).frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerCursor()
        }
    }
}

struct ProjectRow: View {
    @Environment(\.palette) private var p
    let project: Project
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "folder.fill" : "folder").font(.system(size: 13)).foregroundStyle(p.secondary)
                Text(project.name).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer()
                if count > 0 { Text("\(count)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(p.tertiary) }
            }
            .foregroundStyle(p.text)
            .padding(.horizontal, 8).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? p.selected : (hovering ? p.hover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor()
        .onHover { hovering = $0 }
    }
}


/// "Novo projeto": adicionar uma pasta ou importar um workspace inteiro.
struct NewProjectRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var open = false

    var body: some View {
        ActionRow(symbol: "folder.badge.plus", title: "Novo projeto", shortcut: nil) { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .trailing) {
                VStack(spacing: 0) {
                    ActionItem(symbol: "folder.badge.plus", title: "Adicionar projeto…", color: p.text) {
                        open = false; model.showAddProject = true
                    }
                    ActionItem(symbol: "folder.badge.gearshape", title: "Importar workspace…", color: p.text) {
                        open = false; model.showImportWorkspace = true
                    }
                }
                .padding(6).frame(width: 230)
                .environment(\.palette, p)
            }
    }
}
