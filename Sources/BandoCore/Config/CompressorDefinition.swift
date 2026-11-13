import Foundation

/// Compressor: proxy local que encolhe o que o agente manda ao modelo.
///
/// É opcional e vale por sessão. O `bando run` inicia o proxy numa porta livre
/// antes do agente e o encerra junto com ele; nada fica rodando depois.
public struct CompressorDefinition: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var cmd: String
    /// Argumentos do proxy. `{port}` vira a porta escolhida na hora.
    public var args: [String]
    public var env: [String: String]
    public var install: String?
    /// Como apontar cada agente para o proxy (`[compressors.<id>.for.<agente>]`).
    public var variants: [String: CompressorVariant]

    public var supportedAgents: [String] { variants.keys.sorted() }

    public func supports(agent: String) -> Bool { variants[agent] != nil }
}

public struct CompressorVariant: Sendable, Equatable {
    /// Endereço do proxy entregue ao agente (com `{port}`).
    public var url: String
    /// Variável de ambiente do agente que recebe `url`.
    public var urlEnv: String?
    /// Regex da chave de um argumento `chave="valor"` que guarda a URL do provider.
    public var urlArg: String?
    /// Argumentos do agente quando o provider não trouxe URL (com `{url}`).
    public var defaultArgs: [String]
    /// Argumentos do proxy quando há destino (com `{upstream}`).
    public var upstream: [String]
    /// Sufixo tirado do destino antes de passar ao proxy.
    public var upstreamStrip: String?
    /// Variáveis do provider que tornam a sessão incompatível.
    public var blockedEnv: [String]
}

/// Proxy a iniciar antes do agente. `{port}` ainda não foi trocado: quem
/// escolhe a porta é o `bando run`.
public struct ProxyLaunch: Sendable, Equatable {
    public var id: String
    public var name: String
    public var argv: [String]
    public var env: [String: String]
    public var install: String?

    public static let portPlaceholder = "{port}"
}

struct CompressorVariantEntry: Codable, Sendable {
    var url: String?
    var url_env: String?
    var url_arg: String?
    var default_args: [String]?
    var upstream: [String]?
    var upstream_strip: String?
    var blocked_env: [String]?
}

struct CompressorEntry: Codable, Sendable {
    var name: String?
    var cmd: String?
    var args: [String]?
    var env: [String: String]?
    var install: String?
    var `for`: [String: CompressorVariantEntry]?
    var enabled: Bool?

    func resolved(id: String) throws -> CompressorDefinition {
        let section = "compressors.\(id)"
        guard let cmd, !cmd.isEmpty else { throw ConfigError.missingField(section: section, field: "cmd") }
        var variants: [String: CompressorVariant] = [:]
        for (agent, v) in self.for ?? [:] {
            let sub = "\(section).for.\(agent)"
            guard let url = v.url, !url.isEmpty else { throw ConfigError.missingField(section: sub, field: "url") }
            if let pattern = v.url_arg, (try? NSRegularExpression(pattern: pattern)) == nil {
                throw ConfigError.invalidRegex(section: sub, field: "url_arg", pattern: pattern)
            }
            guard v.url_env != nil || v.url_arg != nil || !(v.default_args ?? []).isEmpty else {
                throw ConfigError.missingField(section: sub, field: "url_env, url_arg ou default_args")
            }
            variants[agent] = CompressorVariant(
                url: url, urlEnv: v.url_env, urlArg: v.url_arg, defaultArgs: v.default_args ?? [],
                upstream: v.upstream ?? [], upstreamStrip: v.upstream_strip, blockedEnv: v.blocked_env ?? []
            )
        }
        return CompressorDefinition(
            id: id, name: name ?? id, cmd: cmd, args: args ?? [], env: env ?? [:],
            install: install, variants: variants
        )
    }
}

struct CompressorsFile: Codable {
    var compressors: [String: CompressorEntry]?
}

extension LaunchPlan {
    /// Aponta o agente para o proxy do compressor e monta o comando do proxy.
    ///
    /// O destino (a URL que o provider usaria) sai do ambiente ou dos argumentos
    /// já montados e passa para o proxy. Sem destino, o proxy usa o padrão dele.
    mutating func route(through compressor: CompressorDefinition, agent: AgentDefinition, cmdTokens: Int) throws {
        guard let v = compressor.variants[agent.id] else {
            throw ConfigError.compressorNotForAgent(compressor: compressor.id, agent: agent.id)
        }
        if let blocked = v.blockedEnv.first(where: { env[$0] != nil }) {
            throw ConfigError.compressorBlocked(compressor: compressor.id, variable: blocked)
        }

        var upstream: String?
        var routed = false

        if let name = v.urlEnv {
            if case .literal(let current)? = env[name], !current.isEmpty { upstream = current }
            env[name] = .literal(v.url)
            routed = true
        }

        if let pattern = v.urlArg, let regex = try? NSRegularExpression(pattern: "^(\(pattern))=\"?(.*?)\"?$") {
            for (i, arg) in argv.enumerated() {
                let ns = arg as NSString
                guard let m = regex.firstMatch(in: arg, range: NSRange(location: 0, length: ns.length)) else { continue }
                upstream = ns.substring(with: m.range(at: m.numberOfRanges - 1))
                argv[i] = "\(ns.substring(with: m.range(at: 1)))=\"\(v.url)\""
                routed = true
            }
        }

        if !routed {
            let extra = v.defaultArgs.map { $0.replacingOccurrences(of: "{url}", with: v.url) }
            argv.insert(contentsOf: extra, at: min(cmdTokens, argv.count))
        }

        var proxyArgv = compressor.cmd.split(separator: " ").map(String.init) + compressor.args
        if var target = upstream {
            while target.hasSuffix("/") { target.removeLast() }
            if let strip = v.upstreamStrip, !strip.isEmpty, target.hasSuffix(strip) {
                target.removeLast(strip.count)
            }
            proxyArgv += v.upstream.map { $0.replacingOccurrences(of: "{upstream}", with: target) }
        }
        proxy = ProxyLaunch(id: compressor.id, name: compressor.name, argv: proxyArgv,
                            env: compressor.env, install: compressor.install)
    }

    /// Troca `{port}` pela porta escolhida, no agente e no proxy.
    public func binding(port: Int) -> LaunchPlan {
        guard var p = proxy else { return self }
        let token = ProxyLaunch.portPlaceholder
        let fill: (String) -> String = { $0.replacingOccurrences(of: token, with: String(port)) }
        var copy = self
        copy.argv = argv.map(fill)
        copy.env = env.mapValues { value in
            if case .literal(let text) = value { return .literal(fill(text)) }
            return value
        }
        p.argv = p.argv.map(fill)
        copy.proxy = p
        return copy
    }
}
