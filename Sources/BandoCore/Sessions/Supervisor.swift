import Darwin
import Foundation

/// `bando run <sessão>`: roda dentro do painel tmux da sessão.
///
/// 1. Roda o script de setup do projeto (primeira vez).
/// 2. Resolve os segredos do provider e inicia o agente como processo filho.
///    O segredo só existe no ambiente do filho.
/// 3. Para agentes sem hooks, acompanha a saída do painel (`pipe-pane`) e
///    decide trabalhando / esperando / pronto.
/// 4. Digita a tarefa inicial quando o agente não aceita prompt por argumento.
/// 5. Grava o código de saída e deixa um shell no worktree, para o terminal
///    não sumir quando o agente termina.
public final class Supervisor: @unchecked Sendable {
    let service: SessionService
    let sessionId: String
    let resume: Bool
    let forkFrom: String?
    let promptOverride: String?
    var paneTarget: String { ProcessInfo.processInfo.environment["TMUX_PANE"] ?? "=\(tmuxName):" }
    var tmuxName = ""
    var tmuxServer = Tmux.bandoServer

    public init(service: SessionService, sessionId: String, resume: Bool, forkFrom: String? = nil, promptOverride: String? = nil) {
        self.service = service
        self.sessionId = sessionId
        self.resume = resume
        self.forkFrom = forkFrom
        self.promptOverride = promptOverride
    }

    /// Não retorna em caso normal: termina com `exec` do shell.
    public func run() -> Never {
        let session: Session
        do {
            session = try service.store.findSession(sessionId)
        } catch {
            fail("Sessão não encontrada: \(sessionId)", sessionId: nil, cwd: nil)
        }
        tmuxName = session.tmuxName
        tmuxServer = session.tmuxServer

        // Ctrl-C e afins vão para o agente; o supervisor não pode morrer com eles.
        signal(SIGINT, SIG_IGN)
        signal(SIGQUIT, SIG_IGN)
        signal(SIGTSTP, SIG_IGN)

        // Setup do projeto: uma vez por worktree (não repete ao trocar de agente).
        if !resume, session.usesWorktree, let project = try? service.store.project(session.projectId),
           let setup = project.setupScript, !setup.isEmpty,
           !((try? service.store.events(sessionId: session.id)) ?? []).contains(where: { $0.kind == "setup" }) {
            banner("setup do projeto: \(setup)")
            let status = runShell(setup, cwd: session.worktreePath)
            try? service.record(session.id, kind: "setup", detail: status == 0 ? nil : "saiu com código \(status)")
            if status != 0 { banner("setup saiu com código \(status); continuando") }
        }

        let plan: LaunchPlan
        let agent: AgentDefinition
        let env: [String: String]
        var proxyPid: pid_t = 0
        do {
            let built = try service.launchPlan(for: session, resume: resume, forkFrom: forkFrom, promptOverride: promptOverride)
            if built.0.proxy != nil {
                // Compressor: proxy local numa porta livre, só enquanto o agente roda.
                let started = try startProxy(built.0, session: session)
                plan = started.plan
                proxyPid = started.pid
            } else {
                plan = built.0
            }
            agent = built.1
            if let assigned = built.assignedId { try service.setNativeId(session.id, nativeId: assigned) }
            // Ler o Keychain pode abrir um aviso do macOS e travar até a resposta
            // (acontece quando o binário mudou, ex.: depois de atualizar um build
            // sem Developer ID). Deixa claro na tela e na lateral o que falta.
            let needsKeychain = plan.env.values.contains { if case .keychain = $0 { return true }; return false }
            if needsKeychain {
                banner("lendo chaves no Keychain; se aparecer um aviso do macOS, clique em Permitir")
                try? service.transition(session.id, to: .waiting, kind: "keychain",
                                        detail: "Permita o acesso ao Keychain no aviso do macOS")
            }
            env = try plan.resolvedEnvironment(store: KeychainStore(), environment: ProcessInfo.processInfo.environment)
        } catch {
            stopProxy(proxyPid)
            fail(error.localizedDescription, sessionId: session.id, cwd: session.worktreePath)
        }

        // Título em segundo plano, pelo agente e provider da sessão (mesmo
        // ambiente do agente): responde em segundos enquanto o agente trabalha.
        // Só na primeira subida e com nome provisório.
        if !resume && !session.customName {
            let service = self.service, id = session.id, titleEnv = env
            // Agente que escreve o próprio título no terminal: espera uma vez,
            // dá tempo de ele nomear a conversa e só gera se não nomeou.
            let wait: TimeInterval = agent.terminalTitle == nil ? 0 : 30
            Thread.detachNewThread {
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                if (try? service.refreshTitle(id, env: titleEnv)) ?? nil != nil { ChangeNotifier.post() }
            }
        }

        for (path, content) in plan.files {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try? content.write(toFile: path, atomically: true, encoding: .utf8)
        }

        guard let exe = ExecutableLocator.shared.locate(plan.argv[0]) else {
            stopProxy(proxyPid)
            let hint = (try? service.config.agent(session.agent))?.install.map { "\nInstalar: \($0)" } ?? ""
            fail("\(plan.argv[0]) não encontrado no PATH.\(hint)", sessionId: session.id, cwd: session.worktreePath)
        }

        let mode = service.effectiveStatusMode(agent)
        // Em modo hooks o watcher também roda, mas só para achar perguntas que
        // os hooks não cobrem (ex.: confiança na pasta do Claude Code).
        let watcher: OutputWatcher? = (mode != .none || plan.pendingKeys != nil)
            ? OutputWatcher(supervisor: self, agent: agent, mode: mode, pendingKeys: plan.pendingKeys,
                            worktree: session.worktreePath, usesWorktree: session.usesWorktree,
                            trustRepo: session.usesWorktree ? (try? service.store.project(session.projectId))?.path : nil,
                            env: env)
            : nil
        watcher?.start()

        // Sem tarefa, o agente abre parado esperando você digitar.
        let hasTask = plan.pendingKeys != nil || promptOverride != nil || (!resume && forkFrom == nil && !(session.prompt ?? "").isEmpty)
        try? service.transition(session.id, to: hasTask ? .working : .idle, kind: resume ? "agent-resume" : "agent-start")

        var childEnv = ProcessInfo.processInfo.environment
        childEnv["PATH"] = ExecutableLocator.shared.pathValue
        childEnv.merge(env) { _, new in new }
        let status = spawnAndWait(exe, argv: plan.argv, env: childEnv, cwd: session.worktreePath)

        stopProxy(proxyPid)
        watcher?.stop()
        let code = Int(status)
        if code == 0 {
            try? service.transition(session.id, to: .exited, kind: "exit", exitCode: 0)
        } else {
            try? service.transition(session.id, to: .error, kind: "exit", detail: "saiu com código \(code)", exitCode: code)
        }
        banner("\(agent.name) saiu (código \(code)). Este terminal continua no worktree. Para retomar: bando resume \(session.shortId)")
        execShell(cwd: session.worktreePath)
    }

