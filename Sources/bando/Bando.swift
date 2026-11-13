import ArgumentParser
import BandoCore
import Foundation

@main
struct Bando: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bando",
        abstract: "Orquestrador de agentes de código: sessões em worktree + tmux com qualquer agente e provider.",
        version: BandoVersion.current,
        subcommands: [
            New.self, List.self, Attach.self, Msg.self, Stop.self, Resume.self, Swap.self, Remove.self, Seen.self, Log.self,
            Projects.self, Import.self, Usage.self, ReportCommand.self,
            Agents.self, Providers.self, Compressors.self, Themes.self, Mcp.self, Plan.self, Secret.self, Config.self, Doctor.self,
            Run.self, Hook.self,
        ]
    )
}

// MARK: - Utilidades

func loadConfig() throws -> BandoConfig {
    let config = try BandoConfig.load()
    for issue in config.issues {
        warn("[\(issue.section)] \(issue.message) (entrada ignorada)")
    }
    return config
}

func warn(_ text: String) {
    FileHandle.standardError.write(Data("aviso: \(text)\n".utf8))
}

/// Imprime linhas em colunas alinhadas.
func printTable(_ rows: [[String]]) {
    guard let first = rows.first else { return }
    var widths = Array(repeating: 0, count: first.count)
    for row in rows {
        for (i, cell) in row.enumerated() where i < widths.count {
            widths[i] = max(widths[i], cell.count)
        }
    }
    for row in rows {
        let line = row.enumerated().map { i, cell in
            i == row.count - 1 ? cell : cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
        print(line)
    }
}

func shellQuote(_ s: String) -> String {
    if s.range(of: #"^[A-Za-z0-9_@%+=:,./-]+$"#, options: .regularExpression) != nil { return s }
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - agents

struct Agents: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Lista os agentes configurados e se estão instalados.")

    @Flag(name: .long, help: "Não roda --version de cada agente (mais rápido).")
    var noVersion = false

    @Flag(name: .long, help: "Saída em JSON.")
    var json = false

    func run() throws {
        let config = try loadConfig()
        // Checa as versões em paralelo; cada CLI pode levar ~1 s para responder.
        let agents = config.sortedAgents
        let results = LockedBox([AgentAvailability?](repeating: nil, count: agents.count))
        let probe = !noVersion
        DispatchQueue.concurrentPerform(iterations: agents.count) { i in
            let a = agents[i].availability(probeVersion: probe)
            results.mutate { $0[i] = a }
        }
        let list = results.value.compactMap { $0 }

        if json {
            let items = list.map { a -> [String: Any] in
                [
                    "id": a.agent.id, "name": a.agent.name, "cmd": a.agent.cmd,
                    "installed": a.isInstalled, "path": a.path ?? NSNull(),
                    "version": a.version ?? NSNull(), "status": a.agent.status.rawValue,
                    "custom": config.userAgentIds.contains(a.agent.id),
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }

        var rows = [["ID", "NOME", "ESTADO", "DETECÇÃO", "VERSÃO / INSTALAR"]]
        for a in list {
            let custom = config.userAgentIds.contains(a.agent.id) ? " *" : ""
            rows.append([
                a.agent.id + custom,
                a.agent.name,
                a.isInstalled ? "instalado" : "ausente",
                a.agent.status.rawValue,
                a.isInstalled ? (a.version ?? "-") : (a.agent.install ?? "-"),
            ])
        }
        printTable(rows)
        if !config.userAgentIds.isEmpty {
            print("\n* personalizado em \(BandoPaths.standard().agentsFile.path)")
        }
    }
}

// MARK: - providers

struct Compressors: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lista os compressores (opcionais) e se estão instalados.",
        discussion: "Um compressor é um proxy local que encolhe o que o agente manda ao modelo. Só entra na sessão criada com --compressor."
    )

    func run() throws {
        let config = try loadConfig()
        var rows = [["ID", "NOME", "AGENTES", "INSTALADO"]]
        for c in config.sortedCompressors {
            let exe = c.cmd.split(separator: " ").first.map(String.init) ?? c.cmd
            let installed = ExecutableLocator.shared.locate(exe) != nil
            rows.append([c.id, c.name, c.supportedAgents.joined(separator: ","),
                         installed ? "sim" : "não: \(c.install ?? "veja a documentação")"])
        }
        printTable(rows)
    }
}

struct Providers: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Lista os providers e se as chaves estão cadastradas.")

    @Option(name: .long, help: "Mostra só os providers que servem para este agente.")
    var agent: String?

    func run() throws {
        let config = try loadConfig()
        let store = KeychainStore()
        let list = agent.map { config.providers(for: $0) } ?? config.sortedProviders

        var rows = [["ID", "NOME", "AGENTES", "CHAVE"]]
        for p in list {
            var secrets: [SecretValue] = Array(p.env.values)
            for v in p.variants.values { secrets += v.env.values }
            let keychainRefs = Set(secrets.compactMap { s -> String? in
                if case .keychain(let svc, let acc) = s { return "\(svc)/\(acc)" }
                return nil
            })
            let keyState: String
            if keychainRefs.isEmpty {
                keyState = "-"
            } else {
                let ok = keychainRefs.allSatisfy { ref in
                    let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
                    return ((try? store.read(service: parts[0], account: parts[1])) ?? nil) != nil
                }
                keyState = ok ? "ok" : "falta: bando secret set \(keychainRefs.sorted().joined(separator: ", "))"
            }
            let agents = p.supportedAgents.isEmpty ? "todos" : p.supportedAgents.joined(separator: ",")
            let custom = config.userProviderIds.contains(p.id) ? " *" : ""
            rows.append([p.id + custom, p.name, agents, keyState])
        }
        printTable(rows)
    }
}

// MARK: - mcp

struct Mcp: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Servidores MCP do Bando (~/.config/bando/mcp.toml), entregues a qualquer agente.")

    func run() throws {
        let config = try loadConfig()
        let path = BandoPaths.standard().mcpFile.path
        if config.mcp.isEmpty {
            print("Nenhum servidor MCP cadastrado. Crie o arquivo com: bando config init  (e edite \(path))")
            return
        }
        let store = KeychainStore()
        var rows = [["ID", "NOME", "TIPO", "AGENTES", "PROJETOS", "CHAVES"]]
        for s in config.mcp.values.sorted(by: { $0.id < $1.id }) {
            let refs = (Array(s.env.values) + Array(s.headers.values)).compactMap { v -> (String, String)? in
                if case .keychain(let svc, let acc) = v { return (svc, acc) }
                return nil
            }
            let missing = refs.filter { ((try? store.read(service: $0.0, account: $0.1)) ?? nil) == nil }
            rows.append([s.id, s.name, s.transport.rawValue,
                         s.agents.isEmpty ? "todos" : s.agents.joined(separator: ","),
                         s.projects.isEmpty ? "todos" : s.projects.joined(separator: ","),
                         refs.isEmpty ? "-" : (missing.isEmpty ? "ok" : "falta: " + missing.map { "\($0.0)/\($0.1)" }.joined(separator: ", "))])
        }
        printTable(rows)
        let supported = config.sortedAgents.filter { $0.mcp != nil }.map(\.id)
        print("\nAgentes que recebem MCP do Bando: \(supported.joined(separator: ", "))")
    }
}

