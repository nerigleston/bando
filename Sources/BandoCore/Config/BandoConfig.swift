import Foundation
import TOMLKit

/// Agentes e providers resolvidos: presets embutidos + arquivos do usuário.
///
/// Regra de atualização: o app só troca os presets (que vivem no binário).
/// Os arquivos do usuário nunca são sobrescritos pelo app numa atualização, e
/// a mescla é campo a campo, então correções nos presets chegam sem apagar o
/// que o usuário mudou.
public struct BandoConfig: Sendable {
    public var agents: [String: AgentDefinition]
    public var providers: [String: ProviderDefinition]
    public var themes: [String: ThemeDefinition] = [:]
    public var mcp: [String: McpServer] = [:]
    /// Entradas puladas por erro, para mostrar na tela e no `bando doctor`.
    public var issues: [ConfigIssue] = []
    /// IDs que aparecem no arquivo do usuário (adicionados ou personalizados).
    public var userAgentIds: Set<String> = []
    public var userProviderIds: Set<String> = []
    public var userThemeIds: Set<String> = []

    public var sortedThemes: [ThemeDefinition] {
        themes.values.sorted { ($0.appearance.rawValue, $0.name) < ($1.appearance.rawValue, $1.name) }
    }

    public static let defaultDarkTheme = "bando-escuro"
    public static let defaultLightTheme = "bando-claro"

    public init(agents: [String: AgentDefinition], providers: [String: ProviderDefinition]) {
        self.agents = agents
        self.providers = providers
    }

