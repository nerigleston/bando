import AppKit
import BandoCore
import SwiftUI

struct NewSessionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var projectId: String?
    @State private var prompt = ""
    @State private var name = ""
    @State private var agent = "claude"
    @State private var provider = "default"
    @State private var modelName = ""
    @State private var branch = ""
    @State private var useWorktree = true
    @State private var dependsOn: String?
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nova sessão").font(.title2.weight(.semibold)).padding([.horizontal, .top], 20)
            Form {
                Section {
                    HStack {
                        Picker("Projeto", selection: $projectId) {
                            Text("Escolha…").tag(String?.none)
                            ForEach(model.projects) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Button("Outra pasta…", action: pickFolder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tarefa").font(.callout)
                        TextEditor(text: $prompt)
                            .font(.body)
                            .frame(minHeight: 90, maxHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        Text("Pode deixar vazio para abrir o agente e escrever lá.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Nome (opcional)", text: $name)
                }
                Section("Agente") {
                    Picker("Agente", selection: $agent) {
                        ForEach(agents, id: \.agent.id) { a in
                            Text(a.agent.name + (a.isInstalled ? "" : " (não instalado)")).tag(a.agent.id)
                        }
                    }
                    Picker("Provider", selection: $provider) {
                        ForEach(providers, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    TextField("Modelo (opcional)", text: $modelName, prompt: Text(modelHint))
                }
                Section("Código") {
                    Toggle("Trabalhar num worktree separado", isOn: $useWorktree)
                    if useWorktree {
                        TextField("Branch (opcional)", text: $branch, prompt: Text("bando/<nome>"))
                    }
                    Picker("Começar depois de", selection: $dependsOn) {
                        Text("Agora").tag(String?.none)
                        ForEach(model.sessions.filter { $0.status.isLive || $0.status == .queued }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let error {
                Text(error).foregroundStyle(.red).font(.callout).padding(.horizontal, 20)
            }
            HStack {
                if let a = model.availability[agent], !a.isInstalled, let install = a.agent.install {
                    Text("Instalar: \(install)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                }
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(creating ? "Criando…" : "Criar sessão", action: create)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(projectId == nil || creating)
            }
            .padding(20)
        }
        .frame(width: 560)
        .onAppear(perform: setDefaults)
        .onChange(of: agent) { _, new in
            if !(providers.contains { $0.id == provider }) { provider = "default" }
            _ = new
        }
        .onChange(of: projectId) { _, id in
            if let p = id.flatMap(model.project), let a = p.defaultAgent, model.config?.agents[a] != nil { agent = a }
        }
    }

    /// Instalados primeiro, depois o resto em ordem alfabética.
    var agents: [AgentAvailability] {
        model.availability.values.filter { $0.agent.id != "shell" || true }
            .sorted { ($0.isInstalled ? 0 : 1, $0.agent.name) < ($1.isInstalled ? 0 : 1, $1.agent.name) }
    }

    var providers: [ProviderDefinition] {
        let list = model.config?.providers(for: agent) ?? []
        return list.sorted { ($0.id == "default" ? 0 : 1, $0.name) < ($1.id == "default" ? 0 : 1, $1.name) }
    }

    var modelHint: String {
        model.config?.providers[provider]?.models.first ?? "padrão do agente"
    }

    func setDefaults() {
        projectId = model.newSessionProject ?? model.selectedSession?.projectId
            ?? model.projects.max { ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast) }?.id
        if let p = projectId.flatMap(model.project), let a = p.defaultAgent, model.config?.agents[a] != nil { agent = a }
        else if model.availability["claude"]?.isInstalled != true,
                let first = agents.first(where: { $0.isInstalled && $0.agent.id != "shell" }) { agent = first.agent.id }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Usar esta pasta"
        guard panel.runModal() == .OK, let url = panel.url, let service = model.service else { return }
        do {
            let p = try service.ensureProject(at: url.path)
            model.refreshSessions()
            projectId = p.id
        } catch { self.error = error.localizedDescription }
    }

    func create() {
        guard let service = model.service, let pid = projectId, let project = model.project(pid) else { return }
        creating = true
        error = nil
        let req = SessionService.NewSession(
            project: project,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt,
            name: name.isEmpty ? nil : name,
            agent: agent,
            provider: provider == "default" ? nil : provider,
            model: modelName.isEmpty ? nil : modelName,
            branch: branch.isEmpty ? nil : branch,
            useWorktree: useWorktree,
            dependsOn: dependsOn
        )
        Task.detached {
            do {
                let s = try service.create(req)
                await MainActor.run {
                    model.refreshSessions()
                    if model.gridMode { model.showInGrid(s.id) }
                    model.select(s.id)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    creating = false
                }
            }
        }
    }
}

/// ⌘K: busca rápida de sessões.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var index = 0

    var results: [Session] {
        let all = model.sessions.sorted { ($0.status.urgency, $1.updatedAt) < ($1.status.urgency, $0.updatedAt) }
        guard !query.isEmpty else { return Array(all.prefix(12)) }
        return all.filter { s in
            [s.name, s.agent, s.branch ?? "", model.project(s.projectId)?.name ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.prefix(12).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Buscar sessão por nome, projeto, agente ou branch", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .onSubmit(open)
                .onKeyPress(.downArrow) { index = min(index + 1, max(results.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                .onChange(of: query) { index = 0 }
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, s in
                        HStack(spacing: 8) {
                            StatusIcon(status: s.status)
                            Text(s.name).lineLimit(1)
                            Spacer()
                            Text(model.project(s.projectId)?.name ?? "").foregroundStyle(.secondary).font(.caption)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(i == index ? Color.accentColor.opacity(0.18) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { index = i; open() }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 560)
    }

    func open() {
        guard index < results.count else { return }
        model.select(results[index].id)
        dismiss()
    }
}
