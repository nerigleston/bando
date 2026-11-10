@testable import BandoCore
import Foundation
import TOMLKit
import Testing

@Suite("Leitura de transcript em blocos")
struct TranscriptStreamTests {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bando-tr-\(UUID().uuidString.prefix(8)).jsonl")
    }

    @Test("linhas que cruzam a divisa de 1 MB chegam inteiras e o offset aponta o fim da última")
    func linesAcrossChunks() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        // Linhas de tamanhos variados somando ~3 MB, a última sem \n (incompleta).
        var expected: [String] = []
        var text = ""
        for i in 0..<300 {
            let line = "\(i):" + String(repeating: "x", count: (i * 7919) % 20_000 + 1)
            expected.append(line)
            text += line + "\n"
        }
        text += "incompleta"
        try text.write(to: url, atomically: true, encoding: .utf8)
        var got: [String] = []
        let end = ClaudeTranscript.forEachLine(url) { got.append(String(decoding: $0, as: UTF8.self)); return true }
        #expect(got == expected)
        #expect(end == UInt64(text.utf8.count - "incompleta".utf8.count))
    }

    @Test("parar no meio devolve o offset logo depois da linha")
    func stopEarly() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try "a\nbb\nccc\n".write(to: url, atomically: true, encoding: .utf8)
        var seen: [String] = []
        let end = ClaudeTranscript.forEachLine(url) { seen.append(String(decoding: $0, as: UTF8.self)); return seen.count < 2 }
        #expect(seen == ["a", "bb"])
        #expect(end == 5)
    }

    func turnLine(_ id: String, input: Int, output: Int) -> String {
        #"{"type":"assistant","timestamp":"2026-11-10T00:00:00.000Z","message":{"id":"\#(id)","model":"claude-opus-4-1","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_read_input_tokens":0}}}"#
    }

    @Test("soma incremental igual à leitura completa, mesmo com uma resposta cortada entre leituras")
    func incrementalEqualsFull() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let prices = PriceTable(models: (try? TOMLDecoder().decode(PriceTable.File.self, from: Presets.prices).models) ?? [:])
        let cache = ContextCache()
        try (turnLine("m1", input: 100, output: 10) + "\n" + turnLine("m2", input: 200, output: 5) + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        _ = cache.summary(nativeId: "x", url: url, prices: prices)
        // m2 continua (mesma resposta, uso final maior) e chega m3.
        let h = try FileHandle(forWritingTo: url); h.seekToEndOfFile()
        h.write(Data((turnLine("m2", input: 200, output: 50) + "\n" + turnLine("m3", input: 300, output: 7) + "\n").utf8)); try h.close()
        let inc = try #require(cache.summary(nativeId: "x", url: url, prices: prices))
        let full = try #require(ContextCache().summary(nativeId: "y", url: url, prices: prices))
        #expect(inc.turns == 3 && full.turns == 3)
        #expect(inc.total == full.total)
        #expect(inc.total.output == 10 + 50 + 7)
        #expect(abs(inc.cost - full.cost) < 1e-9)
        #expect(inc.contextTokens == 300)
    }

    @Test("última resposta lida do fim, inclusive longe do fim do arquivo")
    func lastTurnFromTail() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        var text = turnLine("m1", input: 1, output: 1) + "\n" + turnLine("m2", input: 2, output: 2) + "\n"
        // 600 KB de linhas sem uso depois da última resposta: precisa crescer a janela.
        let filler = #"{"type":"user","message":{"content":"\#(String(repeating: "y", count: 1000))"}}"#
        for _ in 0..<600 { text += filler + "\n" }
        try text.write(to: url, atomically: true, encoding: .utf8)
        let last = try #require(ClaudeTranscript.lastTurn(url))
        #expect(last.messageId == "m2")
        #expect(last.usage.input == 2)
    }
}
