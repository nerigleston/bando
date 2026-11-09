import Foundation
import GRDB

/// Importa projetos, sessões, custos e PRs do Xirp a partir do backup JSON
/// que ele grava em `~/Library/Application Support/Xirp/xirp-external/backups/`.
///
/// Só lê os arquivos do Xirp. Pode rodar várias vezes: usa o ID original como
/// chave e atualiza o que mudou.
public struct XirpImporter {
    public struct Report: Sendable, CustomStringConvertible {
        public var backup = ""
        public var projectsNew = 0, projectsUpdated = 0
        public var sessionsNew = 0, sessionsUpdated = 0
        public var sessionsAdopted = 0
        public var usageNew = 0
        public var pullRequests = 0
        public var skipped: [String] = []

        public var description: String {
            var lines = [
                "backup: \(backup)",
                "projetos: \(projectsNew) novos, \(projectsUpdated) atualizados",
                "sessões: \(sessionsNew) novas, \(sessionsUpdated) atualizadas, \(sessionsAdopted) rodando agora (adotadas)",
                "custo: \(usageNew) registros novos",
                "PRs: \(pullRequests)",
            ]
            if !skipped.isEmpty { lines.append("ignorados: \(skipped.count) (\(skipped.prefix(3).joined(separator: "; "))\(skipped.count > 3 ? "; ..." : ""))") }
            return lines.joined(separator: "\n")
        }
    }

