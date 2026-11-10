import Foundation

/// Como o Bando descobre em que estado o agente está.
public enum StatusMode: String, Codable, Sendable, CaseIterable {
    /// Hooks do próprio agente chamam `bando hook`.
    case hooks
    /// Silêncio no terminal dispara leitura da tela e regex `busy`/`waiting`.
    case output
    /// Silêncio vira ocioso, atividade vira trabalhando. Sem regex.
    case silence
    /// Sem detecção (um shell comum, por exemplo).
    case none
}

/// Como a tarefa inicial chega ao agente.
public enum PromptVia: String, Codable, Sendable {
    /// Pelos argumentos de linha de comando (campo `prompt`).
    case args
    /// Digitada no terminal depois que o agente abre, para CLIs sem flag de prompt.
    case keys
}

/// Agente já resolvido: preset + arquivo do usuário, validado.
public struct AgentDefinition: Sendable, Equatable {
    public var id: String
    public var name: String
    public var cmd: String
    public var prompt: [String]
    public var promptVia: PromptVia
    /// Argumentos só para sessão nova (não entram em resume/continue).
    public var fresh: [String]
    /// Define o ID da conversa ao abrir (ex.: ["--session-id", "{new_id}"]).
    public var assignId: [String]
    /// Argumentos para bifurcar a conversa {native_id} numa nova (ex.: Claude --fork-session).
    public var fork: [String]
    public var resume: [String]
    public var continueArgs: [String]
    public var model: [String]
    public var args: [String]
    public var env: [String: String]
    public var status: StatusMode
    public var hooks: String?
    /// Como este agente recebe servidores MCP do Bando (nil = não suporta).
    public var mcp: McpAdapter?
    public var busy: String?
    public var waiting: String?
    /// Segundos sem saída até considerar que o agente parou.
    public var idleAfter: Int
    public var versionArgs: [String]
    public var install: String?
    /// Comando para atualizar a CLI. Sem ele, o botão de atualizar roda `install`
    /// de novo (os instaladores baixam a versão mais nova).
    public var update: String?

    /// O que o botão de atualizar roda.
    public var updateCommand: String? { update ?? install }
    /// Pergunta única para gerar o título da sessão (`{prompt}`, `{model}`).
    /// Vazio: o agente não gera título (fica o nome provisório).
    public var title: [String] = []
    /// Modelo do título quando o provider é a conta do próprio agente.
    public var titleModel: String?
}

/// Forma "parcial" lida do TOML. Tudo opcional para permitir que o arquivo do
/// usuário mude um único campo de um preset.
struct AgentEntry: Codable, Sendable {
    var name: String?
    var cmd: String?
    var prompt: [String]?
    var promptVia: PromptVia?
    var fresh: [String]?
    var assignId: [String]?
    var fork: [String]?
    var resume: [String]?
    var `continue`: [String]?
    var model: [String]?
    var args: [String]?
    var env: [String: String]?
    var status: StatusMode?
    var hooks: String?
    var mcp: McpAdapter?
    var busy: String?
    var waiting: String?
    var idleAfter: Int?
    var version: [String]?
    var install: String?
    var update: String?
    var enabled: Bool?
    var title: [String]?
    var titleModel: String?

    enum CodingKeys: String, CodingKey {
        case name, cmd, prompt, fresh, fork, resume, `continue`, model, args, env, status
        case hooks, busy, waiting, version, install, update, enabled, mcp, title
        case titleModel = "title_model"
        case idleAfter = "idle_after"
        case promptVia = "prompt_via"
        case assignId = "assign_id"
    }

    /// Campos de `override` vencem; os ausentes ficam com o valor de `self`.
    func merged(with o: AgentEntry) -> AgentEntry {
        AgentEntry(
            name: o.name ?? name,
            cmd: o.cmd ?? cmd,
            prompt: o.prompt ?? prompt,
            promptVia: o.promptVia ?? promptVia,
            fresh: o.fresh ?? fresh,
            assignId: o.assignId ?? assignId,
            fork: o.fork ?? fork,
            resume: o.resume ?? resume,
            continue: o.continue ?? self.continue,
            model: o.model ?? model,
            args: o.args ?? args,
            env: o.env ?? env,
            status: o.status ?? status,
            hooks: o.hooks ?? hooks,
            mcp: o.mcp ?? mcp,
            busy: o.busy ?? busy,
            waiting: o.waiting ?? waiting,
            idleAfter: o.idleAfter ?? idleAfter,
            version: o.version ?? version,
            install: o.install ?? install,
            update: o.update ?? update,
            enabled: o.enabled ?? enabled,
            title: o.title ?? title,
            titleModel: o.titleModel ?? titleModel
        )
    }

    func resolved(id: String) throws -> AgentDefinition {
        guard let cmd, !cmd.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ConfigError.missingField(section: "agents.\(id)", field: "cmd")
        }
        // Sem regex, o modo output se comporta como silence.
        let status = status ?? .silence
        for (field, pattern) in [("busy", busy), ("waiting", waiting)] {
            if let pattern, (try? Regex(pattern)) == nil {
                throw ConfigError.invalidRegex(section: "agents.\(id)", field: field, pattern: pattern)
            }
        }
        if let idleAfter, idleAfter < 1 {
            throw ConfigError.invalidValue(section: "agents.\(id)", field: "idle_after", detail: "precisa ser 1 ou mais")
        }
        return AgentDefinition(
            id: id,
            name: name ?? id,
            cmd: cmd,
            prompt: prompt ?? [],
            promptVia: promptVia ?? ((prompt ?? []).isEmpty ? .keys : .args),
            fresh: fresh ?? [],
            assignId: assignId ?? [],
            fork: fork ?? [],
            resume: resume ?? [],
            continueArgs: self.continue ?? [],
            model: model ?? [],
            args: args ?? [],
            env: env ?? [:],
            status: status,
            hooks: hooks,
            mcp: mcp,
            busy: busy,
            waiting: waiting,
            idleAfter: idleAfter ?? 4,
            versionArgs: version ?? ["--version"],
            install: install,
            update: update,
            title: title ?? [],
            titleModel: titleModel
        )
    }
}
