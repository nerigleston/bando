import AppKit
import BandoCore
import SwiftUI

// MARK: - Nova equipe (a partir de template ou do zero)

struct NewTeamSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p

    @State private var projectId: String?
    @State private var name = ""
    @State private var goal = ""
    @State private var selectedTemplateId: String = "feature-completa"
    @State private var roles: [RoleDraft] = []
    @State private var edges: [TeamEdgeDefinition] = []
    @State private var startNow = true
    @State private var error: String?

    struct RoleDraft: Identifiable {
        let id = UUID()
        var roleId: String
        var name: String
        var responsibilities: String
        var agent: String
        var provider: String
        var model: String
        var compressor: String
        var isOrchestrator: Bool
        var worktree: WorktreePolicy
        var shareWorktreeWithRoleId: String?
        var autoStart: Bool
        var canvasX: Double
        var canvasY: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(
                title: "Nova equipe multi-agente",
                description: "Monte uma equipe por projeto combinando agentes, providers e modelos diferentes no mesmo Canvas.",
                symbol: "point.3.connected.trianglepath.dotted"
            )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Projeto")
                    SelectField(selection: $projectId, options: model.projects.map { (Optional($0.id), $0.name) })
                }
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Nome da equipe")
                    TextField("ex.: Refatoração da API", text: $name).fieldBox()
                }
            }
            // Modelos vindos do próprio repositório: quem escreveu o repo decide
            // papéis, agentes e tarefas. Aviso antes de rodar.
            if let path = projectId.flatMap(model.project)?.path,
               FileManager.default.fileExists(atPath: BandoPaths.projectTeamsFile(for: path).path) {
                Label("Este repositório tem .bando/teams.toml: os modelos dele aparecem aqui e podem mudar os padrões. Confira papéis e tarefas antes de criar.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5)).foregroundStyle(StateColor.waiting)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                FieldLabel("Objetivo geral", hint: "enviado ao orquestrador e à equipe")
                TextEditor(text: $goal)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(.vertical, 6)
                    .frame(minHeight: 54, maxHeight: 90)
                    .fieldBox(height: nil)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Template")
                    SelectField(
                        selection: $selectedTemplateId,
                        options: [("__custom__", "Em branco (só Orquestrador)")] + availableTemplates.map { ($0.id, $0.name) }
                    )
                }
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Início")
                    Toggle("Iniciar agentes ao criar", isOn: $startNow)
                        .toggleStyle(.switch).controlSize(.small)
                        .frame(height: 30)
                }
            }

            DialogDivider()

            let connectedList = model.connectedProvidersWithModels
            if !connectedList.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Providers conectados e modelos disponíveis", hint: "clique para ver a lista de modelos")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(connectedList, id: \.provider.id) { item in
                                Menu {
                                    if item.models.isEmpty {
                                        Text("Sem modelos pré-cadastrados (use o campo Modelo)")
                                    } else {
                                        ForEach(item.models, id: \.self) { m in
                                            Text(m)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Circle().fill(StateColor.working).frame(width: 6, height: 6)
                                        Text(item.provider.name).font(.system(size: 11.5, weight: .medium))
                                        if !item.models.isEmpty {
                                            Text("(\(item.models.count))")
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(p.secondary)
                                        }
                                        Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(p.tertiary)
                                    }
                                    .foregroundStyle(p.text)
                                    .padding(.horizontal, 9).frame(height: 24)
                                    .background(Capsule().fill(p.panel.opacity(0.6)))
                                    .overlay(Capsule().strokeBorder(p.border.opacity(1.5)))
                                }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().pointerCursor()
                            }
                        }
                    }
                }
            }

            HStack {
                FieldLabel("Papéis da equipe (\(roles.count))", hint: "cada papel pode usar agente, provider e modelo próprios")
                Spacer()
                Button {
                    let idx = roles.count
                    let defAgent = defaultAgentId()
                    roles.append(RoleDraft(
                        roleId: "especialista-\(idx + 1)",
                        name: "Especialista \(idx + 1)",
                        responsibilities: "",
                        agent: defAgent,
                        provider: "default",
                        model: "",
                        compressor: "",
                        isOrchestrator: false,
                        worktree: .isolated,
                        shareWorktreeWithRoleId: roles.first(where: \.isOrchestrator)?.roleId,
                        autoStart: true,
                        canvasX: Double(100 + (idx % 3) * 420),
                        canvasY: Double(80 + (idx / 3) * 320)
                    ))
                } label: {
                    Label("Adicionar papel", systemImage: "plus")
                }
                .buttonStyle(OutlineButtonStyle())
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($roles) { $role in
                        RoleDraftRow(
                            role: $role,
                            allRoles: roles,
                            canDelete: roles.count > 1,
                            onDelete: { roles.removeAll { $0.id == role.id } }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 260)

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(StateColor.failed)
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(OutlineButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Criar equipe", action: create)
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(projectId == nil || roles.isEmpty)
            }
        }
        .dialog(width: 780, palette: p)
        .onAppear {
            model.refreshProviders()
            setup()
        }
        .onChange(of: selectedTemplateId) { _, _ in applyTemplate() }
        .onChange(of: projectId) { _, _ in applyTemplate() }
    }

    var availableTemplates: [TeamTemplate] {
        let proj = projectId.flatMap(model.project)
        return model.config?.teams(forProject: proj?.path) ?? []
    }

    func defaultAgentId() -> String {
        let proj = projectId.flatMap(model.project)
        let preferred = proj?.defaultAgent ?? model.lastAgent
        if model.availability[preferred]?.isInstalled == true { return preferred }
        return model.availability.values.first(where: { $0.isInstalled && $0.agent.id != "shell" })?.agent.id ?? "claude"
    }

    func setup() {
        projectId = model.selectedSession?.projectId
            ?? model.projects.max { ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast) }?.id
        if let first = availableTemplates.first { selectedTemplateId = first.id }
        applyTemplate()
    }

    func applyTemplate() {
        let defAgent = defaultAgentId()
        let defProvider = projectId.flatMap(model.project)?.defaultProvider ?? "default"
        if selectedTemplateId == "__custom__" {
            roles = [
                RoleDraft(
                    roleId: "orchestrator", name: "Orquestrador",
                    responsibilities: "Analisar o objetivo, coordenar especialistas e consolidar a entrega.",
                    agent: defAgent, provider: defProvider, model: "", compressor: "",
                    isOrchestrator: true, worktree: .isolated, shareWorktreeWithRoleId: nil,
                    autoStart: true, canvasX: 80, canvasY: 160
                ),
            ]
            edges = []
            return
        }
        guard let tpl = availableTemplates.first(where: { $0.id == selectedTemplateId }) else { return }
        if name.isEmpty { name = tpl.name }
        roles = tpl.roles.map { r in
            let a = r.agent ?? defAgent
            let prov = r.provider ?? defProvider
            let mod = r.model ?? (prov != "default" ? (model.config?.providers[prov]?.models.first ?? "") : "")
            return RoleDraft(
                roleId: r.id, name: r.name, responsibilities: r.responsibilities,
                agent: a, provider: prov, model: mod, compressor: r.compressor ?? "",
                isOrchestrator: r.isOrchestrator, worktree: r.worktree,
                shareWorktreeWithRoleId: r.shareWorktreeWith, autoStart: r.autoStart,
                canvasX: r.canvasX, canvasY: r.canvasY
            )
        }
        edges = tpl.edges
    }

    func create() {
        guard let pid = projectId, let project = model.project(pid) else { return }
        let specs = roles.map { r in
            TeamService.RoleSpec(
                roleId: r.roleId,
                name: r.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? r.roleId : r.name,
                responsibilities: r.responsibilities,
                agent: r.agent,
                provider: r.provider == "default" ? nil : r.provider,
                model: r.model.isEmpty ? nil : r.model,
                compressor: r.compressor.isEmpty ? nil : r.compressor,
                isOrchestrator: r.isOrchestrator,
                worktree: r.worktree,
                shareWorktreeWithRoleId: r.shareWorktreeWithRoleId,
                autoStart: r.autoStart,
                canvasX: r.canvasX,
                canvasY: r.canvasY
            )
        }
        let edgeSpecs = edges.map { TeamService.EdgeSpec(fromRoleId: $0.fromRole, toRoleId: $0.toRole, kind: $0.kind) }
        let req = TeamService.CreateTeamRequest(
            project: project,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Equipe \(project.name)" : name,
            goal: goal.isEmpty ? nil : goal,
            templateId: selectedTemplateId == "__custom__" ? nil : selectedTemplateId,
            roles: specs,
            edges: edgeSpecs,
            startNow: startNow
        )
        model.createTeam(req)
        dismiss()
    }
}

