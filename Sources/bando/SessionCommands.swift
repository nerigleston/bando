import ArgumentParser
import BandoCore
import Foundation

func makeService() throws -> SessionService {
    let config = try loadConfig()
    return SessionService(store: try BandoStore(), config: config)
}

func relative(_ date: Date) -> String {
    let s = Int(Date().timeIntervalSince(date))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)min" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}

// MARK: - new

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Cria uma sessão: worktree + tmux + agente.",
        discussion: """
        Exemplos:
          bando new "corrigir o login"
          bando new -a agy "refatorar a API"
          bando new -a claude -p openrouter -m z-ai/glm-5 "revisar testes"
          bando new --depends-on a1b2 "escrever a documentação"
        """
    )

    @Argument(help: "Tarefa inicial para o agente.")
    var prompt: String?

    @Option(name: .shortAndLong, help: "Agente (padrão: o do projeto, ou claude).")
    var agent: String?

    @Option(name: .shortAndLong, help: "Provider.")
    var provider: String?

    @Option(name: .shortAndLong, help: "Modelo.")
    var model: String?

    @Option(name: .shortAndLong, help: "Nome da sessão (padrão: início da tarefa).")
    var name: String?

    @Option(name: .long, help: "Projeto: caminho, nome ou ID (padrão: pasta atual).")
    var project: String?

    @Option(name: .long, help: "Branch (padrão: bando/<nome>).")
    var branch: String?

    @Option(name: .long, help: "Branch base (padrão: o atual do repositório).")
    var base: String?

    @Flag(name: .long, help: "Roda na pasta do projeto, sem worktree.")
    var noWorktree = false

    @Option(name: .long, help: "Só inicia quando esta sessão terminar a primeira vez.")
    var dependsOn: String?

    @Flag(name: .long, help: "Entra no terminal da sessão logo depois de criar.")
    var attach = false

    func run() throws {
        let service = try makeService()
        let proj = try project.map { try service.findProject($0) }
            ?? service.ensureProject(at: FileManager.default.currentDirectoryPath)
        let s = try service.create(.init(
            project: proj, prompt: prompt, name: name,
            agent: agent ?? proj.defaultAgent ?? "claude",
            provider: provider ?? proj.defaultProvider, model: model,
            branch: branch, baseBranch: base, useWorktree: !noWorktree, dependsOn: dependsOn
        ))
        print("\(s.shortId)  \(s.name)")
        print("  \(s.status.label) · \(s.agent)\(s.provider.map { "·\($0)" } ?? "") · \(s.worktreePath)")
        if s.status == .queued, let parent = s.dependsOn {
            print("  na fila: inicia quando \(parent.prefix(8)) terminar")
        }
        if attach { try attachSession(s.id) }
    }
}

// MARK: - ls

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ls", abstract: "Lista sessões, as mais urgentes primeiro.")

    @Flag(name: .shortAndLong, help: "Inclui sessões encerradas e paradas.")
    var all = false

    @Option(name: .long, help: "Filtra por projeto.")
    var project: String?

    @Flag(name: .long, help: "Saída em JSON.")
    var json = false

    func run() throws {
        let service = try makeService()
        try? service.reconcile()
        var sessions = try service.store.sessions(includeFinished: all)
        if let project {
            let p = try service.findProject(project)
            sessions = sessions.filter { $0.projectId == p.id }
        }
        sessions.sort { ($0.status.urgency, $1.statusChangedAt) < ($1.status.urgency, $0.statusChangedAt) }
        if json {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            print(String(decoding: try enc.encode(sessions), as: UTF8.self))
            return
        }
        if sessions.isEmpty {
            print(all ? "Nenhuma sessão." : "Nenhuma sessão ativa. Crie com: bando new \"tarefa\"  (ou veja todas com -a)")
            return
        }
        let projects = Dictionary(uniqueKeysWithValues: try service.store.projects().map { ($0.id, $0.name) })
        var rows = [["ID", "ESTADO", "HÁ", "PROJETO", "AGENTE", "NOME"]]
        for s in sessions {
            var agent = s.agent
            if let p = s.provider { agent += "·\(p)" }
            var name = s.name
            if let d = s.statusDetail, s.status == .waiting { name += "  ← \(d.prefix(50))" }
            rows.append([s.shortId, s.status.label, relative(s.statusChangedAt), projects[s.projectId] ?? "?", agent, name])
        }
        printTable(rows)
    }
}