    // MARK: - Processo filho

    /// posix_spawn sem novo grupo de processos (o agente fica em primeiro plano
    /// no terminal) e com os sinais restaurados ao padrão no filho.
    func spawnAndWait(_ exe: String, argv: [String], env: [String: String], cwd: String) -> Int32 {
        FileManager.default.changeCurrentDirectoryPath(cwd)
        var attr = posix_spawnattr_t(nil as OpaquePointer?)
        posix_spawnattr_init(&attr)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for sig in [SIGINT, SIGQUIT, SIGTSTP, SIGHUP, SIGPIPE] { sigaddset(&defaults, sig) }
        posix_spawnattr_setsigdefault(&attr, &defaults)
        var empty = sigset_t()
        sigemptyset(&empty)
        posix_spawnattr_setsigmask(&attr, &empty)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        let cArgs = argv.map { strdup($0) } + [nil]
        let cEnv = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            cArgs.forEach { free($0) }
            cEnv.forEach { free($0) }
            posix_spawnattr_destroy(&attr)
        }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, exe, nil, &attr, cArgs, cEnv)
        guard rc == 0 else {
            banner("falha ao iniciar \(exe): \(String(cString: strerror(rc)))")
            return 127
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        // WIFEXITED / WEXITSTATUS / WTERMSIG à mão (macros não chegam ao Swift).
        let low = status & 0x7f
        return low == 0 ? (status >> 8) & 0xff : 128 + low
    }

    // MARK: - Proxy do compressor

    /// Inicia o proxy do compressor e devolve o plano com a porta trocada.
    ///
    /// O proxy roda em grupo de processos próprio (Ctrl-C no terminal não o
    /// derruba) e com a saída num arquivo de log. Ele morre quando o agente
    /// sai, ou quando o supervisor recebe SIGHUP/SIGTERM (tmux encerrado).
    func startProxy(_ template: LaunchPlan, session: Session) throws -> (plan: LaunchPlan, pid: pid_t) {
        guard let port = Self.freePort() else { throw BandoError.invalid("não achei uma porta livre para o compressor") }
        let plan = template.binding(port: port)
        guard let proxy = plan.proxy else { return (plan, 0) }
        guard let exe = ExecutableLocator.shared.locate(proxy.argv[0]) else {
            let hint = proxy.install.map { "\nInstalar: \($0)" } ?? ""
            throw BandoError.invalid("\(proxy.argv[0]) (compressor \(proxy.name)) não encontrado no PATH.\(hint)")
        }
        let dir = service.paths.stateDir.appendingPathComponent("run")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("\(session.id).proxy.log").path

        var actions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var attr = posix_spawnattr_t(nil as OpaquePointer?)
        posix_spawnattr_init(&attr)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for sig in [SIGINT, SIGQUIT, SIGTSTP, SIGHUP, SIGPIPE] { sigaddset(&defaults, sig) }
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setpgroup(&attr, 0)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETPGROUP))

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExecutableLocator.shared.pathValue
        env.merge(proxy.env) { _, new in new }
        let cArgs = proxy.argv.map { strdup($0) } + [nil]
        let cEnv = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            cArgs.forEach { free($0) }
            cEnv.forEach { free($0) }
            posix_spawnattr_destroy(&attr)
            posix_spawn_file_actions_destroy(&actions)
        }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, exe, &actions, &attr, cArgs, cEnv)
        guard rc == 0 else { throw BandoError.invalid("falha ao iniciar \(exe): \(String(cString: strerror(rc)))") }

        // Se o tmux for encerrado, o supervisor morre por sinal: leva o proxy junto.
        supervisorProxyPid = pid
        signal(SIGHUP, supervisorProxyCleanup)
        signal(SIGTERM, supervisorProxyCleanup)

        banner("compressão: iniciando \(proxy.name) na porta \(port)")
        // Espera única na subida: o proxy leva alguns segundos para abrir a porta.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == pid {
                supervisorProxyPid = 0
                throw BandoError.invalid("o compressor \(proxy.name) saiu ao iniciar. Log: \(log)")
            }
            if Self.isListening(port) { return (plan, pid) }
            usleep(200_000)
        }
        stopProxy(pid)
        throw BandoError.invalid("o compressor \(proxy.name) não abriu a porta \(port) em 30 s. Log: \(log)")
    }

    func stopProxy(_ pid: pid_t) {
        guard pid > 0 else { return }
        // O proxy tem grupo próprio: o sinal vai para ele e para os filhos dele.
        kill(-pid, SIGTERM)
        var status: Int32 = 0
        for _ in 0..<30 {
            if waitpid(pid, &status, WNOHANG) != 0 { supervisorProxyPid = 0; return }
            usleep(100_000)
        }
        kill(-pid, SIGKILL)
        _ = waitpid(pid, &status, 0)
        supervisorProxyPid = 0
    }

    /// Porta TCP livre em 127.0.0.1 (o sistema escolhe).
    static func freePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = loopback(port: 0)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { return nil }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        guard got == 0 else { return nil }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    static func isListening(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = loopback(port: port)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        } == 0
    }

    static func loopback(port: Int) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return addr
    }

    func runShell(_ script: String, cwd: String) -> Int32 {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExecutableLocator.shared.pathValue
        return spawnAndWait(shell, argv: [shell, "-lc", script], env: env, cwd: cwd)
    }

    func execShell(cwd: String) -> Never {
        FileManager.default.changeCurrentDirectoryPath(cwd)
        signal(SIGINT, SIG_DFL); signal(SIGQUIT, SIG_DFL); signal(SIGTSTP, SIG_DFL)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        setenv("PATH", ExecutableLocator.shared.pathValue, 1)
        setenv("LANG", UTF8Locale.lang(), 1)
        let args = [strdup(shell), strdup("-l"), nil]
        execv(shell, args)
        exit(0)
    }

    func fail(_ message: String, sessionId: String?, cwd: String?) -> Never {
        banner("erro: \(message)")
        if let sessionId { try? service.transition(sessionId, to: .error, kind: "start-failed", detail: message) }
        execShell(cwd: cwd ?? FileManager.default.homeDirectoryForCurrentUser.path)
    }

    func banner(_ text: String) {
        FileHandle.standardError.write(Data("\u{1B}[2m[bando] \(text)\u{1B}[0m\n".utf8))
    }
}