private struct RoleDraftRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @Binding var role: NewTeamSheet.RoleDraft
    let allRoles: [NewTeamSheet.RoleDraft]
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { role.isOrchestrator.toggle() } label: {
                    Image(systemName: role.isOrchestrator ? "crown.fill" : "crown")
                        .foregroundStyle(role.isOrchestrator ? StateColor.waiting : p.tertiary)
                }
                .buttonStyle(.plain).pointerCursor().help("Marcar como Orquestrador")

                TextField("Papel", text: $role.name).fieldBox(height: 28).frame(width: 130)

                SelectField(selection: $role.agent, options: agents.map {
                    ($0.agent.id, $0.agent.name + ($0.isInstalled ? "" : " (ausente)"))
                }, height: 28)
                .frame(width: 135)

                ProviderField(agentId: role.agent, selection: $role.provider, height: 28)
                    .frame(width: 155)

                ModelField(agentId: role.agent, providerId: role.provider, text: $role.model, height: 28)
                    .frame(minWidth: 160, maxWidth: .infinity)

                if canDelete {
                    IconButton(symbol: "trash", help: "Remover papel", size: 12, action: onDelete)
                }
            }

            HStack(spacing: 8) {
                TextField("Responsabilidade deste agente…", text: $role.responsibilities)
                    .fieldBox(height: 26)
                    .frame(maxWidth: .infinity)
                Picker("", selection: $role.worktree) {
                    Text("Worktree próprio").tag(WorktreePolicy.isolated)
                    Text("Compartilhado").tag(WorktreePolicy.shared)
                }
                .labelsHidden().frame(width: 138)

                if role.worktree == .shared {
                    let owners = allRoles.filter { $0.id != role.id && $0.worktree == .isolated }
                    if !owners.isEmpty {
                        Picker("", selection: Binding(
                            get: { role.shareWorktreeWithRoleId ?? owners.first?.roleId ?? "" },
                            set: { role.shareWorktreeWithRoleId = $0 }
                        )) {
                            ForEach(owners) { o in Text("com \(o.name)").tag(o.roleId) }
                        }
                        .labelsHidden().frame(width: 112)
                    }
                }
                Toggle("Auto", isOn: $role.autoStart).toggleStyle(.checkbox).font(.system(size: 11)).fixedSize()
                    .help("Iniciar junto com a equipe (desmarque para iniciar só quando o orquestrador delegar)")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(p.panel.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.border))
        .onChange(of: role.agent) { _, _ in
            if !providers.contains(where: { $0.id == role.provider }) { role.provider = "default" }
        }
        .onChange(of: role.provider) { _, new in
            role.model = model.config?.providers[new]?.models.first ?? ""
        }
    }

    var agents: [AgentAvailability] {
        model.availability.values.filter { $0.agent.id != "shell" }
            .sorted { ($0.isInstalled ? 0 : 1, $0.agent.name) < ($1.isInstalled ? 0 : 1, $1.agent.name) }
    }

    var providers: [ProviderDefinition] {
        (model.config?.providers(for: role.agent) ?? [])
            .sorted { ($0.id == "default" ? 0 : 1, $0.name) < ($1.id == "default" ? 0 : 1, $1.name) }
    }
}

