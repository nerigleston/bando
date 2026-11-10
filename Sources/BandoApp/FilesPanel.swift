import AppKit
import BandoCore
import SwiftUI

// MARK: - Painel de arquivos (à direita do terminal)

/// Árvore do worktree da sessão. Só leitura: abrir um arquivo mostra o
/// conteúdo numa aba ao lado do terminal. Recarrega quando o painel abre,
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
            model.openFiles[session.id] = node.path
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
                .font(.system(size: 11)).foregroundStyle(node.isDirectory ? p.secondary : p.tertiary)
            Text(node.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(changeColor ?? p.text)
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
        .help(relative)
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
            tab(title: (path as NSString).lastPathComponent, symbol: "doc.text", active: showingFile) { select(true) }
            IconButton(symbol: "xmark", help: "Fechar arquivo", size: 10) {
                model.openFiles[session.id] = nil
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

/// Conteúdo do arquivo, só leitura, com número de linha e busca (⌘F).
struct FileViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let path: String
    /// Muda quando a sessão muda de estado, para reler o arquivo.
    let stamp: SessionStatus
    @State private var content: FileContent?
    @State private var error: String?

    var body: some View {
        Group {
            switch content {
            case .text(let s)?:
                CodeTextView(text: s, fontSize: max(model.fontSize - 1, 9), theme: model.theme)
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
        .task(id: "\(path)|\(stamp.rawValue)") { await load() }
    }

    func notice(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(p.secondary)
            Button("Abrir no app padrão") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                .buttonStyle(.link)
        }
    }

    func load() async {
        let path = path
        let result = await Task.detached { () -> Result<FileContent, Error> in
            Result { try FileBrowser.read(path) }
        }.value
        switch result {
        case .success(let c): content = c; error = nil
        case .failure(let e): content = nil; error = e.localizedDescription
        }
    }
}

/// NSTextView só leitura: aguenta arquivos grandes melhor que um `Text`.
struct CodeTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let theme: ThemeDefinition?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 6, height: 8)
        // Sem quebra de linha: código fica como está, com rolagem horizontal.
        tv.isHorizontallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let ruler = LineNumberRuler(textView: tv)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        apply(to: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) { apply(to: scroll) }

    func apply(to scroll: NSScrollView) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let fg = theme.map { NSColor($0.foreground.color) } ?? .textColor
        if tv.string != text || tv.font != font {
            let keep = tv.visibleRect.origin
            tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: fg]))
            tv.font = font
            tv.scroll(keep)
        }
        tv.textColor = fg
        if let sel = theme?.selection { tv.selectedTextAttributes = [.backgroundColor: NSColor(sel.color)] }
        (scroll.verticalRulerView as? LineNumberRuler)?.font = NSFont.monospacedDigitSystemFont(ofSize: max(fontSize - 2, 8), weight: .regular)
        scroll.verticalRulerView?.needsDisplay = true
    }
}

/// Números de linha na régua vertical da NSTextView.
final class LineNumberRuler: NSRulerView {
    var font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification,
                                               object: textView.enclosingScrollView?.contentView)
    }

    required init(coder: NSCoder) { fatalError("não usado") }

    @objc func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let text = tv.string as NSString
        let visible = tv.visibleRect
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // Número da primeira linha visível: conta as quebras antes dela.
        var line = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: chars.location),
                                 options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let width = "\(max(line, 1) + 9999)".count
        let thickness = CGFloat(width) * font.maximumAdvancement.width + 14
        if abs(thickness - ruleThickness) > 1 { ruleThickness = thickness }
        var index = chars.location
        let end = NSMaxRange(chars)
        let inset = tv.textContainerInset.height
        while index < end || (index == end && index == text.length && line == 1) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyph = lm.glyphIndexForCharacter(at: min(index, max(text.length - 1, 0)))
            var r = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            r.origin.y += inset - visible.origin.y
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: r.minY + (r.height - size.height) / 2), withAttributes: attrs)
            if NSMaxRange(lineRange) <= index { break }
            index = NSMaxRange(lineRange)
            line += 1
            if text.length == 0 { break }
        }
    }
}
