import Foundation
import GRDB

/// Copia o uso dos transcripts para a tabela `usage`, de forma incremental
/// (guarda até onde leu cada arquivo). É chamado no fim de cada vez do agente
/// e ao abrir os relatórios; não roda em segundo plano.
public struct UsageCollector {
    let store: BandoStore
    let prices: PriceTable

    public init(store: BandoStore, prices: PriceTable = .load()) {
        self.store = store
        self.prices = prices
    }

    /// Coleta todas as sessões do Claude Code com conversa conhecida.
    @discardableResult
    public func collectAll() throws -> Int {
        let sessions = try store.pool.read { db in
            try Session.filter(Column("nativeId") != nil).fetchAll(db)
        }
        return try sessions.reduce(0) { $0 + (try collect($1)) }
    }

    /// Coleta uma sessão. Devolve quantas respostas novas entraram.
    @discardableResult
    public func collect(_ session: Session) throws -> Int {
        guard let native = session.nativeId, let url = ClaudeTranscript.file(for: native) else { return 0 }
        let key = url.path
        let start = try store.pool.read { db in
            try UInt64(Int.fetchOne(db, sql: "SELECT offset FROM transcriptOffset WHERE path = ?", arguments: [key]) ?? 0)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: key)[.size] as? UInt64) ?? 0
        guard size > start else { return 0 }
        let (turns, end) = ClaudeTranscript.read(url, from: start)
        var inserted = 0
        try store.pool.write { db in
            // O transcript é a fonte original. Se a sessão veio do Xirp e o
            // transcript existe, os registros do Xirp dela saem: os IDs dele
            // não casam com os do Claude e, com fork ou retomada, a mesma
            // resposta seria contada pelas duas fontes (verificado: 883
            // respostas em 30 dias). Sem transcript, os registros ficam.
            if session.xirpId != nil {
                try db.execute(sql: "DELETE FROM usage WHERE sessionId = ? AND sourceKey LIKE 'xirp%'", arguments: [session.id])
            }
            for t in turns {
                var record = UsageRecord(
                    id: nil, sessionId: session.id, agent: session.agent, provider: session.provider, model: t.model,
                    inputTokens: t.usage.input, outputTokens: t.usage.output,
                    cacheRead: t.usage.cacheRead, cacheWrite: t.usage.cacheWrite,
                    costUsd: prices.cost(t.usage, model: t.model), at: t.at,
                    sourceKey: "claude:\(t.messageId)"
                )
                // Registro do Xirp da mesma resposta (de outra sessão, fork ou
                // sessão apagada): mesmo horário (±2 s) e mesma saída.
                try db.execute(sql: """
                    DELETE FROM usage WHERE sourceKey LIKE 'xirp%' AND outputTokens = ? AND at BETWEEN ? AND ?
                    """, arguments: [t.usage.output, t.at.addingTimeInterval(-2), t.at.addingTimeInterval(2)])
                // A mesma resposta pode ter sido lida antes (por outra conversa).
                if try UsageRecord.filter(Column("sourceKey") == record.sourceKey).fetchCount(db) == 0 {
                    try record.insert(db)
                    inserted += 1
                }
            }
            try db.execute(sql: """
                INSERT INTO transcriptOffset (path, offset, updatedAt) VALUES (?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET offset = excluded.offset, updatedAt = excluded.updatedAt
                """, arguments: [key, Int(end), Date()])
        }
        return inserted
    }
}
