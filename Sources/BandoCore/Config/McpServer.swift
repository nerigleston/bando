import Foundation

/// Servidor MCP cadastrado uma vez no Bando e entregue a qualquer agente.
///
/// Fica em `~/.config/bando/mcp.toml`. Chaves vão como `keychain:...` e só
/// chegam ao ambiente do processo do agente (nunca em argumentos ou arquivos).
public struct McpServer: Sendable, Equatable, Identifiable {
    public enum Transport: String, Codable, Sendable { case stdio, http, sse }

    public var id: String
    public var name: String
    public var transport: Transport
    public var command: String?
    public var args: [String]
    public var env: [String: SecretValue]
    public var url: String?
    public var headers: [String: SecretValue]
    /// Agentes que recebem este servidor. Vazio = todos os que suportam MCP.
    public var agents: [String]
    /// Projetos (nome ou caminho). Vazio = todos.
    public var projects: [String]

    public func applies(agent: String, project: Project?) -> Bool {
        if !agents.isEmpty && !agents.contains(agent) { return false }
        guard !projects.isEmpty else { return true }
        guard let project else { return false }
        return projects.contains { $0 == project.name || $0 == project.path || $0 == project.id }
    }
}

struct McpEntry: Codable, Sendable {
    var name: String?
    var transport: McpServer.Transport?
    var command: String?
    var args: [String]?
    var env: [String: String]?
    var url: String?
    var headers: [String: String]?
    var agents: [String]?
    var projects: [String]?
    var enabled: Bool?

    func resolved(id: String) throws -> McpServer {
        let section = "mcp.\(id)"
        guard id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw ConfigError.invalidValue(section: section, field: "id", detail: "use só letras, números, - e _")
        }
        let transport = transport ?? (url != nil ? .http : .stdio)
        if transport == .stdio && (command ?? "").isEmpty {
            throw ConfigError.missingField(section: section, field: "command")
        }
        if transport != .stdio && (url ?? "").isEmpty {
            throw ConfigError.missingField(section: section, field: "url")
        }
        func parse(_ dict: [String: String]?) throws -> [String: SecretValue] {
            var out: [String: SecretValue] = [:]
            for (k, v) in dict ?? [:] { out[k] = try SecretValue(parsing: v) }
            return out
        }
        return McpServer(id: id, name: name ?? id, transport: transport, command: command, args: args ?? [],
                         env: try parse(env), url: url, headers: try parse(headers),
                         agents: agents ?? [], projects: projects ?? [])
    }
}

struct McpFile: Codable { var mcp: [String: McpEntry]? }

/// Como cada agente recebe os servidores MCP.
public enum McpAdapter: String, Codable, Sendable, CaseIterable {
    // Gemini CLI fica de fora: GEMINI_CLI_SYSTEM_SETTINGS_PATH só é aceito
    // com arquivo e pasta do root (verificado na versão 0.64).
    case claude, codex, opencode

    public var label: String {
        switch self {
        case .claude: "--mcp-config"
        case .codex: "-c mcp_servers"
        case .opencode: "OPENCODE_CONFIG_CONTENT"
        }
    }
}

/// O que o agente precisa para enxergar os servidores.
public struct McpLaunch: Sendable, Equatable {
    public var args: [String] = []
    public var env: [String: SecretValue] = [:]
    /// Arquivos a gravar antes de iniciar (sem segredos), caminho → conteúdo.
    public var files: [String: String] = [:]

    public init() {}

    public var isEmpty: Bool { args.isEmpty && env.isEmpty && files.isEmpty }

