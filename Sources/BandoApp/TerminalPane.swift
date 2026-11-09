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

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        // O histórico longo fica no tmux (rolagem com o mouse); o terminal local
        // só precisa de um pouco além da tela.
        view.changeScrollback(200)
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
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
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

    private func apply(to view: LocalProcessTerminalView) {
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

    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
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

        func stopWatching() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}
