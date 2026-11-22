import Foundation

/// Monta o contexto da equipe entregue ao agente no início da sessão
/// (arquivo `.bando/team-<id>.md` + preâmbulo estruturado do prompt).
public enum TeamContext {
    public static func relativePath(teamId: String) -> String {
        ".bando/team-\(String(teamId.prefix(8))).md"
    }

    /// Grava o resumo vivo da equipe no worktree da sessão para o agente consultar.
    @discardableResult
    public static func writeContextFile(
        for session: Session,
        team: TeamRecord,
        members: [Session],
        edges: [TeamEdgeRecord],
        config: BandoConfig
    ) -> URL? {
        let rel = relativePath(teamId: team.id)
        let url = URL(fileURLWithPath: session.worktreePath).appendingPathComponent(rel)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            Handoff.ensureIgnored(worktree: session.worktreePath)
            let body = renderMarkdown(for: session, team: team, members: members, edges: edges, config: config)
            try body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    public static func renderMarkdown(
        for session: Session,
        team: TeamRecord,
        members: [Session],
        edges: [TeamEdgeRecord],
        config: BandoConfig
    ) -> String {
        var lines: [String] = []
        lines.append("# Equipe: \(team.name) (\(team.shortId))")
        if let goal = team.goal, !goal.isEmpty {
            lines.append("")
            lines.append("**Objetivo geral:** \(goal)")
        }
        lines.append("")
        lines.append("## Seu papel nesta equipe")
        let roleName = session.roleTitle ?? session.name
        lines.append("- **Sessão:** `\(session.shortId)` (\(roleName)\(session.isOrchestrator ? " — Orquestrador" : ""))")
        let agentName = config.agents[session.agent]?.name ?? session.agent
        let providerLabel = session.provider.map { config.providers[$0]?.name ?? $0 } ?? "Conta do agente"
        let modelLabel = session.model ?? "padrão"
        lines.append("- **Runtime:** \(agentName) · \(providerLabel) · \(modelLabel)")
        lines.append("- **Worktree:** `\(session.worktreePath)`" + (session.branch.map { " (branch `\($0)`)" } ?? ""))
        if let resp = session.responsibilities, !resp.isEmpty {
            lines.append("- **Responsabilidades:** \(resp)")
        }

        let peers = members.filter { $0.id != session.id }
        lines.append("")
        lines.append("## Membros conectados")
        if peers.isEmpty {
            lines.append("_Nenhum outro membro conectado no momento._")
        } else {
            for m in peers {
                let mRole = m.roleTitle ?? m.name
                let mAgent = config.agents[m.agent]?.name ?? m.agent
                let mProv = m.provider.map { config.providers[$0]?.name ?? $0 } ?? "padrão"
                let mModel = m.model ?? "padrão"
                let relation = edges
                    .filter { ($0.fromSessionId == session.id && $0.toSessionId == m.id) || ($0.toSessionId == session.id && $0.fromSessionId == m.id) }
                    .map { e in e.fromSessionId == session.id ? "→ \(e.kind.rawValue)" : "← \(e.kind.rawValue)" }
                    .joined(separator: ", ")
                let relInfo = relation.isEmpty ? "" : " [\(relation)]"
                let wt = m.worktreeSourceId != nil ? "worktree compartilhado" : (m.branch ?? m.worktreePath)
                lines.append("- **`\(m.shortId)` \(mRole)**\(m.isOrchestrator ? " (Orquestrador)" : "")\(relInfo): `\(mAgent)` · `\(mProv)` · `\(mModel)` — estado: `\(m.status.label)` — \(wt)")
                if let r = m.responsibilities, !r.isEmpty {
                    lines.append("  Responsabilidade: \(r)")
                }
            }
        }

        lines.append("")
        lines.append("## Como coordenar a equipe")
        if config.agents[session.agent]?.mcp != nil {
            lines.append("Você tem o servidor MCP `bando-team` disponível (`team_list_members`, `team_spawn_member`, `team_delegate`, `team_read_output`, `team_stop_member`).")
        }
        lines.append("Você também pode usar os comandos CLI do Bando no terminal:")
        lines.append("- `bando team show \(team.shortId)` — ver membros, papéis e estados")
        lines.append("- `bando team delegate <id-ou-papel> \"<tarefa>\" --team \(team.shortId)` — delegar tarefa para um membro")
        lines.append("- `bando team add \(team.shortId) --role \"<papel>\" --agent <agente> --provider <provider> --model <modelo> --responsibilities \"<escopo>\" --prompt \"<tarefa>\"` — criar novo especialista na equipe")
        lines.append("- `bando team output <id-ou-papel> --team \(team.shortId)` — ler últimas linhas do terminal de outro membro")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Monta o prompt inicial combinado para uma sessão pertencente a uma equipe.
    public static func enrichedPrompt(
        basePrompt: String?,
        for session: Session,
        team: TeamRecord,
        contextFileRelativePath: String?
    ) -> String? {
        var parts: [String] = []
        let role = session.roleTitle ?? session.name
        var header = "[Modo Equipe · \(team.name)] Seu papel: \(role)\(session.isOrchestrator ? " (Orquestrador)" : "")."
        if let goal = team.goal, !goal.isEmpty {
            header += " Objetivo geral: \(goal)."
        }
        parts.append(header)
        if let resp = session.responsibilities, !resp.isEmpty {
            parts.append("Suas responsabilidades:\n\(resp)")
        }
        if let contextFileRelativePath {
            parts.append("Consulte o arquivo `\(contextFileRelativePath)` para ver os membros conectados, providers/modelos e comandos de coordenação da equipe.")
        }
        if let base = basePrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty {
            parts.append("Tarefa:\n\(base)")
        } else if session.isOrchestrator {
            parts.append("Analise o objetivo e coordene a equipe ativamente: envie tarefas concretas aos especialistas conectados usando `team_delegate` (ou `bando team delegate`), acompanhe a execução com `team_read_output` (ou `bando team output`) e consolide os resultados.")
        }
        return parts.joined(separator: "\n\n")
    }
}
