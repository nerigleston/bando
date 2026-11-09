import AppKit
import BandoCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings().tabItem { Label("Aparência", systemImage: "paintpalette") }
            AgentsSettings().tabItem { Label("Agentes", systemImage: "terminal") }
            ProvidersSettings().tabItem { Label("Providers", systemImage: "key") }
            McpSettings().tabItem { Label("MCP", systemImage: "point.3.connected.trianglepath.dotted") }
            GeneralSettings().tabItem { Label("Geral", systemImage: "gearshape") }
        }
        .frame(width: 640, height: 480)
    }
}

struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let themes = model.config?.sortedThemes ?? []
        Form {
            Picker("Tema", selection: $model.themePreference) {
                Text("Seguir o sistema").tag("system")
                Divider()
                ForEach(themes) { Text($0.name).tag($0.id) }
            }
            if model.themePreference == "system" {
                Picker("Quando o sistema estiver claro", selection: $model.lightTheme) {
                    ForEach(themes.filter { $0.appearance == .light }) { Text($0.name).tag($0.id) }
                }
                Picker("Quando o sistema estiver escuro", selection: $model.darkTheme) {
                    ForEach(themes.filter { $0.appearance == .dark }) { Text($0.name).tag($0.id) }
                }
            }
            Slider(value: $model.fontSize, in: 10...20, step: 1) { Text("Fonte do terminal: \(Int(model.fontSize)) pt") }
            if let t = model.theme { ThemePreview(theme: t, fontSize: model.fontSize) }
            Section {
                HStack {
                    Text("Seus temas ficam em ~/.config/bando/themes.toml").foregroundStyle(.secondary)
                    Spacer()
                    Button("Abrir arquivo") { openUserFile(BandoPaths.standard().themesFile, template: UserTemplates.themes) }
                    Button("Recarregar") { Task { await model.reload() } }
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}

struct ThemePreview: View {
    let theme: ThemeDefinition
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<16, id: \.self) { i in Rectangle().fill(theme.ansi[i].color).frame(height: 10) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Group {
                Text("$ ").foregroundColor(theme.ansi[2].color) + Text("bando new -a claude \"corrigir o login\"").foregroundColor(theme.foreground.color)
                Text("✓ ").foregroundColor(theme.ansi[2].color) + Text("worktree criado em ").foregroundColor(theme.foreground.color) + Text("bando/corrigir-o-login").foregroundColor(theme.ansi[4].color)
                Text("! ").foregroundColor(theme.ansi[3].color) + Text("Posso rodar os testes? (y/n)").foregroundColor(theme.foreground.color)
            }
            .font(.system(size: fontSize, design: .monospaced))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.background.color))
        .environment(\.colorScheme, theme.appearance == .dark ? .dark : .light)
    }
}

struct AgentsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.availability.values.sorted { ($0.isInstalled ? 0 : 1, $0.agent.name) < ($1.isInstalled ? 0 : 1, $1.agent.name) }, id: \.agent.id) { a in
                    HStack {
                        Circle().fill(a.isInstalled ? Color.green : Color.secondary.opacity(0.35)).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(a.agent.name)
                                if model.config?.userAgentIds.contains(a.agent.id) == true {
                                    Text("personalizado").font(.caption2).padding(.horizontal, 4).background(Capsule().fill(.quaternary))
                                }
                            }
                            Text(a.isInstalled ? (a.path ?? "") : (a.agent.install.map { "Instalar: \($0)" } ?? "não instalado"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                        }
                        Spacer()
                        Text(statusLabel(a.agent)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            footer(file: BandoPaths.standard().agentsFile, template: UserTemplates.agents,
                   text: "Adicione ou ajuste agentes em ~/.config/bando/agents.toml")
        }
    }

    func statusLabel(_ a: AgentDefinition) -> String {
        guard let service = model.service else { return "" }
        switch service.effectiveStatusMode(a) {
        case .hooks: return "estado por hooks"
        case .output: return "estado pela tela"
        case .silence: return "estado por atividade"
        case .none: return ""
        }
    }

    func footer(file: URL, template: String, text: String) -> some View {
        HStack {
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Abrir arquivo") { openUserFile(file, template: template) }
            Button("Recarregar") { Task { await model.reload() } }
        }
        .padding(12)
    }
}