    /// Traduz os servidores para o formato do agente.
    ///
    /// Cada valor secreto vira uma variável `BANDO_MCP_<ID>_<CHAVE>` no ambiente
    /// do agente, e a configuração só referencia o nome. No Codex, variáveis de
    /// servidores stdio são repassadas com o próprio nome (`env_vars`).
    public static func build(_ servers: [McpServer], adapter: McpAdapter, runDir: URL, sessionId: String) -> McpLaunch {
        var out = McpLaunch()
        guard !servers.isEmpty else { return out }

        func varName(_ id: String, _ key: String) -> String {
            let clean = (id + "_" + key).uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
            return "BANDO_MCP_" + String(clean)
        }
        /// Valor para a config: literal como está; segredo vira referência.
        func ref(_ server: McpServer, _ key: String, _ value: SecretValue, style: (String) -> String) -> String {
            if case .literal(let v) = value { return v }
            let name = varName(server.id, key)
            out.env[name] = value
            return style(name)
        }

        switch adapter {
        case .claude:
            var map: [String: Any] = [:]
            for s in servers {
                var cfg: [String: Any] = [:]
                if s.transport == .stdio {
                    cfg["command"] = s.command
                    cfg["args"] = s.args
                    if !s.env.isEmpty {
                        cfg["env"] = Dictionary(uniqueKeysWithValues: s.env.map { k, v in (k, ref(s, k, v) { "${\($0)}" }) })
                    }
                } else {
                    cfg["type"] = s.transport.rawValue
                    cfg["url"] = s.url
                    if !s.headers.isEmpty {
                        cfg["headers"] = Dictionary(uniqueKeysWithValues: s.headers.map { k, v in (k, ref(s, k, v) { "${\($0)}" }) })
                    }
                }
                map[s.id] = cfg
            }
            out.args = ["--mcp-config", json(["mcpServers": map])]

        case .codex:
            for s in servers {
                var fields: [String] = []
                if s.transport == .stdio {
                    fields.append("command=\(toml(s.command ?? ""))")
                    fields.append("args=[\(s.args.map(toml).joined(separator: ","))]")
                    var literal: [String] = [], forwarded: [String] = []
                    for (k, v) in s.env.sorted(by: { $0.key < $1.key }) {
                        if case .literal(let value) = v { literal.append("\(tomlKey(k))=\(toml(value))") }
                        else { out.env[k] = v; forwarded.append(toml(k)) }
                    }
                    if !literal.isEmpty { fields.append("env={\(literal.joined(separator: ","))}") }
                    if !forwarded.isEmpty { fields.append("env_vars=[\(forwarded.joined(separator: ","))]") }
                } else {
                    fields.append("url=\(toml(s.url ?? ""))")
                    var literal: [String] = [], fromEnv: [String] = []
                    for (k, v) in s.headers.sorted(by: { $0.key < $1.key }) {
                        if case .literal(let value) = v { literal.append("\(tomlKey(k))=\(toml(value))") }
                        else { let name = varName(s.id, k); out.env[name] = v; fromEnv.append("\(tomlKey(k))=\(toml(name))") }
                    }
                    if !literal.isEmpty { fields.append("http_headers={\(literal.joined(separator: ","))}") }
                    if !fromEnv.isEmpty { fields.append("env_http_headers={\(fromEnv.joined(separator: ","))}") }
                }
                out.args += ["-c", "mcp_servers.\(s.id)={\(fields.joined(separator: ","))}"]
            }

        case .opencode:
            var map: [String: Any] = [:]
            for s in servers {
                if s.transport == .stdio {
                    var cfg: [String: Any] = ["type": "local", "command": [s.command ?? ""] + s.args, "enabled": true]
                    if !s.env.isEmpty {
                        cfg["environment"] = Dictionary(uniqueKeysWithValues: s.env.map { k, v in (k, ref(s, k, v) { "{env:\($0)}" }) })
                    }
                    map[s.id] = cfg
                } else {
                    var cfg: [String: Any] = ["type": "remote", "url": s.url ?? "", "enabled": true]
                    if !s.headers.isEmpty {
                        cfg["headers"] = Dictionary(uniqueKeysWithValues: s.headers.map { k, v in (k, ref(s, k, v) { "{env:\($0)}" }) })
                    }
                    map[s.id] = cfg
                }
            }
            out.env["OPENCODE_CONFIG_CONTENT"] = .literal(json(["mcp": map]))

        }
        return out
    }

    static func json(_ obj: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    static func toml(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func tomlKey(_ k: String) -> String {
        k.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil ? k : toml(k)
    }
}