// MARK: - themes

struct Themes: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Lista os temas (o app escolhe em Ajustes > Aparência).")

    func run() throws {
        let config = try loadConfig()
        let tty = isatty(STDOUT_FILENO) == 1
        var rows = [["ID", "NOME", "TIPO", "CORES"]]
        for t in config.sortedThemes {
            // Amostra das cores no próprio terminal (fundo, texto e 6 ANSI).
            let sample = tty ? ([t.background, t.foreground] + t.ansi[1...6]).map { c in
                "\u{1B}[48;2;\(c.r);\(c.g);\(c.b)m  \u{1B}[0m"
            }.joined() : "\(t.background) \(t.foreground)"
            let custom = config.userThemeIds.contains(t.id) ? " *" : ""
            rows.append([t.id + custom, t.name, t.appearance == .dark ? "escuro" : "claro", sample])
        }
        printTable(rows)
    }
}

// MARK: - plan

struct Plan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mostra o comando e o ambiente que seriam usados para iniciar um agente. Não roda nada.",
        discussion: "Os segredos aparecem como referência (Keychain, $VAR), nunca o valor."
    )

    @Option(name: .shortAndLong, help: "ID do agente (veja bando agents).")
    var agent: String

    @Option(name: .shortAndLong, help: "ID do provider (veja bando providers).")
    var provider: String?

    @Option(name: .shortAndLong, help: "Modelo.")
    var model: String?

    @Option(name: .long, help: "Retomar a conversa com este ID nativo do agente.")
    var resume: String?

    @Flag(name: .customLong("continue"), help: "Continuar a última conversa.")
    var continueLast = false

    @Option(name: .long, help: "ID do compressor (veja bando compressors).")
    var compressor: String?

    @Argument(help: "Tarefa inicial.")
    var prompt: String?

    func run() throws {
        let config = try loadConfig()
        let agentDef = try config.agent(agent)
        let providerDef = try provider.map { try config.provider($0) }
        let compressorDef = try compressor.map { try config.compressor($0) }
        let mode: LaunchRequest.Mode = resume.map { .resume(nativeId: $0) } ?? (continueLast ? .continueLast : .fresh)
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: agentDef, provider: providerDef, model: model, prompt: prompt, mode: mode,
            compressor: compressorDef
        ))

        print("comando:")
        print("  " + plan.argv.map(shellQuote).joined(separator: " "))
        if !plan.env.isEmpty {
            print("ambiente:")
            for (k, v) in plan.env.sorted(by: { $0.key < $1.key }) {
                print("  \(k) = \(v)")
            }
        }
        if let keys = plan.pendingKeys {
            print("digitado no terminal depois de abrir:")
            print("  \(keys)")
        }
        if let proxy = plan.proxy {
            print("compressor (\(proxy.name)), iniciado antes do agente numa porta livre:")
            print("  " + proxy.argv.map(shellQuote).joined(separator: " "))
            for (k, v) in proxy.env.sorted(by: { $0.key < $1.key }) { print("  \(k) = \(v)") }
            if ExecutableLocator.shared.locate(proxy.argv[0]) == nil {
                warn("\(proxy.argv[0]) não foi encontrado no PATH. Instalar: \(proxy.install ?? "veja a documentação do compressor")")
            }
        }
        if ExecutableLocator.shared.locate(agentDef.executableName()) == nil {
            warn("\(agentDef.executableName()) não foi encontrado no PATH. Instalar: \(agentDef.install ?? "veja a documentação do agente")")
        }
    }
}

