import Foundation
import GRDB

/// Regras de negócio das equipes multi-agente e do Canvas.
public final class TeamService: @unchecked Sendable {
    public let service: SessionService
    public var store: BandoStore { service.store }
    public var config: BandoConfig { service.config }

    public init(service: SessionService) {
        self.service = service
    }

    public convenience init() throws {
        try self.init(service: SessionService())
    }

    // MARK: - Criação de equipe

    public struct RoleSpec: Sendable {
        public var roleId: String
        public var name: String
        public var responsibilities: String
        public var agent: String
        public var provider: String?
        public var model: String?
        public var compressor: String?
        public var isOrchestrator: Bool
        public var worktree: WorktreePolicy
        public var shareWorktreeWithRoleId: String?
        public var autoStart: Bool
        public var canvasX: Double
        public var canvasY: Double
        public var prompt: String?

        public init(
            roleId: String, name: String, responsibilities: String = "",
            agent: String, provider: String? = nil, model: String? = nil, compressor: String? = nil,
            isOrchestrator: Bool = false, worktree: WorktreePolicy = .isolated,
            shareWorktreeWithRoleId: String? = nil, autoStart: Bool = true,
            canvasX: Double = 100, canvasY: Double = 100, prompt: String? = nil
        ) {
            self.roleId = roleId
            self.name = name
            self.responsibilities = responsibilities
            self.agent = agent
            self.provider = provider
            self.model = model
            self.compressor = compressor
            self.isOrchestrator = isOrchestrator
            self.worktree = worktree
            self.shareWorktreeWithRoleId = shareWorktreeWithRoleId
            self.autoStart = autoStart
            self.canvasX = canvasX
            self.canvasY = canvasY
            self.prompt = prompt
        }
    }

    public struct EdgeSpec: Sendable {
        public var fromRoleId: String
        public var toRoleId: String
        public var kind: TeamEdgeKind
        public var label: String?

        public init(fromRoleId: String, toRoleId: String, kind: TeamEdgeKind, label: String? = nil) {
            self.fromRoleId = fromRoleId
            self.toRoleId = toRoleId
            self.kind = kind
            self.label = label
        }
    }

    public struct CreateTeamRequest: Sendable {
        public var project: Project
        public var name: String
        public var goal: String?
        public var templateId: String?
        public var roles: [RoleSpec]
        public var edges: [EdgeSpec]
        public var startNow: Bool

        public init(
            project: Project, name: String, goal: String? = nil, templateId: String? = nil,
            roles: [RoleSpec], edges: [EdgeSpec] = [], startNow: Bool = true
        ) {
            self.project = project
            self.name = name
            self.goal = goal
            self.templateId = templateId
            self.roles = roles
            self.edges = edges
            self.startNow = startNow
        }

        /// Constrói um pedido de criação a partir de um `TeamTemplate` do catálogo/usuário.
        public static func from(
            template: TeamTemplate,
            project: Project,
            name: String? = nil,
            goal: String? = nil,
            defaultAgent: String = "claude",
            defaultProvider: String? = nil,
            startNow: Bool = true
        ) -> CreateTeamRequest {
            let roles = template.roles.map { r in
                RoleSpec(
                    roleId: r.id,
                    name: r.name,
                    responsibilities: r.responsibilities,
                    agent: r.agent ?? project.defaultAgent ?? defaultAgent,
                    provider: r.provider ?? project.defaultProvider ?? defaultProvider,
                    model: r.model,
                    compressor: r.compressor,
                    isOrchestrator: r.isOrchestrator,
                    worktree: r.worktree,
                    shareWorktreeWithRoleId: r.shareWorktreeWith,
                    autoStart: r.autoStart,
                    canvasX: r.canvasX,
                    canvasY: r.canvasY
                )
            }
            let edges = template.edges.map { EdgeSpec(fromRoleId: $0.fromRole, toRoleId: $0.toRole, kind: $0.kind) }
            return CreateTeamRequest(
                project: project,
                name: name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name! : template.name,
                goal: goal,
                templateId: template.id,
                roles: roles,
                edges: edges,
                startNow: startNow
            )
        }
    }

