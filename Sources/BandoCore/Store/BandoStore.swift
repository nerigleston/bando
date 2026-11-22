import Foundation
import GRDB

/// Banco do Bando (SQLite em WAL). App e CLI abrem o mesmo arquivo; depois de
/// gravar, avisam os outros processos com `ChangeNotifier.post()`.
public final class BandoStore: Sendable {
    public let pool: DatabasePool
    public let paths: BandoPaths

    public init(paths: BandoPaths = .standard()) throws {
        self.paths = paths
        try FileManager.default.createDirectory(at: paths.stateDir, withIntermediateDirectories: true)
        var config = Configuration()
        // Outro processo pode estar escrevendo; espera em vez de falhar.
        config.busyMode = .timeout(5)
        config.foreignKeysEnabled = true
        let dbPath = paths.database.path
        let isNew = !FileManager.default.fileExists(atPath: dbPath)
        if !isNew { try Self.backupBeforeMigrating(paths: paths) }
        pool = try DatabasePool(path: dbPath, configuration: config)
        try Self.migrator.migrate(pool)
    }

    // MARK: - Migrações

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "project") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("path", .text).notNull().unique()
                t.column("defaultAgent", .text)
                t.column("defaultProvider", .text)
                t.column("baseBranch", .text)
                t.column("setupScript", .text)
                t.column("worktreeRoot", .text)
                t.column("xirpId", .text).unique()
                t.column("createdAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime)
            }
            try db.create(table: "session") { t in
                t.primaryKey("id", .text)
                t.belongsTo("project", onDelete: .cascade).notNull()
                t.column("name", .text).notNull()
                t.column("prompt", .text)
                t.column("agent", .text).notNull()
                t.column("provider", .text)
                t.column("model", .text)
                t.column("worktreePath", .text).notNull()
                t.column("branch", .text)
                t.column("baseBranch", .text)
                t.column("usesWorktree", .boolean).notNull()
                t.column("tmuxName", .text).notNull()
                t.column("tmuxServer", .text).notNull().defaults(to: "bando")
                t.column("nativeId", .text)
                t.column("status", .text).notNull().indexed()
                t.column("statusDetail", .text)
                t.column("exitCode", .integer)
                t.column("dependsOn", .text).references("session", onDelete: .setNull)
                t.column("xirpId", .text).unique()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("statusChangedAt", .datetime).notNull()
                t.column("finishedAt", .datetime)
                t.column("seenAt", .datetime)
            }
            try db.create(table: "event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .text).notNull().references("session", onDelete: .cascade).indexed()
                t.column("kind", .text).notNull()
                t.column("status", .text)
                t.column("detail", .text)
                t.column("at", .datetime).notNull().indexed()
            }
            try db.create(table: "usage") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .text).references("session", onDelete: .setNull).indexed()
                t.column("agent", .text)
                t.column("provider", .text)
                t.column("model", .text)
                t.column("inputTokens", .integer).notNull().defaults(to: 0)
                t.column("outputTokens", .integer).notNull().defaults(to: 0)
                t.column("cacheRead", .integer).notNull().defaults(to: 0)
                t.column("cacheWrite", .integer).notNull().defaults(to: 0)
                t.column("costUsd", .double).notNull().defaults(to: 0)
                t.column("at", .datetime).notNull().indexed()
                t.column("sourceKey", .text).unique()
            }
            try db.create(table: "pullRequest") { t in
                t.primaryKey("id", .text)
                t.column("sessionId", .text).references("session", onDelete: .setNull)
                t.column("host", .text)
                t.column("repoOwner", .text)
                t.column("repoName", .text)
                t.column("number", .integer)
                t.column("headBranch", .text)
                t.column("state", .text)
                t.column("createdAt", .datetime)
                t.column("mergedAt", .datetime)
            }
            try db.create(table: "transcriptOffset") { t in
                t.primaryKey("path", .text)
                t.column("offset", .integer).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        m.registerMigration("v2-pin-hide") { db in
            try db.alter(table: "session") { t in
                t.add(column: "pinned", .boolean).notNull().defaults(to: false)
                t.add(column: "hidden", .boolean).notNull().defaults(to: false)
            }
        }
        m.registerMigration("v3-usage-match-index") { db in
            // Casamento de registros do Xirp com respostas do transcript.
            try db.create(index: "usage_output_at", on: "usage", columns: ["outputTokens", "at"])
        }
        // A pasta pessoal (sessões fora de repositório, vindas do Xirp ou não)
        // aparece como "Geral", não com o nome do usuário.
        m.registerMigration("v4-general-project") { db in
            try db.execute(sql: "UPDATE project SET name = ? WHERE path = ?",
                           arguments: [Project.generalName, Project.generalPath])
        }
        // Nome escolhido pelo usuário fica marcado para o título automático não trocar.
        m.registerMigration("v5-custom-name") { db in
            try db.alter(table: "session") { t in t.add(column: "customName", .boolean).notNull().defaults(to: false) }
        }
        // Compressor opcional por sessão (proxy local iniciado pelo `bando run`).
        m.registerMigration("v6-compressor") { db in
            try db.alter(table: "session") { t in t.add(column: "compressor", .text) }
        }
        // Modo orquestrador multi-agente: equipes, ligações no canvas e papéis por sessão.
        m.registerMigration("v7-teams") { db in
            try db.create(table: "team") { t in
                t.primaryKey("id", .text)
                t.belongsTo("project", onDelete: .cascade).notNull()
                t.column("name", .text).notNull()
                t.column("goal", .text)
                t.column("templateId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "teamEdge") { t in
                t.primaryKey("id", .text)
                t.column("teamId", .text).notNull().references("team", onDelete: .cascade).indexed()
                t.column("fromSessionId", .text).notNull().references("session", onDelete: .cascade)
                t.column("toSessionId", .text).notNull().references("session", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("label", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.alter(table: "session") { t in
                t.add(column: "teamId", .text).references("team", onDelete: .setNull).indexed()
                t.add(column: "roleId", .text)
                t.add(column: "roleTitle", .text)
                t.add(column: "responsibilities", .text)
                t.add(column: "isOrchestrator", .boolean).notNull().defaults(to: false)
                t.add(column: "worktreeSourceId", .text)
                t.add(column: "canvasX", .double)
                t.add(column: "canvasY", .double)
            }
        }
        // Tamanho personalizado dos cartões no Canvas (largura e altura).
        m.registerMigration("v8-canvas-size") { db in
            try db.alter(table: "session") { t in
                t.add(column: "canvasWidth", .double)
                t.add(column: "canvasHeight", .double)
            }
        }
        // Rastreamento de interações e sentido da troca nas ligações do Canvas.
        m.registerMigration("v9-edge-activity") { db in
            try db.alter(table: "teamEdge") { t in
                t.add(column: "lastDirection", .text)
                t.add(column: "lastActivityAt", .datetime)
                t.add(column: "interactionCount", .integer).notNull().defaults(to: 0)
            }
        }
        return m
    }

    /// Copia o banco antes de aplicar migrações novas (mantém os 5 últimos).
    static func backupBeforeMigrating(paths: BandoPaths) throws {
        let queue = try DatabaseQueue(path: paths.database.path)
        let pending = try queue.read { db in try !migrator.hasCompletedMigrations(db) }
        try queue.close()
        guard pending else { return }
        let dir = paths.stateDir.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try FileManager.default.copyItem(at: paths.database, to: dir.appendingPathComponent("bando-\(stamp).sqlite"))
        let old = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("bando-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for url in old.dropFirst(5) { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Consultas comuns

    public func projects() throws -> [Project] {
        try pool.read { db in try Project.order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db) }
    }

    public func sessions(includeFinished: Bool = true) throws -> [Session] {
        try pool.read { db in
            var q = Session.all()
            if !includeFinished {
                q = q.filter(![SessionStatus.exited.rawValue, SessionStatus.stopped.rawValue].contains(Column("status")))
            }
            return try q.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public func session(_ id: String) throws -> Session? {
        try pool.read { db in try Session.fetchOne(db, key: id) }
    }

    public func project(_ id: String) throws -> Project? {
        try pool.read { db in try Project.fetchOne(db, key: id) }
    }

    /// Acha a sessão por ID completo, prefixo do ID ou nome exato.
    public func findSession(_ ref: String) throws -> Session {
        let all = try sessions()
        if let s = all.first(where: { $0.id == ref }) { return s }
        let byName = all.filter { $0.name == ref }
        if byName.count == 1 { return byName[0] }
        let byPrefix = all.filter { $0.id.hasPrefix(ref.lowercased()) }
        if byPrefix.count == 1 { return byPrefix[0] }
        if byName.count + byPrefix.count > 1 { throw BandoError.ambiguous(ref) }
        throw BandoError.notFound("sessão \(ref)")
    }

    public func events(sessionId: String) throws -> [SessionEvent] {
        try pool.read { db in
            try SessionEvent.filter(Column("sessionId") == sessionId).order(Column("at")).fetchAll(db)
        }
    }

    public func events(forSessionIds sessionIds: [String], kinds: [String]? = nil, limit: Int = 50) throws -> [SessionEvent] {
        guard !sessionIds.isEmpty else { return [] }
        return try pool.read { db in
            var query = SessionEvent.filter(sessionIds.contains(Column("sessionId")))
            if let kinds, !kinds.isEmpty {
                query = query.filter(kinds.contains(Column("kind")))
            }
            return try query.order(Column("at").desc, Column("id").desc).limit(limit).fetchAll(db)
        }
    }

    // MARK: - Equipes

    public func teams(projectId: String? = nil) throws -> [TeamRecord] {
        try pool.read { db in
            var q = TeamRecord.all()
            if let projectId { q = q.filter(Column("projectId") == projectId) }
            return try q.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    public func team(_ id: String) throws -> TeamRecord? {
        try pool.read { db in try TeamRecord.fetchOne(db, key: id) }
    }

    public func findTeam(_ ref: String) throws -> TeamRecord {
        let all = try teams()
        if let t = all.first(where: { $0.id == ref }) { return t }
        let byName = all.filter { $0.name.localizedCaseInsensitiveCompare(ref) == .orderedSame }
        if byName.count == 1 { return byName[0] }
        let byPrefix = all.filter { $0.id.hasPrefix(ref.lowercased()) }
        if byPrefix.count == 1 { return byPrefix[0] }
        if byName.count + byPrefix.count > 1 { throw BandoError.ambiguous(ref) }
        throw BandoError.notFound("equipe \(ref)")
    }

    public func sessions(inTeam teamId: String) throws -> [Session] {
        try pool.read { db in
            try Session.filter(Column("teamId") == teamId)
                .order(Column("isOrchestrator").desc, Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func edges(inTeam teamId: String) throws -> [TeamEdgeRecord] {
        try pool.read { db in
            try TeamEdgeRecord.filter(Column("teamId") == teamId).order(Column("createdAt").asc).fetchAll(db)
        }
    }

    public func allTeamEdges() throws -> [TeamEdgeRecord] {
        try pool.read { db in try TeamEdgeRecord.order(Column("createdAt").asc).fetchAll(db) }
    }
}

public enum BandoError: Error, LocalizedError, Equatable {
    case notFound(String)
    case ambiguous(String)
    case notGitRepository(String)
    case command(String, String)
    case unsafeDelete(String)
    case tmuxMissing
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let what): "Não encontrado: \(what)"
        case .ambiguous(let ref): "\"\(ref)\" corresponde a mais de uma sessão; use mais caracteres do ID"
        case .notGitRepository(let path): "\(path) não é um repositório git (use --no-worktree para rodar sem worktree)"
        case .command(let cmd, let out): "Falhou: \(cmd)\n\(out)"
        case .unsafeDelete(let why): "Não apaguei: \(why). Use --force para apagar mesmo assim."
        case .tmuxMissing: "tmux não encontrado. Instale com: brew install tmux"
        case .invalid(let why): why
        }
    }
}
