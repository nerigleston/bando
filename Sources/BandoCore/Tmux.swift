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

    public func listSessions() -> [String] {
        guard let r = try? tmux(["list-sessions", "-F", "#{session_name}"]), r.ok else { return [] }
        return r.trimmed.split(separator: "\n").map(String.init)
    }

    /// Comando para anexar (usado pelo terminal do app e por `bando attach`).
    public func attachCommand(_ name: String) -> [String] {
        [executable] + serverArgs + ["attach-session", "-t", "=\(name)"]
    }
}
