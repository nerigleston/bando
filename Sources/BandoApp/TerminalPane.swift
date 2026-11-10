import AppKit
import BandoCore
import SwiftTerm
import SwiftUI

/// Terminal nativo (SwiftTerm) anexado à sessão tmux. Desmontado quando sai
/// da tela: o agente continua no tmux e o app não guarda o terminal na memória.
struct TerminalPane: NSViewRepresentable {
    let argv: [String]
    var cwd: String?
    var theme: ThemeDefinition?
    var fontSize: Double = 13
    var focused: Bool = true
    /// Chamado quando o usuário clica dentro deste terminal (a grade move o foco).
    var onFocus: (() -> Void)? = nil

    func makeNSView(context: Context) -> BandoTerminalView {
        let view = BandoTerminalView(frame: .zero)
        view.workingDirectory = cwd
        view.processDelegate = context.coordinator
        // O histórico longo fica no tmux (rolagem com o mouse); o terminal local
        // só precisa de um pouco além da tela.
        view.changeScrollback(200)
        // Option fica com o layout do teclado: no ABNT2, Option+Q é "/" e
        // Option+W é "?". Nas teclas sem texto (setas, Enter, Backspace) segue
        // como Meta, então Option+Enter e Option+seta continuam funcionando.
        view.optionAsMetaKey = false
        view.optionAsMetaKeyForFunctionalKeys = true
        apply(to: view)
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        env.append("LANG=\(ProcessInfo.processInfo.environment["LANG"] ?? "pt_BR.UTF-8")")
        env.append("PATH=\(ExecutableLocator.shared.pathValue)")
        view.startProcess(
            executable: argv[0], args: Array(argv.dropFirst()), environment: env,
            currentDirectory: cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        )
        context.coordinator.appliedTheme = theme?.id
        context.coordinator.appliedFont = fontSize
        context.coordinator.onFocus = onFocus
        context.coordinator.watchClicks(on: view)
        context.coordinator.watchShiftReturn(on: view)
        return view
    }

    func updateNSView(_ view: BandoTerminalView, context: Context) {
        context.coordinator.onFocus = onFocus
        if context.coordinator.appliedTheme != theme?.id || context.coordinator.appliedFont != fontSize {
            apply(to: view)
            context.coordinator.appliedTheme = theme?.id
            context.coordinator.appliedFont = fontSize
        }
        if focused, view.window?.firstResponder !== view {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }

    private func apply(to view: BandoTerminalView) {
        view.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        guard let theme else { return }
        view.nativeBackgroundColor = theme.background.nsColor
        view.nativeForegroundColor = theme.foreground.nsColor
        view.caretColor = theme.cursor.nsColor
        view.selectedTextBackgroundColor = theme.selection.nsColor
        view.installColors(theme.ansi.map {
            SwiftTerm.Color(red: UInt16($0.r) * 257, green: UInt16($0.g) * 257, blue: UInt16($0.b) * 257)
        })
    }

    static func dismantleNSView(_ view: BandoTerminalView, coordinator: Coordinator) {
        // Encerra só o cliente `tmux attach`; a sessão continua.
        coordinator.stopWatching()
        view.terminate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var appliedTheme: String?
        var appliedFont: Double = 0
        var onFocus: (() -> Void)?
        private var monitor: Any?

        /// O SwiftTerm não deixa sobrescrever becomeFirstResponder; um monitor
        /// local de clique (só eventos deste app) avisa quando o clique cai aqui.
        func watchClicks(on view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak view] event in
                if let view, event.window === view.window,
                   view.bounds.contains(view.convert(event.locationInWindow, from: nil)) {
                    self?.onFocus?()
                }
                return event
            }
        }

        private var keyMonitor: Any?

        /// Shift+Enter quebra a linha no agente: manda Esc+Enter, a mesma
        /// sequência do Option+Enter (o terminal manda Enter puro para Shift+Enter,
        /// e os agentes não distinguem). Só vale para o terminal com foco.
        func watchShiftReturn(on view: BandoTerminalView) {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view] event in
                // ⌘V com imagem (print copiado): grava e cola o caminho, como o
                // Xirp. Com texto, segue o colar normal do terminal.
                if let view, event.window === view.window, view.window?.firstResponder === view,
                   event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                   event.charactersIgnoringModifiers == "v",
                   let path = BandoTerminalView.saveImage(from: .general) {
                    view.send(txt: BandoTerminalView.shellEscape(path) + " ")
                    return nil
                }
                guard let view, event.window === view.window, view.window?.firstResponder === view,
                      event.keyCode == 36 || event.keyCode == 76,   // Return e Enter do teclado numérico
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .shift
                else { return event }
                view.send(data: [0x1B, 0x0D][...])
                return nil
            }
        }

        func stopWatching() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}