// MARK: - attach / msg / stop / resume / rm / seen

struct Attach: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Entra no terminal da sessão (sair sem parar: Ctrl-b d).")
    @Argument(help: "ID, prefixo do ID ou nome.") var session: String

    func run() throws { try attachSession(session) }
}

/// Substitui o processo atual pelo `tmux attach` da sessão.
func attachSession(_ ref: String) throws {
    let service = try makeService()
    let s = try service.store.findSession(ref)
    let tmux = try Tmux(server: s.tmuxServer)
    guard tmux.hasSession(s.tmuxName) else {
        throw ValidationError("A sessão não está rodando. Retome com: bando resume \(s.shortId)")
    }
    try? service.markSeen(s.id)
    let argv = tmux.attachCommand(s.tmuxName)
    let c = argv.map { strdup($0) } + [nil]
    execv(argv[0], c)
    throw ExitCode.failure
}

struct Msg: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Digita uma mensagem no terminal da sessão.")
    @Argument var session: String
    @Argument(help: "Texto. Sem argumento, lê da entrada padrão.") var text: String?
    @Flag(name: .long, help: "Não aperta Enter no fim.") var noEnter = false

    func run() throws {
        let body = text ?? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        try makeService().message(session, text: body.trimmingCharacters(in: .newlines), enter: !noEnter)
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Para a sessão (encerra o tmux; o worktree fica).")
    @Argument var session: String
    func run() throws {
        let s = try makeService().stop(session)
        print("parada: \(s.shortId) \(s.name)")
    }
}

struct Resume: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Retoma uma sessão parada, continuando a conversa do agente.")
    @Argument var session: String
    @Flag(name: .long) var attach = false
    func run() throws {
        let s = try makeService().resume(session)
        print("retomada: \(s.shortId) \(s.name)")
        if attach { try attachSession(s.id) }
    }
}

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Apaga a sessão e o worktree. Recusa se houver mudança não commitada ou commit sem push."
    )
    @Argument var session: String
    @Flag(name: .long, help: "Mantém o worktree no disco.") var keepWorktree = false
    @Flag(name: .long, help: "Apaga também o branch.") var deleteBranch = false
    @Flag(name: .long, help: "Apaga mesmo com trabalho não salvo.") var force = false

    func run() throws {
        let service = try makeService()
        let s = try service.store.findSession(session)
        try service.delete(s.id, options: .init(removeWorktree: !keepWorktree, deleteBranch: deleteBranch, force: force))
        print("apagada: \(s.shortId) \(s.name)")
    }
}

struct Seen: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Marca como vista (\"pronto para revisar\" vira \"ocioso\").")
    @Argument var session: String
    func run() throws {
        let service = try makeService()
        try service.markSeen(try service.store.findSession(session).id)
    }
}

struct Log: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Histórico de estados de uma sessão.")
    @Argument var session: String
    func run() throws {
        let service = try makeService()
        let s = try service.store.findSession(session)
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm:ss"
        for e in try service.store.events(sessionId: s.id) {
            print("\(f.string(from: e.at))  \(e.kind.padding(toLength: 14, withPad: " ", startingAt: 0)) \(e.status?.label ?? "")\(e.detail.map { "  \($0)" } ?? "")")
        }
    }
}

// MARK: - projects

struct Projects: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Lista projetos.", subcommands: [ListProjects.self, SetProject.self], defaultSubcommand: ListProjects.self)

    struct ListProjects: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "ls")
        func run() throws {
            let service = try makeService()
            let sessions = try service.store.sessions()
            var rows = [["ID", "NOME", "SESSÕES", "AGENTE", "CAMINHO"]]
            for p in try service.store.projects() {
                let count = sessions.filter { $0.projectId == p.id }.count
                rows.append([String(p.id.prefix(8)), p.name, "\(count)", p.defaultAgent ?? "-", p.path])
            }
            printTable(rows)
        }
    }

    struct SetProject: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set", abstract: "Muda padrões do projeto.")
        @Argument(help: "Projeto (caminho, nome ou ID).") var project: String
        @Option var agent: String?
        @Option var provider: String?
        @Option(name: .long, help: "Branch base dos worktrees.") var base: String?
        @Option(name: .long, help: "Script rodado no worktree novo antes do agente. Vazio remove.") var setup: String?
        @Option(name: .long, help: "Pasta dos worktrees.") var worktreeRoot: String?

        func run() throws {
            let service = try makeService()
            var p = try service.findProject(project)
            if let agent { _ = try service.config.agent(agent); p.defaultAgent = agent }
            if let provider { _ = try service.config.provider(provider); p.defaultProvider = provider }
            if let base { p.baseBranch = base }
            if let setup { p.setupScript = setup.isEmpty ? nil : setup }
            if let worktreeRoot { p.worktreeRoot = worktreeRoot }
            try service.store.pool.write { db in try p.update(db) }
            ChangeNotifier.post()
            print("ok: \(p.name)")
        }
    }
}

