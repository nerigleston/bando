import Foundation
import GRDB

/// Estado de uma sessão. A ordem de `urgency` define a lateral do app.
public enum SessionStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    /// Esperando outra sessão terminar (`depends_on`).
    case queued
    case starting
    case working
    /// Pedindo permissão ou resposta.
    case waiting
    /// Terminou a vez e há mudanças no worktree que você ainda não viu.
    case review
    /// Terminou a vez sem mudança nova.
    case idle
    /// Parada pelo usuário (o tmux foi encerrado).
    case stopped
    /// O agente saiu com código 0.
    case exited
    /// O agente saiu com erro ou não conseguiu iniciar.
    case error

    /// Sessão com processo vivo no tmux.
    public var isLive: Bool {
        switch self {
        case .starting, .working, .waiting, .review, .idle: true
        default: false
        }
    }

    /// Para a fila: a sessão pai "terminou" quando concluiu a primeira vez.
    public var releasesDependents: Bool {
        switch self {
        case .review, .idle, .exited, .stopped: true
        default: false
        }
    }

    public var label: String {
        switch self {
        case .queued: "na fila"
        case .starting: "iniciando"
        case .working: "trabalhando"
        case .waiting: "esperando você"
        case .review: "pronto para revisar"
        case .idle: "ocioso"
        case .stopped: "parado"
        case .exited: "encerrado"
        case .error: "erro"
        }
    }

    /// Menor = mais urgente.
    public var urgency: Int {
        switch self {
        case .waiting: 0
        case .error: 1
        case .review: 2
        case .working, .starting: 3
        case .queued: 4
        case .idle: 5
        case .stopped, .exited: 6
        }
    }
}

public struct Project: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "project"

    /// Pasta pessoal: sessões abertas fora de um repositório ficam no projeto
    /// "Geral", que aponta para ela (sem worktree).
    public static var generalPath: String { URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path }
    public static let generalName = "Geral"
    public var isGeneral: Bool { path == Project.generalPath }

    public var id: String
    public var name: String
    public var path: String
    public var defaultAgent: String?
    public var defaultProvider: String?
    public var baseBranch: String?
    /// Roda no worktree novo antes do agente (copiar .env, instalar dependências).
    public var setupScript: String?
    /// Pasta dos worktrees; nil = `<pai>/.bando-worktrees/<repo>`.
    public var worktreeRoot: String?
    public var xirpId: String?
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(id: String = UUID().uuidString.lowercased(), name: String, path: String,
                defaultAgent: String? = nil, defaultProvider: String? = nil, baseBranch: String? = nil,
                setupScript: String? = nil, worktreeRoot: String? = nil, xirpId: String? = nil,
                createdAt: Date = Date(), lastUsedAt: Date? = nil) {
        self.id = id; self.name = name; self.path = path
        self.defaultAgent = defaultAgent; self.defaultProvider = defaultProvider
        self.baseBranch = baseBranch; self.setupScript = setupScript; self.worktreeRoot = worktreeRoot
        self.xirpId = xirpId; self.createdAt = createdAt; self.lastUsedAt = lastUsedAt
    }
}

public struct Session: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "session"

    public var id: String
    public var projectId: String
    public var name: String
    public var prompt: String?
    public var agent: String
    public var provider: String?
    public var model: String?
    public var worktreePath: String
    public var branch: String?
    public var baseBranch: String?
    public var usesWorktree: Bool
    public var tmuxName: String
    /// Servidor tmux: "bando" (próprio) ou "default" (sessão adotada do Xirp).
    public var tmuxServer: String
    /// ID da conversa no agente, para retomar.
    public var nativeId: String?
    public var status: SessionStatus
    public var statusDetail: String?
    public var exitCode: Int?
    public var dependsOn: String?
    public var xirpId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var statusChangedAt: Date
    public var finishedAt: Date?
    /// Momento em que o usuário viu a sessão por último (limpa `review`).
    public var seenAt: Date?
    /// Fixada no topo da lateral.
    public var pinned: Bool = false
    /// Escondida da lateral (continua existindo e aparece na busca).
    public var hidden: Bool = false

    public init(id: String = UUID().uuidString.lowercased(), projectId: String, name: String, prompt: String?,
                agent: String, provider: String?, model: String?, worktreePath: String, branch: String?,
                baseBranch: String?, usesWorktree: Bool, tmuxName: String, tmuxServer: String = "bando",
                nativeId: String? = nil, status: SessionStatus, dependsOn: String? = nil, xirpId: String? = nil,
                createdAt: Date = Date()) {
        self.id = id; self.projectId = projectId; self.name = name; self.prompt = prompt
        self.agent = agent; self.provider = provider; self.model = model
        self.worktreePath = worktreePath; self.branch = branch; self.baseBranch = baseBranch
        self.usesWorktree = usesWorktree; self.tmuxName = tmuxName; self.tmuxServer = tmuxServer
        self.nativeId = nativeId; self.status = status; self.dependsOn = dependsOn; self.xirpId = xirpId
        self.createdAt = createdAt; self.updatedAt = createdAt; self.statusChangedAt = createdAt
    }

    public var shortId: String { String(id.prefix(8)) }
}

/// Histórico: cada mudança de estado e cada hook. É a base dos relatórios.
public struct SessionEvent: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "event"

    public var id: Int64?
    public var sessionId: String
    public var kind: String
    public var status: SessionStatus?
    public var detail: String?
    public var at: Date

    public init(sessionId: String, kind: String, status: SessionStatus? = nil, detail: String? = nil, at: Date = Date()) {
        self.sessionId = sessionId; self.kind = kind; self.status = status; self.detail = detail; self.at = at
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Tokens e custo (importados do Xirp ou lidos dos transcripts).
public struct UsageRecord: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "usage"

    public var id: Int64?
    public var sessionId: String?
    public var agent: String?
    public var provider: String?
    public var model: String?
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public var costUsd: Double
    public var at: Date
    /// Chave de deduplicação (ex.: "xirp:<id>").
    public var sourceKey: String?

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct PullRequestRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pullRequest"

    public var id: String
    public var sessionId: String?
    public var host: String?
    public var repoOwner: String?
    public var repoName: String?
    public var number: Int?
    public var headBranch: String?
    public var state: String?
    public var createdAt: Date?
    public var mergedAt: Date?
}