    /// Cria a equipe, todas as sessões dos papéis e as ligações do Canvas.
    @discardableResult
    public func createTeam(_ req: CreateTeamRequest) throws -> (team: TeamRecord, sessions: [Session], edges: [TeamEdgeRecord]) {
        guard !req.roles.isEmpty else {
            throw BandoError.invalid("A equipe precisa de pelo menos um papel")
        }
        // Valida agentes, providers e compressores antes de criar qualquer worktree.
        for r in req.roles {
            _ = try config.agent(r.agent)
            if let p = r.provider {
                guard try config.provider(p).supports(agent: r.agent) else {
                    throw ConfigError.providerNotForAgent(provider: p, agent: r.agent)
                }
            }
            if let c = r.compressor {
                guard try config.compressor(c).supports(agent: r.agent) else {
                    throw ConfigError.compressorNotForAgent(compressor: c, agent: r.agent)
                }
            }
        }

        let team = TeamRecord(
            projectId: req.project.id,
            name: req.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Equipe" : req.name,
            goal: req.goal?.trimmingCharacters(in: .whitespacesAndNewlines),
            templateId: req.templateId
        )
        try store.pool.write { db in try team.insert(db) }

        // Nós com worktree próprio nascem primeiro para os compartilhados encontrarem o dono.
        let orderedRoles = topologicalWorktreeOrder(req.roles)
        var byRoleId: [String: Session] = [:]
        var createdSessions: [Session] = []

        for r in orderedRoles {
            let shareOwner: Session?
            if r.worktree == .shared {
                if let ref = r.shareWorktreeWithRoleId, let owner = byRoleId[ref] {
                    shareOwner = owner
                } else {
                    shareOwner = createdSessions.first(where: \.isOrchestrator) ?? createdSessions.first
                }
            } else {
                shareOwner = nil
            }

            let sessionPrompt = r.prompt ?? (r.isOrchestrator ? req.goal : nil)
            let session = try createMemberSession(
                team: team,
                project: req.project,
                spec: r,
                prompt: sessionPrompt,
                shareOwner: shareOwner
            )
            byRoleId[r.roleId] = session
            createdSessions.append(session)
        }

        // Ligações do Canvas + dependências de execução (`sequence` e `handoff`).
        var createdEdges: [TeamEdgeRecord] = []
        for e in req.edges {
            guard let from = byRoleId[e.fromRoleId], let to = byRoleId[e.toRoleId], from.id != to.id else { continue }
            if let edge = try? connect(teamId: team.id, from: from.id, to: to.id, kind: e.kind, label: e.label, syncContext: false) {
                createdEdges.append(edge)
            }
        }

        // Atualiza os arquivos `.bando/team-<id>.md` antes de subir os agentes.
        syncContextFiles(teamId: team.id)

        if req.startNow {
            let latest = try store.sessions(inTeam: team.id)
            let autoStartMap = Dictionary(uniqueKeysWithValues: req.roles.map { ($0.roleId, $0.autoStart) })
            for s in latest {
                let shouldStart = s.roleId.flatMap { autoStartMap[$0] } ?? true
                if shouldStart && s.status != .queued {
                    try service.start(s, mode: .fresh)
                }
            }
        }

        ChangeNotifier.post()
        return (team, try store.sessions(inTeam: team.id), try store.edges(inTeam: team.id))
    }

    /// Ordena para que os donos de worktree sejam criados antes dos que compartilham.
    private func topologicalWorktreeOrder(_ roles: [RoleSpec]) -> [RoleSpec] {
        let isolated = roles.filter { $0.worktree == .isolated }
        let shared = roles.filter { $0.worktree == .shared }
        return isolated + shared
    }