/// PID do proxy do compressor, para o tratador de sinal do supervisor.
nonisolated(unsafe) var supervisorProxyPid: pid_t = 0

/// SIGHUP/SIGTERM no supervisor: encerra o proxy e sai. Só chama funções
/// seguras em tratador de sinal.
let supervisorProxyCleanup: @convention(c) (Int32) -> Void = { _ in
    let pid = supervisorProxyPid
    if pid > 0 {
        // O proxy tem grupo próprio: o sinal vai para ele e para os filhos dele.
        kill(-pid, SIGTERM)
        var status: Int32 = 0
        var gone = false
        for _ in 0..<30 where !gone {
            if waitpid(pid, &status, WNOHANG) != 0 { gone = true } else { _ = poll(nil, 0, 100) }
        }
        // Medido com o Headroom 0.44: depois que o agente cai, ele pode não sair no SIGTERM.
        if !gone { kill(-pid, SIGKILL) }
    }
    _exit(129)
}

/// Acompanha a saída do painel para agentes sem hooks.
///
/// O tmux copia a saída para um FIFO (`pipe-pane`). Saída acima de um limite
/// marca "trabalhando"; `idle_after` segundos sem saída disparam a leitura da
/// tela (`capture-pane`) e as regex do agente. Sem polling: o timer só é
/// rearmado quando chega saída.
final class OutputWatcher: @unchecked Sendable {
    unowned let supervisor: Supervisor
    let agent: AgentDefinition
    let mode: StatusMode
    let worktree: String
    let usesWorktree: Bool
    var pendingKeys: String?

