import Foundation

/// Leitura dos transcripts do Claude Code (`~/.claude/projects/*/<id>.jsonl`).
///
/// Cada resposta do modelo é uma linha `type: "assistant"` com `message.id`,
/// `message.model` e `message.usage`. Uma resposta com vários blocos repete a
/// mesma `message.id`; vale a última.
public enum ClaudeTranscript {
    public struct Turn: Sendable {
        public var messageId: String
        public var model: String?
        public var usage: TokenUsage
        public var at: Date
    }

    public static var projectsDir: URL {
        let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
        return (env ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"))
            .appendingPathComponent("projects")
    }

    /// Arquivo da conversa `nativeId`, procurando em todas as pastas de projeto.
    public static func file(for nativeId: String) -> URL? {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else { return nil }
        for dir in dirs {
            let candidate = dir.appendingPathComponent("\(nativeId).jsonl")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Lê as respostas a partir de `offset` bytes. Devolve as respostas e o novo
    /// offset (fim da última linha completa), para leitura incremental.
    public static func read(_ url: URL, from offset: UInt64 = 0) -> (turns: [Turn], offset: UInt64) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ([], offset) }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return ([], offset) }
        let complete = data[data.startIndex...lastNewline]

        var byId: [String: Turn] = [:]
        var order: [String] = []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in complete.split(separator: 0x0A) {
            // Filtro barato antes do JSON: só linhas de resposta com uso.
            guard line.count > 40, line.range(of: Data("\"usage\"".utf8)) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let id = message["id"] as? String,
                  let u = message["usage"] as? [String: Any] else { continue }
            var usage = TokenUsage(
                input: u["input_tokens"] as? Int ?? 0,
                output: u["output_tokens"] as? Int ?? 0,
                cacheRead: u["cache_read_input_tokens"] as? Int ?? 0
            )
            if let detail = u["cache_creation"] as? [String: Any] {
                usage.cacheWrite5m = detail["ephemeral_5m_input_tokens"] as? Int ?? 0
                usage.cacheWrite1h = detail["ephemeral_1h_input_tokens"] as? Int ?? 0
            } else {
                usage.cacheWrite5m = u["cache_creation_input_tokens"] as? Int ?? 0
            }
            let at = (obj["timestamp"] as? String).flatMap { iso.date(from: $0) } ?? Date()
            if byId[id] == nil { order.append(id) }
            byId[id] = Turn(messageId: id, model: message["model"] as? String, usage: usage, at: at)
        }
        let turns = order.compactMap { byId[$0] }.filter { $0.model != "<synthetic>" }
        return (turns, offset + UInt64(complete.count))
    }
}

/// Resumo de contexto e custo de uma conversa do agente.
public struct ContextSummary: Sendable {
    public var model: String?
    public var contextTokens: Int
    public var contextWindow: Int
    public var total: TokenUsage
    public var cost: Double
    public var turns: Int

    public var fraction: Double { contextWindow > 0 ? min(Double(contextTokens) / Double(contextWindow), 1) : 0 }

    /// Lê o transcript inteiro da conversa. Só para agentes que gravam uso
    /// (Claude Code); devolve nil para os outros.
    public static func load(nativeId: String?, prices: PriceTable) -> ContextSummary? {
        guard let nativeId, let url = ClaudeTranscript.file(for: nativeId) else { return nil }
        let turns = ClaudeTranscript.read(url).turns
        guard let last = turns.last else { return nil }
        let total = turns.reduce(TokenUsage()) { $0 + $1.usage }
        let cost = turns.reduce(0.0) { $0 + prices.cost($1.usage, model: $1.model) }
        return ContextSummary(model: last.model, contextTokens: last.usage.contextTokens,
                              contextWindow: prices.contextWindow(for: last.model),
                              total: total, cost: cost, turns: turns.count)
    }
}
