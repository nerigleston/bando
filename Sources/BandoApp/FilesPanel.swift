import AppKit
import BandoCore
import SwiftUI

// MARK: - Painel de arquivos (à direita do terminal)

/// Árvore do worktree da sessão. Abrir um arquivo mostra o conteúdo numa aba
/// ao lado do terminal, onde dá para editar e salvar. Recarrega quando o painel abre,
/// quando o agente muda de estado e pelo botão; sem polling.
struct FilesPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let session: Session

    @State private var children: [String: [FileNode]] = [:]
    @State private var expanded: Set<String> = []
    @State private var changes: [String: FileChange] = [:]
    @State private var failed: Set<String> = []
    @State private var loading = false

    var root: String { session.worktreePath }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("Arquivos").font(.system(size: 12, weight: .semibold))
                Spacer()
                if loading { ProgressView().controlSize(.mini) }
                IconButton(symbol: "arrow.clockwise", help: "Recarregar", size: 12) { reload() }
                IconButton(symbol: "minus.square", help: "Recolher pastas", size: 12) { expanded = [] }
                IconButton(symbol: "xmark", help: "Fechar painel (⌘E)", size: 12) { model.showFiles = false }
            }
            .padding(.leading, 12).padding(.trailing, 4)
            .frame(height: 34)
            Rectangle().fill(p.border).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.node.path) { row in
                        FileRow(node: row.node, depth: row.depth, expanded: expanded.contains(row.node.path),
                                change: changes[row.node.path],
                                selected: model.openFiles[session.id] == row.node.path,
                                root: root) { tap(row.node) }
                    }
                    if children[root]?.isEmpty == true {
                        Text("Pasta vazia").font(.system(size: 12)).foregroundStyle(p.tertiary).padding(12)
                    }
                    if failed.contains(root) {
                        Text("Não consegui ler a pasta da sessão.").font(.system(size: 12))
                            .foregroundStyle(p.tertiary).padding(12)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(p.card)
        .task(id: session.id) { reload() }
        // O agente terminou um turno ou mudou de estado: arquivos podem ter mudado.
        .onChange(of: session.status) { reload() }
    }

    /// Linhas visíveis: a árvore aberta, em profundidade.
    var rows: [(node: FileNode, depth: Int)] {
        var out: [(FileNode, Int)] = []
        func walk(_ dir: String, _ depth: Int) {
            for n in children[dir] ?? [] {
                out.append((n, depth))
                if n.isDirectory, expanded.contains(n.path) { walk(n.path, depth + 1) }
            }
        }
        walk(root, 0)
        return out.map { (node: $0.0, depth: $0.1) }
    }

    func tap(_ node: FileNode) {
        if node.isDirectory {
            if expanded.contains(node.path) {
                expanded.remove(node.path)
            } else {
                expanded.insert(node.path)
                if children[node.path] == nil { load([node.path]) }
            }
        } else {
            model.setOpenFile(node.path, for: session.id)
        }
    }

    /// Relê a raiz e as pastas abertas, e o status do git.
    func reload() {
        let open = expanded.filter { FileManager.default.fileExists(atPath: $0) }
        expanded = open
        children = children.filter { $0.key == root || open.contains($0.key) }
        load([root] + open.sorted(), withChanges: true)
    }

    func load(_ dirs: [String], withChanges: Bool = false) {
        let root = root
        loading = true
        Task.detached(priority: .userInitiated) {
            var found: [String: [FileNode]] = [:]
            var bad: Set<String> = []
            let git = try? Git()
            for d in dirs {
                if let list = try? FileBrowser.list(d, git: git) { found[d] = list } else { bad.insert(d) }
            }
            let ch = withChanges ? FileBrowser.changes(in: root, git: git) : nil
            await MainActor.run {
                children.merge(found) { _, new in new }
                failed.subtract(found.keys)
                failed.formUnion(bad)
                if let ch { changes = ch }
                loading = false
            }
        }
    }
}