    let queue = DispatchQueue(label: "bando.watcher")
    var timer: DispatchSourceTimer?
    var fifoPath = ""
    var bytesSinceQuiet = 0
    var sawOutput = false
    var state: SessionStatus = .working
    /// Em modo hooks: o watcher marcou "esperando" por causa de texto na tela.
    var screenWaiting = false
    let busy: Regex<AnyRegexOutput>?
    let waiting: Regex<AnyRegexOutput>?

    /// Bytes de saída que contam como "o agente voltou a trabalhar". Abaixo
    /// disso é eco de digitação ou cursor piscando.
    static let activityThreshold = 160

    /// Repositório principal (worktree): com ele confiável, responde sim à
    /// pergunta de confiança do agente uma vez, logo no começo.
    let trustRepo: String?
    let env: [String: String]
    var trustAnswered = false
    let startedAt = Date()

    init(supervisor: Supervisor, agent: AgentDefinition, mode: StatusMode, pendingKeys: String?,
         worktree: String, usesWorktree: Bool, trustRepo: String? = nil, env: [String: String] = [:]) {
        self.trustRepo = trustRepo
        self.env = env
        self.supervisor = supervisor
        self.agent = agent
        self.mode = mode
        self.pendingKeys = pendingKeys
        self.worktree = worktree
        self.usesWorktree = usesWorktree
        busy = agent.busy.flatMap { try? Regex($0) }
        waiting = agent.waiting.flatMap { try? Regex($0) }
    }

    func start() {
        let dir = supervisor.service.paths.stateDir.appendingPathComponent("run")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fifoPath = dir.appendingPathComponent("\(supervisor.sessionId).fifo").path
        unlink(fifoPath)
        guard mkfifo(fifoPath, 0o600) == 0 else { return }
        guard let tmux = try? Tmux(server: supervisor.tmuxServer) else { return }
        do {
            try tmux.pipePane(supervisor.paneTarget, command: "exec cat > \(HookPresets.shellQuote(fifoPath))")
        } catch {
            supervisor.banner("sem acompanhamento de estado: \(error.localizedDescription)")
            return
        }
        let path = fifoPath
        let queue = self.queue
        Thread.detachNewThread { [weak self] in
            guard let handle = FileHandle(forReadingAtPath: path) else { return }
            // Cada leitura vira um objeto "autoreleased"; numa thread própria,
            // sem pool, eles nunca seriam liberados (vazamento medido: 78 MB).
            var open = true
            while open {
                autoreleasepool {
                    let data = handle.availableData
                    if data.isEmpty { open = false; return }
                    let count = data.count
                    queue.async { [weak self] in self?.onOutput(count) }
                }
            }
        }
        // Se o agente não imprimir nada, ainda assim tenta digitar a tarefa.
        armTimer(after: 8)
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
        if let tmux = try? Tmux(server: supervisor.tmuxServer) {
            _ = try? tmux.tmux(["pipe-pane", "-t", supervisor.paneTarget])
        }
        unlink(fifoPath)
    }

    /// Saída conta como atividade só acima do limite por janela de checagem.
    /// Redesenhos pequenos (spinner parado, relógio, cursor) não impedem que
    /// o agente seja visto como parado: medido no Antigravity, 75 bytes em
    /// 10 s esperando resposta, chegando a cada 2-3 s.
    func onOutput(_ count: Int) {
        sawOutput = true
        bytesSinceQuiet += count
        if state != .working && bytesSinceQuiet >= Self.activityThreshold && (mode == .output || mode == .silence) {
            set(.working, detail: nil)
        }
        // Não reinicia o relógio a cada pedaço de saída: só arma se não houver.
        if timer == nil { armTimer(after: pendingKeys != nil ? 1.5 : Double(agent.idleAfter)) }
    }