    public static var defaultBackupDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Xirp/xirp-external/backups")
    }

    public static func latestBackup(in dir: URL = defaultBackupDir) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
        guard let latest = files.max(by: {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }) else { throw BandoError.notFound("backup do Xirp em \(dir.path)") }
        return latest
    }

    let store: BandoStore

    public init(store: BandoStore) { self.store = store }

    /// `sessionsOnly`: importa projetos e sessões, sem custos nem PRs (para
    /// reimportar sem trazer de volta custos já deduplicados).
    public func run(backup: URL, dryRun: Bool, sessionsOnly: Bool = false) throws -> Report {
        var report = Report(backup: backup.path)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as? [String: Any]
        guard let tables = root?["tables"] as? [String: Any] else {
            throw BandoError.invalid("Formato de backup desconhecido: \(backup.lastPathComponent)")
        }
        let projects = tables["projects"] as? [[String: Any]] ?? []
        let sessions = tables["sessions"] as? [[String: Any]] ?? []
        let costs = sessionsOnly ? [] : tables["cost_records"] as? [[String: Any]] ?? []
        let prs = sessionsOnly ? [] : tables["session_pr_outcomes"] as? [[String: Any]] ?? []

        // Sessões tmux do Xirp rodando agora, no servidor padrão do usuário.
        let liveXirp = Set((try? Tmux(server: "default"))?.listSessions().filter { $0.hasPrefix("xirp-") } ?? [])

        let work: (Database) throws -> Void = { db in
            var projectMap: [String: String] = [:]  // id do Xirp → id do Bando

            for p in projects {
                guard let xid = p["id"] as? String, let path = p["path"] as? String else { continue }
                let name = (p["name"] as? String) ?? URL(fileURLWithPath: path).lastPathComponent
                if var existing = try Project.filter(Column("xirpId") == xid || Column("path") == path).fetchOne(db) {
                    existing.xirpId = xid
                    existing.defaultAgent = existing.defaultAgent ?? (p["default_agent"] as? String)
                    existing.baseBranch = existing.baseBranch ?? (p["worktree_base_branch"] as? String) ?? (p["default_branch"] as? String)
                    existing.setupScript = existing.setupScript ?? nonEmpty(p["worktree_post_checkout_command"])
                    try existing.update(db)
                    projectMap[xid] = existing.id
                    report.projectsUpdated += 1
                } else {
                    let project = Project(
                        name: name, path: path,
                        defaultAgent: p["default_agent"] as? String,
                        baseBranch: (p["worktree_base_branch"] as? String) ?? (p["default_branch"] as? String),
                        setupScript: nonEmpty(p["worktree_post_checkout_command"]),
                        xirpId: xid,
                        createdAt: date(p["created_at"]) ?? Date(),
                        lastUsedAt: date(p["last_activity_at"])
                    )
                    try project.insert(db)
                    projectMap[xid] = project.id
                    report.projectsNew += 1
                }
            }

            var sessionMap: [String: String] = [:]
            for s in sessions {
                guard let xid = s["id"] as? String else { continue }
                var worktreePath = (s["worktree_path"] as? String) ?? ""
                var projectId = (s["project_id"] as? String).flatMap { projectMap[$0] }
                if projectId == nil, s["project_id"] as? String == nil,
                   worktreePath.isEmpty || repositoryRoot(worktreePath) == nil {
                    // Sessão do "General" do Xirp (fora de projeto): vai para o
                    // "Geral" do Bando e roda na pasta pessoal.
                    if worktreePath.isEmpty { worktreePath = Project.generalPath }
                    if let existing = try Project.filter(Column("path") == Project.generalPath).fetchOne(db) {
                        projectId = existing.id
                    } else {
                        let general = Project(name: Project.generalName, path: Project.generalPath)
                        try general.insert(db)
                        projectId = general.id
                        report.projectsNew += 1
                    }
                }
                if projectId == nil {
                    // Projeto apagado no Xirp: recria a partir da pasta da sessão.
                    guard let path = repositoryRoot(worktreePath) else {
                        report.skipped.append("sessão \(xid.prefix(8)) sem projeto nem pasta"); continue
                    }
                    if let existing = try Project.filter(Column("path") == path).fetchOne(db) {
                        projectId = existing.id
                    } else {
                        let project = Project(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
                        try project.insert(db)
                        projectId = project.id
                        report.projectsNew += 1
                    }
                    if let xp = s["project_id"] as? String { projectMap[xp] = projectId }
                }
                guard let projectId else { continue }
                let launch = s["agent_launch_options"] as? [String: Any]
                let agent = (launch?["agentName"] as? String) ?? "claude"
                let tmuxName = "xirp-\(xid)"
                let live = liveXirp.contains(tmuxName)
                // Importada e não rodando: entra como parada (pode retomar). O
                // estado original fica no detalhe, sem poluir a lista com erros antigos.
                let status: SessionStatus = live ? .idle : .stopped
                let originalStatus = s["status"] as? String
                let worktree = worktreePath
                let created = date(s["created_at"]) ?? Date()

                if var existing = try Session.filter(Column("xirpId") == xid).fetchOne(db) {
                    // Não mexe em sessões que já estão sendo controladas pelo Bando.
                    if existing.tmuxServer == "default" || !existing.status.isLive {
                        existing.status = status
                        existing.nativeId = existing.nativeId ?? (s["cli_session_id"] as? String)
                        existing.updatedAt = Date()
                        try existing.update(db)
                    }
                    sessionMap[xid] = existing.id
                    report.sessionsUpdated += 1
                } else {
                    var session = Session(
                        projectId: projectId,
                        name: sessionName(s, worktree: worktree),
                        prompt: s["goal"] as? String,
                        agent: agent, provider: nil,
                        model: (s["model"] as? String) ?? (s["requested_model"] as? String),
                        worktreePath: worktree, branch: s["branch"] as? String, baseBranch: nil,
                        usesWorktree: worktree != Project.generalPath,
                        // Sessões vivas continuam no tmux do Xirp; as outras, se
                        // retomadas, sobem no servidor do Bando.
                        tmuxName: live ? tmuxName : "bando_\(xid.prefix(8))",
                        tmuxServer: live ? "default" : Tmux.bandoServer,
                        nativeId: s["cli_session_id"] as? String,
                        status: status, xirpId: xid, createdAt: created
                    )
                    session.updatedAt = date(s["updated_at"]) ?? created
                    session.statusChangedAt = date(s["status_changed_at"]) ?? session.updatedAt
                    session.finishedAt = date(s["completed_at"])
                    session.statusDetail = originalStatus.map { "no Xirp: \($0)" }
                    try session.insert(db)
                    var e = SessionEvent(sessionId: session.id, kind: "import:xirp", status: status, at: created)
                    try e.insert(db)
                    sessionMap[xid] = session.id
                    report.sessionsNew += 1
                }
                if live { report.sessionsAdopted += 1 }
            }

            for c in costs {
                guard let cid = c["id"].map({ "\($0)" }) else { continue }
                // O Xirp repete a mesma resposta em sessões com fork; o ID da
                // mensagem dele elimina a duplicata.
                let key = (c["message_id"] as? String).map { "xirp-msg:\($0)" } ?? "xirp:\(cid)"
                if try UsageRecord.filter(Column("sourceKey") == key).fetchCount(db) > 0 { continue }
                var u = UsageRecord(
                    id: nil,
                    sessionId: (c["session_id"] as? String).flatMap { sessionMap[$0] },
                    agent: c["agent"] as? String, provider: nil, model: c["model"] as? String,
                    inputTokens: int(c["input_tokens"]), outputTokens: int(c["output_tokens"]),
                    cacheRead: int(c["cache_read"]),
                    cacheWrite: int(c["cache_write_5m"]) + int(c["cache_write_1h"]),
                    costUsd: (c["cost_usd"] as? Double) ?? Double(int(c["cost_usd"])),
                    at: date(c["turn_ts"]) ?? date(c["created_at"]) ?? Date(),
                    sourceKey: key
                )
                try u.insert(db)
                report.usageNew += 1
            }

            for p in prs {
                guard let pid = p["id"].map({ "xirp:\($0)" }) else { continue }
                let pr = PullRequestRecord(
                    id: pid, sessionId: (p["session_id"] as? String).flatMap { sessionMap[$0] },
                    host: p["host"] as? String, repoOwner: p["repo_owner"] as? String, repoName: p["repo_name"] as? String,
                    number: p["pr_number"] as? Int, headBranch: p["head_branch"] as? String, state: p["state"] as? String,
                    createdAt: date(p["pr_created_at"]), mergedAt: date(p["pr_merged_at"])
                )
                try pr.save(db)
                report.pullRequests += 1
            }

            if dryRun { throw DryRun() }
        }

        do {
            try store.pool.write(work)
        } catch is DryRun {
            // Transação desfeita de propósito.
        }
        if !dryRun { ChangeNotifier.post() }
        return report
    }

    struct DryRun: Error {}

    func sessionName(_ s: [String: Any], worktree: String) -> String {
        for key in ["name", "goal", "last_user_message", "branch"] {
            if let v = nonEmpty(s[key]) {
                let line = v.split(separator: "\n").first.map(String.init) ?? v
                return String(line.prefix(60))
            }
        }
        return worktree.isEmpty ? "sessão do Xirp" : URL(fileURLWithPath: worktree).lastPathComponent
    }

    /// Raiz do repositório da pasta (ou a própria pasta, se existir).
    func repositoryRoot(_ path: String) -> String? {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        // Worktree do Xirp: <repo>-worktree-session-<apelido>; o git devolve a raiz do worktree,
        // então pega o repositório principal pelo --git-common-dir.
        if let git = try? Git(),
           let r = try? Shell.run(git.executable, ["rev-parse", "--path-format=absolute", "--git-common-dir"], cwd: path), r.ok {
            let common = URL(fileURLWithPath: r.trimmed)
            return common.lastPathComponent == ".git" ? common.deletingLastPathComponent().path : path
        }
        return path
    }

    func nonEmpty(_ v: Any?) -> String? {
        guard let s = v as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    func int(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) ?? 0 }
        return 0
    }

    nonisolated(unsafe) static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) static let iso = ISO8601DateFormatter()

    func date(_ v: Any?) -> Date? {
        if let s = v as? String { return Self.isoFrac.date(from: s) ?? Self.iso.date(from: s) }
        if let n = v as? Double { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        if let n = v as? Int { return Date(timeIntervalSince1970: Double(n) > 1e12 ? Double(n) / 1000 : Double(n)) }
        return nil
    }
}
