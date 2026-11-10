import Foundation
import GRDB

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

    /// Percorre as linhas completas a partir de `offset`, lendo em blocos de
    /// 1 MB (transcripts passam de 200 MB; ler inteiro estourava a memória do
    /// app). `body` devolve false para parar. Devolve o offset do fim da última
    /// linha completa lida, para a próxima leitura continuar dali.
    @discardableResult
    public static func forEachLine(_ url: URL, from offset: UInt64 = 0, _ body: (Data) -> Bool) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        var position = offset
        var carry = Data()
        while true {
            let chunk = autoreleasepool { (try? handle.read(upToCount: 1 << 20)) ?? Data() }
            if chunk.isEmpty { break }
            var buffer = carry
            buffer.append(chunk)
            var start = buffer.startIndex
            while let newline = buffer[start...].firstIndex(of: 0x0A) {
                let line = buffer[start..<newline]
                start = buffer.index(after: newline)
                if !line.isEmpty, !body(Data(line)) {
                    return position + UInt64(buffer.distance(from: buffer.startIndex, to: start))
                }
            }
            position += UInt64(buffer.distance(from: buffer.startIndex, to: start))
            carry = Data(buffer[start...])
        }
        return position
    }

    /// Última resposta com uso, lida do fim do arquivo (janelas de 256 KB que
    /// crescem até 8 MB). Para o anel de contexto, que só precisa dela.
    public static func lastTurn(_ url: URL) -> Turn? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let size = try? handle.seekToEnd() else { return nil }
        defer { try? handle.close() }
        var window: UInt64 = 256 * 1024
        while true {
            let start = size > window ? size - window : 0
            try? handle.seek(toOffset: start)
            let data = (try? handle.read(upToCount: Int(size - start))) ?? Data()
            // Linhas inteiras, de trás para frente (a primeira pode estar cortada).
            var lines = data.split(separator: 0x0A)
            if start > 0, !lines.isEmpty { lines.removeFirst() }
            for line in lines.reversed() {
                if let t = parseTurn(Data(line)) { return t }
            }
            if start == 0 || window >= 8 * 1024 * 1024 { return nil }
            window *= 4
        }
    }

    // ISO8601DateFormatter é seguro entre threads (documentação da Apple).
    nonisolated(unsafe) private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let usageKey = Data("\"usage\"".utf8)

    /// Uma linha de resposta com uso, ou nil.
    static func parseTurn(_ line: Data) -> Turn? {
        guard line.count > 40, line.range(of: usageKey) != nil,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let id = message["id"] as? String,
              let u = message["usage"] as? [String: Any],
              message["model"] as? String != "<synthetic>" else { return nil }
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
        let at = (obj["timestamp"] as? String).flatMap { isoParser.date(from: $0) } ?? Date()
        return Turn(messageId: id, model: message["model"] as? String, usage: usage, at: at)
    }

    /// Lê as respostas a partir de `offset` bytes. Devolve as respostas e o novo
    /// offset (fim da última linha completa), para leitura incremental.
    public static func read(_ url: URL, from offset: UInt64 = 0) -> (turns: [Turn], offset: UInt64) {
        var byId: [String: Turn] = [:]
        var order: [String] = []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let usageKey = Data("\"usage\"".utf8)
        let end = forEachLine(url, from: offset) { line in
            // Filtro barato antes do JSON: só linhas de resposta com uso.
            guard line.count > 40, line.range(of: usageKey) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let id = message["id"] as? String,
                  let u = message["usage"] as? [String: Any] else { return true }
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
            return true
        }
        let turns = order.compactMap { byId[$0] }.filter { $0.model != "<synthetic>" }
        return (turns, end)
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

    /// Contexto e custo da conversa. Só para agentes que gravam uso (Claude
    /// Code); nil para os outros. Incremental: guarda até onde leu cada conversa
    /// e, na próxima vez, lê só o que foi acrescentado.
    public static func load(nativeId: String?, prices: PriceTable) -> ContextSummary? {
        guard let nativeId, let url = ClaudeTranscript.file(for: nativeId) else { return nil }
        return ContextCache.shared.summary(nativeId: nativeId, url: url, prices: prices)
    }

    /// Versão leve para a interface: contexto e modelo da última resposta (lida
    /// do fim do arquivo) e totais do banco, que a coleta de custos já grava.
    /// Sem registros no banco ainda, cai na leitura incremental do arquivo.
    public static func quick(session: Session, store: BandoStore, prices: PriceTable) -> ContextSummary? {
        guard let nativeId = session.nativeId, let url = ClaudeTranscript.file(for: nativeId),
              let last = ClaudeTranscript.lastTurn(url) else { return nil }
        let row = try? store.pool.read { db in
            try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS n, SUM(inputTokens) AS i, SUM(outputTokens) AS o, SUM(cacheRead) AS r,
                       SUM(cacheWrite) AS w, SUM(costUsd) AS c FROM usage WHERE sessionId = ?
                """, arguments: [session.id])
        }
        guard let row, let n = row["n"] as Int?, n > 0 else { return load(nativeId: nativeId, prices: prices) }
        let total = TokenUsage(input: row["i"] ?? 0, output: row["o"] ?? 0, cacheWrite5m: row["w"] ?? 0, cacheRead: row["r"] ?? 0)
        return ContextSummary(model: last.model, contextTokens: last.usage.contextTokens,
                              contextWindow: prices.contextWindow(for: last.model),
                              total: total, cost: row["c"] ?? 0, turns: n)
    }
}

/// Soma de cada conversa já lida, por `nativeId`, para não reler o arquivo todo
/// a cada resposta do agente.
final class ContextCache: @unchecked Sendable {
    static let shared = ContextCache()
    private struct Entry {
        var offset: UInt64 = 0
        var size: UInt64 = 0
        var total = TokenUsage()
        var cost = 0.0
        var turns = 0
        var last: ClaudeTranscript.Turn?
    }
    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    func summary(nativeId: String, url: URL, prices: PriceTable) -> ContextSummary? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
        lock.lock(); var e = entries[nativeId] ?? Entry(); lock.unlock()
        if size < e.size { e = Entry() }   // arquivo reescrito (compactado): lê de novo
        if size != e.size || e.last == nil {
            let read = ClaudeTranscript.read(url, from: e.offset)
            var turns = read.turns
            // A mesma resposta pode ter linhas antes e depois do corte da leitura anterior.
            if let last = e.last, let first = turns.first, first.messageId == last.messageId {
                e.total = e.total - last.usage
                e.cost -= prices.cost(last.usage, model: last.model)
                e.turns -= 1
            }
            for t in turns {
                e.total = e.total + t.usage
                e.cost += prices.cost(t.usage, model: t.model)
            }
            e.turns += turns.count
            if let l = turns.popLast() { e.last = l }
            e.offset = read.offset
            e.size = size
            lock.lock(); entries[nativeId] = e; lock.unlock()
        }
        guard let last = e.last else { return nil }
        return ContextSummary(model: last.model, contextTokens: last.usage.contextTokens,
                              contextWindow: prices.contextWindow(for: last.model),
                              total: e.total, cost: e.cost, turns: e.turns)
    }
}