// MARK: - secret

struct Secret: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Cadastra chaves de providers no Keychain do macOS.",
        subcommands: [Set_.self, Remove.self, Check.self]
    )

    static func split(_ ref: String) throws -> (String, String) {
        let raw = ref.hasPrefix("keychain:") ? ref : "keychain:\(ref)"
        guard case .keychain(let s, let a) = try SecretValue(parsing: raw) else {
            throw ValidationError("Use <serviço>/<conta>, por exemplo bando/openrouter")
        }
        return (s, a)
    }

    struct Set_: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Grava uma chave. Lê do terminal sem eco, ou da entrada padrão com --stdin."
        )
        @Argument(help: "Referência, ex.: bando/openrouter")
        var ref: String
        @Flag(help: "Lê a chave da entrada padrão (para scripts).")
        var stdin = false

        func run() throws {
            let (service, account) = try Secret.split(ref)
            let value: String
            if stdin {
                value = (readLine(strippingNewline: true) ?? "")
            } else {
                guard let p = getpass("Chave para \(service)/\(account): ") else { throw ExitCode.failure }
                value = String(cString: p)
            }
            guard !value.isEmpty else { throw ValidationError("Chave vazia; nada foi gravado.") }
            try KeychainStore().write(value, service: service, account: account)
            print("Gravado no Keychain: \(service)/\(account)")
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: "Apaga uma chave do Keychain.")
        @Argument var ref: String
        func run() throws {
            let (service, account) = try Secret.split(ref)
            try KeychainStore().delete(service: service, account: account)
            print("Removido: \(service)/\(account)")
        }
    }

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "check", abstract: "Diz se a chave existe (sem mostrar o valor).")
        @Argument var ref: String
        func run() throws {
            let (service, account) = try Secret.split(ref)
            let exists = try KeychainStore().read(service: service, account: account) != nil
            print(exists ? "existe" : "não existe")
            if !exists { throw ExitCode(1) }
        }
    }
}