// MARK: - internos: run e hook

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uso interno: supervisor da sessão dentro do tmux.", shouldDisplay: false)
    @Argument var session: String
    @Flag var resume = false
    @Option var fork: String?
    @Option var prompt: String?

    func run() throws {
        let service = try makeService()
        Supervisor(service: service, sessionId: session, resume: resume, forkFrom: fork, promptOverride: prompt).run()
    }
}

struct Hook: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uso interno: chamado pelos hooks dos agentes.", shouldDisplay: false)
    @Argument var event: String
    @Option var session: String?

    func run() {
        // Sem sessão do Bando (hook disparado fora dele): não faz nada.
        guard let id = session ?? ProcessInfo.processInfo.environment["BANDO_SESSION_ID"], !id.isEmpty,
              let service = try? makeService() else { return }
        let payload = isatty(STDIN_FILENO) == 0 ? FileHandle.standardInput.readDataToEndOfFile() : nil
        HookHandler.handle(event: event, sessionId: id, payload: payload, service: service)
    }
}

// MARK: - import

struct Import: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Importa dados de outras ferramentas.", subcommands: [Xirp.self])

    struct Xirp: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Importa projetos, sessões, custos e PRs do Xirp (lê o backup JSON, não altera o Xirp).")
        @Option(name: .long, help: "Arquivo de backup (padrão: o mais recente).") var backup: String?
        @Flag(name: .long, help: "Mostra o que entraria, sem gravar.") var dryRun = false
        @Flag(name: .customLong("so-sessoes"), help: "Importa só projetos e sessões, sem custos nem PRs.") var sessionsOnly = false

        func run() throws {
            let store = try BandoStore()
            let file = try backup.map { URL(fileURLWithPath: $0) } ?? XirpImporter.latestBackup()
            let report = try XirpImporter(store: store).run(backup: file, dryRun: dryRun, sessionsOnly: sessionsOnly)
            print(report)
            if dryRun { print("(simulação: nada foi gravado)") }
        }
    }
}

// MARK: - usage

struct Usage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uso de tokens e custo estimado (sessões do Claude Code).",
        discussion: "Sem argumentos, atualiza a tabela de preços e coleta o uso de todas as sessões.")

    @Option(name: .long, help: "Mostra contexto e custo de uma conversa do Claude Code pelo ID.")
    var conversation: String?

    @Flag(name: .long, help: "Baixa a tabela de preços remota mesmo que a cópia local seja recente.")
    var refreshPrices = false

    func run() async throws {
        await PriceTable.refreshRemote(force: refreshPrices)
        let prices = PriceTable.load()
        if let conversation {
            guard let s = ContextSummary.load(nativeId: conversation, prices: prices) else {
                throw ValidationError("Transcript não encontrado para \(conversation)")
            }
            let pct = String(format: "%.1f%%", s.fraction * 100)
            print("modelo:     \(s.model ?? "?")")
            print("contexto:   \(s.contextTokens.formatted()) / \(s.contextWindow.formatted()) (\(pct))")
            print("respostas:  \(s.turns)")
            print("tokens:     entrada \(s.total.input.formatted()) · saída \(s.total.output.formatted()) · cache escrita \(s.total.cacheWrite.formatted()) · cache leitura \(s.total.cacheRead.formatted())")
            print("custo:      US$ \(String(format: "%.2f", s.cost))")
            return
        }
        let store = try BandoStore()
        let n = try UsageCollector(store: store, prices: prices).collectAll()
        print("\(n) respostas novas coletadas. Tabela remota: \(prices.remoteUpdatedAt ?? "não baixada") (\(prices.remote.count) padrões)")
    }
}