    private func createMemberSession(
        team: TeamRecord,
        project: Project,
        spec: RoleSpec,
        prompt: String?,
        shareOwner: Session?
    ) throws -> Session {
        let useWorktree = shareOwner == nil
        var s = try service.create(.init(
            project: project,
            prompt: prompt,
            name: spec.name,
            agent: spec.agent,
            provider: spec.provider,
            model: spec.model,
            useWorktree: useWorktree,
            startNow: false,
            compressor: spec.compressor
        ))

        try store.pool.write { db in
            guard var fresh = try Session.fetchOne(db, key: s.id) else { return }
            fresh.teamId = team.id
            fresh.roleId = spec.roleId
            fresh.roleTitle = spec.name
            fresh.responsibilities = spec.responsibilities.isEmpty ? nil : spec.responsibilities
            fresh.isOrchestrator = spec.isOrchestrator
            fresh.canvasX = spec.canvasX
            fresh.canvasY = spec.canvasY
            fresh.status = .stopped
            fresh.customName = true
            if let shareOwner {
                fresh.worktreePath = shareOwner.worktreePath
                fresh.branch = shareOwner.branch
                fresh.baseBranch = shareOwner.baseBranch
                fresh.usesWorktree = false
                fresh.worktreeSourceId = shareOwner.id
            }
            fresh.updatedAt = Date()
            try fresh.update(db)
            s = fresh
        }
        return s
    }

    // MARK: - Edição dinâmica da equipe e do Canvas

    /// Adiciona um novo membro à equipe (pela UI, CLI ou dinamicamente pelo orquestrador).
    @discardableResult
    public func addMember(
        to teamId: String,
        roleTitle: String,
        roleId: String? = nil,
        agent: String,
        provider: String? = nil,
        model: String? = nil,
        compressor: String? = nil,
        responsibilities: String = "",
        prompt: String? = nil,
        isOrchestrator: Bool = false,
        worktree: WorktreePolicy = .isolated,
        shareWithSessionId: String? = nil,
        dependsOnSessionId: String? = nil,
        connectFromSessionId: String? = nil,
        edgeKind: TeamEdgeKind = .delegate,
        canvasX: Double? = nil,
        canvasY: Double? = nil,
        startNow: Bool = true
    ) throws -> Session {
        guard let team = try store.team(teamId),
              let project = try store.project(team.projectId) else {
            throw BandoError.notFound("equipe \(teamId)")
        }
        let existing = try store.sessions(inTeam: teamId)
        let rid = roleId ?? uniqueRoleId(from: roleTitle, existing: existing)
        let pos = defaultPosition(existing: existing, x: canvasX, y: canvasY)

        var shareOwner: Session?
        if worktree == .shared {
            if let shareWithSessionId {
                shareOwner = existing.first { $0.id == shareWithSessionId || $0.id.hasPrefix(shareWithSessionId) || $0.roleId == shareWithSessionId }
            }
            if shareOwner == nil {
                shareOwner = existing.first(where: \.isOrchestrator) ?? existing.first
            }
        }

        let spec = RoleSpec(
            roleId: rid,
            name: roleTitle,
            responsibilities: responsibilities,
            agent: agent,
            provider: provider,
            model: model,
            compressor: compressor,
            isOrchestrator: isOrchestrator,
            worktree: worktree,
            autoStart: startNow,
            canvasX: pos.x,
            canvasY: pos.y,
            prompt: prompt
        )
        let session = try createMemberSession(team: team, project: project, spec: spec, prompt: prompt, shareOwner: shareOwner)

        // A dependência vale sempre, com ou sem conexão de quem criou: antes,
        // com connectFromSessionId preenchido o membro começava sem esperar.
        if let dep = dependsOnSessionId {
            try service.setDependency(session.id, parent: dep)
            // Dependência ainda rodando: o membro espera na fila e inicia sozinho
            // quando ela terminar (mesmo caminho do --depends-on).
            if let parent = try store.session(dep), !parent.status.releasesDependents {
                try service.transition(session.id, to: .queued, kind: "queued", detail: "esperando \(parent.roleTitle ?? parent.name)")
            }
        }
        if let fromId = connectFromSessionId ?? dependsOnSessionId {
            let kind: TeamEdgeKind = dependsOnSessionId != nil && connectFromSessionId == nil ? .sequence : edgeKind
            _ = try? connect(teamId: teamId, from: fromId, to: session.id, kind: kind, label: nil, syncContext: false)
            if startNow {
                recordFlow(teamId: teamId, from: fromId, to: session.id)
            }
        }

        syncContextFiles(teamId: teamId)

        let updated = try store.session(session.id) ?? session
        if startNow && updated.status != .queued {
            try service.start(updated, mode: .fresh)
        }
        try touchTeam(teamId)
        ChangeNotifier.post()
        return try store.session(session.id) ?? updated
    }

