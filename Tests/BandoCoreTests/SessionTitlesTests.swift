@testable import BandoCore
import Foundation
import Testing

@Suite("Nome das sessões")
struct SessionTitlesTests {
    @Test("provisório: primeira linha, até 6 palavras, maiúscula no começo")
    func provisional() {
        #expect(SessionTitles.provisional("corrigir o login quando a senha expira e o token some") == "Corrigir o login quando a senha")
        #expect(SessionTitles.provisional("ver o README\nsegunda linha") == "Ver o README")
        #expect(SessionTitles.provisional(String(repeating: "palavra", count: 12)).hasSuffix("…"))
    }

    @Test("resposta do modelo: limpa aspas e ponto, recusa o que não é título")
    func normalize() {
        #expect(SessionTitles.normalize("\"Corrigir login expirado.\"") == "Corrigir login expirado")
        #expect(SessionTitles.normalize("  Painel de arquivos  ") == "Painel de arquivos")
        #expect(SessionTitles.normalize("Título") == nil)                       // uma palavra
        #expect(SessionTitles.normalize("linha um\nlinha dois") == nil)         // várias linhas
        #expect(SessionTitles.normalize("Desculpe, não consigo ajudar") == nil) // recusa
        #expect(SessionTitles.normalize("Sorry, I cannot do that") == nil)
        #expect(SessionTitles.normalize("um dois três quatro cinco seis sete oito nove") == nil)
    }

    @Test("gera de verdade com a CLI do Claude (BANDO_TEST_TITLES=1)",
          .enabled(if: ProcessInfo.processInfo.environment["BANDO_TEST_TITLES"] == "1"))
    func realGeneration() throws {
        let title = try #require(SessionTitles.generate(task: "o shift+enter não está quebrando linha no terminal, só option+enter"))
        print("título gerado:", title)
        #expect((2...8).contains(title.split(separator: " ").count))
    }
}

@Suite("Nome dado pelo usuário")
struct CustomNameTests {
    @Test("renomear marca o nome; o título automático não troca depois")
    func renameIsKept() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bando-tests-\(UUID().uuidString.prefix(8))")
        let paths = BandoPaths(configDir: root.appendingPathComponent("cfg"), stateDir: root.appendingPathComponent("state"))
        try FileManager.default.createDirectory(at: paths.configDir, withIntermediateDirectories: true)
        let dir = root.appendingPathComponent("solta")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let service = SessionService(store: try BandoStore(paths: paths), config: try BandoConfig.load(paths: paths))
        let project = try service.ensureProject(at: dir.path)
        let s = try service.create(.init(project: project, prompt: "corrigir o login quando a senha expira", agent: "shell", startNow: false))
        #expect(s.name == "Corrigir o login quando a senha")
        #expect(s.customName == false)
        try service.rename(s.id, to: "Login")
        #expect(try service.store.session(s.id)?.customName == true)
        #expect(try service.refreshTitle(s.id) == nil)
        #expect(try service.store.session(s.id)?.name == "Login")
    }
}

@Suite("Sessão sem tarefa")
struct PlaceholderTitleTests {
    @Test("nome de sessão vazia é reconhecido")
    func placeholder() {
        #expect(SessionTitles.isPlaceholder("sessão 4f66"))
        #expect(!SessionTitles.isPlaceholder("Sessão vazia rápida"))
        #expect(!SessionTitles.isPlaceholder("Corrigir login"))
    }
}

@Suite("Primeira mensagem (conversa real)")
struct FirstMessageTests {
    @Test("lê a primeira mensagem de uma conversa do Claude Code (BANDO_TEST_NATIVE=<id>)",
          .enabled(if: ProcessInfo.processInfo.environment["BANDO_TEST_NATIVE"] != nil))
    func realTranscript() throws {
        let id = ProcessInfo.processInfo.environment["BANDO_TEST_NATIVE"]!
        let first = try #require(SessionTitles.firstUserMessage(nativeId: id))
        print("primeira mensagem:", first.prefix(120))
        #expect(!first.hasPrefix("<"))
    }
}