/// Terminal do Bando: Cmd+clique num caminho de arquivo mostra no Finder.
/// O SwiftTerm só abre links com esquema (https://…) e bloqueia caminhos.
final class BandoTerminalView: LocalProcessTerminalView {
    /// Pasta da sessão, para resolver caminhos relativos.
    var workingDirectory: String?

    // MARK: Arrastar e soltar (o SwiftTerm não trata)

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.dropText(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.dropText(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    /// Cola o caminho (ou o texto) no terminal, como o Terminal do macOS. Não
    /// manda Enter: quem decide é o usuário.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let text = Self.dropText(from: sender.draggingPasteboard) else { return false }
        window?.makeFirstResponder(self)
        send(txt: text)
        return true
    }

    /// Arquivos viram caminhos protegidos e separados por espaço (com espaço no
    /// fim, para emendar o próximo); URL web e texto entram como estão.
    static func dropText(from pb: NSPasteboard) -> String? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.map { shellEscape($0.path) }.joined(separator: " ") + " "
        }
        // Imagem sem arquivo (navegador, miniatura do print): grava e cola o caminho.
        if let path = saveImage(from: pb) { return shellEscape(path) + " " }
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let u = urls.first { return u.absoluteString }
        return pb.string(forType: .string)
    }

    /// Pasta das imagens coladas ou arrastadas sem arquivo (o macOS limpa a
    /// pasta temporária sozinho).
    static var uploadsDir: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bando-uploads", isDirectory: true)
    }

    /// Grava a imagem da área de transferência em PNG e devolve o caminho.
    /// Nil se não houver imagem ou se houver texto (aí o texto tem prioridade).
    static func saveImage(from pb: NSPasteboard) -> String? {
        guard pb.string(forType: .string) == nil else { return nil }
        let png: Data?
        if let d = pb.data(forType: .png) { png = d }
        else if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) { png = rep.representation(using: .png, properties: [:]) }
        else if let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            png = rep.representation(using: .png, properties: [:])
        } else { png = nil }
        guard let png, !png.isEmpty else { return nil }
        let dir = uploadsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-image.png")
        do { try png.write(to: url) } catch { return nil }
        return url.path
    }

    /// Barra invertida antes de espaço e caracteres que o shell interpreta.
    static func shellEscape(_ path: String) -> String {
        let special = Set(" !\"#$&'()*,;<=>?[\\]^`{|}~")
        return String(path.flatMap { special.contains($0) ? ["\\", $0] : [$0] })
    }

    override func requestOpenLink(source: TerminalView, request: TerminalLinkRequest) {
        if let url = Self.fileURL(from: request.link, relativeTo: workingDirectory) {
            // Só mostra no Finder (seleciona o item); não abre nem executa.
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        super.requestOpenLink(source: source, request: request)
    }

    /// Caminho existente a partir do texto do link: aceita absoluto, ~, file://
    /// e relativo; tira pontuação do fim e sufixo :linha:coluna.
    static func fileURL(from link: String, relativeTo cwd: String?) -> URL? {
        var text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, "(<[{'\"`".contains(first) { text.removeFirst() }
        if text.hasPrefix("file://") {
            guard let u = URL(string: text), u.isFileURL else { return nil }
            text = u.path
        } else if text.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#, options: .regularExpression) != nil {
            return nil   // outro esquema (https, etc.): fica com o SwiftTerm
        }
        let fm = FileManager.default
        func resolve(_ t: String) -> URL? {
            guard !t.isEmpty else { return nil }
            var path = (t as NSString).expandingTildeInPath
            if !path.hasPrefix("/") {
                guard let cwd else { return nil }
                path = (cwd as NSString).appendingPathComponent(path)
            }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            return fm.fileExists(atPath: url.path) ? url : nil
        }
        if let u = resolve(text) { return u }
        // Pontuação de frase no fim ("arquivo.zip." ou "(pasta)").
        var trimmed = text
        while let last = trimmed.last, ".,;:)]}'\"`>".contains(last) {
            trimmed.removeLast()
            if let u = resolve(trimmed) { return u }
        }
        // Sufixo :linha ou :linha:coluna (saída de compiladores e grep).
        if let r = trimmed.range(of: #"(:\d+){1,2}$"#, options: .regularExpression) {
            return resolve(String(trimmed[..<r.lowerBound]))
        }
        return nil
    }
}
