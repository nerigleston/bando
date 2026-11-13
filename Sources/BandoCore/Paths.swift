import Foundation

/// Onde o Bando guarda cada coisa. Todas as pastas podem ser trocadas por
/// variável de ambiente, o que também serve para os testes.
public struct BandoPaths: Sendable {
    /// `~/.config/bando` (ou `$BANDO_CONFIG_DIR`, ou `$XDG_CONFIG_HOME/bando`).
    public var configDir: URL
    /// `~/Library/Application Support/Bando` (ou `$BANDO_STATE_DIR`).
    public var stateDir: URL

    public init(configDir: URL, stateDir: URL) {
        self.configDir = configDir
        self.stateDir = stateDir
    }

    public static func standard(environment env: [String: String] = ProcessInfo.processInfo.environment) -> BandoPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let config: URL
        if let dir = env["BANDO_CONFIG_DIR"], !dir.isEmpty {
            config = URL(fileURLWithPath: dir)
        } else if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            config = URL(fileURLWithPath: xdg).appendingPathComponent("bando")
        } else {
            config = home.appendingPathComponent(".config/bando")
        }
        let state: URL
        if let dir = env["BANDO_STATE_DIR"], !dir.isEmpty {
            state = URL(fileURLWithPath: dir)
        } else {
            state = home.appendingPathComponent("Library/Application Support/Bando")
        }
        return BandoPaths(configDir: config, stateDir: state)
    }

    public var agentsFile: URL { configDir.appendingPathComponent("agents.toml") }
    public var providersFile: URL { configDir.appendingPathComponent("providers.toml") }
    public var themesFile: URL { configDir.appendingPathComponent("themes.toml") }
    public var mcpFile: URL { configDir.appendingPathComponent("mcp.toml") }
    public var database: URL { stateDir.appendingPathComponent("bando.sqlite") }
    /// JSONL do compressor da sessão: uma linha por pedido, só contagens de tokens.
    public func compressorStatsFile(sessionId: String) -> URL {
        stateDir.appendingPathComponent("run").appendingPathComponent("\(sessionId).compressor.jsonl")
    }

    /// Pasta dos worktrees de um repositório: `<pai>/.bando-worktrees/<repo>`.
    /// Fica no mesmo disco do repositório, então o git não copia objetos.
    public static func worktreeRoot(forRepository repo: URL) -> URL {
        repo.deletingLastPathComponent()
            .appendingPathComponent(".bando-worktrees")
            .appendingPathComponent(repo.lastPathComponent)
    }
}