// MARK: - config

struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Arquivos de configuração.",
        subcommands: [Paths.self, Init.self, Presets_.self, Check.self]
    )

    struct Paths: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "path", abstract: "Mostra onde ficam os arquivos.")
        func run() {
            let p = BandoPaths.standard()
            print("agentes:   \(p.agentsFile.path)")
            print("providers: \(p.providersFile.path)")
            print("temas:     \(p.themesFile.path)")
            print("estado:    \(p.stateDir.path)")
        }
    }

    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "init",
            abstract: "Cria agents.toml e providers.toml comentados, se ainda não existirem. Nunca sobrescreve."
        )
        func run() throws {
            let p = BandoPaths.standard()
            try FileManager.default.createDirectory(at: p.configDir, withIntermediateDirectories: true)
            for (url, text) in [(p.agentsFile, UserTemplates.agents), (p.providersFile, UserTemplates.providers),
                                (p.themesFile, UserTemplates.themes), (p.mcpFile, UserTemplates.mcp),
                                (p.configDir.appendingPathComponent("handoff.md"), UserTemplates.handoff)] {
                if FileManager.default.fileExists(atPath: url.path) {
                    print("já existe, mantido: \(url.path)")
                } else {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    print("criado: \(url.path)")
                }
            }
        }
    }

    struct Presets_: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "presets", abstract: "Imprime os presets embutidos (referência para personalizar).")
        @Argument(help: "agents, providers ou themes") var which: String = "agents"
        func run() throws {
            switch which {
            case "agents": print(Presets.agents)
            case "providers": print(Presets.providers)
            case "themes": print(Presets.themes)
            default: throw ValidationError("Use agents, providers ou themes")
            }
        }
    }

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "check", abstract: "Valida os arquivos do usuário.")
        func run() throws {
            let config = try BandoConfig.load()
            if config.issues.isEmpty {
                print("ok: \(config.agents.count) agentes, \(config.providers.count) providers")
            } else {
                for i in config.issues { print("[\(i.section)] \(i.message)") }
                throw ExitCode(1)
            }
        }
    }
}

// MARK: - doctor

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Confere as dependências e a configuração.")

    func run() throws {
        let locator = ExecutableLocator.shared
        var ok = true
        func check(_ name: String, _ passed: Bool, _ detail: String) {
            print("\(passed ? "ok  " : "erro") \(name): \(detail)")
            if !passed { ok = false }
        }

        if let tmux = locator.locate("tmux") {
            let v = locator.version(of: tmux, args: ["-V"]) ?? "?"
            let number = Double(v.split(separator: " ").last?.filter { "0123456789.".contains($0) } ?? "") ?? 0
            check("tmux", number >= 3.3, "\(v) em \(tmux)\(number < 3.3 ? " (precisa 3.3 ou mais)" : "")")
        } else {
            check("tmux", false, "não encontrado. Instale com: brew install tmux")
        }
        if let git = locator.locate("git") {
            check("git", true, locator.version(of: git, args: ["--version"]) ?? git)
        } else {
            check("git", false, "não encontrado")
        }

        do {
            let config = try BandoConfig.load()
            check("config", config.issues.isEmpty, "\(config.agents.count) agentes, \(config.providers.count) providers, \(config.issues.count) avisos")
            for i in config.issues { print("     [\(i.section)] \(i.message)") }
            let installed = config.sortedAgents.filter { locator.locate($0.executableName()) != nil }
            check("agentes instalados", !installed.isEmpty, installed.map(\.id).joined(separator: ", "))
        } catch {
            check("config", false, error.localizedDescription)
        }

        if !ok { throw ExitCode(1) }
    }
}
