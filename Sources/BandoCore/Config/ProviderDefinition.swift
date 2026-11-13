import Foundation

/// Provider: de onde vem o modelo. Na prática, variáveis de ambiente e
/// argumentos extras injetados no agente.
///
/// O mesmo provider pode entrar de jeitos diferentes em cada agente (o
/// OpenRouter entra no Claude Code por variável de ambiente e no Codex por
/// `-c model_providers...`). Por isso existem as variantes por agente.
public struct ProviderDefinition: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var env: [String: SecretValue]
    public var args: [String]
    public var models: [String]
    /// Agentes liberados sem variante própria. Vazio e sem variantes = qualquer um.
    public var agents: [String]
    /// Configuração específica por agente (`[providers.<id>.for.<agente>]`).
    public var variants: [String: ProviderVariant]

    public var supportedAgents: [String] {
        Array(Set(agents).union(variants.keys)).sorted()
    }

    public func supports(agent: String) -> Bool {
        if agents.isEmpty && variants.isEmpty { return true }
        return agents.contains(agent) || variants[agent] != nil
    }

    /// Ambiente e argumentos para um agente: base do provider + variante.
    /// Retorna nil se o provider não serve para o agente.
    public func settings(for agent: String) -> ProviderVariant? {
        guard supports(agent: agent) else { return nil }
        var env = self.env
        var args = self.args
        if let v = variants[agent] {
            env.merge(v.env) { _, new in new }
            args += v.args
        }
        return ProviderVariant(env: env, args: args, modelPrefix: variants[agent]?.modelPrefix)
    }
}

public struct ProviderVariant: Sendable, Equatable {
    public var env: [String: SecretValue]
    public var args: [String]
    /// Prefixo que o agente exige no nome do modelo deste provider (ex.: "ollama/"
    /// no OpenCode, "ollama_chat/" no Aider). Só entra se o modelo ainda não o tiver.
    public var modelPrefix: String? = nil
}

/// Valor de uma variável de ambiente do provider.
///
/// - `keychain:<serviço>/<conta>` é lido do Keychain na hora de iniciar.
/// - `env:<VAR>` copia uma variável do ambiente de quem inicia.
/// - qualquer outro texto é usado como está.
public enum SecretValue: Sendable, Equatable, CustomStringConvertible {
    case literal(String)
    case keychain(service: String, account: String)
    case environment(String)

    public init(parsing raw: String) throws {
        if raw.hasPrefix("keychain:") {
            let ref = raw.dropFirst("keychain:".count)
            let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw ConfigError.invalidSecretRef(raw)
            }
            self = .keychain(service: parts[0], account: parts[1])
        } else if raw.hasPrefix("env:") {
            let name = String(raw.dropFirst("env:".count))
            guard !name.isEmpty else { throw ConfigError.invalidSecretRef(raw) }
            self = .environment(name)
        } else {
            self = .literal(raw)
        }
    }

    /// Texto seguro para mostrar: nunca revela o segredo.
    public var description: String {
        switch self {
        case .literal(let v): v.isEmpty ? "(vazio)" : v
        case .keychain(let s, let a): "Keychain \(s)/\(a)"
        case .environment(let n): "$\(n)"
        }
    }

    public var isSecret: Bool {
        if case .literal = self { return false }
        return true
    }
}

struct ProviderVariantEntry: Codable, Sendable {
    var env: [String: String]?
    var args: [String]?
    var model_prefix: String?
}

struct ProviderEntry: Codable, Sendable {
    var name: String?
    var env: [String: String]?
    var args: [String]?
    var models: [String]?
    var agents: [String]?
    var `for`: [String: ProviderVariantEntry]?
    var enabled: Bool?

    func merged(with o: ProviderEntry) -> ProviderEntry {
        var variants = self.for ?? [:]
        for (agent, v) in o.for ?? [:] {
            let base = variants[agent]
            variants[agent] = ProviderVariantEntry(env: v.env ?? base?.env, args: v.args ?? base?.args,
                                                   model_prefix: v.model_prefix ?? base?.model_prefix)
        }
        return ProviderEntry(
            name: o.name ?? name,
            env: o.env ?? env,
            args: o.args ?? args,
            models: o.models ?? models,
            agents: o.agents ?? agents,
            for: variants.isEmpty ? nil : variants,
            enabled: o.enabled ?? enabled
        )
    }

    func resolved(id: String) throws -> ProviderDefinition {
        let section = "providers.\(id)"
        var variants: [String: ProviderVariant] = [:]
        for (agent, v) in self.for ?? [:] {
            variants[agent] = ProviderVariant(
                env: try Self.parseEnv(v.env, section: "\(section).for.\(agent)"),
                args: v.args ?? [],
                modelPrefix: v.model_prefix.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
        return ProviderDefinition(
            id: id,
            name: name ?? id,
            env: try Self.parseEnv(env, section: section),
            args: args ?? [],
            models: models ?? [],
            agents: agents ?? [],
            variants: variants
        )
    }

    private static func parseEnv(_ raw: [String: String]?, section: String) throws -> [String: SecretValue] {
        var parsed: [String: SecretValue] = [:]
        for (key, value) in raw ?? [:] {
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                throw ConfigError.invalidValue(section: section, field: "env", detail: "nome de variável inválido: \(key)")
            }
            parsed[key] = try SecretValue(parsing: value)
        }
        return parsed
    }
}
