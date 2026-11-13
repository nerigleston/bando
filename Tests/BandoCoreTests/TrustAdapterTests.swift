@testable import BandoCore
import Foundation
import Testing

@Suite("Confiança de pasta")
struct TrustAdapterTests {
    func configDir(trusting paths: [String]) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bando-trust-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var projects: [String: Any] = [:]
        for p in paths { projects[p] = ["hasTrustDialogAccepted": true] }
        projects["/outro"] = ["hasTrustDialogAccepted": false]
        let data = try JSONSerialization.data(withJSONObject: ["projects": projects])
        try data.write(to: dir.appendingPathComponent(".claude.json"))
        return dir.path
    }

    @Test("Claude: vale a pasta marcada e as de baixo dela")
    func claudeAncestors() throws {
        let cfg = try configDir(trusting: ["/Volumes/SSD/www/app"])
        let env = ["CLAUDE_CONFIG_DIR": cfg]
        #expect(TrustAdapter.claude.isTrusted("/Volumes/SSD/www/app", env: env))
        #expect(TrustAdapter.claude.isTrusted("/Volumes/SSD/www/app/sub/pasta", env: env))
        #expect(!TrustAdapter.claude.isTrusted("/Volumes/SSD/www/outro-app", env: env))
        #expect(!TrustAdapter.claude.isTrusted("/outro", env: env))
    }

    @Test("Claude: reconhece a pergunta de confiança na tela")
    func claudePrompt() {
        #expect("Do you trust the files in this folder?".firstMatch(of: TrustAdapter.claude.prompt) != nil)
        #expect("Quick safety check: Is this a project you created or one you trust this folder?".firstMatch(of: TrustAdapter.claude.prompt) != nil)
        #expect("Corrigir o login".firstMatch(of: TrustAdapter.claude.prompt) == nil)
    }

    @Test("o catálogo liga a confiança só no Claude")
    func catalog() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bando-cat-\(UUID().uuidString.prefix(8))")
        let config = try BandoConfig.load(paths: BandoPaths(configDir: root.appendingPathComponent("cfg"), stateDir: root.appendingPathComponent("st")))
        #expect(try config.agent("claude").trust == .claude)
        #expect(try config.agent("codex").trust == nil)
    }
}
