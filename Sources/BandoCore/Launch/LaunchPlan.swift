import Foundation

/// O que a sessão pede ao iniciar o agente.
public struct LaunchRequest: Sendable {
    public enum Mode: Sendable, Equatable {
        case fresh
        /// Retoma uma conversa específica do agente.
        case resume(nativeId: String)
        /// Continua a conversa mais recente do diretório.
        case continueLast
        /// Abre uma conversa nova a partir de outra (fork).
        case fork(nativeId: String)
    }

    public var agent: AgentDefinition
    public var provider: ProviderDefinition?
    public var model: String?
    public var prompt: String?
    public var mode: Mode
    public var sessionId: String?
    public var worktree: String?
    public var branch: String?
    /// ID de conversa escolhido pelo Bando (para agentes com `assign_id`).
    public var newNativeId: String?
    /// Argumentos de hooks gerados pelo Bando (ex.: --settings do Claude).
    public var hookArgs: [String]
    /// Argumentos e ambiente dos servidores MCP do Bando.
    public var mcp: McpLaunch
    /// Compressor escolhido para a sessão (opcional).
    public var compressor: CompressorDefinition?

    public init(
        agent: AgentDefinition, provider: ProviderDefinition? = nil, model: String? = nil,
        prompt: String? = nil, mode: Mode = .fresh, sessionId: String? = nil,
        worktree: String? = nil, branch: String? = nil, newNativeId: String? = nil, hookArgs: [String] = [],
        mcp: McpLaunch = McpLaunch(), compressor: CompressorDefinition? = nil
    ) {
        self.agent = agent
        self.provider = provider
        self.model = model
        self.prompt = prompt
        self.mode = mode
        self.sessionId = sessionId
        self.worktree = worktree
        self.branch = branch
        self.newNativeId = newNativeId
        self.hookArgs = hookArgs
        self.mcp = mcp
        self.compressor = compressor
    }
}

/// Comando pronto para rodar. Os segredos continuam como referência
/// (`SecretValue`) até o último momento: só o `bando run` os resolve.
public struct LaunchPlan: Sendable, Equatable {
    /// argv[0] e argumentos.
    public var argv: [String]
    public var env: [String: SecretValue]
    /// Texto a digitar no terminal depois que o agente abrir (`prompt_via = "keys"`).
    public var pendingKeys: String?
    /// Arquivos a gravar antes de iniciar (configuração sem segredos).
    public var files: [String: String] = [:]
    /// Proxy do compressor a iniciar antes do agente (com `{port}` por trocar).
    public var proxy: ProxyLaunch?

    public static func build(_ req: LaunchRequest, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchPlan {
        let agent = req.agent

        var providerSettings: ProviderVariant?
        if let provider = req.provider {
            guard let s = provider.settings(for: agent.id) else {
                throw ConfigError.providerNotForAgent(provider: provider.id, agent: agent.id)
            }
            providerSettings = s
        }

        var values: [String: String] = [:]
        values["model"] = req.model.flatMap { $0.isEmpty ? nil : $0 }
        values["session_id"] = req.sessionId
        values["worktree"] = req.worktree
        values["branch"] = req.branch
        if case .resume(let id) = req.mode { values["native_id"] = id }
        if case .fork(let id) = req.mode { values["native_id"] = id }
        values["new_id"] = req.newNativeId
        let wantsArgsPrompt = agent.promptVia == .args && !(req.prompt ?? "").isEmpty
        if wantsArgsPrompt { values["prompt"] = req.prompt }

        var argv = expandEnvironment(agent.cmd, environment: environment)
            .split(separator: " ").map(String.init)
        let cmdTokens = argv.count
        argv += try expandGroup(agent.args, values)
        argv += req.hookArgs
        argv += req.mcp.args
        argv += try expandGroup(providerSettings?.args ?? [], values)
        argv += try expandGroup(agent.model, values)
        switch req.mode {
        case .fresh:
            argv += try expandGroup(agent.fresh, values)
            argv += try expandGroup(agent.assignId, values)
        case .resume: argv += try expandGroup(agent.resume, values)
        case .continueLast: argv += try expandGroup(agent.continueArgs, values)
        case .fork:
            argv += try expandGroup(agent.fork.isEmpty ? agent.resume : agent.fork, values)
        }
        if wantsArgsPrompt { argv += try expandGroup(agent.prompt, values) }

        var env: [String: SecretValue] = [:]
        for (k, v) in agent.env { env[k] = .literal(expandEnvironment(v, environment: environment)) }
        for (k, v) in providerSettings?.env ?? [:] { env[k] = v }
        for (k, v) in req.mcp.env { env[k] = v }
        if let id = req.sessionId { env["BANDO_SESSION_ID"] = .literal(id) }

        let keys = (!wantsArgsPrompt && !(req.prompt ?? "").isEmpty) ? req.prompt : nil
        var plan = LaunchPlan(argv: argv, env: env, pendingKeys: keys, files: req.mcp.files)
        if let compressor = req.compressor {
            try plan.route(through: compressor, agent: agent, cmdTokens: cmdTokens)
        }
        return plan
    }

    /// Expande placeholders `{x}` num grupo de argumentos. Se algum placeholder
    /// do grupo não tiver valor, o grupo inteiro sai (ex.: `["--model", "{model}"]`
    /// some quando não há modelo).
    static func expandGroup(_ group: [String], _ values: [String: String]) throws -> [String] {
        var out: [String] = []
        for arg in group {
            var result = ""
            var rest = Substring(arg)
            while let open = rest.firstIndex(of: "{") {
                result += rest[..<open]
                guard let close = rest[open...].firstIndex(of: "}") else {
                    result += rest[open...]
                    rest = ""
                    break
                }
                let key = String(rest[rest.index(after: open)..<close])
                guard isPlaceholder(key) else {
                    // Chaves que não são placeholders (JSON, por exemplo) ficam como estão.
                    result += rest[open...close]
                    rest = rest[rest.index(after: close)...]
                    continue
                }
                guard let value = values[key] else { return [] }
                result += value
                rest = rest[rest.index(after: close)...]
            }
            result += rest
            out.append(result)
        }
        return out
    }

    static let placeholders: Set<String> = ["prompt", "model", "native_id", "new_id", "session_id", "worktree", "branch"]

    static func isPlaceholder(_ key: String) -> Bool { placeholders.contains(key) }

    /// Expande `$VAR` e `${VAR}` (usado em `cmd`, como `$SHELL`).
    public static func expandEnvironment(_ text: String, environment: [String: String]) -> String {
        guard text.contains("$") else { return text }
        let pattern = #"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let nameRange = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            let name = ns.substring(with: nameRange)
            result += environment[name] ?? (name == "SHELL" ? "/bin/zsh" : "")
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
