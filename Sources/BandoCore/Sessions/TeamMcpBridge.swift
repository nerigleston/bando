import Foundation

/// Servidor MCP embutido via stdio (`bando mcp-bridge --team <id> --session <id>`).
///
/// Roda sob demanda dentro do ciclo de vida do agente cliente (sem daemon).
/// Permite que a sessão orquestradora inspecione, crie e delegue tarefas a outros
/// membros da equipe usando ferramentas estruturadas, independentemente do provider.
public final class TeamMcpBridge: @unchecked Sendable {
    let teamId: String
    let sessionId: String
    let service: SessionService
    let teamService: TeamService

    public init(teamId: String, sessionId: String, service: SessionService) {
        self.teamId = teamId
        self.sessionId = sessionId
        self.service = service
        self.teamService = TeamService(service: service)
    }

    /// Loop principal de leitura em `stdin` e escrita em `stdout`.
    public func runStdio() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8),
                  let response = handleMessage(data) else { continue }
            if let outData = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys, .withoutEscapingSlashes]) {
                var payload = outData
                payload.append(0x0A)
                FileHandle.standardOutput.write(payload)
            }
        }
    }

    /// Processa uma mensagem JSON-RPC 2.0 e devolve a resposta (ou nil para notificações).
    public func handleMessage(_ data: Data) -> [String: Any]? {
        guard let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = req["method"] as? String else {
            return errorResponse(id: nil, code: -32700, message: "JSON inválido")
        }
        let id = req["id"]
        // Notificações JSON-RPC não têm id e não devem gerar resposta.
        if id == nil || id is NSNull { return nil }

        let params = req["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return resultResponse(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "bando-team", "version": BandoVersion.current],
            ])

        case "ping":
            return resultResponse(id: id, result: [String: Any]())

        case "tools/list":
            return resultResponse(id: id, result: ["tools": Self.toolSchemas()])

        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            return resultResponse(id: id, result: callTool(name: name, arguments: args))

        default:
            return errorResponse(id: id, code: -32601, message: "Método desconhecido: \(method)")
        }
    }

    /// Limite de membros por equipe criados pela ponte: um orquestrador em laço
    /// não consegue abrir sessões sem fim.
    static let maxMembers = 8

    /// Só o orquestrador da própria equipe usa a ponte. Os outros membros nem
    /// recebem o servidor (ver SessionService), e isto barra quem chamar à mão.
    func authorizedCaller() throws -> Session {
        guard let caller = try service.store.session(sessionId), caller.teamId == teamId else {
            throw BandoError.invalid("A sessão \(sessionId) não pertence à equipe \(teamId).")
        }
        guard caller.isOrchestrator else {
            throw BandoError.invalid("Só o orquestrador da equipe pode usar estas ferramentas.")
        }
        return caller
    }

    /// Texto que o terminal do agente trataria como comando, não como pedido:
    /// "!" roda shell no Claude Code e no Codex, "/" abre comandos do agente.
    static func isCommandText(_ text: String) -> Bool {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first else { return false }
        return first == "!" || first == "/"
    }

    func callTool(name: String, arguments args: [String: Any]) -> [String: Any] {
        do {
            _ = try authorizedCaller()
            let text: String
            switch name {
            case "team_list_members":
                text = try toolListMembers()
            case "team_spawn_member":
                text = try toolSpawnMember(args)
            case "team_delegate":
                text = try toolDelegate(args)
            case "team_read_output":
                text = try toolReadOutput(args)
            case "team_stop_member":
                text = try toolStopMember(args)
            default:
                return toolError("Ferramenta desconhecida: \(name)")
            }
            return ["content": [["type": "text", "text": text]], "isError": false]
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    private func toolListMembers() throws -> String {
        guard let team = try service.store.team(teamId) else { throw BandoError.notFound("equipe \(teamId)") }
        let members = try service.store.sessions(inTeam: teamId)
        let edges = try service.store.edges(inTeam: teamId)
        let payload: [String: Any] = [
            "team": ["id": team.id, "shortId": team.shortId, "name": team.name, "goal": team.goal ?? ""],
            "members": members.map { m -> [String: Any] in
                [
                    "id": m.id,
                    "shortId": m.shortId,
                    "roleId": m.roleId ?? "",
                    "role": m.roleTitle ?? m.name,
                    "isOrchestrator": m.isOrchestrator,
                    "agent": m.agent,
                    "provider": m.provider ?? "default",
                    "model": m.model ?? "",
                    "status": m.status.rawValue,
                    "statusDetail": m.statusDetail ?? "",
                    "worktree": m.worktreePath,
                    "sharedWorktree": m.worktreeSourceId != nil,
                    "branch": m.branch ?? "",
                    "responsibilities": m.responsibilities ?? "",
                ]
            },
            "edges": edges.map { e -> [String: Any] in
                ["id": e.id, "from": e.fromSessionId, "to": e.toSessionId, "kind": e.kind.rawValue]
            },
        ]
        return jsonString(payload)
    }

    private func toolSpawnMember(_ args: [String: Any]) throws -> String {
        guard let role = args["role"] as? String, !role.isEmpty else {
            throw BandoError.invalid("Campo obrigatório: role")
        }
        guard let caller = try service.store.session(sessionId) else {
            throw BandoError.notFound("sessão orquestradora \(sessionId)")
        }
        let agent = (args["agent"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? caller.agent
        let provider = (args["provider"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let model = (args["model"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let responsibilities = (args["responsibilities"] as? String) ?? ""
        let task = (args["task"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let shared = (args["shared_worktree"] as? Bool) ?? false
        let dependsOn = (args["depends_on"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let depSession = try dependsOn.map { try teamService.findMember($0, inTeam: teamId).id }
        if let task, Self.isCommandText(task) {
            throw BandoError.invalid("A tarefa não pode começar com \"!\" ou \"/\": o terminal do agente rodaria como comando.")
        }
        guard try service.store.sessions(inTeam: teamId).count < Self.maxMembers else {
            throw BandoError.invalid("A equipe já tem \(Self.maxMembers) membros; pare ou remova um antes de criar outro.")
        }

        let created = try teamService.addMember(
            to: teamId,
            roleTitle: role,
            agent: agent,
            provider: provider,
            model: model,
            responsibilities: responsibilities,
            prompt: task,
            isOrchestrator: false,
            worktree: shared ? .shared : .isolated,
            shareWithSessionId: shared ? sessionId : nil,
            dependsOnSessionId: depSession,
            connectFromSessionId: sessionId,
            edgeKind: depSession != nil ? .sequence : .delegate,
            startNow: true
        )
        return jsonString([
            "id": created.id,
            "shortId": created.shortId,
            "role": created.roleTitle ?? created.name,
            "agent": created.agent,
            "provider": created.provider ?? "default",
            "model": created.model ?? "",
            "status": created.status.rawValue,
            "worktree": created.worktreePath,
            "branch": created.branch ?? "",
        ])
    }

    private func toolDelegate(_ args: [String: Any]) throws -> String {
        guard let member = args["member"] as? String, !member.isEmpty,
              let task = args["task"] as? String, !task.isEmpty else {
            throw BandoError.invalid("Campos obrigatórios: member e task")
        }
        guard !Self.isCommandText(task) else {
            throw BandoError.invalid("A tarefa não pode começar com \"!\" ou \"/\": o terminal do agente rodaria como comando.")
        }
        let updated = try teamService.delegate(to: member, inTeam: teamId, task: task, fromSessionId: sessionId)
        return jsonString([
            "id": updated.id,
            "shortId": updated.shortId,
            "role": updated.roleTitle ?? updated.name,
            "status": updated.status.rawValue,
            "delivered": true,
            "hint": "Tarefa enviada ao terminal de \(updated.roleTitle ?? updated.name). Use team_read_output após alguns segundos para conferir o andamento.",
        ])
    }

    private func toolReadOutput(_ args: [String: Any]) throws -> String {
        guard let member = args["member"] as? String, !member.isEmpty else {
            throw BandoError.invalid("Campo obrigatório: member")
        }
        let lines = min(max((args["lines"] as? Int) ?? 60, 10), 300)
        let target = try teamService.findMember(member, inTeam: teamId)
        teamService.recordOutputRead(bySessionId: sessionId, targetId: target.id, inTeam: teamId)
        let screen: String
        if let tmux = try? Tmux(server: target.tmuxServer), tmux.hasSession(target.tmuxName) {
            screen = tmux.capture(target.tmuxName, lines: lines)
        } else {
            screen = "(sessão sem terminal ativo no momento)"
        }
        let changed = (try? Git())?.changedFileCount(target.worktreePath) ?? 0
        return jsonString([
            "id": target.id,
            "shortId": target.shortId,
            "role": target.roleTitle ?? target.name,
            "status": target.status.rawValue,
            "statusDetail": target.statusDetail ?? "",
            "changedFiles": changed,
            "output": screen,
        ])
    }

    private func toolStopMember(_ args: [String: Any]) throws -> String {
        guard let member = args["member"] as? String, !member.isEmpty else {
            throw BandoError.invalid("Campo obrigatório: member")
        }
        let target = try teamService.findMember(member, inTeam: teamId)
        guard target.id != sessionId else { throw BandoError.invalid("O orquestrador não pode parar a si mesmo.") }
        let stopped = try service.stop(target.id)
        return jsonString(["id": stopped.id, "shortId": stopped.shortId, "status": stopped.status.rawValue])
    }

    // MARK: - Helpers JSON-RPC

    private func resultResponse(id: Any?, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private func jsonString(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    public static func toolSchemas() -> [[String: Any]] {
        [
            [
                "name": "team_list_members",
                "description": "Lista os membros da equipe atual, seus papéis, agentes, providers, modelos, worktrees, estados e conexões.",
                "inputSchema": ["type": "object", "properties": [String: Any]()],
            ],
            [
                "name": "team_spawn_member",
                "description": "Cria e inicia um novo especialista conectado à equipe no Canvas com agente, provider, modelo e responsabilidade definidos.",
                "inputSchema": [
                    "type": "object",
                    "required": ["role", "responsibilities", "task"],
                    "properties": [
                        "role": ["type": "string", "description": "Título do papel (ex.: Revisor de Segurança, Frontend)."],
                        "responsibilities": ["type": "string", "description": "Responsabilidades permanentes do papel."],
                        "task": ["type": "string", "description": "Tarefa inicial atribuída ao agente."],
                        "agent": ["type": "string", "description": "ID do agente do catálogo (claude, codex, opencode, agy, etc.)."],
                        "provider": ["type": "string", "description": "ID do provider (anthropic, openrouter, ollama, venice, etc.)."],
                        "model": ["type": "string", "description": "Nome do modelo dentro do provider."],
                        "shared_worktree": ["type": "boolean", "description": "true para compartilhar o mesmo worktree do orquestrador; false (padrão) cria worktree próprio."],
                        "depends_on": ["type": "string", "description": "ID ou papel de outro membro que precisa terminar antes deste iniciar."],
                    ],
                ],
            ],
            [
                "name": "team_delegate",
                "description": "Envia ou delega uma nova tarefa para um membro existente da equipe (inicia se estiver parado ou envia no terminal se ativo).",
                "inputSchema": [
                    "type": "object",
                    "required": ["member", "task"],
                    "properties": [
                        "member": ["type": "string", "description": "ID, prefixo, roleId ou nome do papel do membro."],
                        "task": ["type": "string", "description": "Instrução ou tarefa a executar."],
                    ],
                ],
            ],
            [
                "name": "team_read_output",
                "description": "Captura as últimas linhas do terminal e o estado/arquivos alterados de um membro da equipe.",
                "inputSchema": [
                    "type": "object",
                    "required": ["member"],
                    "properties": [
                        "member": ["type": "string", "description": "ID, prefixo, roleId ou nome do papel do membro."],
                        "lines": ["type": "integer", "description": "Quantidade de linhas do terminal (padrão 60, máx 300)."],
                    ],
                ],
            ],
            [
                "name": "team_stop_member",
                "description": "Para a execução de um membro da equipe sem apagar o worktree.",
                "inputSchema": [
                    "type": "object",
                    "required": ["member"],
                    "properties": [
                        "member": ["type": "string", "description": "ID, prefixo, roleId ou nome do papel do membro."],
                    ],
                ],
            ],
        ]
    }
}