    /// Vincula uma sessão existente do mesmo projeto ao Canvas da equipe.
    @discardableResult
    public func attachExistingSession(
        _ sessionId: String,
        to teamId: String,
        roleTitle: String? = nil,
        responsibilities: String? = nil,
        canvasX: Double? = nil,
        canvasY: Double? = nil
    ) throws -> Session {
        guard try store.team(teamId) != nil else { throw BandoError.notFound("equipe \(teamId)") }
        let existing = try store.sessions(inTeam: teamId)
        let pos = defaultPosition(existing: existing, x: canvasX, y: canvasY)
        try store.pool.write { db in
            guard var s = try Session.fetchOne(db, key: sessionId) else { throw BandoError.notFound("sessão \(sessionId)") }
            s.teamId = teamId
            s.roleId = s.roleId ?? uniqueRoleId(from: roleTitle ?? s.name, existing: existing)
            s.roleTitle = roleTitle ?? s.roleTitle ?? s.name
            if let responsibilities { s.responsibilities = responsibilities }
            s.canvasX = s.canvasX ?? pos.x
            s.canvasY = s.canvasY ?? pos.y
            s.updatedAt = Date()
            try s.update(db)
        }
        syncContextFiles(teamId: teamId)
        try touchTeam(teamId)
        ChangeNotifier.post()
        return try store.session(sessionId)!
    }

    /// Cria ligação direcionada no Canvas entre duas sessões da mesma equipe.
    @discardableResult
    public func connect(
        teamId: String,
        from fromSessionId: String,
        to toSessionId: String,
        kind: TeamEdgeKind,
        label: String? = nil,
        syncContext: Bool = true
    ) throws -> TeamEdgeRecord {
        guard fromSessionId != toSessionId else {
            throw BandoError.invalid("Uma sessão não pode se ligar a ela mesma")
        }
        let members = try store.sessions(inTeam: teamId)
        guard members.contains(where: { $0.id == fromSessionId }),
              let target = members.first(where: { $0.id == toSessionId }) else {
            throw BandoError.notFound("membro da equipe")
        }

        if let existing = try store.edges(inTeam: teamId)
            .first(where: { $0.fromSessionId == fromSessionId && $0.toSessionId == toSessionId && $0.kind == kind }) {
            return existing
        }

        if kind == .sequence || kind == .handoff {
            // Reutiliza a detecção de ciclos do SessionService.
            try service.setDependency(target.id, parent: fromSessionId)
        }

        let edge = TeamEdgeRecord(teamId: teamId, fromSessionId: fromSessionId, toSessionId: toSessionId, kind: kind, label: label)
        try store.pool.write { db in try edge.insert(db) }
        if syncContext { syncContextFiles(teamId: teamId) }
        try touchTeam(teamId)
        ChangeNotifier.post()
        return edge
    }

    public func disconnect(edgeId: String) throws {
        let edge: TeamEdgeRecord? = try store.pool.write { db in
            guard let e = try TeamEdgeRecord.fetchOne(db, key: edgeId) else { return nil }
            _ = try TeamEdgeRecord.deleteOne(db, key: edgeId)
            return e
        }
        guard let edge else { return }
        if (edge.kind == .sequence || edge.kind == .handoff),
           let target = try store.session(edge.toSessionId), target.dependsOn == edge.fromSessionId {
            try? service.setDependency(target.id, parent: nil)
        }
        syncContextFiles(teamId: edge.teamId)
        try? touchTeam(edge.teamId)
        ChangeNotifier.post()
    }

    public func updatePosition(sessionId: String, x: Double, y: Double) throws {
        try store.pool.write { db in
            try db.execute(sql: "UPDATE session SET canvasX = ?, canvasY = ? WHERE id = ?", arguments: [x, y, sessionId])
        }
        ChangeNotifier.post()
    }