// MARK: - Adicionar novo agente ao Canvas

struct AddTeamMemberSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p

    let team: TeamRecord
    @State private var roleTitle = ""
    @State private var agent = "claude"
    @State private var provider = "default"
    @State private var modelName = ""
    @State private var compressor = ""
    @State private var responsibilities = ""
    @State private var prompt = ""
    @State private var isOrchestrator = false
    @State private var worktree: WorktreePolicy = .isolated
    @State private var shareWithSessionId: String?
    @State private var connectFromSessionId: String?
    @State private var edgeKind: TeamEdgeKind = .delegate
    @State private var startNow = true

    var body: some View {
        let members = model.teamSessions(team.id)
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(
                title: "Adicionar agente à equipe",
                description: "Escolha o papel, agente, provider, modelo e como ele se conecta no Canvas.",
                symbol: "person.badge.plus"
            )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Papel")
                    TextField("ex.: Revisor de Segurança", text: $roleTitle).fieldBox()
                }
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Orquestrador")
                    Toggle("É coordenador", isOn: $isOrchestrator).toggleStyle(.switch).controlSize(.small).frame(height: 30)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Agente")
                    SelectField(selection: $agent, options: agents.map {
                        ($0.agent.id, $0.agent.name + ($0.isInstalled ? "" : " (não instalado)"))
                    })
                }
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Provider")
                    ProviderField(agentId: agent, selection: $provider)
                }
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Modelo", hint: "opcional")
                    ModelField(agentId: agent, providerId: provider, text: $modelName, placeholder: modelHint)
                }
            }

            if !compressors.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Compressão", hint: "opcional")
                    SelectField(selection: $compressor, options: [("", "Sem compressão")] + compressors.map { ($0.id, $0.name) })
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                FieldLabel("Responsabilidades")
                TextEditor(text: $responsibilities)
                    .font(.system(size: 12.5)).scrollContentBackground(.hidden)
                    .padding(.vertical, 4).frame(minHeight: 50, maxHeight: 80).fieldBox(height: nil)
            }

            VStack(alignment: .leading, spacing: 5) {
                FieldLabel("Tarefa inicial", hint: "opcional")
                TextField("Deixe vazio para aguardar delegação do orquestrador", text: $prompt).fieldBox()
            }

            DialogDivider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Worktree")
                    SelectField(selection: $worktree, options: WorktreePolicy.allCases.map { ($0, $0.label) })
                }
                if worktree == .shared && !members.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        FieldLabel("Compartilhar com")
                        SelectField(selection: $shareWithSessionId, options: members.map { (Optional($0.id), $0.roleTitle ?? $0.name) })
                    }
                }
            }

            if !members.isEmpty {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        FieldLabel("Conectar a partir de", hint: "opcional")
                        SelectField(selection: $connectFromSessionId, options: [(String?.none, "Sem ligação inicial")] + members.map { (Optional($0.id), $0.roleTitle ?? $0.name) })
                    }
                    if connectFromSessionId != nil {
                        VStack(alignment: .leading, spacing: 5) {
                            FieldLabel("Tipo de ligação")
                            SelectField(selection: $edgeKind, options: TeamEdgeKind.allCases.map { ($0, $0.label) })
                        }
                    }
                }
            }

            Toggle("Iniciar sessão imediatamente", isOn: $startNow).toggleStyle(.switch).controlSize(.small)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(OutlineButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Adicionar") {
                    let title = roleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.addTeamMember(
                        to: team.id,
                        roleTitle: title.isEmpty ? (model.config?.agents[agent]?.name ?? agent) : title,
                        agent: agent,
                        provider: provider == "default" ? nil : provider,
                        model: modelName.isEmpty ? nil : modelName,
                        compressor: compressor.isEmpty ? nil : compressor,
                        responsibilities: responsibilities,
                        prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt,
                        isOrchestrator: isOrchestrator,
                        worktree: worktree,
                        shareWithSessionId: shareWithSessionId,
                        connectFromSessionId: connectFromSessionId,
                        edgeKind: edgeKind,
                        startNow: startNow
                    )
                    dismiss()
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .dialog(width: 580, palette: p)
        .onAppear {
            let orch = members.first(where: \.isOrchestrator) ?? members.first
            connectFromSessionId = orch?.id
            shareWithSessionId = orch?.id
        }
        .onChange(of: agent) { _, _ in
            if !providers.contains(where: { $0.id == provider }) { provider = "default" }
        }
        .onChange(of: provider) { _, new in
            modelName = model.config?.providers[new]?.models.first ?? ""
        }
    }

    var agents: [AgentAvailability] {
        model.availability.values.filter { $0.agent.id != "shell" }
            .sorted { ($0.isInstalled ? 0 : 1, $0.agent.name) < ($1.isInstalled ? 0 : 1, $1.agent.name) }
    }

    var providers: [ProviderDefinition] {
        (model.config?.providers(for: agent) ?? [])
            .sorted { ($0.id == "default" ? 0 : 1, $0.name) < ($1.id == "default" ? 0 : 1, $1.name) }
    }

    var compressors: [CompressorDefinition] { model.config?.compressors(for: agent) ?? [] }
    var modelHint: String { model.config?.providers[provider]?.models.first ?? "padrão da CLI" }
}