    public var sortedAgents: [AgentDefinition] {
        agents.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var sortedProviders: [ProviderDefinition] {
        providers.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func agent(_ id: String) throws -> AgentDefinition {
        guard let a = agents[id] else { throw ConfigError.unknownAgent(id) }
        return a
    }

    public func provider(_ id: String) throws -> ProviderDefinition {
        guard let p = providers[id] else { throw ConfigError.unknownProvider(id) }
        return p
    }

    public func providers(for agent: String) -> [ProviderDefinition] {
        sortedProviders.filter { $0.supports(agent: agent) }
    }

    /// Carrega presets e, se existirem, os arquivos do usuário.
    public static func load(paths: BandoPaths = .standard()) throws -> BandoConfig {
        try load(
            userAgents: try readIfExists(paths.agentsFile),
            userProviders: try readIfExists(paths.providersFile),
            userThemes: try readIfExists(paths.themesFile),
            userMcp: try readIfExists(paths.mcpFile),
            agentsFileName: paths.agentsFile.path,
            providersFileName: paths.providersFile.path,
            themesFileName: paths.themesFile.path
        )
    }

    /// Versão sem disco, usada nos testes e na tela de configurações
    /// (para validar o texto antes de salvar).
    public static func load(
        userAgents: String?,
        userProviders: String?,
        userThemes: String? = nil,
        userMcp: String? = nil,
        agentsFileName: String = "agents.toml",
        providersFileName: String = "providers.toml",
        themesFileName: String = "themes.toml"
    ) throws -> BandoConfig {
        let presetAgents = try decode(AgentsFile.self, Presets.agents, file: "presets/agents.toml").agents ?? [:]
        let presetProviders = try decode(ProvidersFile.self, Presets.providers, file: "presets/providers.toml").providers ?? [:]

        let userA = try userAgents.map { try decode(AgentsFile.self, $0, file: agentsFileName).agents ?? [:] } ?? [:]
        let userP = try userProviders.map { try decode(ProvidersFile.self, $0, file: providersFileName).providers ?? [:] } ?? [:]

        // Uma entrada com problema vira aviso e é pulada. O resto continua
        // funcionando, inclusive depois de uma atualização que mude ou remova
        // um preset que o usuário tinha personalizado.
        var issues: [ConfigIssue] = []

        var agents: [String: AgentDefinition] = [:]
        for id in Set(presetAgents.keys).union(userA.keys).sorted() {
            let base = presetAgents[id] ?? AgentEntry()
            let entry = userA[id].map { base.merged(with: $0) } ?? base
            if entry.enabled == false { continue }
            do {
                agents[id] = try entry.resolved(id: id)
            } catch {
                issues.append(ConfigIssue(
                    section: "agents.\(id)",
                    message: error.localizedDescription,
                    origin: presetAgents[id] == nil ? .user : (userA[id] == nil ? .preset : .both)
                ))
            }
        }

        var providers: [String: ProviderDefinition] = [:]
        for id in Set(presetProviders.keys).union(userP.keys).sorted() {
            let base = presetProviders[id] ?? ProviderEntry()
            let entry = userP[id].map { base.merged(with: $0) } ?? base
            if entry.enabled == false { continue }
            do {
                providers[id] = try entry.resolved(id: id)
            } catch {
                issues.append(ConfigIssue(
                    section: "providers.\(id)",
                    message: error.localizedDescription,
                    origin: presetProviders[id] == nil ? .user : (userP[id] == nil ? .preset : .both)
                ))
            }
        }

        let presetThemes = try decode(ThemesFile.self, Presets.themes, file: "presets/themes.toml").themes ?? [:]
        let userT = try userThemes.map { try decode(ThemesFile.self, $0, file: themesFileName).themes ?? [:] } ?? [:]
        var themes: [String: ThemeDefinition] = [:]
        for id in Set(presetThemes.keys).union(userT.keys).sorted() {
            var entry = presetThemes[id] ?? ThemeEntry()
            if let user = userT[id] {
                // "base" permite herdar de outro tema e mudar só algumas cores.
                if let base = user.base, let baseEntry = presetThemes[base] ?? userT[base] {
                    entry = baseEntry.merged(with: ThemeEntry(name: nil))
                }
                entry = entry.merged(with: user)
            }
            if entry.enabled == false { continue }
            do {
                themes[id] = try entry.resolved(id: id)
            } catch {
                issues.append(ConfigIssue(section: "themes.\(id)", message: error.localizedDescription,
                                          origin: presetThemes[id] == nil ? .user : (userT[id] == nil ? .preset : .both)))
            }
        }

        var mcp: [String: McpServer] = [:]
        if let userMcp {
            let entries = try decode(McpFile.self, userMcp, file: "mcp.toml").mcp ?? [:]
            for (id, e) in entries.sorted(by: { $0.key < $1.key }) where e.enabled != false {
                do { mcp[id] = try e.resolved(id: id) }
                catch { issues.append(ConfigIssue(section: "mcp.\(id)", message: error.localizedDescription, origin: .user)) }
            }
        }

        var config = BandoConfig(agents: agents, providers: providers)
        config.mcp = mcp
        config.themes = themes
        config.userThemeIds = Set(userT.keys)
        config.issues = issues
        config.userAgentIds = Set(userA.keys)
        config.userProviderIds = Set(userP.keys)
        return config
    }

    private static func readIfExists(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ text: String, file: String) throws -> T {
        do {
            return try TOMLDecoder().decode(T.self, from: text)
        } catch let error as TOMLParseError {
            throw ConfigError.parse(file: file, detail: "linha \(error.source.begin.line): \(error.description)")
        } catch {
            throw ConfigError.parse(file: file, detail: String(describing: error))
        }
    }
}

public struct ConfigIssue: Sendable, Equatable {
    public enum Origin: String, Sendable {
        case preset, user, both
    }
    public var section: String
    public var message: String
    public var origin: Origin
}

extension BandoConfig {
    /// Tema para a aparência atual. `preference` é "system" ou o ID de um tema.
    public func theme(preference: String, systemIsDark: Bool, light: String, dark: String) -> ThemeDefinition {
        let id = preference == "system" ? (systemIsDark ? dark : light) : preference
        return themes[id]
            ?? themes[systemIsDark ? Self.defaultDarkTheme : Self.defaultLightTheme]
            ?? themes.values.first!
    }
}

struct AgentsFile: Codable {
    var agents: [String: AgentEntry]?
}

struct ProvidersFile: Codable {
    var providers: [String: ProviderEntry]?
}