    public func updateFrame(sessionId: String, x: Double, y: Double, width: Double?, height: Double?) throws {
        try store.pool.write { db in
            try db.execute(
                sql: "UPDATE session SET canvasX = ?, canvasY = ?, canvasWidth = ?, canvasHeight = ? WHERE id = ?",
                arguments: [x, y, width, height, sessionId]
            )
        }
        ChangeNotifier.post()
    }

    public func updateRole(
        sessionId: String,
        roleTitle: String?,
        responsibilities: String?,
        isOrchestrator: Bool? = nil,
        agent: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        compressor: String? = nil,
        clearProvider: Bool = false,
        clearModel: Bool = false,
        clearCompressor: Bool = false
    ) throws {
        var teamId: String?
        try store.pool.write { db in
            guard var s = try Session.fetchOne(db, key: sessionId) else { throw BandoError.notFound("sessão \(sessionId)") }
            if let roleTitle, !roleTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                s.roleTitle = roleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                s.name = s.roleTitle!
                s.customName = true
            }
            if let responsibilities {
                let clean = responsibilities.trimmingCharacters(in: .whitespacesAndNewlines)
                s.responsibilities = clean.isEmpty ? nil : clean
            }
            if let isOrchestrator { s.isOrchestrator = isOrchestrator }
            if let agent { _ = try config.agent(agent); s.agent = agent }
            if clearProvider { s.provider = nil } else if let provider { s.provider = provider }
            if clearModel { s.model = nil } else if let model { s.model = model }
            if clearCompressor { s.compressor = nil } else if let compressor { s.compressor = compressor }
            s.updatedAt = Date()
            try s.update(db)
            teamId = s.teamId
        }
        if let teamId {
            syncContextFiles(teamId: teamId)
            try? touchTeam(teamId)
        }
        ChangeNotifier.post()
    }

    // MARK: - Coordenação e delegação

    /// Encontra um membro dentro da equipe por ID completo, prefixo, roleId ou roleTitle.
    public func findMember(_ ref: String, inTeam teamId: String) throws -> Session {
        let members = try store.sessions(inTeam: teamId)
        if let exact = members.first(where: { $0.id == ref }) { return exact }
        if let byRole = members.first(where: { $0.roleId?.caseInsensitiveCompare(ref) == .orderedSame }) { return byRole }
        let byTitle = members.filter {
            ($0.roleTitle ?? $0.name).localizedCaseInsensitiveCompare(ref) == .orderedSame
        }
        if byTitle.count == 1 { return byTitle[0] }
        let byPrefix = members.filter { $0.id.hasPrefix(ref.lowercased()) }
        if byPrefix.count == 1 { return byPrefix[0] }
        if byTitle.count + byPrefix.count > 1 { throw BandoError.ambiguous(ref) }
        throw BandoError.notFound("membro \(ref) na equipe")
    }

    /// Delega uma tarefa para um nó da equipe: envia no tmux se vivo, ou inicia/retoma com a tarefa.
    @discardableResult
    public func delegate(to ref: String, inTeam teamId: String, task: String, fromSessionId: String? = nil) throws -> Session {
        let target = try findMember(ref, inTeam: teamId)
        let cleanTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTask.isEmpty else { throw BandoError.invalid("A tarefa delegada não pode ficar vazia") }

        let senderId = fromSessionId
            ?? (try? store.sessions(inTeam: teamId))?.first(where: { $0.isOrchestrator && $0.id != target.id })?.id
        let senderLabel = try? senderId.flatMap { try store.session($0) }.map { $0.roleTitle ?? $0.name }
        let targetLabel = target.roleTitle ?? target.name
        let routeLabel = senderLabel.map { "\($0) → \(targetLabel)" } ?? targetLabel

        let tmux = try? Tmux(server: target.tmuxServer)
        if let tmux, tmux.hasSession(target.tmuxName), target.status.isLive {
            // Se o nó acabou de subir e ainda está inicializando o TUI, aguarda brevemente antes de enviar teclas.
            if target.status == .starting {
                for _ in 0..<6 {
                    let current = try? store.session(target.id)?.status
                    if current != .starting { break }
                    Thread.sleep(forTimeInterval: 0.45)
                }
            }
            let busy = (try? service.config.agent(target.agent))?.busy.flatMap { try? Regex($0) }
            try tmux.sendInstruction(target.tmuxName, text: cleanTask, busy: busy)
            try service.record(target.id, kind: "message", detail: String(cleanTask.prefix(200)))
            let summary = "\(routeLabel): \(cleanTask.replacingOccurrences(of: "\n", with: " ").prefix(140))"
            try service.record(target.id, kind: "team-delegate", detail: summary)
            let latestStatus = (try? store.session(target.id)?.status) ?? target.status
            if latestStatus != .working {
                try? service.transition(target.id, to: .working, kind: "team-delegate", detail: summary)
            }
            if let senderId { recordFlow(teamId: teamId, from: senderId, to: target.id) }
            return try store.session(target.id) ?? target
        }

        // Nunca iniciou ainda: grava como prompt e inicia do zero com contexto completo.
        let neverStarted = !(try store.events(sessionId: target.id)).contains(where: { $0.kind == "start" || $0.kind == "resume" })
        try store.pool.write { db in
            guard var fresh = try Session.fetchOne(db, key: target.id) else { return }
            if neverStarted { fresh.prompt = cleanTask }
            fresh.updatedAt = Date()
            try fresh.update(db)
        }
        let updated = try store.session(target.id) ?? target
        syncContextFiles(teamId: teamId)
        if neverStarted {
            try service.start(updated, mode: .fresh)
        } else {
            try service.start(updated, mode: .handoff(cleanTask))
        }
        let summary = "\(routeLabel): \(cleanTask.replacingOccurrences(of: "\n", with: " ").prefix(140))"
        try service.record(target.id, kind: "team-delegate", detail: summary)
        if let senderId { recordFlow(teamId: teamId, from: senderId, to: target.id) }
        return try store.session(target.id) ?? updated
    }

    /// Registra leitura de saída/resultado de `targetId` por `callerId` (fluxo de volta no Canvas).
    public func recordOutputRead(bySessionId callerId: String?, targetId: String, inTeam teamId: String) {
        let receiver = callerId
            ?? (try? store.sessions(inTeam: teamId))?.first(where: { $0.isOrchestrator && $0.id != targetId })?.id
        guard let receiver, receiver != targetId else { return }
        if let reader = try? store.session(receiver), let target = try? store.session(targetId) {
            let readerLabel = reader.roleTitle ?? reader.name
            let targetLabel = target.roleTitle ?? target.name
            try? service.record(targetId, kind: "team-read", detail: "\(readerLabel) leu saída de \(targetLabel)")
            ChangeNotifier.post()
        }
        recordFlow(teamId: teamId, from: targetId, to: receiver)
    }

    /// Quando um membro da equipe conclui um turno ou pede resposta, registra fluxo
    /// de retorno nas ligações que apontam para ele (ex.: Especialista → Orquestrador).
    public func recordMemberTurnReturn(sessionId: String) {
        guard let s = try? store.session(sessionId), let teamId = s.teamId,
              let edges = try? store.edges(inTeam: teamId) else { return }
        let incoming = edges.filter { $0.toSessionId == sessionId }
        guard !incoming.isEmpty else { return }
        let memberLabel = s.roleTitle ?? s.name
        let targetNames = incoming.compactMap { e -> String? in
            guard let peer = try? store.session(e.fromSessionId) else { return nil }
            return peer.roleTitle ?? peer.name
        }
        if !targetNames.isEmpty {
            try? service.record(sessionId, kind: "team-return", detail: "\(memberLabel) → \(targetNames.joined(separator: ", ")): concluiu turno (\(s.status.label))")
            ChangeNotifier.post()
        }
        for edge in incoming {
            recordFlow(teamId: teamId, from: sessionId, to: edge.fromSessionId)
        }
    }

    /// Atualiza a direção e o timestamp da última troca de informação entre `senderId` e `receiverId`.
    public func recordFlow(teamId: String, from senderId: String, to receiverId: String) {
        let now = Date()
        let changed = (try? store.pool.write { db -> Bool in
            let edges = try TeamEdgeRecord.filter(Column("teamId") == teamId).fetchAll(db)
            var updatedAny = false
            for var edge in edges {
                let desired: TeamEdgeDirection
                if edge.fromSessionId == senderId && edge.toSessionId == receiverId {
                    desired = .forward
                } else if edge.fromSessionId == receiverId && edge.toSessionId == senderId {
                    desired = .reverse
                } else {
                    continue
                }
                // Se houve fluxo no sentido oposto nos últimos 4 s, mostra troca bidirecional.
                if let prev = edge.lastDirection, prev != desired,
                   let at = edge.lastActivityAt, now.timeIntervalSince(at) < 4 {
                    edge.lastDirection = .bidirectional
                } else {
                    edge.lastDirection = desired
                }
                edge.lastActivityAt = now
                edge.interactionCount += 1
                try edge.update(db)
                updatedAny = true
            }
            return updatedAny
        }) ?? false
        if changed { ChangeNotifier.post() }
    }

    /// Prepara o arquivo de handoff quando uma sessão pai com aresta `.handoff` libera um dependente.
    public func handoffPromptForDependent(parent: Session, child: Session) -> String? {
        guard let teamId = child.teamId,
              let edges = try? store.edges(inTeam: teamId),
              edges.contains(where: { $0.fromSessionId == parent.id && $0.toSessionId == child.id && $0.kind == .handoff })
        else { return nil }

        let rel = ".bando/handoff-\(parent.shortId).md"
        let dst = URL(fileURLWithPath: child.worktreePath).appendingPathComponent(rel)
        var sections: [String] = []
        sections.append("# Handoff de \(parent.roleTitle ?? parent.name) (\(parent.shortId))")
        if let resp = parent.responsibilities, !resp.isEmpty {
            sections.append("Responsabilidade anterior: \(resp)")
        }
        if let tmux = try? Tmux(server: parent.tmuxServer), tmux.hasSession(parent.tmuxName) {
            let tail = tmux.capture(parent.tmuxName, lines: 50).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                sections.append("## Última saída do terminal\n```\n\(tail)\n```")
            }
        }
        if let git = try? Git(), let r = try? Shell.run(git.executable, ["status", "--short"], cwd: parent.worktreePath), r.ok, !r.trimmed.isEmpty {
            sections.append("## Arquivos alterados no worktree anterior (`\(parent.worktreePath)`)\n```\n\(r.trimmed)\n```")
        }
        try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        Handoff.ensureIgnored(worktree: child.worktreePath)
        try? sections.joined(separator: "\n\n").write(to: dst, atomically: true, encoding: .utf8)
        recordFlow(teamId: teamId, from: parent.id, to: child.id)

        let base = child.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = "A etapa anterior (\(parent.roleTitle ?? parent.name)) concluiu. Leia o repasse em `\(rel)` antes de continuar."
        return [intro, base].compactMap { $0 }.joined(separator: "\n\n")
    }

    /// Inicia todos os nós parados/prontos da equipe que não dependem de outro nó ainda ativo.
    public func startTeam(_ teamId: String) throws {
        let members = try store.sessions(inTeam: teamId)
        syncContextFiles(teamId: teamId)
        for s in members {
            if s.status.isLive || s.status == .queued { continue }
            if let dep = s.dependsOn, let parent = members.first(where: { $0.id == dep }), !parent.status.releasesDependents {
                try service.transition(s.id, to: .queued, kind: "team-start")
                continue
            }
            let neverStarted = !(try store.events(sessionId: s.id)).contains(where: { $0.kind == "start" || $0.kind == "resume" })
            try service.start(s, mode: (neverStarted || s.nativeId == nil) ? .fresh : .resume)
        }
    }

    public func stopTeam(_ teamId: String) throws {
        for s in try store.sessions(inTeam: teamId) where s.status.isLive || s.status == .queued {
            _ = try service.stop(s.id)
        }
    }

    /// Verifica se apagar a equipe perderia trabalho não salvo em algum worktree próprio.
    public func deleteBlockers(teamId: String) throws -> [String] {
        var reasons: [String] = []
        for s in try store.sessions(inTeam: teamId) where s.usesWorktree {
            if let why = try service.deleteBlocker(s.id) {
                reasons.append("\(s.roleTitle ?? s.name): \(why)")
            }
        }
        return reasons
    }

    public func deleteTeam(_ teamId: String, removeWorktrees: Bool = true, deleteBranches: Bool = false, force: Bool = false) throws {
        if removeWorktrees && !force {
            let blockers = try deleteBlockers(teamId: teamId)
            if !blockers.isEmpty {
                throw BandoError.unsafeDelete(blockers.joined(separator: "; "))
            }
        }
        let members = try store.sessions(inTeam: teamId)
        // Remove sessões dependentes (worktree compartilhado) antes das donas.
        let ordered = members.filter { !$0.usesWorktree } + members.filter { $0.usesWorktree }
        for s in ordered {
            try service.delete(s.id, options: .init(removeWorktree: removeWorktrees, deleteBranch: deleteBranches, force: force))
        }
        _ = try store.pool.write { db in try TeamRecord.deleteOne(db, key: teamId) }
        ChangeNotifier.post()
    }

    /// Exporta a topologia atual de uma equipe no Canvas como `TeamTemplate`.
    public func exportTemplate(teamId: String, templateId: String, name: String, description: String?) throws -> TeamTemplate {
        let members = try store.sessions(inTeam: teamId)
        guard !members.isEmpty else { throw BandoError.invalid("A equipe não possui nós para salvar") }
        let edges = try store.edges(inTeam: teamId)
        let roleById = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.roleId ?? $0.shortId) })
        let roles = members.enumerated().map { idx, s in
            let shareRole = s.worktreeSourceId.flatMap { roleById[$0] }
            return TeamRoleDefinition(
                id: s.roleId ?? s.shortId,
                name: s.roleTitle ?? s.name,
                responsibilities: s.responsibilities ?? "",
                agent: s.agent,
                provider: s.provider,
                model: s.model,
                compressor: s.compressor,
                isOrchestrator: s.isOrchestrator,
                worktree: s.worktreeSourceId != nil ? .shared : .isolated,
                shareWorktreeWith: shareRole,
                autoStart: true,
                canvasX: s.canvasX ?? Double(100 + (idx % 3) * 380),
                canvasY: s.canvasY ?? Double(100 + (idx / 3) * 260)
            )
        }
        let edgeDefs = edges.compactMap { e -> TeamEdgeDefinition? in
            guard let f = roleById[e.fromSessionId], let t = roleById[e.toSessionId] else { return nil }
            return TeamEdgeDefinition(fromRole: f, toRole: t, kind: e.kind)
        }
        return TeamTemplate(id: templateId, name: name, description: description, roles: roles, edges: edgeDefs)
    }

    // MARK: - Auxiliares

    public func syncContextFiles(teamId: String) {
        guard let team = try? store.team(teamId),
              let members = try? store.sessions(inTeam: teamId),
              let edges = try? store.edges(inTeam: teamId) else { return }
        var writtenDirs = Set<String>()
        for s in members where FileManager.default.fileExists(atPath: s.worktreePath) {
            // Se dois nós compartilham o worktree, cada um ainda recebe contexto atualizado;
            // gravamos uma vez por diretório quando o mesmo arquivo representa a equipe inteira,
            // ou específico para o papel do último (como cada sessão tem papel próprio, escrevemos
            // só se o diretório ainda não recebeu ou usamos team-<teamShortId>-<sessionShortId>.md).
            _ = writtenDirs.insert(s.worktreePath)
            _ = TeamContext.writeContextFile(for: s, team: team, members: members, edges: edges, config: config)
        }
    }

    private func touchTeam(_ teamId: String) throws {
        try store.pool.write { db in
            try db.execute(sql: "UPDATE team SET updatedAt = ? WHERE id = ?", arguments: [Date(), teamId])
        }
    }

    private func uniqueRoleId(from title: String, existing: [Session]) -> String {
        let base = Slug.make(title, maxLength: 24)
        let taken = Set(existing.compactMap(\.roleId))
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    private func defaultPosition(existing: [Session], x: Double?, y: Double?) -> (x: Double, y: Double) {
        if let x, let y { return (x, y) }
        let idx = existing.count
        return (Double(100 + (idx % 3) * 380), Double(100 + (idx / 3) * 280))
    }
}
