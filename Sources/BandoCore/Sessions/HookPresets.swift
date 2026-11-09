import Foundation

/// Hooks que o Bando passa para cada agente ao iniciar a sessão.
///
/// Nada é gravado nos arquivos de configuração globais do agente: os hooks vão
/// por argumento só nas sessões do Bando. Assim não disparam em sessões
/// abertas fora do Bando nem em outros agentes que leem os mesmos arquivos.
public enum HookPresets {
    /// Presets com implementação. Agentes com `status = "hooks"` cujo preset
    /// ainda não existe aqui caem no modo de leitura da saída.
    public static let implemented: Set<String> = ["claude"]

    public static func supports(_ preset: String?) -> Bool {
        preset.map(implemented.contains) ?? false
    }

    /// Argumentos extras para o agente.
    public static func launchArgs(preset: String?, bandoPath: String, sessionId: String) -> [String] {
        switch preset {
        case "claude":
            return ["--settings", claudeSettings(bandoPath: bandoPath, sessionId: sessionId)]
        default:
            return []
        }
    }

    /// JSON de settings do Claude Code só com hooks. Cada hook chama
    /// `bando hook <evento> --session <id>`; o Claude manda os detalhes do
    /// evento em JSON pela entrada padrão.
    static func claudeSettings(bandoPath: String, sessionId: String) -> String {
        func command(_ event: String) -> [String: Any] {
            ["type": "command",
             "command": "\(shellQuote(bandoPath)) hook \(event) --session \(sessionId)",
             "timeout": 10]
        }
        let events: [(String, String)] = [
            ("SessionStart", "start"),
            ("UserPromptSubmit", "working"),
            ("PreToolUse", "working"),
            ("PostToolUse", "working"),
            ("PermissionRequest", "waiting"),
            ("Notification", "notification"),
            ("Stop", "turn-end"),
        ]
        var hooks: [String: Any] = [:]
        for (claudeEvent, bandoEvent) in events {
            hooks[claudeEvent] = [["hooks": [command(bandoEvent)]]]
        }
        let data = try! JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func shellQuote(_ s: String) -> String {
        if s.range(of: #"^[A-Za-z0-9_@%+=:,./-]+$"#, options: .regularExpression) != nil { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Onde está o executável `bando` que os hooks e o tmux devem chamar.
public enum BandoCLI {
    public static func path() -> String {
        if let env = ProcessInfo.processInfo.environment["BANDO_CLI"], !env.isEmpty { return env }
        let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let exe = URL(fileURLWithPath: Bundle.main.executablePath ?? me.path).resolvingSymlinksInPath()
        // Dentro do Bando.app o CLI fica ao lado do executável do app.
        let sibling = exe.deletingLastPathComponent().appendingPathComponent("bando-cli")
        if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling.path }
        if exe.lastPathComponent == "bando" || exe.lastPathComponent == "bando-cli" { return exe.path }
        let devBuild = exe.deletingLastPathComponent().appendingPathComponent("bando")
        if FileManager.default.isExecutableFile(atPath: devBuild.path) { return devBuild.path }
        return ExecutableLocator.shared.locate("bando") ?? "bando"
    }
}
