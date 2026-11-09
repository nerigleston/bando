import Foundation
import TOMLKit

/// Preço por milhão de tokens e janela de contexto de um modelo.
public struct ModelPrice: Codable, Sendable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheWrite5m: Double?
    public var cacheWrite1h: Double?
    public var cacheRead: Double?
    public var context: Int?

    enum CodingKeys: String, CodingKey {
        case input, output, context
        case cacheWrite5m = "cache_write_5m"
        case cacheWrite1h = "cache_write_1h"
        case cacheRead = "cache_read"
    }
}

/// Tabela de preços, em ordem de prioridade:
/// 1. `~/.config/bando/prices.toml` (do usuário);
/// 2. catálogo embutido (`catalog/prices.toml`, preços oficiais da Anthropic);
/// 3. fonte remota em JSON (padrão: jangada.dev.br/prices.json), com padrões
///    em regex e vários providers, baixada no máximo uma vez por dia.
public struct PriceTable: @unchecked Sendable {
    public var models: [String: ModelPrice]
    /// Padrões da fonte remota.
    public var remote: [(regex: NSRegularExpression, pattern: String, price: ModelPrice)] = []
    public var remoteUpdatedAt: String?

    struct File: Codable { var models: [String: ModelPrice]? }

    public static let defaultRemoteURL = URL(string: "https://jangada.dev.br/prices.json")!

    public init(models: [String: ModelPrice]) { self.models = models }

    public static func load(paths: BandoPaths = .standard()) -> PriceTable {
        var models = (try? TOMLDecoder().decode(File.self, from: Presets.prices).models) ?? [:]
        let user = paths.configDir.appendingPathComponent("prices.toml")
        if let text = try? String(contentsOf: user, encoding: .utf8),
           let extra = try? TOMLDecoder().decode(File.self, from: text).models {
            models.merge(extra) { _, new in new }
        }
        var table = PriceTable(models: models)
        if let data = try? Data(contentsOf: remoteCache(paths)) { table.applyRemote(data) }
        return table
    }

    static func remoteCache(_ paths: BandoPaths) -> URL { paths.stateDir.appendingPathComponent("prices-remote.json") }

    /// Baixa a fonte remota se a cópia local tiver mais de um dia. Falha em
    /// silêncio (fica com a cópia anterior).
    public static func refreshRemote(paths: BandoPaths = .standard(), url: URL = defaultRemoteURL, force: Bool = false) async {
        let cache = remoteCache(paths)
        if !force, let date = (try? FileManager.default.attributesOfItem(atPath: cache.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < 86_400 { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bando/\(BandoVersion.current)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["token"] != nil else { return }
        try? FileManager.default.createDirectory(at: paths.stateDir, withIntermediateDirectories: true)
        try? data.write(to: cache, options: .atomic)
    }

    mutating func applyRemote(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["token"] as? [[String: Any]] else { return }
        remoteUpdatedAt = obj["updated_at"] as? String
        remote = tokens.compactMap { t in
            guard let pattern = t["pattern"] as? String,
                  let input = (t["input"] as? NSNumber)?.doubleValue,
                  let output = (t["output"] as? NSNumber)?.doubleValue,
                  let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let write = (t["cache_write"] as? NSNumber)?.doubleValue
            return (regex, pattern, ModelPrice(input: input, output: output, cacheWrite5m: write, cacheWrite1h: nil,
                                               cacheRead: (t["cache_read"] as? NSNumber)?.doubleValue, context: nil))
        }
    }

    /// Preço do modelo: prefixo mais longo do catálogo; senão, o padrão remoto
    /// que casa o trecho mais longo do nome.
    public func price(for model: String?) -> ModelPrice? {
        guard let model = model?.lowercased() else { return nil }
        let normalized = model.replacingOccurrences(of: ".", with: "-")
        if let key = models.keys.filter({ normalized.hasPrefix($0) || model.hasPrefix($0) }).max(by: { $0.count < $1.count }) {
            return models[key]
        }
        let range = NSRange(model.startIndex..., in: model)
        var best: (length: Int, patternLength: Int, price: ModelPrice)?
        for r in remote {
            guard let m = r.regex.firstMatch(in: model, range: range) else { continue }
            let candidate = (m.range.length, r.pattern.count, r.price)
            if best == nil || (candidate.0, candidate.1) > (best!.length, best!.patternLength) { best = candidate }
        }
        return best?.price
    }

    /// Janela de contexto do modelo (sufixo "[1m]" força 1 milhão).
    public func contextWindow(for model: String?) -> Int {
        if model?.contains("[1m]") == true { return 1_000_000 }
        return price(for: model)?.context ?? 200_000
    }

    public func cost(_ u: TokenUsage, model: String?) -> Double {
        guard let p = price(for: model) else { return 0 }
        let m = 1_000_000.0
        let write5 = Double(u.cacheWrite5m) * (p.cacheWrite5m ?? p.input * 1.25)
        let write1h = Double(u.cacheWrite1h) * (p.cacheWrite1h ?? p.input * 2)
        return (Double(u.input) * p.input + Double(u.output) * p.output + write5 + write1h
                + Double(u.cacheRead) * (p.cacheRead ?? p.input * 0.1)) / m
    }
}

/// Tokens de uma resposta (ou soma de várias).
public struct TokenUsage: Sendable, Equatable {
    public var input = 0
    public var output = 0
    public var cacheWrite5m = 0
    public var cacheWrite1h = 0
    public var cacheRead = 0

    public init(input: Int = 0, output: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0) {
        self.input = input; self.output = output
        self.cacheWrite5m = cacheWrite5m; self.cacheWrite1h = cacheWrite1h; self.cacheRead = cacheRead
    }

    public var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
    /// Tamanho do contexto que esta resposta enviou ao modelo.
    public var contextTokens: Int { input + cacheWrite + cacheRead }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, output: a.output + b.output,
                   cacheWrite5m: a.cacheWrite5m + b.cacheWrite5m, cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h,
                   cacheRead: a.cacheRead + b.cacheRead)
    }
}
