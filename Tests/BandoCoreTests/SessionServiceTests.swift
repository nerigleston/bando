@testable import BandoCore
import Foundation
import GRDB
import Testing

/// Serviço de sessões contra um banco e pastas temporárias (sem iniciar agente:
/// `startNow: false`, então não precisa de tmux).
@Suite("Serviço de sessões")
struct SessionServiceTests {
    let root: URL
    let paths: BandoPaths
    let service: SessionService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bando-tests-\(UUID().uuidString.prefix(8))")
        paths = BandoPaths(configDir: root.appendingPathComponent("cfg"), stateDir: root.appendingPathComponent("state"))
        try FileManager.default.createDirectory(at: paths.configDir, withIntermediateDirectories: true)
        let store = try BandoStore(paths: paths)
        service = SessionService(store: store, config: try BandoConfig.load(paths: paths))
    }

    func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func git(_ args: [String], in dir: URL) throws {
        let r = try Shell.run(try Git().executable, args, cwd: dir.path)
        #expect(r.ok, "git \(args.joined(separator: " ")): \(r.stderr)")
    }

    @Test("pasta sem git: a sessão roda direto nela, sem worktree")
    func nonGitFolderRunsInPlace() throws {
        let dir = try folder("solta")
        let project = try service.ensureProject(at: dir.path)
        let s = try service.create(.init(project: project, prompt: "olhar", agent: "shell", useWorktree: true, startNow: false))
        #expect(s.usesWorktree == false)
        #expect(s.worktreePath == project.path)
        #expect(s.branch == nil)
    }

    @Test("repositório git: a sessão ganha worktree e branch próprios")
    func gitRepoGetsWorktree() throws {
        let repo = try folder("repo")
        try git(["init", "-q", "-b", "main"], in: repo)
        try "x\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: repo)
        try git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"], in: repo)
        let project = try service.ensureProject(at: repo.path)
        let s = try service.create(.init(project: project, prompt: "corrigir login", agent: "shell", startNow: false))
        #expect(s.usesWorktree)
        #expect(s.worktreePath != project.path)
        #expect(FileManager.default.fileExists(atPath: s.worktreePath))
        #expect(s.branch?.hasPrefix("bando/corrigir-login") == true)
    }

    @Test("pasta pessoal vira o projeto Geral")
    func generalProject() throws {
        let general = try service.generalProject()
        #expect(general.isGeneral)
        #expect(general.name == Project.generalName)
        #expect(try service.ensureProject(at: NSHomeDirectory()).id == general.id)
    }

    @Test("migração v4 renomeia a pasta pessoal para Geral")
    func migrationRenamesHome() throws {
        try service.store.pool.write { db in
            var p = Project(name: "neri", path: Project.generalPath)
            try p.insert(db)
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v4-general-project'")
        }
        let reopened = try BandoStore(paths: paths)
        let name = try reopened.pool.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM project WHERE path = ?", arguments: [Project.generalPath])
        }
        #expect(name == Project.generalName)
    }

    @Test("importação do Xirp leva sessões sem projeto para o Geral, sem custos com --so-sessoes")
    func xirpGeneralSessions() throws {
        let backup = root.appendingPathComponent("backup.json")
        let json: [String: Any] = ["version": 1, "tables": [
            "projects": [],
            "sessions": [
                ["id": "aaaa1111-0000-0000-0000-000000000000", "name": "Ideia de ERP", "project_id": NSNull(),
                 "worktree_path": NSNull(), "status": "idle", "cli_session_id": "c1"],
            ],
            "cost_records": [["id": 1, "message_id": "m1", "session_id": "aaaa1111-0000-0000-0000-000000000000",
                              "model": "claude-sonnet-4-5", "input_tokens": 10, "output_tokens": 5]],
            "session_pr_outcomes": [],
        ]]
        try JSONSerialization.data(withJSONObject: json).write(to: backup)
        let report = try XirpImporter(store: service.store).run(backup: backup, dryRun: false, sessionsOnly: true)
        #expect(report.sessionsNew == 1)
        #expect(report.skipped.isEmpty)
        let (session, project, usage) = try service.store.pool.read { db in
            (try Session.filter(Column("xirpId") == "aaaa1111-0000-0000-0000-000000000000").fetchOne(db),
             try Project.filter(Column("path") == Project.generalPath).fetchOne(db),
             try UsageRecord.fetchCount(db))
        }
        #expect(session?.projectId == project?.id)
        #expect(session?.worktreePath == Project.generalPath)
        #expect(session?.usesWorktree == false)
        #expect(usage == 0)
    }
}