struct FileRow: View {
    @Environment(\.palette) private var p
    let node: FileNode
    let depth: Int
    let expanded: Bool
    let change: FileChange?
    let selected: Bool
    let root: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: node.isDirectory ? (expanded ? "chevron.down" : "chevron.right") : "")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(p.tertiary)
                .frame(width: 10)
            Image(systemName: node.isDirectory ? "folder" : "doc.text")
                .font(.system(size: 11)).foregroundStyle(node.isDirectory && !node.isIgnored ? p.secondary : p.tertiary)
            Text(node.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(changeColor ?? (node.isIgnored ? p.tertiary : p.text))
            Spacer(minLength: 4)
            if let change, !node.isDirectory {
                Text(changeLetter(change)).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(changeColor ?? p.secondary)
            }
        }
        .padding(.leading, 8 + CGFloat(depth) * 14).padding(.trailing, 10)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? p.selected : hovering ? p.hover : .clear))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .contextMenu {
            Button("Mostrar no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
            }
            if !node.isDirectory {
                Button("Abrir no app padrão") { NSWorkspace.shared.open(URL(fileURLWithPath: node.path)) }
            }
            Divider()
            Button("Copiar caminho") { copy(node.path) }
            Button("Copiar caminho relativo") { copy(relative) }
        }
        .help(node.isIgnored ? relative + " (ignorado pelo git)" : relative)
    }

    var relative: String {
        node.path.hasPrefix(root + "/") ? String(node.path.dropFirst(root.count + 1)) : node.path
    }

    var changeColor: Color? {
        switch change {
        case .modified?, .renamed?: StateColor.waiting
        case .added?, .untracked?: StateColor.working
        case .deleted?: StateColor.failed
        case nil: nil
        }
    }

    func changeLetter(_ c: FileChange) -> String {
        switch c {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .untracked: "U"
        case .renamed: "R"
        }
    }

    func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

/// Divisória arrastável entre o terminal e o painel de arquivos.
struct FilesResizer: View {
    @Environment(AppModel.self) private var model
    @State private var start: CGFloat?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? model.palette.accent.opacity(0.6) : model.palette.border)
            .frame(width: 1)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { g in
                    if start == nil { start = model.filesWidth }
                    model.filesWidth = min(max((start ?? 280) - g.translation.width, 200), 560)
                }
                .onEnded { _ in start = nil })
    }
}

// MARK: - Arquivo aberto

/// Abas acima do conteúdo da sessão: o terminal e o arquivo aberto.
struct FileTabs: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let session: Session
    let path: String
    let showingFile: Bool
    let select: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            tab(title: "Terminal", symbol: "terminal", active: !showingFile) { select(false) }
            tab(title: (path as NSString).lastPathComponent + (model.drafts[path] != nil ? " •" : ""),
                symbol: "doc.text", active: showingFile) { select(true) }
            IconButton(symbol: "xmark", help: "Fechar arquivo", size: 10) {
                model.setOpenFile(nil, for: session.id)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }

    func tab(title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? p.text : p.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? p.selected : .clear))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(path)
    }
}

