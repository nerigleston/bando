import Foundation

/// Como o worktree de um membro da equipe é criado.
public enum WorktreePolicy: String, Codable, Sendable, CaseIterable {
    /// Cria um worktree e branch próprios para o membro (padrão).
    case isolated
    /// Compartilha o worktree do orquestrador ou de outro nó da equipe.
    case shared

    public var label: String {
        switch self {
        case .isolated: "Worktree próprio"
        case .shared: "Worktree compartilhado"
        }
    }
}

/// Tipo de ligação direcionada entre dois nós da equipe no Canvas.
public enum TeamEdgeKind: String, Codable, Sendable, CaseIterable {
    /// O nó de origem (ex.: orquestrador) pode delegar tarefas e conversar com o destino.
    case delegate
    /// O nó de destino aguarda a conclusão do nó de origem (`dependsOn`).
    case sequence
    /// O destino aguarda a origem e recebe resumo/handoff automático ao iniciar.
    case handoff

    public var label: String {
        switch self {
        case .delegate: "Delegação"
        case .sequence: "Sequência"
        case .handoff: "Handoff"
        }
    }
}

/// Sentido da última troca de informação registrada numa ligação do Canvas.
public enum TeamEdgeDirection: String, Codable, Sendable, CaseIterable {
    /// Da origem para o destino (ex.: orquestrador delegando tarefa ou handoff).
    case forward
    /// Do destino de volta para a origem (ex.: resultado retornado ou saída lida).
    case reverse
    /// Troca simultânea nos dois sentidos.
    case bidirectional
}

/// Papel pré-definido dentro de um template de equipe.
public struct TeamRoleDefinition: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var responsibilities: String
    public var agent: String?
    public var provider: String?
    public var model: String?
    public var compressor: String?
    public var isOrchestrator: Bool
    public var worktree: WorktreePolicy
    public var shareWorktreeWith: String?
    public var autoStart: Bool
    public var canvasX: Double
    public var canvasY: Double

    public init(
        id: String, name: String, responsibilities: String = "",
        agent: String? = nil, provider: String? = nil, model: String? = nil, compressor: String? = nil,
        isOrchestrator: Bool = false, worktree: WorktreePolicy = .isolated, shareWorktreeWith: String? = nil,
        autoStart: Bool = true, canvasX: Double = 100, canvasY: Double = 100
    ) {
        self.id = id
        self.name = name
        self.responsibilities = responsibilities
        self.agent = agent
        self.provider = provider
        self.model = model
        self.compressor = compressor
        self.isOrchestrator = isOrchestrator
        self.worktree = worktree
        self.shareWorktreeWith = shareWorktreeWith
        self.autoStart = autoStart
        self.canvasX = canvasX
        self.canvasY = canvasY
    }
}

/// Conexão entre papéis em um template de equipe.
public struct TeamEdgeDefinition: Sendable, Equatable {
    public var fromRole: String
    public var toRole: String
    public var kind: TeamEdgeKind

    public init(fromRole: String, toRole: String, kind: TeamEdgeKind) {
        self.fromRole = fromRole
        self.toRole = toRole
        self.kind = kind
    }
}

/// Template reutilizável de equipe (de `catalog/teams.toml`, `~/.config/bando/teams.toml`
/// ou `.bando/teams.toml` do projeto).
public struct TeamTemplate: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var description: String?
    public var roles: [TeamRoleDefinition]
    public var edges: [TeamEdgeDefinition]

    public init(id: String, name: String, description: String? = nil, roles: [TeamRoleDefinition], edges: [TeamEdgeDefinition] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.roles = roles
        self.edges = edges
    }
}

// MARK: - Decodificação TOML (mescla campo a campo)

struct TeamRoleEntry: Codable, Sendable {
    var name: String?
    var responsibilities: String?
    var agent: String?
    var provider: String?
    var model: String?
    var compressor: String?
    var isOrchestrator: Bool?
    var worktree: WorktreePolicy?
    var shareWorktreeWith: String?
    var autoStart: Bool?
    var canvasX: Double?
    var canvasY: Double?

    enum CodingKeys: String, CodingKey {
        case name, responsibilities, agent, provider, model, compressor, worktree
        case isOrchestrator = "is_orchestrator"
        case shareWorktreeWith = "share_worktree_with"
        case autoStart = "auto_start"
        case canvasX = "canvas_x"
        case canvasY = "canvas_y"
    }

