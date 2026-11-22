import ArgumentParser
import BandoCore
import Foundation

struct Team: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Gerencia equipes multi-agente e conexões entre sessões.",
        subcommands: [
            NewTeam.self, ListTeams.self, ShowTeam.self, TemplatesTeam.self,
            AddMember.self, ConnectTeam.self, DisconnectTeam.self,
            DelegateTeam.self, OutputTeam.self, StartTeam.self, StopTeam.self, RemoveTeam.self,
        ],
        defaultSubcommand: ListTeams.self
    )

    struct NewTeam: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "new", abstract: "Cria uma equipe a partir de um template ou só com o orquestrador.")

        @Option(name: .shortAndLong, help: "Nome da equipe.") var name: String?
        @Option(name: .shortAndLong, help: "Template em teams.toml (ex.: feature-completa).") var template: String?
        @Option(name: .long, help: "Projeto (caminho, nome ou ID; padrão: pasta atual).") var project: String?
        @Option(name: .shortAndLong, help: "Objetivo geral da equipe.") var goal: String?
        @Option(name: .shortAndLong, help: "Agente padrão dos papéis sem agente fixo.") var agent: String?
        @Option(name: .shortAndLong, help: "Provider padrão dos papéis.") var provider: String?
        @Flag(name: .long, help: "Cria os nós sem iniciar os agentes.") var noStart = false

        func run() throws {
            let service = try makeService()
            let teamSvc = TeamService(service: service)
            let proj = try project.map { try service.findProject($0) }
                ?? service.ensureProject(at: FileManager.default.currentDirectoryPath)
            let req: TeamService.CreateTeamRequest
            if let template {
                let tpl = try service.config.team(template)
                req = .from(
                    template: tpl, project: proj, name: name, goal: goal,
                    defaultAgent: agent ?? proj.defaultAgent ?? "claude",
                    defaultProvider: provider ?? proj.defaultProvider,
                    startNow: !noStart
                )
            } else {
                let role = TeamService.RoleSpec(
                    roleId: "orchestrator",
                    name: "Orquestrador",
                    responsibilities: "Coordenar os especialistas da equipe e consolidar o resultado.",
                    agent: agent ?? proj.defaultAgent ?? "claude",
                    provider: provider ?? proj.defaultProvider,
                    isOrchestrator: true,
                    worktree: .isolated,
                    autoStart: !noStart,
                    canvasX: 120,
                    canvasY: 200
                )
                req = TeamService.CreateTeamRequest(
                    project: proj,
                    name: name ?? "Equipe \(proj.name)",
                    goal: goal,
                    roles: [role],
                    startNow: !noStart
                )
            }
            let created = try teamSvc.createTeam(req)
            print("\(created.team.shortId)  \(created.team.name)  (\(created.sessions.count) nós)")
            for s in created.sessions {
                print("  \(s.shortId)  \(s.roleTitle ?? s.name) · \(s.agent)\(s.provider.map { "·\($0)" } ?? "") · \(s.status.label)")
            }
        }
    }

    struct ListTeams: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "ls", abstract: "Lista as equipes.")

        @Option(name: .long, help: "Filtra por projeto.") var project: String?
        @Flag(name: .long, help: "Saída em JSON.") var json = false

        func run() throws {
            let service = try makeService()
            let pid = try project.map { try service.findProject($0).id }
            let teams = try service.store.teams(projectId: pid)
            if json {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                enc.dateEncodingStrategy = .iso8601
                print(String(decoding: try enc.encode(teams), as: UTF8.self))
                return
            }
            if teams.isEmpty {
                print("Nenhuma equipe. Crie com: bando team new -t feature-completa -g \"objetivo\"")
                return
            }
            let projects = Dictionary(uniqueKeysWithValues: try service.store.projects().map { ($0.id, $0.name) })
            var rows = [["ID", "PROJETO", "NÓS", "NOME", "OBJETIVO"]]
            for t in teams {
                let count = (try? service.store.sessions(inTeam: t.id).count) ?? 0
                rows.append([t.shortId, projects[t.projectId] ?? "?", "\(count)", t.name, String((t.goal ?? "-").prefix(50))])
            }
            printTable(rows)
        }
    }

    struct TemplatesTeam: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "templates", abstract: "Lista os templates de equipe disponíveis.")

        func run() throws {
            let config = try loadConfig()
            var rows = [["ID", "NOME", "PAPÉIS", "DESCRIÇÃO"]]
            for t in config.sortedTeams {
                let custom = config.userTeamIds.contains(t.id) ? " *" : ""
                rows.append([t.id + custom, t.name, t.roles.map(\.name).joined(separator: ", "), t.description ?? "-"])
            }
            printTable(rows)
        }
    }

    struct ShowTeam: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Mostra os membros e ligações de uma equipe.")
        @Argument(help: "ID, prefixo ou nome da equipe.") var team: String
        @Flag(name: .long) var json = false

        func run() throws {
            let service = try makeService()
            let t = try service.store.findTeam(team)
            let members = try service.store.sessions(inTeam: t.id)
            let edges = try service.store.edges(inTeam: t.id)
            if json {
                let payload: [String: Any] = [
                    "team": ["id": t.id, "name": t.name, "goal": t.goal ?? ""],
                    "members": members.map { m -> [String: Any] in
                        [
                            "id": m.id, "shortId": m.shortId, "role": m.roleTitle ?? m.name,
                            "isOrchestrator": m.isOrchestrator, "agent": m.agent,
                            "provider": m.provider ?? "default", "model": m.model ?? "",
                            "status": m.status.rawValue, "sharedWorktree": m.worktreeSourceId != nil,
                            "worktree": m.worktreePath,
                        ]
                    },
                    "edges": edges.map { ["id": $0.id, "from": $0.fromSessionId, "to": $0.toSessionId, "kind": $0.kind.rawValue] },
                ]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                return
            }
            print("\(t.shortId)  \(t.name)")
            if let g = t.goal, !g.isEmpty { print("objetivo: \(g)") }
            print("\nmembros:")
            var rows = [["ID", "PAPEL", "ESTADO", "AGENTE/PROVIDER", "MODELO", "WORKTREE"]]
            for m in members {
                let role = (m.isOrchestrator ? "★ " : "") + (m.roleTitle ?? m.name)
                let ap = m.agent + (m.provider.map { "·\($0)" } ?? "")
                let wt = m.worktreeSourceId != nil ? "compartilhado" : (m.branch ?? m.worktreePath)
                rows.append([m.shortId, role, m.status.label, ap, m.model ?? "-", wt])
            }
            printTable(rows)
            if !edges.isEmpty {
                let byId = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.roleTitle ?? $0.name) })
                print("\nligações:")
                for e in edges {
                    print("  \(e.id.prefix(8))  \(byId[e.fromSessionId] ?? e.fromSessionId) --[\(e.kind.rawValue)]--> \(byId[e.toSessionId] ?? e.toSessionId)")
                }
            }
        }
    }

    struct AddMember: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "Adiciona um novo agente/papel à equipe.")
        @Argument(help: "Equipe (ID, prefixo ou nome).") var team: String
        @Option(name: .long, help: "Título do papel.") var role: String
        @Option(name: .shortAndLong, help: "Agente.") var agent: String = "claude"
        @Option(name: .shortAndLong, help: "Provider.") var provider: String?
        @Option(name: .shortAndLong, help: "Modelo.") var model: String?
        @Option(name: .long, help: "Compressor.") var compressor: String?
        @Option(name: .long, help: "Responsabilidades do papel.") var responsibilities: String = ""
        @Option(name: .long, help: "Tarefa inicial.") var prompt: String?
        @Flag(name: .long, help: "Define como orquestrador.") var orchestrator = false
        @Option(name: .long, help: "Compartilhar worktree com esta sessão/papel.") var shareWith: String?
        @Option(name: .long, help: "Aguardar este membro concluir.") var dependsOn: String?
        @Flag(name: .long, help: "Não iniciar automaticamente.") var noStart = false

        func run() throws {
            let service = try makeService()
            let teamSvc = TeamService(service: service)
            let t = try service.store.findTeam(team)
            let depId = try dependsOn.map { try teamSvc.findMember($0, inTeam: t.id).id }
            let s = try teamSvc.addMember(
                to: t.id,
                roleTitle: role,
                agent: agent,
                provider: provider,
                model: model,
                compressor: compressor,
                responsibilities: responsibilities,
                prompt: prompt,
                isOrchestrator: orchestrator,
                worktree: shareWith != nil ? .shared : .isolated,
                shareWithSessionId: shareWith,
                dependsOnSessionId: depId,
                startNow: !noStart
            )
            print("\(s.shortId)  \(s.roleTitle ?? s.name) · \(s.agent)\(s.provider.map { "·\($0)" } ?? "") · \(s.status.label)")
        }
    }

    struct ConnectTeam: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "connect", abstract: "Liga dois nós da equipe no Canvas.")
        @Argument var team: String
        @Argument var from: String
        @Argument var to: String
        @Option(name: .shortAndLong, help: "delegate | sequence | handoff") var kind: String = "delegate"

        func run() throws {
            guard let k = TeamEdgeKind(rawValue: kind) else {
                throw ValidationError("Tipo inválido: use delegate, sequence ou handoff")
            }
            let service = try makeService()
            let teamSvc = TeamService(service: service)
            let t = try service.store.findTeam(team)
            let src = try teamSvc.findMember(from, inTeam: t.id)
            let dst = try teamSvc.findMember(to, inTeam: t.id)
            let edge = try teamSvc.connect(teamId: t.id, from: src.id, to: dst.id, kind: k)
            print("\(edge.id.prefix(8))  \(src.roleTitle ?? src.name) --[\(k.rawValue)]--> \(dst.roleTitle ?? dst.name)")
        }
    }

    struct DisconnectTeam: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "disconnect", abstract: "Remove uma ligação do Canvas.")
        @Argument var edgeId: String

        func run() throws {
            let service = try makeService()
            let teamSvc = TeamService(service: service)
            let all = try service.store.allTeamEdges()
            guard let match = all.first(where: { $0.id == edgeId || $0.id.hasPrefix(edgeId.lowercased()) }) else {
                throw BandoError.notFound("ligação \(edgeId)")
            }
            try teamSvc.disconnect(edgeId: match.id)
            print("removida: \(match.id.prefix(8))")
        }
    }

    struct DelegateTeam: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delegate", abstract: "Delega uma tarefa para um membro da equipe.")
        @Argument(help: "ID, prefixo ou papel do membro.") var member: String
        @Argument(help: "Instrução da tarefa.") var task: String
        @Option(name: .long, help: "Equipe (usa BANDO_TEAM_ID se omitido).") var team: String?

        func run() throws {
            let service = try makeService()
            let teamSvc = TeamService(service: service)
            let teamId = try resolveTeamId(team, service: service)
            let updated = try teamSvc.delegate(to: member, inTeam: teamId, task: task,
                                               fromSessionId: ProcessInfo.processInfo.environment["BANDO_SESSION_ID"])
            print("\(updated.shortId)  \(updated.roleTitle ?? updated.name) · \(updated.status.label)")
        }
    }

    struct OutputTeam: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "output", abstract: "Captura as últimas linhas do terminal de um membro.")
        @Argument var member: String
        @Option(name: .long) var team: String?
        @Option(name: .shortAndLong) var lines: Int = 60

        func run() throws {
            let service = try makeService()
            let teamSvc = TeamService(service: service)
            let teamId = try resolveTeamId(team, service: service)
            let target = try teamSvc.findMember(member, inTeam: teamId)
            if let caller = ProcessInfo.processInfo.environment["BANDO_SESSION_ID"], !caller.isEmpty {
                teamSvc.recordOutputRead(bySessionId: caller, targetId: target.id, inTeam: teamId)
            }
            print("[\(target.roleTitle ?? target.name) · \(target.status.label)]")
            if let tmux = try? Tmux(server: target.tmuxServer), tmux.hasSession(target.tmuxName) {
                print(tmux.capture(target.tmuxName, lines: lines))
            } else {
                print("(sessão parada)")
            }
        }
    }

    struct StartTeam: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "start", abstract: "Inicia os nós prontos da equipe.")
        @Argument var team: String
        func run() throws {
            let service = try makeService()
            let t = try service.store.findTeam(team)
            try TeamService(service: service).startTeam(t.id)
            print("iniciada: \(t.shortId) \(t.name)")
        }
    }

    struct StopTeam: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "stop", abstract: "Para todas as sessões ativas da equipe.")
        @Argument var team: String
        func run() throws {
            let service = try makeService()
            let t = try service.store.findTeam(team)
            try TeamService(service: service).stopTeam(t.id)
            print("parada: \(t.shortId) \(t.name)")
        }
    }

    struct RemoveTeam: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: "Apaga a equipe, sessões e worktrees.")
        @Argument var team: String
        @Flag(name: .long) var keepWorktrees = false
        @Flag(name: .long) var deleteBranches = false
        @Flag(name: .long) var force = false

        func run() throws {
            let service = try makeService()
            let t = try service.store.findTeam(team)
            try TeamService(service: service).deleteTeam(t.id, removeWorktrees: !keepWorktrees, deleteBranches: deleteBranches, force: force)
            print("apagada: \(t.shortId) \(t.name)")
        }
    }
}

private func resolveTeamId(_ ref: String?, service: SessionService) throws -> String {
    if let ref, !ref.isEmpty { return try service.store.findTeam(ref).id }
    if let env = ProcessInfo.processInfo.environment["BANDO_TEAM_ID"], !env.isEmpty { return env }
    throw ValidationError("Informe --team <id> ou rode de dentro de uma sessão de equipe")
}

struct McpBridge: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-bridge",
        abstract: "Uso interno: servidor MCP stdio da equipe para agentes.",
        shouldDisplay: false
    )
    @Option var team: String
    @Option var session: String

    func run() throws {
        let service = try makeService()
        TeamMcpBridge(teamId: team, sessionId: session, service: service).runStdio()
    }
}