    func armTimer(after seconds: Double) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + seconds)
        t.setEventHandler { [weak self] in self?.onSilence() }
        t.resume()
        timer = t
    }

    func onSilence() {
        timer = nil
        let noisy = bytesSinceQuiet >= Self.activityThreshold
        bytesSinceQuiet = 0
        if let keys = pendingKeys {
            if noisy { armTimer(after: 1.5); return }
            pendingKeys = nil
            if let tmux = try? Tmux(server: supervisor.tmuxServer) {
                try? tmux.send(supervisor.tmuxName, text: keys, enter: true)
            }
            return
        }
        guard mode == .output || mode == .silence || mode == .hooks, sawOutput else { return }
        let screen = (try? Tmux(server: supervisor.tmuxServer))?.capture(supervisor.paneTarget, lines: 40) ?? ""
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: true).suffix(15).map(String.init)
        let tail = lines.joined(separator: "\n")
        if answerTrustPrompt(tail) { armTimer(after: 2); return }
        let waitingMatch = waiting.flatMap { tail.firstMatch(of: $0) }
        if mode == .hooks {
            // Hooks mandam no estado; aqui só entram perguntas fora dos hooks.
            if waitingMatch != nil {
                screenWaiting = true
                set(.waiting, detail: question(in: lines))
            } else if screenWaiting {
                screenWaiting = false
                set(.idle, detail: nil)
            }
            return
        }
        if waitingMatch != nil {
            set(.waiting, detail: question(in: lines))
            return
        }
        if let busy, tail.firstMatch(of: busy) != nil {
            if state != .working { set(.working, detail: nil) }
            armTimer(after: Double(agent.idleAfter))
            return
        }
        if noisy {
            // Ainda escrevendo: confere de novo no próximo intervalo.
            armTimer(after: Double(agent.idleAfter))
            return
        }
        guard state == .working || state == .waiting else { return }
        let changed = usesWorktree ? ((try? Git())?.changedFileCount(worktree) ?? 0) : 0
        set(changed > 0 ? .review : .idle, detail: changed > 0 ? "\(changed) arquivo(s) alterado(s)" : nil)
    }

    /// A pergunta na tela: última linha terminada em "?" (ou a linha que casou).
    func question(in lines: [String]) -> String? {
        // Tira espaços e bordas de caixa (│ ╭ ╰ ─) que algumas CLIs desenham.
        let frame = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "│┃║╭╮╰╯─━═|"))
        let trimmed = lines.map { $0.trimmingCharacters(in: frame) }
        if let q = trimmed.last(where: { $0.hasSuffix("?") && $0.count > 8 }) { return q }
        // Pergunta no meio da linha ("Trust this folder? Codex can..."): corta no "?".
        if let line = trimmed.last(where: { $0.contains("?") && $0.count > 8 }), let i = line.firstIndex(of: "?") {
            return String(line[...i])
        }
        if let waiting, let line = trimmed.last(where: { $0.firstMatch(of: waiting) != nil }) { return line }
        return nil
    }

    /// Pergunta de confiança na tela, nos primeiros 60 s, com o repositório
    /// principal já confiável: confirma uma vez. Fora disso, a pergunta fica
    /// para você (e a sessão aparece como esperando).
    func answerTrustPrompt(_ tail: String) -> Bool {
        guard !trustAnswered, let adapter = agent.trust, let repo = trustRepo,
              Date().timeIntervalSince(startedAt) < 60,
              tail.firstMatch(of: adapter.prompt) != nil,
              adapter.isTrusted(repo, env: env),
              let tmux = try? Tmux(server: supervisor.tmuxServer) else { return false }
        trustAnswered = true
        _ = try? tmux.tmux(["send-keys", "-t", "=\(supervisor.tmuxName):", adapter.confirmKey])
        try? supervisor.service.record(supervisor.sessionId, kind: "trust-auto", detail: "repositório confiável: \(repo)")
        return true
    }

    func set(_ status: SessionStatus, detail: String?) {
        state = status
        try? supervisor.service.transition(supervisor.sessionId, to: status, kind: "watch", detail: detail)
        // Fim de turno sem hooks: lê o título que o agente pôs no terminal (barato).
        if status == .idle || status == .review,
           (try? supervisor.service.refreshTitle(supervisor.sessionId, allowGenerate: false)) ?? nil != nil {
            ChangeNotifier.post()
        }
    }
}