    init(
        name: String? = nil, responsibilities: String? = nil, agent: String? = nil,
        provider: String? = nil, model: String? = nil, compressor: String? = nil,
        isOrchestrator: Bool? = nil, worktree: WorktreePolicy? = nil,
        shareWorktreeWith: String? = nil, autoStart: Bool? = nil,
        canvasX: Double? = nil, canvasY: Double? = nil
    ) {
        self.name = name
        self.responsibilities = responsibilities
        self.agent = agent
        self.provider = provider
        self.model = model
        self.compressor = compressor
        self.isOrchestrator = isOrchestrator
        self.worktree = worktree
        self.shareWorktreeWith = shareWorktreeWith
        self.autoStart = autoStart
        self.canvasX = canvasX
        self.canvasY = canvasY
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        responsibilities = try c.decodeIfPresent(String.self, forKey: .responsibilities)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        compressor = try c.decodeIfPresent(String.self, forKey: .compressor)
        isOrchestrator = try c.decodeIfPresent(Bool.self, forKey: .isOrchestrator)
        worktree = try c.decodeIfPresent(WorktreePolicy.self, forKey: .worktree)
        shareWorktreeWith = try c.decodeIfPresent(String.self, forKey: .shareWorktreeWith)
        autoStart = try c.decodeIfPresent(Bool.self, forKey: .autoStart)
        canvasX = Self.decodeNumber(c, forKey: .canvasX)
        canvasY = Self.decodeNumber(c, forKey: .canvasY)
    }

    private static func decodeNumber(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        return nil
    }

    func merged(with o: TeamRoleEntry) -> TeamRoleEntry {
        TeamRoleEntry(
            name: o.name ?? name,
            responsibilities: o.responsibilities ?? responsibilities,
            agent: o.agent ?? agent,
            provider: o.provider ?? provider,
            model: o.model ?? model,
            compressor: o.compressor ?? compressor,
            isOrchestrator: o.isOrchestrator ?? isOrchestrator,
            worktree: o.worktree ?? worktree,
            shareWorktreeWith: o.shareWorktreeWith ?? shareWorktreeWith,
            autoStart: o.autoStart ?? autoStart,
            canvasX: o.canvasX ?? canvasX,
            canvasY: o.canvasY ?? canvasY
        )
    }

    func resolved(id: String, index: Int) -> TeamRoleDefinition {
        TeamRoleDefinition(
            id: id,
            name: name ?? id,
            responsibilities: responsibilities ?? "",
            agent: agent?.isEmpty == true ? nil : agent,
            provider: provider?.isEmpty == true ? nil : provider,
            model: model?.isEmpty == true ? nil : model,
            compressor: compressor?.isEmpty == true ? nil : compressor,
            isOrchestrator: isOrchestrator ?? false,
            worktree: worktree ?? .isolated,
            shareWorktreeWith: shareWorktreeWith?.isEmpty == true ? nil : shareWorktreeWith,
            autoStart: autoStart ?? true,
            canvasX: canvasX ?? Double(100 + (index % 3) * 380),
            canvasY: canvasY ?? Double(100 + (index / 3) * 260)
        )
    }
}

struct TeamEdgeEntry: Codable, Sendable {
    var from: String?
    var to: String?
    var kind: TeamEdgeKind?
}

struct TeamEntry: Codable, Sendable {
    var name: String?
    var description: String?
    var roles: [String: TeamRoleEntry]?
    var edges: [TeamEdgeEntry]?
    var enabled: Bool?

    func merged(with o: TeamEntry) -> TeamEntry {
        var mergedRoles = roles ?? [:]
        for (rid, rEntry) in o.roles ?? [:] {
            mergedRoles[rid] = mergedRoles[rid].map { $0.merged(with: rEntry) } ?? rEntry
        }
        return TeamEntry(
            name: o.name ?? name,
            description: o.description ?? description,
            roles: mergedRoles.isEmpty ? nil : mergedRoles,
            edges: o.edges ?? edges,
            enabled: o.enabled ?? enabled
        )
    }

