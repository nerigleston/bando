@testable import BandoCore
import Foundation
import Testing

@Suite("Título do terminal e nome de branch")
struct TitlesAndBranchTests {
    static let claude = #"^[✳⠀-⣿] (.+)$"#
    static let codex = #"^(?:[⠀-⣿] \| )?(.+) \| [^|]+$"#

    @Test("Claude: tira o ✳ e o spinner; recusa o nome do agente e o título do shell")
    func claudeTitles() {
        let reject = ["Claude Code", "claude", "repo"]
        #expect(SessionTitles.fromTerminal("✳ Novo robô Veniti", pattern: Self.claude, rejecting: reject) == "Novo robô Veniti")
        #expect(SessionTitles.fromTerminal("⠐ Revisão do HIL", pattern: Self.claude, rejecting: reject) == "Revisão do HIL")
        #expect(SessionTitles.fromTerminal("✳ Claude Code", pattern: Self.claude, rejecting: reject) == nil)
        #expect(SessionTitles.fromTerminal("neri@MacBook-Air:/Volumes/SSD_EXT/www/x", pattern: Self.claude, rejecting: reject) == nil)
    }

    @Test("Codex: nome da conversa entre a atividade e a pasta; sem nome, nada")
    func codexTitles() {
        let reject = ["Codex", "codex", "veja-o-veniti-6c19", "ia-assist"]
        #expect(SessionTitles.fromTerminal("Deixar automação Veniti indetectável | veja-o-veniti-pfvr-qu...",
                                           pattern: Self.codex, rejecting: reject) == "Deixar automação Veniti indetectável")
        #expect(SessionTitles.fromTerminal("⠋ | Corrigir login | ia-assist", pattern: Self.codex, rejecting: reject) == "Corrigir login")
        #expect(SessionTitles.fromTerminal("ia-assist", pattern: Self.codex, rejecting: reject) == nil)
        #expect(SessionTitles.fromTerminal("⠋ | ia-assist", pattern: Self.codex, rejecting: reject) == nil)
    }

    @Test("os padrões do catálogo são os testados aqui")
    func catalogPatterns() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bando-cat-\(UUID().uuidString.prefix(8))")
        let paths = BandoPaths(configDir: root.appendingPathComponent("cfg"), stateDir: root.appendingPathComponent("state"))
        let config = try BandoConfig.load(paths: paths)
        #expect(try config.agent("claude").terminalTitle == Self.claude)
        #expect(try config.agent("codex").terminalTitle == Self.codex)
    }

    @Test("branch: tira palavras vazias e limita o tamanho")
    func branchSummary() {
        #expect(Slug.summary("veja o veniti pfvr, quero que seja irreconhecível") == "veniti-seja-irreconhecivel")
        #expect(Slug.summary("quero criar um robo novo, veja o veniti") == "criar-robo-novo-veniti")
        #expect(Slug.summary("Novo robô Veniti") == "novo-robo-veniti")
        #expect(Slug.summary("veja isso") == "veja-isso")   // só palavras vazias: fica o texto
        #expect(Slug.summary("Corrigir o cálculo do frete interestadual com ICMS e DIFAL no checkout").count <= 32)
    }
}