struct ProvidersSettings: View {
    @Environment(AppModel.self) private var model
    @State private var editing: ProviderDefinition?
    @State private var key = ""
    @State private var keyState: [String: Bool] = [:]
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filtrar providers", text: $filter).textFieldStyle(.roundedBorder).padding(12)
            List {
                ForEach(providers, id: \.id) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name)
                            Text(p.supportedAgents.isEmpty ? "todos os agentes" : p.supportedAgents.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let refs = keychainRefs(p).first {
                            if keyState[refs] == true {
                                Label("chave salva", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.caption)
                            }
                            Button(keyState[refs] == true ? "Trocar chave" : "Cadastrar chave") { editing = p; key = "" }
                        }
                    }
                }
            }
            HStack {
                Text("As chaves ficam no Keychain do macOS e só vão para o processo do agente.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Abrir arquivo") { openUserFile(BandoPaths.standard().providersFile, template: UserTemplates.providers) }
            }
            .padding(12)
        }
        .task { refreshKeys() }
        .sheet(item: $editing) { p in
            VStack(alignment: .leading, spacing: 12) {
                Text("Chave do \(p.name)").font(.headline)
                SecureField("Cole a chave", text: $key).textFieldStyle(.roundedBorder)
                Text("Gravada no Keychain como \(keychainRefs(p).joined(separator: ", ")).")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancelar") { editing = nil }.keyboardShortcut(.cancelAction)
                    Button("Salvar") { save(p) }.keyboardShortcut(.defaultAction).disabled(key.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    var providers: [ProviderDefinition] {
        let all = model.config?.sortedProviders ?? []
        guard !filter.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(filter) || $0.id.contains(filter.lowercased()) }
    }

    func keychainRefs(_ p: ProviderDefinition) -> [String] {
        var values = Array(p.env.values)
        for v in p.variants.values { values += v.env.values }
        return Array(Set(values.compactMap { v -> String? in
            if case .keychain(let s, let a) = v { return "\(s)/\(a)" }
            return nil
        })).sorted()
    }

    func refreshKeys() {
        let store = KeychainStore()
        var state: [String: Bool] = [:]
        for p in model.config?.sortedProviders ?? [] {
            for ref in keychainRefs(p) {
                let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
                state[ref] = ((try? store.read(service: parts[0], account: parts[1])) ?? nil) != nil
            }
        }
        keyState = state
    }

    func save(_ p: ProviderDefinition) {
        // Um provider pode usar mais de um item (ex.: chave e header); a chave
        // digitada vai para o primeiro, que é a chave de API.
        guard let ref = keychainRefs(p).first else { return }
        let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
        do {
            try KeychainStore().write(key, service: parts[0], account: parts[1])
            editing = nil
            refreshKeys()
        } catch {
            model.showError("Keychain", error)
        }
    }
}

struct McpSettings: View {
    @Environment(AppModel.self) private var model
    @State private var editing: KeyRef?
    @State private var key = ""
    @State private var keyState: [String: Bool] = [:]

    struct KeyRef: Identifiable { let id: String; let server: String }

    var servers: [McpServer] { (model.config?.mcp.values.sorted { $0.id < $1.id }) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            if servers.isEmpty {
                ContentUnavailableView {
                    Label("Nenhum servidor MCP", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Cadastre os servidores uma vez em ~/.config/bando/mcp.toml e o Bando entrega a todos os agentes que suportam MCP (Claude Code, Codex, OpenCode e Gemini CLI), sem mexer na configuração deles.")
                } actions: {
                    Button("Abrir mcp.toml") { openUserFile(BandoPaths.standard().mcpFile, template: UserTemplates.mcp) }
                }
            } else {
                List(servers) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.name).font(.system(size: 13, weight: .medium))
                            Text(s.transport.rawValue).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            Spacer()
                            Text(s.agents.isEmpty ? "todos os agentes" : s.agents.joined(separator: ", "))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text(s.url ?? ([s.command ?? ""] + s.args).joined(separator: " "))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        ForEach(refs(s), id: \.self) { ref in
                            HStack(spacing: 6) {
                                Image(systemName: keyState[ref] == true ? "checkmark.seal.fill" : "key")
                                    .foregroundStyle(keyState[ref] == true ? .green : .orange)
                                Text(ref).font(.system(size: 11, design: .monospaced))
                                Button(keyState[ref] == true ? "Trocar" : "Cadastrar") { editing = KeyRef(id: ref, server: s.name); key = "" }
                                    .buttonStyle(.link).font(.system(size: 11))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Text("Chaves no Keychain; só o processo do agente as recebe, nunca os argumentos.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Abrir arquivo") { openUserFile(BandoPaths.standard().mcpFile, template: UserTemplates.mcp) }
                Button("Recarregar") { Task { await model.reload(); refresh() } }
            }
            .padding(12)
        }
        .task { refresh() }
        .sheet(item: $editing) { ref in
            VStack(alignment: .leading, spacing: 12) {
                Text("Chave de \(ref.server)").font(.headline)
                SecureField("Cole a chave", text: $key).textFieldStyle(.roundedBorder)
                Text("Gravada no Keychain como \(ref.id).").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancelar") { editing = nil }.keyboardShortcut(.cancelAction)
                    Button("Salvar") {
                        let parts = ref.id.split(separator: "/", maxSplits: 1).map(String.init)
                        do { try KeychainStore().write(key, service: parts[0], account: parts[1]); editing = nil; refresh() }
                        catch { model.showError("Keychain", error) }
                    }
                    .keyboardShortcut(.defaultAction).disabled(key.isEmpty)
                }
            }
            .padding(20).frame(width: 420)
        }
    }

    func refs(_ s: McpServer) -> [String] {
        (Array(s.env.values) + Array(s.headers.values)).compactMap { v in
            if case .keychain(let svc, let acc) = v { return "\(svc)/\(acc)" }
            return nil
        }.sorted()
    }

    func refresh() {
        let store = KeychainStore()
        var state: [String: Bool] = [:]
        for s in servers {
            for ref in refs(s) {
                let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
                state[ref] = ((try? store.read(service: parts[0], account: parts[1])) ?? nil) != nil
            }
        }
        keyState = state
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var cliMessage: String?
    @State private var importMessage: String?
    @State private var importing = false

    var body: some View {
        Form {
            Section("Linha de comando") {
                Text("O comando `bando` faz tudo o que o app faz, pelo terminal.").foregroundStyle(.secondary)
                HStack {
                    Button("Instalar em ~/.local/bin/bando", action: installCLI)
                    if let cliMessage { Text(cliMessage).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("Trocar de agente numa sessão") {
                Picker("Levar para o novo agente", selection: Binding(get: { model.handoffDefault }, set: { model.handoffDefault = $0 })) {
                    ForEach(HandoffMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("O pedido de resumo fica em ~/.config/bando/handoff.md").foregroundStyle(.secondary)
                    Spacer()
                    Button("Editar pedido de resumo") {
                        openUserFile(BandoPaths.standard().configDir.appendingPathComponent("handoff.md"), template: UserTemplates.handoff)
                    }
                }
            }
            Section("Importar do Xirp") {
                Text("Traz projetos, sessões, custos e PRs do backup do Xirp. Não altera nada no Xirp e pode ser repetido.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button(importing ? "Importando…" : "Importar agora", action: importXirp).disabled(importing)
                    if let importMessage { Text(importMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
            Section("Arquivos") {
                LabeledContent("Configuração", value: BandoPaths.standard().configDir.path)
                LabeledContent("Dados", value: BandoPaths.standard().stateDir.path)
            }
        }
        .formStyle(.grouped)
    }

    func installCLI() {
        let cli = BandoCLI.path()
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        let link = dir.appendingPathComponent("bando")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil || FileManager.default.fileExists(atPath: link.path) {
                try FileManager.default.removeItem(at: link)
            }
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: cli)
            cliMessage = "pronto: \(link.path) → \(cli)"
        } catch {
            cliMessage = error.localizedDescription
        }
    }

    func importXirp() {
        guard let store = model.service?.store else { return }
        importing = true
        Task.detached {
            let message: String
            do {
                let report = try XirpImporter(store: store).run(backup: XirpImporter.latestBackup(), dryRun: false)
                message = "\(report.projectsNew) projetos e \(report.sessionsNew) sessões novos, \(report.usageNew) registros de custo"
            } catch {
                message = error.localizedDescription
            }
            await MainActor.run {
                importMessage = message
                importing = false
                model.refreshSessions()
            }
        }
    }
}

/// Abre um arquivo do usuário no editor padrão, criando com o modelo se não existir.
func openUserFile(_ url: URL, template: String) {
    if !FileManager.default.fileExists(atPath: url.path) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? template.write(to: url, atomically: true, encoding: .utf8)
    }
    NSWorkspace.shared.open(url)
}