// MARK: - report

struct ReportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Resumo de um período: tempo de agente, sessões, custo e projetos.",
        discussion: "Exemplos: bando report --week   bando report --month --previous 1   bando report --from 2026-11-01 --to 2026-11-15")

    @Flag(name: .long) var day = false
    @Flag(name: .long) var week = false
    @Flag(name: .long) var month = false
    @Option(name: .long, help: "Quantos períodos para trás.") var previous = 0
    @Option(name: .long, help: "Início (AAAA-MM-DD).") var from: String?
    @Option(name: .long, help: "Fim, inclusivo (AAAA-MM-DD).") var to: String?

    func run() throws {
        let store = try BandoStore()
        try UsageCollector(store: store).collectAll()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var period: ReportPeriod
        if let from, let start = f.date(from: from) {
            let end = to.flatMap { f.date(from: $0) }.map { Calendar.current.date(byAdding: .day, value: 1, to: $0)! } ?? Date()
            period = ReportPeriod(kind: .custom, start: start, end: end)
        } else {
            let kind: ReportPeriod.Kind = day ? .day : (month ? .month : .week)
            period = ReportPeriod.containing(Date(), kind: kind).shifted(by: -previous)
        }
        let r = try ReportService(store: store).report(period)
        let df = DateFormatter(); df.dateStyle = .medium
        func dur(_ s: Double) -> String { s >= 3600 ? String(format: "%dh%02d", Int(s) / 3600, Int(s) % 3600 / 60) : "\(Int(s) / 60) min" }
        print("\(df.string(from: period.start)) até \(df.string(from: period.end.addingTimeInterval(-1)))")
        print("tempo de agente: \(dur(r.agentSeconds))   esperando você: \(dur(r.waitingSeconds))")
        print("sessões: \(r.sessionsCreated) criadas, \(r.sessionsActive) com atividade")
        print("custo estimado: US$ \(String(format: "%.2f", r.cost))")
        if let p = r.peakWindow { print("pico: \(p.startHour)h às \(p.startHour + 3)h") }
        if !r.projects.isEmpty {
            print("\nprojetos:")
            var rows = [["PROJETO", "TEMPO", "ESPERANDO", "SESSÕES", "CUSTO"]]
            for p in r.projects.prefix(15) {
                rows.append([p.project, dur(p.seconds), dur(p.waitingSeconds), "\(p.sessions)", String(format: "US$ %.2f", p.cost)])
            }
            printTable(rows)
        }
        if !r.costByModel.isEmpty {
            print("\nmodelos:")
            printTable([["AGENTE", "MODELO", "RESPOSTAS", "CUSTO"]] + r.costByModel.prefix(10).map {
                [$0.agent ?? "?", $0.model, "\($0.turns)", String(format: "US$ %.2f", $0.cost)]
            })
        }
    }
}


// MARK: - swap

struct Swap: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Troca o agente, provider ou modelo de uma sessão sem perder o worktree.",
        discussion: """
        Mesmo agente: retoma a conversa com o provider/modelo novo.
        Outro agente: conversa nova no mesmo worktree, levando:
          resumo       o agente atual escreve .bando/handoff.md (padrão)
          resumo-novo  o Bando exporta a conversa e o novo agente escreve o resumo
                       (só do Claude Code; serve quando o atual bateu o limite)
          conversa     o Bando exporta a conversa (só do Claude Code)
          nenhum       só a tarefa original
        O pedido de resumo é editável em ~/.config/bando/handoff.md.
        """)

    @Argument var session: String
    @Option(name: .shortAndLong) var agent: String
    @Option(name: .shortAndLong) var provider: String?
    @Option(name: .shortAndLong) var model: String?
    @Option(name: .long, help: "resumo, resumo-novo, conversa ou nenhum") var levar: String = HandoffMode.summary.rawValue

    func run() throws {
        guard let mode = HandoffMode(rawValue: levar) else { throw ValidationError("Use --levar resumo, resumo-novo, conversa ou nenhum") }
        let service = try makeService()
        try service.swapAgent(session, agent: agent, provider: provider, model: model, handoff: mode) { print($0) }
        print("pronto: sessão agora com \(agent)")
    }
}
