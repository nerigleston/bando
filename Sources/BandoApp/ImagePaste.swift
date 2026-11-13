import AppKit

/// ⌘V com imagem ou arquivo nos campos de texto do app (tarefa da nova sessão,
/// campo do projeto). O editor do SwiftUI ignora imagem: aqui ela vira um PNG
/// em `$TMPDIR/bando-uploads/` (como no terminal) e o caminho entra onde está o
/// cursor. Texto continua com a colagem normal.
@MainActor
enum ImagePaste {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    /// True se tratou a colagem (o evento não segue para o campo).
    static func handle(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v",
              // Campo de várias linhas com foco. O terminal (SwiftTerm) não é
              // NSTextView e tem a própria colagem de imagem.
              let textView = event.window?.firstResponder as? NSTextView,
              !textView.isFieldEditor, textView.isEditable,
              let paths = attachmentPaths(from: .general) else { return false }
        let text = paths.joined(separator: " ") + " "
        textView.insertText(text, replacementRange: textView.selectedRange())
        return true
    }

    /// Caminhos para colar: arquivos copiados no Finder, ou a imagem da área de
    /// transferência gravada em PNG. Nil quando é só texto.
    static func attachmentPaths(from pb: NSPasteboard) -> [String]? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.map(\.path)
        }
        if let path = BandoTerminalView.saveImage(from: pb) { return [path] }
        return nil
    }
}
