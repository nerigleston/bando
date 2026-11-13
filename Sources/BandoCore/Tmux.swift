import Foundation

/// Acesso ao tmux. As sessões do Bando ficam num servidor próprio
/// (`tmux -L bando`), separado das sessões tmux do usuário.
public struct Tmux: Sendable {
    public let executable: String
    public let server: String

    public static let bandoServer = "bando"

    public init(server: String = Tmux.bandoServer) throws {
        guard let tmux = ExecutableLocator.shared.locate("tmux") else { throw BandoError.tmuxMissing }
        executable = tmux
        self.server = server
    }

    /// Argumentos que escolhem o servidor. "default" = servidor padrão do usuário
    /// (usado para sessões adotadas do Xirp).
    public var serverArgs: [String] { server == "default" ? [] : ["-L", server] }

    @discardableResult
    func tmux(_ args: [String]) throws -> Shell.Result {
        try Shell.run(executable, serverArgs + args)
    }

    public func hasSession(_ name: String) -> Bool {
        (try? tmux(["has-session", "-t", "=\(name)"]))?.ok ?? false
    }

    /// Cria a sessão desanexada rodando `command` no diretório `cwd`.
    public func newSession(name: String, cwd: String, command: [String], env: [String: String] = [:]) throws {
        var args = ["new-session", "-d", "-s", name, "-c", cwd, "-x", "200", "-y", "50"]
        for (k, v) in env.sorted(by: { $0.key < $1.key }) { args += ["-e", "\(k)=\(v)"] }
        args += command
        let r = try tmux(args)
        guard r.ok else { throw BandoError.command("tmux new-session", r.stderr) }
        // Opções da sessão: histórico maior, sem barra de status (o app mostra
        // o próprio cabeçalho), mouse ligado para rolar no SwiftTerm.
        // window-size latest: com a sessão aberta em mais de um lugar (grade +
        // terminal), o tamanho segue o terminal usado por último.
        for opt in [["history-limit", "20000"], ["status", "off"], ["mouse", "on"], ["window-size", "latest"]] {
            // set-option não aceita o prefixo "=" (has-session aceita).
            _ = try? tmux(["set-option", "-t", name, opt[0], opt[1]])
        }
        applyServerOptions()
    }

    /// Opções do servidor do Bando, aplicadas ao criar sessão e a cada vez que
    /// um terminal se conecta (cobre sessões antigas):
    /// - links OSC 8 (texto clicável com o endereço escondido, como as fontes
    ///   do Claude Code) só passam se o terminal anunciar "hyperlinks", e o
    ///   padrão do tmux para xterm não anuncia. Índice fixo para não repetir;
    /// - cópia por OSC 52 vinda do agente: com o padrão "external" o tmux
    ///   descarta a cópia que o próprio programa pede e nada chega ao macOS.
    func applyServerOptions() {
        for opt in Self.serverOptions { _ = try? tmux(opt) }
    }

    static let serverOptions: [[String]] = [
        ["set-option", "-s", "terminal-features[90]", "xterm*:hyperlinks"],
        ["set-option", "-s", "set-clipboard", "on"],
    ]

    /// Título que o programa do painel definiu (OSC 0/2). Nil se a sessão não existe.
    public func paneTitle(_ name: String) -> String? {
        guard let r = try? tmux(["display-message", "-p", "-t", "=\(name):", "#{pane_title}"]), r.ok else { return nil }
        return r.trimmed
    }

    public func kill(_ name: String) throws {
        _ = try tmux(["kill-session", "-t", "=\(name)"])
    }

    /// Digita texto literal e, se pedido, Enter.
    public func send(_ name: String, text: String, enter: Bool = true) throws {
        let r = try tmux(["send-keys", "-t", "=\(name):", "-l", text])
        guard r.ok else { throw BandoError.command("tmux send-keys", r.stderr) }
        // Texto digitado de uma vez parece "colado" para algumas CLIs (Codex),
        // e um Enter imediato vira quebra de linha. Uma pausa curta resolve.
        if enter {
            Thread.sleep(forTimeInterval: 0.25)
            _ = try tmux(["send-keys", "-t", "=\(name):", "Enter"])
        }
    }

    /// Texto visível no painel (sem cores).
    public func capture(_ target: String, lines: Int = 60) -> String {
        (try? tmux(["capture-pane", "-p", "-t", target, "-S", "-\(lines)"]))?.stdout ?? ""
    }

    /// Copia a saída do painel para `command` (que lê da entrada padrão).
    public func pipePane(_ target: String, command: String) throws {
        let r = try tmux(["pipe-pane", "-O", "-t", target, command])
        guard r.ok else { throw BandoError.command("tmux pipe-pane", r.stderr) }
    }

    /// Nome do processo em primeiro plano no painel ativo da sessão (ex.: "zsh",
    /// "node"), ou nil se a sessão não existe.
    public func foregroundCommand(_ name: String) -> String? {
        guard let r = try? tmux(["display-message", "-p", "-t", "=\(name):", "#{pane_current_command}"]), r.ok else { return nil }
        let cmd = r.trimmed
        return cmd.isEmpty ? nil : cmd
    }

    /// O painel está só com um shell parado no prompt (nada rodando nele).
    public static func isIdleShell(_ command: String, userShell: String? = ProcessInfo.processInfo.environment["SHELL"]) -> Bool {
        let name = command.hasPrefix("-") ? String(command.dropFirst()) : command
        var shells: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "nu"]
        if let userShell { shells.insert((userShell as NSString).lastPathComponent) }
        return shells.contains(name)
    }

    public func listSessions() -> [String] {
        guard let r = try? tmux(["list-sessions", "-F", "#{session_name}"]), r.ok else { return [] }
        return r.trimmed.split(separator: "\n").map(String.init)
    }

    /// Comando para anexar (usado pelo terminal do app e por `bando attach`).
    /// No servidor do Bando aplica `serverOptions` antes, no mesmo comando: as
    /// funções do terminal são lidas quando ele se conecta, então isso cobre
    /// sessões criadas antes da opção existir. O servidor padrão do usuário
    /// (sessões adotadas do Xirp) não é mexido.
    public func attachCommand(_ name: String) -> [String] {
        let attach = ["attach-session", "-t", "=\(name)"]
        guard server != "default" else { return [executable] + serverArgs + attach }
        return [executable] + serverArgs + Self.serverOptions.flatMap { $0 + [";"] } + attach
    }
}