    func resolved(id: String) throws -> TeamTemplate {
        let section = "teams.\(id)"
        guard id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw ConfigError.invalidValue(section: section, field: "id", detail: "use só letras, números, - e _")
        }
        let rawRoles = roles ?? [:]
        guard !rawRoles.isEmpty else {
            throw ConfigError.missingField(section: section, field: "roles")
        }
        // Orquestrador vem primeiro, depois ordem alfabética pelo id do papel.
        let orderedIds = rawRoles.keys.sorted { a, b in
            let oa = rawRoles[a]?.isOrchestrator == true ? 0 : 1
            let ob = rawRoles[b]?.isOrchestrator == true ? 0 : 1
            return (oa, a) < (ob, b)
        }
        let resolvedRoles = orderedIds.enumerated().map { idx, rid in
            rawRoles[rid]!.resolved(id: rid, index: idx)
        }
        let roleSet = Set(orderedIds)
        var resolvedEdges: [TeamEdgeDefinition] = []
        for e in edges ?? [] {
            guard let from = e.from, let to = e.to else {
                throw ConfigError.missingField(section: "\(section).edges", field: "from/to")
            }
            guard roleSet.contains(from) else { throw ConfigError.unknownRole(team: id, role: from) }
            guard roleSet.contains(to) else { throw ConfigError.unknownRole(team: id, role: to) }
            guard from != to else {
                throw ConfigError.invalidValue(section: "\(section).edges", field: "to", detail: "papel não pode ligar para si mesmo")
            }
            resolvedEdges.append(TeamEdgeDefinition(fromRole: from, toRole: to, kind: e.kind ?? .delegate))
        }
        return TeamTemplate(
            id: id,
            name: name ?? id,
            description: description,
            roles: resolvedRoles,
            edges: resolvedEdges
        )
    }
}

struct TeamsFile: Codable {
    var teams: [String: TeamEntry]?
}

// MARK: - Serialização TOML (salvar templates pela UI)

public enum TeamTemplateTOML {
    /// Gera um bloco TOML válido para `[teams.<id>]`.
    public static func render(_ team: TeamTemplate) -> String {
        var lines: [String] = []
        lines.append("[teams.\(bareKey(team.id))]")
        lines.append("name = \(quote(team.name))")
        if let desc = team.description, !desc.isEmpty {
            lines.append("description = \(quote(desc))")
        }
        for role in team.roles {
            lines.append("")
            lines.append("[teams.\(bareKey(team.id)).roles.\(bareKey(role.id))]")
            lines.append("name = \(quote(role.name))")
            if role.isOrchestrator { lines.append("is_orchestrator = true") }
            if let agent = role.agent, !agent.isEmpty { lines.append("agent = \(quote(agent))") }
            if let provider = role.provider, !provider.isEmpty { lines.append("provider = \(quote(provider))") }
            if let model = role.model, !model.isEmpty { lines.append("model = \(quote(model))") }
            if let comp = role.compressor, !comp.isEmpty { lines.append("compressor = \(quote(comp))") }
            lines.append("worktree = \(quote(role.worktree.rawValue))")
            if let share = role.shareWorktreeWith, !share.isEmpty { lines.append("share_worktree_with = \(quote(share))") }
            if !role.autoStart { lines.append("auto_start = false") }
            lines.append("canvas_x = \(Int(role.canvasX.rounded()))")
            lines.append("canvas_y = \(Int(role.canvasY.rounded()))")
            if !role.responsibilities.isEmpty {
                lines.append("responsibilities = \(quote(role.responsibilities))")
            }
        }
        for edge in team.edges {
            lines.append("")
            lines.append("[[teams.\(bareKey(team.id)).edges]]")
            lines.append("from = \(quote(edge.fromRole))")
            lines.append("to = \(quote(edge.toRole))")
            lines.append("kind = \(quote(edge.kind.rawValue))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Salva ou substitui o bloco `[teams.<id>]` no arquivo alvo, preservando outros times.
    public static func upsert(_ team: TeamTemplate, into fileURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let stripped = removingSection(id: team.id, from: existing)
        let sep = stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : (stripped.hasSuffix("\n\n") ? "" : (stripped.hasSuffix("\n") ? "\n" : "\n\n"))
        let result = stripped + sep + render(team)
        try result.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func removingSection(id: String, from content: String) -> String {
        let prefix = "[teams.\(id)]"
        let subPrefix = "[teams.\(id)."
        let arrayPrefix = "[[teams.\(id)."
        var out: [String] = []
        var skipping = false
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                if trimmed == prefix || trimmed.hasPrefix(subPrefix) || trimmed.hasPrefix(arrayPrefix) {
                    skipping = true
                    continue
                } else {
                    skipping = false
                }
            }
            if !skipping { out.append(String(rawLine)) }
        }
        while out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast() }
        return out.isEmpty ? "" : out.joined(separator: "\n") + "\n"
    }

    private static func bareKey(_ s: String) -> String {
        s.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil ? s : quote(s)
    }

    private static func quote(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
