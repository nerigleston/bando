import Foundation

/// O que vai para o novo agente quando a sessão troca de agente.
public enum HandoffMode: String, Codable, Sendable, CaseIterable {
    /// O agente atual escreve um resumo em `.bando/handoff.md` antes de sair.
    case summary = "resumo"
    /// O Bando exporta a conversa para `.bando/conversa.md` e o novo agente
    /// escreve o resumo em `.bando/handoff.md` antes de seguir. Não depende
    /// do agente atual estar rodando (serve quando ele bateu o limite).
    case receiverSummary = "resumo-novo"
    /// O Bando exporta a conversa inteira para `.bando/handoff.md` (sem tokens).
    case transcript = "conversa"
    /// Só a tarefa original.
    case none = "nenhum"

    public var label: String {
        switch self {
        case .summary: "Resumo em .md (escrito pelo agente atual)"
        case .receiverSummary: "Resumo em .md (escrito pelo novo agente)"
        case .transcript: "Conversa completa em .md"
        case .none: "Só a tarefa"
        }
    }
}

/// Arquivo de repasse dentro do worktree, fora do git.
public enum Handoff {
    public static let relativePath = ".bando/handoff.md"
    /// Conversa exportada para o novo agente ler e resumir.
    public static let conversationPath = ".bando/conversa.md"

    public static func url(worktree: String) -> URL {
        URL(fileURLWithPath: worktree).appendingPathComponent(relativePath)
    }

    public static func conversationURL(worktree: String) -> URL {
        URL(fileURLWithPath: worktree).appendingPathComponent(conversationPath)
    }

    /// Pedido ao novo agente quando é ele quem escreve o resumo.
    public static func receiverRequest() -> String {
        "Antes de qualquer coisa, leia o arquivo \(conversationPath): é a conversa anterior completa. "
            + "Escreva em \(relativePath), em Markdown e de forma objetiva: objetivo e estado atual do trabalho; "
            + "comandos usados (build, testes, execução, deploy) exatamente como aparecem; decisões e particularidades combinadas; "
            + "o que falta fazer; arquivos e pastas importantes. Depois continue o trabalho a partir desse resumo."
    }

    /// Texto do pedido de resumo: `~/.config/bando/handoff.md` (do usuário) ou o padrão.
    public static func template(paths: BandoPaths) -> String {
        let file = paths.configDir.appendingPathComponent("handoff.md")
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            // Comentários do modelo (linhas com "#" no início) não vão para o agente.
            let body = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("#") }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { return body }
        }
        return UserTemplates.handoffDefault
    }

    /// Põe `.bando/` no ignore local do repositório (não é commitado), para o
    /// arquivo de repasse não aparecer em `git status` nem em commits.
    public static func ensureIgnored(worktree: String) {
        guard let git = try? Git(),
              let r = try? Shell.run(git.executable, ["rev-parse", "--git-path", "info/exclude"], cwd: worktree), r.ok else { return }
        var path = r.trimmed
        if !path.hasPrefix("/") { path = URL(fileURLWithPath: worktree).appendingPathComponent(path).path }
        let current = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard !current.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == ".bando/" }) else { return }
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = (current.isEmpty || current.hasSuffix("\n") ? "" : "\n") + "# Arquivos de repasse do Bando\n.bando/\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Conversa do Claude Code em Markdown: falas do usuário, respostas e
    /// ferramentas usadas (só o comando, sem a saída).
    public static func claudeTranscriptMarkdown(nativeId: String, title: String) -> String? {
        guard let url = ClaudeTranscript.file(for: nativeId) else { return nil }
        var out = ["# Conversa anterior: \(title)", "",
                   "Exportada pelo Bando da sessão do Claude Code \(nativeId).", ""]
        var lastRole = ""
        ClaudeTranscript.forEachLine(url) { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = obj["type"] as? String, type == "user" || type == "assistant",
                  obj["isSidechain"] as? Bool != true,
                  let message = obj["message"] as? [String: Any] else { return true }
            var parts: [String] = []
            if let text = message["content"] as? String {
                parts.append(text)
            } else if let blocks = message["content"] as? [[String: Any]] {
                for b in blocks {
                    switch b["type"] as? String {
                    case "text":
                        if let t = b["text"] as? String { parts.append(t) }
                    case "tool_use":
                        let name = b["name"] as? String ?? "ferramenta"
                        let input = b["input"] as? [String: Any] ?? [:]
                        let detail = (input["command"] ?? input["file_path"] ?? input["pattern"] ?? input["url"]).map { "\($0)" } ?? ""
                        parts.append("- `\(name)`" + (detail.isEmpty ? "" : ": `\(detail.prefix(200))`"))
                    default: break   // tool_result e thinking ficam de fora
                    }
                }
            }
            let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !text.hasPrefix("<") else { return true }
            let role = type == "user" ? "Você" : "Claude"
            if role != lastRole { out.append("## \(role)"); lastRole = role }
            out.append(text)
            out.append("")
            return true
        }
        return out.joined(separator: "\n")
    }
}
