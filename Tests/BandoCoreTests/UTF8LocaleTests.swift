@testable import BandoCore
import Foundation
import Testing

@Suite("Locale UTF-8 das sessões")
struct UTF8LocaleTests {
    @Test("mantém o LANG que já é UTF-8")
    func keepsUTF8() {
        #expect(UTF8Locale.lang(env: ["LANG": "pt_BR.UTF-8"], preferred: "en_US") == "pt_BR.UTF-8")
        #expect(UTF8Locale.lang(env: ["LANG": "C.UTF-8"], preferred: "en_US") == "C.UTF-8")
    }

    @Test("sem LANG (app aberto pelo Finder) usa o idioma do macOS em UTF-8")
    func fromSystemLanguage() {
        #expect(UTF8Locale.lang(env: [:], preferred: "pt_BR@rg=brzzzz", exists: { _ in true }) == "pt_BR.UTF-8")
    }

    @Test("LANG sem UTF-8 é trocado; idioma sem locale UTF-8 cai no en_US")
    func replacesNonUTF8() {
        #expect(UTF8Locale.lang(env: ["LANG": "C"], preferred: "pt_BR", exists: { _ in true }) == "pt_BR.UTF-8")
        #expect(UTF8Locale.lang(env: [:], preferred: "xx_YY", exists: { _ in false }) == "en_US.UTF-8")
    }

    @Test("sessão sempre recebe LANG UTF-8")
    func sessionEnvironmentHasUTF8() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bando-locale-\(UUID().uuidString.prefix(8))")
        let paths = BandoPaths(configDir: root.appendingPathComponent("cfg"), stateDir: root.appendingPathComponent("state"))
        try FileManager.default.createDirectory(at: paths.configDir, withIntermediateDirectories: true)
        let service = SessionService(store: try BandoStore(paths: paths), config: try BandoConfig.load(paths: paths))
        let s = Session(id: "x", projectId: "p", name: "n", prompt: nil, agent: "shell", provider: nil, model: nil,
                        worktreePath: root.path, branch: nil, baseBranch: nil, usesWorktree: false,
                        tmuxName: "bando_x", status: .starting, dependsOn: nil)
        let env = service.sessionEnvironment(s)
        let lang = try #require(env["LANG"])
        #expect(UTF8Locale.isUTF8(lang))
        // Links OSC 8 ligados para agentes que desligam dentro do tmux (OpenCode).
        #expect(env["FORCE_HYPERLINK"] != nil)
    }
}