/// Conteúdo do arquivo, com número de linha e busca (⌘F). Texto UTF-8 dá para
/// editar e salvar (⌘S); com edição pendente, não relê o arquivo sozinho.
struct FileViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let path: String
    /// Muda quando a sessão muda de estado, para reler o arquivo.
    let stamp: SessionStatus
    @State private var content: FileContent?
    @State private var error: String?
    /// Texto como está no disco (base para saber se mudou) e o que está na tela.
    @State private var saved: String?
    @State private var draft = ""
    @State private var editable = false
    @State private var conflict = false
    @State private var saveError: String?

    var dirty: Bool { saved != nil && draft != saved }

    var body: some View {
        VStack(spacing: 0) {
            if dirty || conflict || saveError != nil { editBar }
            Group {
                switch content {
                case .text?:
                    CodeTextView(text: draft, fontSize: max(model.fontSize - 1, 9), theme: model.theme,
                                 editable: editable) { draft = $0 }
                case .binary(let size)?:
                    notice("Arquivo binário", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                case .tooLarge(let size)?:
                    notice("Arquivo grande demais para mostrar aqui",
                           ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                case nil:
                    if let error { notice("Não consegui abrir o arquivo", error) } else { ProgressView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: "\(path)|\(stamp.rawValue)") { await load() }
        .onChange(of: draft) { _, _ in syncDraft() }
        .onChange(of: saved) { _, _ in syncDraft() }
    }

    /// Guarda o rascunho no modelo enquanto houver mudança não salva.
    func syncDraft() {
        if dirty, let saved { model.drafts[path] = FileDraft(saved: saved, text: draft) } else { model.drafts[path] = nil }
    }

    /// Faixa fina no topo: só aparece com mudança, conflito ou erro.
    var editBar: some View {
        HStack(spacing: 8) {
            if conflict {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(StateColor.waiting)
                Text("O arquivo mudou no disco (o agente pode ter editado).").font(.system(size: 12))
                Spacer()
                Button("Recarregar") { conflict = false; Task { await load(force: true) } }.buttonStyle(OutlineButtonStyle())
                Button("Sobrescrever") { save(force: true) }.buttonStyle(AccentButtonStyle(tint: StateColor.waiting))
            } else {
                Circle().fill(StateColor.waiting).frame(width: 6, height: 6)
                Text(saveError ?? "Alterado").font(.system(size: 12))
                    .foregroundStyle(saveError == nil ? p.secondary : StateColor.failed).lineLimit(1)
                Spacer()
                Button("Descartar") { if let saved { draft = saved }; saveError = nil }.buttonStyle(OutlineButtonStyle())
                Button("Salvar") { save(force: false) }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(p.card)
        .overlay(alignment: .bottom) { Rectangle().fill(p.border).frame(height: 1) }
    }

    func notice(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(p.secondary)
            Button("Abrir no app padrão") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                .buttonStyle(.link)
        }
    }

    func load(force: Bool = false) async {
        // Edição pendente: não troca o texto da tela por baixo de quem edita.
        if dirty && !force { return }
        // Rascunho de antes de trocar de aba ou de sessão: volta com ele.
        if !force, let d = model.drafts[path] {
            content = .text(d.text); error = nil; editable = true
            saved = d.saved; draft = d.text; saveError = nil
            return
        }
        let path = path
        let result = await Task.detached { () -> Result<(FileContent, Bool), Error> in
            Result { (try FileBrowser.read(path), FileBrowser.isUTF8Text(path)) }
        }.value
        switch result {
        case .success(let (c, utf8)):
            content = c; error = nil; editable = utf8
            if case .text(let s) = c { saved = s; draft = s } else { saved = nil }
        case .failure(let e):
            content = nil; error = e.localizedDescription; saved = nil
        }
        saveError = nil
    }

    func save(force: Bool) {
        guard let base = saved else { return }
        do {
            try FileBrowser.write(draft, to: path, expecting: force ? nil : base)
            saved = draft
            content = .text(draft)
            conflict = false; saveError = nil
        } catch FileBrowser.WriteError.changedOnDisk {
            conflict = true
        } catch {
            saveError = "Não salvou: \(error.localizedDescription)"
        }
    }
}

/// Ponte SwiftUI para `CodeScrollView`.
struct CodeTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let theme: ThemeDefinition?
    var editable = false
    var onEdit: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> CodeScrollView {
        let view = CodeScrollView(frame: .zero)
        apply(to: view)
        return view
    }

    func updateNSView(_ view: CodeScrollView, context: Context) { apply(to: view) }

    func apply(to view: CodeScrollView) {
        view.textView.isEditable = editable
        view.onEdit = onEdit
        view.show(text: text,
                  font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                  foreground: theme.map { NSColor($0.foreground.color) } ?? .textColor,
                  background: theme.map { NSColor($0.background.color) } ?? .textBackgroundColor,
                  selection: theme.map { NSColor($0.selection.color) })
    }
}
