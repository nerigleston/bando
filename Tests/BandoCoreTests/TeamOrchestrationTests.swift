@testable import BandoCore
import Foundation
import GRDB
import Testing

@Suite("Equipes e Modo Orquestrador")
struct TeamOrchestrationTests {
    let root: URL
    let paths: BandoPaths
    let store: BandoStore
    let config: BandoConfig
    let service: SessionService
    let teamService: TeamService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bando-team-tests-\(UUID().uuidString.prefix(8))")
        paths = BandoPaths(configDir: root.appendingPathComponent("cfg"), stateDir: root.appendingPathComponent("state"))
        try FileManager.default.createDirectory(at: paths.configDir, withIntermediateDirectories: true)
        store = try BandoStore(paths: paths)
        config = try BandoConfig.load(paths: paths)
        service = SessionService(store: store, config: config)
        teamService = TeamService(service: service)
    }

    func makeRepo(_ name: String) throws -> URL {
        let dir = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gitExe = try Git().executable
        for args in [
            ["init", "-q", "-b", "main"],
            ["config", "user.name", "Tester"],
            ["config", "user.email", "tester@example.com"],
        ] {
            let r = try Shell.run(gitExe, args, cwd: dir.path)
            #expect(r.ok, "git \(args.joined(separator: " ")): \(r.stderr)")
        }
        try "hello\n".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let add = try Shell.run(gitExe, ["add", "."], cwd: dir.path)
        #expect(add.ok)
        let commit = try Shell.run(gitExe, ["commit", "-q", "-m", "init"], cwd: dir.path)
        #expect(commit.ok)
        return dir
    }

    @Test("presets de equipe carregam sem avisos e aceitam override + serialização TOML")
    func templatesLoadAndSerialize() throws {
        #expect(config.issues.isEmpty)
        #expect(config.teams["feature-completa"] != nil)
        #expect(config.teams["revisao-paralela"] != nil)
        #expect(config.teams["pipeline-sequencial"] != nil)

        let custom = try BandoConfig.load(
            userAgents: nil,
            userProviders: nil,
            userTeams: """
            [teams.feature-completa.roles.implementer]
            agent = "codex"
            provider = "openrouter"
            model = "z-ai/glm-5"

            [teams.invalida]
            name = "Sem papéis"
            """
        )
        let merged = try custom.team("feature-completa")
        let imp = try #require(merged.roles.first { $0.id == "implementer" })
        #expect(imp.agent == "codex")
        #expect(imp.provider == "openrouter")
        #expect(imp.model == "z-ai/glm-5")
        #expect(imp.worktree == .shared)
        #expect(custom.teams["invalida"] == nil)
        #expect(custom.issues.contains { $0.section == "teams.invalida" })

        // Serialização e releitura pelo arquivo do usuário.
        try TeamTemplateTOML.upsert(merged, into: paths.teamsFile)
        let reloaded = try BandoConfig.load(paths: paths)
        let again = try reloaded.team("feature-completa")
        #expect(again.roles.count == merged.roles.count)
        #expect(again.edges == merged.edges)
    }

    @Test("cria equipe multi-provider com worktree próprio vs compartilhado e dependências")
    func createMultiProviderTeam() throws {
        let repo = try makeRepo("projeto-a")
        let project = try service.ensureProject(at: repo.path)

        let req = TeamService.CreateTeamRequest(
            project: project,
            name: "Squad API",
            goal: "Implementar endpoints e revisar segurança",
            templateId: "feature-completa",
            roles: [
                .init(roleId: "orch", name: "Orquestrador", responsibilities: "Coordenar equipe",
                      agent: "claude", provider: "anthropic", model: "claude-sonnet-4-6",
                      isOrchestrator: true, worktree: .isolated, autoStart: false, canvasX: 100, canvasY: 200),
                .init(roleId: "impl", name: "Implementador", responsibilities: "Escrever código",
                      agent: "codex", provider: "openrouter", model: "openai/gpt-5",
                      isOrchestrator: false, worktree: .shared, shareWorktreeWithRoleId: "orch",
                      autoStart: false, canvasX: 480, canvasY: 100),
                .init(roleId: "rev", name: "Revisor", responsibilities: "Revisar e testar",
                      agent: "opencode", provider: "ollama", model: "qwen3-coder",
                      isOrchestrator: false, worktree: .isolated, autoStart: false, canvasX: 480, canvasY: 320),
            ],
            edges: [
                .init(fromRoleId: "orch", toRoleId: "impl", kind: .delegate),
                .init(fromRoleId: "impl", toRoleId: "rev", kind: .handoff),
            ],
            startNow: false
        )

        let created = try teamService.createTeam(req)
        #expect(created.sessions.count == 3)
        #expect(created.edges.count == 2)

        let orch = try #require(created.sessions.first { $0.roleId == "orch" })
        let impl = try #require(created.sessions.first { $0.roleId == "impl" })
        let rev = try #require(created.sessions.first { $0.roleId == "rev" })

        #expect(orch.isOrchestrator == true)
        #expect(orch.usesWorktree == true)
        #expect(impl.usesWorktree == false)
        #expect(impl.worktreeSourceId == orch.id)
        #expect(impl.worktreePath == orch.worktreePath)
        #expect(impl.branch == orch.branch)

        #expect(rev.usesWorktree == true)
        #expect(rev.worktreePath != orch.worktreePath)
        #expect(rev.dependsOn == impl.id)

        // Persistência de posição e tamanho redimensionado no Canvas.
        try teamService.updateFrame(sessionId: orch.id, x: 140, y: 220, width: 620, height: 440)
        let reloadedOrch = try #require(try store.session(orch.id))
        #expect(reloadedOrch.canvasX == 140)
        #expect(reloadedOrch.canvasY == 220)
        #expect(reloadedOrch.canvasWidth == 620)
        #expect(reloadedOrch.canvasHeight == 440)

        // Arquivo de contexto da equipe gravado e ignorado pelo git.
        let ctxFile = URL(fileURLWithPath: orch.worktreePath).appendingPathComponent(TeamContext.relativePath(teamId: created.team.id))
        #expect(FileManager.default.fileExists(atPath: ctxFile.path))
        let ctxText = try String(contentsOf: ctxFile, encoding: .utf8)
        #expect(ctxText.contains("Squad API"))
        #expect(ctxText.contains("Implementador"))
        #expect(ctxText.contains("Revisor"))

        // Plano de lançamento injeta MCP bando-team e contexto da equipe no prompt.
        let (plan, _, _) = try service.launchPlan(for: orch, resume: false)
        #expect(plan.argv.contains("--mcp-config"))
        #expect(plan.argv.joined(separator: " ").contains("bando-team"))
        #expect(plan.argv.last?.contains("[Modo Equipe · Squad API]") == true)

        // Impede apagar equipe sem --force se o worktree tiver alterações não commitadas.
        try "mudança\n".write(to: URL(fileURLWithPath: orch.worktreePath).appendingPathComponent("dirty.txt"), atomically: true, encoding: .utf8)
        #expect(throws: BandoError.self) {
            try teamService.deleteTeam(created.team.id, force: false)
        }
        try teamService.deleteTeam(created.team.id, force: true)
        #expect(try store.team(created.team.id) == nil)
        #expect(try store.sessions(inTeam: created.team.id).isEmpty)
    }

    @Test("conexão de sequência recusa ciclos e MCP bridge responde JSON-RPC")
    func cycleDetectionAndMcpBridge() throws {
        let dir = root.appendingPathComponent("sem-git")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let project = try service.ensureProject(at: dir.path)

        let created = try teamService.createTeam(.init(
            project: project,
            name: "MCP Test",
            goal: "Testar ponte MCP",
            roles: [
                .init(roleId: "lead", name: "Líder", responsibilities: "Coordenar", agent: "claude", isOrchestrator: true, autoStart: false),
                .init(roleId: "worker", name: "Worker", responsibilities: "Executar", agent: "codex", autoStart: false),
            ],
            edges: [.init(fromRoleId: "lead", toRoleId: "worker", kind: .sequence)],
            startNow: false
        ))
        let lead = try #require(created.sessions.first { $0.roleId == "lead" })
        let worker = try #require(created.sessions.first { $0.roleId == "worker" })

        #expect(throws: BandoError.self) {
            try teamService.connect(teamId: created.team.id, from: worker.id, to: lead.id, kind: .sequence)
        }

        let bridge = TeamMcpBridge(teamId: created.team.id, sessionId: lead.id, service: service)
        let initReq = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "initialize"])
        let initResp = try #require(bridge.handleMessage(initReq))
        let result = try #require(initResp["result"] as? [String: Any])
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "bando-team")

        let listToolsReq = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let listToolsResp = try #require(bridge.handleMessage(listToolsReq))
        let tools = try #require((listToolsResp["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.contains { $0["name"] as? String == "team_spawn_member" })

        let callReq = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": ["name": "team_list_members", "arguments": [String: Any]()],
        ])
        let callResp = try #require(bridge.handleMessage(callReq))
        let content = try #require((callResp["result"] as? [String: Any])?["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        #expect(text.contains("MCP Test"))
        #expect(text.contains("Worker"))
    }

    @Test("descoberta de providers conectados e lista de modelos")
    func providerDiscoveryAndModels() throws {
        struct MemorySecrets: SecretStore {
            let items: [String: String]
            func read(service: String, account: String) throws -> String? { items["\(service)/\(account)"] }
            func write(_ value: String, service: String, account: String) throws {}
            func delete(service: String, account: String) throws {}
        }

        let secrets = MemorySecrets(items: ["bando/openrouter": "sk-test"])
        let openrouter = try config.provider("openrouter")
        let anthropic = try config.provider("anthropic")
        let ollama = try config.provider("ollama")

        #expect(ProviderDiscovery.connectionState(for: openrouter, store: secrets) == .connected)
        #expect(ProviderDiscovery.connectionState(for: anthropic, store: secrets) == .disconnected)
        #expect(ProviderDiscovery.connectionState(for: ollama, store: secrets) == .localOffline)
        #expect(ProviderDiscovery.connectionState(for: ollama, store: secrets, reachableLocals: ["ollama"]) == .connected)

        let ollamaJSON = Data(#"{"models":[{"name":"qwen3-coder:30b"},{"name":"deepseek-r1:14b"}]}"#.utf8)
        #expect(ProviderDiscovery.parseModelList(ollamaJSON) == ["qwen3-coder:30b", "deepseek-r1:14b"])

        let openAIJSON = Data(#"{"data":[{"id":"local-model-1"},{"id":"local-model-2"}]}"#.utf8)
        #expect(ProviderDiscovery.parseModelList(openAIJSON) == ["local-model-1", "local-model-2"])

        let models = ProviderDiscovery.models(
            for: "claude",
            providerId: "ollama",
            config: config,
            discovered: ["ollama": ["qwen3-coder:30b"]]
        )
        #expect(models.first == "qwen3-coder:30b")
        #expect(models.contains(where: { ollama.models.contains($0) }))

        // Conta do agente ("default") herda modelos nativos quando o agente não define os seus.
        let nativeModels = ProviderDiscovery.models(for: "claude", providerId: "default", config: config)
        #expect(!nativeModels.isEmpty)
        #expect(nativeModels == anthropic.models)
    }

    @Test("registro de direção e contagem de interações nas arestas entre agentes")
    func edgeInteractionFlowDirection() throws {
        let repo = try makeRepo("flow-repo")
        let project = try service.ensureProject(at: repo.path)
        let created = try teamService.createTeam(.init(
            project: project,
            name: "Fluxo",
            goal: "Testar direção nas arestas",
            roles: [
                .init(roleId: "lead", name: "Orquestrador", responsibilities: "Delegar", agent: "claude", isOrchestrator: true, autoStart: false),
                .init(roleId: "impl", name: "Implementador", responsibilities: "Codar", agent: "codex", autoStart: false),
            ],
            edges: [.init(fromRoleId: "lead", toRoleId: "impl", kind: .delegate)],
            startNow: false
        ))
        let lead = try #require(created.sessions.first { $0.roleId == "lead" })
        let impl = try #require(created.sessions.first { $0.roleId == "impl" })

        // Fluxo inicial: Orquestrador -> Implementador (.forward).
        teamService.recordFlow(teamId: created.team.id, from: lead.id, to: impl.id)
        var edges = try store.edges(inTeam: created.team.id)
        var edge = try #require(edges.first)
        #expect(edge.lastDirection == .forward)
        #expect(edge.interactionCount == 1)
        #expect(edge.lastActivityAt != nil)

        // Leitura ou retorno imediato no sentido inverso (impl -> lead) promove para .bidirectional.
        teamService.recordOutputRead(bySessionId: lead.id, targetId: impl.id, inTeam: created.team.id)
        edges = try store.edges(inTeam: created.team.id)
        edge = try #require(edges.first)
        #expect(edge.lastDirection == .bidirectional)
        #expect(edge.interactionCount == 2)

        // Retorno de turno do membro dependente sem pulso recente marca .reverse na aresta.
        try store.pool.write { db in
            var stale = edge
            stale.lastActivityAt = Date().addingTimeInterval(-30)
            try stale.update(db)
        }
        teamService.recordMemberTurnReturn(sessionId: impl.id)
        edges = try store.edges(inTeam: created.team.id)
        edge = try #require(edges.first)
        #expect(edge.lastDirection == .reverse)
        #expect(edge.interactionCount == 3)

        // Eventos de comunicação da equipe ficam gravados para exibição no Canvas.
        let teamEvents = try store.events(
            forSessionIds: [lead.id, impl.id],
            kinds: ["team-read", "team-return"],
            limit: 10
        )
        #expect(teamEvents.contains { $0.kind == "team-read" })
        #expect(teamEvents.contains { $0.kind == "team-return" })
    }

    @Test("assinatura de tela do OutputWatcher ignora relógio e spinner parados")
    func outputWatcherScreenSignatureIgnoresClock() {
        let frame1 = [
            "Codex concluído.",
            "Worked for 19s • 02:16",
            "Ask Codex to do anything",
        ]
        let frame2 = [
            "Codex concluído.",
            "✳ Worked for 19s • 02:17",
            "Ask Codex to do anything",
        ]
        let frame3 = [
            "Codex executando outra tarefa.",
            "Worked for 25s • 02:23",
            "Ask Codex to do anything",
        ]
        #expect(OutputWatcher.screenSignature(from: frame1) == OutputWatcher.screenSignature(from: frame2))
        #expect(OutputWatcher.screenSignature(from: frame1) != OutputWatcher.screenSignature(from: frame3))
    }

    @Test("detector de envio pendente no composer reenvia Enter quando prompt fica preso")
    func tmuxRetrySubmitDetection() throws {
        let prompt = """
        Verifique SSRF no webhook.
        Responda CURTO: achados por item e VEREDITO final (aprovar / aprovar-com-ressalvas / reprovar).
        """
        let stuckInCodex = """
        > sempre ou é tratado como falha repetível?
          - **SSRF**: validar IP privado
          Responda CURTO: achados por item e VEREDITO final (aprovar / aprovar-com-ressalvas / reprovar).

        GPT-6.1 Terra high · ~/projetos/exemplo
        △ 2 warnings · f2 to view
        """
        let submittedInCodex = """
        > Responda CURTO: achados por item e VEREDITO final (aprovar / aprovar-com-ressalvas / reprovar).
        • Working (3s • esc to interrupt)
        Ask Codex to do anything
        GPT-6.1 Terra high · ~/projetos/exemplo
        """
        let busy = try #require(try BandoConfig.load(userAgents: nil, userProviders: nil).agent("codex").busy.flatMap { try Regex($0) })
        #expect(Tmux.shouldRetrySubmit(prompt: prompt, captured: stuckInCodex, busy: busy) == true)
        #expect(Tmux.shouldRetrySubmit(prompt: prompt, captured: submittedInCodex, busy: busy) == false)
    }

    // MARK: - Segurança da ponte, dependência e worktree compartilhado

    func call(_ bridge: TeamMcpBridge, _ tool: String, _ args: [String: Any] = [:]) throws -> (isError: Bool, text: String) {
        let req = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": tool, "arguments": args],
        ])
        let response = try #require(bridge.handleMessage(req))
        let result = try #require(response["result"] as? [String: Any])
        let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        return (result["isError"] as? Bool ?? false, text)
    }

    func smallTeam(_ name: String) throws -> (team: TeamRecord, lead: Session, worker: Session) {
        let repo = try makeRepo(name)
        let project = try service.ensureProject(at: repo.path)
        let created = try teamService.createTeam(.init(
            project: project, name: name, goal: "Testar segurança",
            roles: [
                .init(roleId: "lead", name: "Líder", responsibilities: "Coordenar", agent: "claude",
                      isOrchestrator: true, worktree: .isolated, autoStart: false),
                .init(roleId: "worker", name: "Worker", responsibilities: "Executar", agent: "claude",
                      worktree: .shared, shareWorktreeWithRoleId: "lead", autoStart: false),
            ],
            startNow: false
        ))
        return (created.team,
                try #require(created.sessions.first { $0.roleId == "lead" }),
                try #require(created.sessions.first { $0.roleId == "worker" }))
    }

    @Test("ponte de equipe: só o orquestrador usa, sem comando no texto e sem parar a si mesmo")
    func bridgeOnlyForOrchestrator() throws {
        let (team, lead, worker) = try smallTeam("ponte-segura")

        // Quem não é orquestrador não recebe o servidor nem consegue usar as ferramentas.
        let (workerPlan, _, _) = try service.launchPlan(for: worker, resume: false)
        #expect(!workerPlan.argv.joined(separator: " ").contains("bando-team"))
        let (leadPlan, _, _) = try service.launchPlan(for: lead, resume: false)
        #expect(leadPlan.argv.joined(separator: " ").contains("bando-team"))
        let fromWorker = TeamMcpBridge(teamId: team.id, sessionId: worker.id, service: service)
        #expect(try call(fromWorker, "team_list_members").isError)

        let bridge = TeamMcpBridge(teamId: team.id, sessionId: lead.id, service: service)
        #expect(try call(bridge, "team_list_members").isError == false)
        // "!" roda shell no Claude Code; "/" abre comando do agente.
        #expect(try call(bridge, "team_delegate", ["member": "worker", "task": "!rm -rf ~"]).isError)
        #expect(try call(bridge, "team_delegate", ["member": "worker", "task": "  /permissions"]).isError)
        #expect(try call(bridge, "team_stop_member", ["member": "lead"]).isError)
        #expect(TeamMcpBridge.isCommandText("Corrija o login") == false)
    }

    @Test("ponte de equipe: limite de membros por equipe")
    func bridgeMemberLimit() throws {
        let (team, lead, _) = try smallTeam("ponte-limite")
        for i in 0..<(TeamMcpBridge.maxMembers - 2) {
            _ = try teamService.addMember(to: team.id, roleTitle: "Extra \(i)", agent: "shell", startNow: false)
        }
        let bridge = TeamMcpBridge(teamId: team.id, sessionId: lead.id, service: service)
        let r = try call(bridge, "team_spawn_member", ["role": "Mais um", "responsibilities": "x", "task": "y", "agent": "shell"])
        #expect(r.isError)
        #expect(r.text.contains("\(TeamMcpBridge.maxMembers)"))
    }

    @Test("membro criado com conexão e dependência espera a dependência na fila")
    func dependencyWithConnectionWaits() throws {
        let (team, lead, worker) = try smallTeam("dependencia")
        // A dependência ainda trabalhando (parada ela já liberaria o membro).
        try service.transition(worker.id, to: .working, kind: "teste")
        let member = try teamService.addMember(
            to: team.id, roleTitle: "Revisor", agent: "shell",
            dependsOnSessionId: worker.id, connectFromSessionId: lead.id, startNow: false)
        let fresh = try #require(try store.session(member.id))
        #expect(fresh.dependsOn == worker.id)
        #expect(fresh.status == .queued)
    }

    @Test("apagar a sessão dona não remove o worktree que outro membro usa")
    func deleteKeepsSharedWorktree() throws {
        let (_, lead, worker) = try smallTeam("worktree-compartilhado")
        #expect(worker.worktreePath == lead.worktreePath)
        try service.delete(lead.id, options: .init(removeWorktree: true, force: true))
        #expect(FileManager.default.fileExists(atPath: worker.worktreePath))
    }
}
