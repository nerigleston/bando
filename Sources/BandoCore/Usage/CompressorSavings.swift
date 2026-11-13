import Foundation

/// Economia do compressor de uma sessão: soma dos tokens de entrada antes e
/// depois da compressão, pedido a pedido.
public struct CompressorSavings: Sendable, Equatable {
    public var requests = 0
    public var before = 0
    public var after = 0

    public init(requests: Int = 0, before: Int = 0, after: Int = 0) {
        self.requests = requests
        self.before = before
        self.after = after
    }

    public var saved: Int { max(before - after, 0) }
    public var fraction: Double { before > 0 ? Double(saved) / Double(before) : 0 }
}

/// Leitura incremental do JSONL do compressor. Guarda até onde já leu, então
/// cada atualização só lê as linhas novas. Linha incompleta no fim (o proxy
/// ainda escrevendo) fica para a próxima leitura.
public struct CompressorSavingsReader: Sendable {
    public let file: URL
    public let beforeKey: String
    public let afterKey: String
    public private(set) var offset: UInt64 = 0
    public private(set) var totals = CompressorSavings()

    public init(file: URL, beforeKey: String, afterKey: String) {
        self.file = file
        self.beforeKey = beforeKey
        self.afterKey = afterKey
    }

    public init?(compressor: CompressorDefinition, sessionId: String, paths: BandoPaths) {
        guard let before = compressor.statsBefore, let after = compressor.statsAfter else { return nil }
        self.init(file: paths.compressorStatsFile(sessionId: sessionId), beforeKey: before, afterKey: after)
    }

    /// Lê o que entrou desde a última vez e devolve o total.
    @discardableResult
    public mutating func update() -> CompressorSavings {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return totals }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        // Arquivo menor que o já lido: foi recriado. Recomeça do zero.
        if size < offset { offset = 0; totals = CompressorSavings() }
        guard size > offset else { return totals }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), let end = data.lastIndex(of: UInt8(ascii: "\n")) else { return totals }
        for line in data[...end].split(separator: UInt8(ascii: "\n")) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let b = (obj[beforeKey] as? NSNumber)?.intValue,
                  let a = (obj[afterKey] as? NSNumber)?.intValue, b > 0 else { continue }
            totals.requests += 1
            totals.before += b
            totals.after += a
        }
        offset += UInt64(end - data.startIndex + 1)
        return totals
    }
}