// MARK: - Salvar topologia atual como template TOML

struct SaveTeamTemplateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p

    let team: TeamRecord
    @State private var templateId = ""
    @State private var name = ""
    @State private var description = ""
    @State private var scope: Scope = .user
    @State private var error: String?

    enum Scope: String, CaseIterable {
        case user = "Global (~/.config/bando/teams.toml)"
        case project = "Só neste projeto (.bando/teams.toml)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeader(
                title: "Salvar equipe como template",
                description: "Grava os papéis, agentes, providers, modelos, worktrees e conexões do Canvas em TOML.",
                symbol: "square.and.arrow.down"
            )
            VStack(alignment: .leading, spacing: 5) {
                FieldLabel("ID do template")
                TextField("ex.: squad-api", text: $templateId).fieldBox()
            }
            VStack(alignment: .leading, spacing: 5) {
                FieldLabel("Nome")
                TextField("Nome exibido", text: $name).fieldBox()
            }
            VStack(alignment: .leading, spacing: 5) {
                FieldLabel("Descrição", hint: "opcional")
                TextField("Resumo do fluxo", text: $description).fieldBox()
            }
            VStack(alignment: .leading, spacing: 5) {
                FieldLabel("Onde salvar")
                SelectField(selection: $scope, options: Scope.allCases.map { ($0, $0.rawValue) })
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(StateColor.failed) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(OutlineButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Salvar template", action: save).buttonStyle(AccentButtonStyle()).keyboardShortcut(.return, modifiers: .command)
            }
        }
        .dialog(width: 480, palette: p)
        .onAppear {
            name = team.name
            templateId = Slug.make(team.name, maxLength: 32)
            description = team.goal ?? ""
        }
    }

    func save() {
        guard let service = model.service else { return }
        let id = Slug.make(templateId, maxLength: 32)
        do {
            let tpl = try TeamService(service: service).exportTemplate(
                teamId: team.id,
                templateId: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : name,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description
            )
            let targetURL: URL
            if scope == .project, let proj = model.project(team.projectId) {
                targetURL = BandoPaths.projectTeamsFile(for: proj.path)
            } else {
                targetURL = service.paths.teamsFile
            }
            try TeamTemplateTOML.upsert(tpl, into: targetURL)
            Task { await model.reload() }
            model.toast = "Template \(tpl.name) salvo"
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
