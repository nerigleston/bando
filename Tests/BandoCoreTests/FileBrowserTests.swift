@testable import BandoCore
import Foundation
import Testing

@Suite("Painel de arquivos")
struct FileBrowserTests {
    func tempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bando-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("pastas primeiro, ordem natural, esconde .git e o que o git ignora")
    func listing() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let fm = FileManager.default
        for d in ["src", ".git", "node_modules"] { try fm.createDirectory(atPath: "\(dir)/\(d)", withIntermediateDirectories: true) }
        for f in ["b10.txt", "b2.txt", "A.md", ".DS_Store"] { fm.createFile(atPath: "\(dir)/\(f)", contents: Data("x".utf8)) }
        let git = try Git()
        try Shell.check(git.executable, ["init", "-q"], cwd: dir)
        fm.createFile(atPath: "\(dir)/.gitignore", contents: Data("node_modules\n".utf8))

        let names = try FileBrowser.list(dir, git: git).map(\.name)
        #expect(names == ["src", ".gitignore", "A.md", "b2.txt", "b10.txt"])
    }

    @Test("fora de um repositório nada é escondido além dos fixos")
    func outsideRepo() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: "\(dir)/node_modules", withIntermediateDirectories: true)
        let names = try FileBrowser.list(dir, git: try Git()).map(\.name)
        #expect(names == ["node_modules"])
    }

    @Test("texto, binário e grande demais")
    func reading() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        FileManager.default.createFile(atPath: "\(dir)/a.txt", contents: Data("olá\n".utf8))
        FileManager.default.createFile(atPath: "\(dir)/b.bin", contents: Data([0x89, 0x50, 0x00, 0x01]))
        #expect(try FileBrowser.read("\(dir)/a.txt") == .text("olá\n"))
        #expect(try FileBrowser.read("\(dir)/b.bin") == .binary(size: 4))
        #expect(try FileBrowser.read("\(dir)/a.txt", maxBytes: 2) == .tooLarge(size: 5))
    }

    @Test("status do git vira marca no arquivo e na pasta")
    func porcelain() {
        let out = " M src/app.swift\0?? novo.txt\0R  dst.txt\0src.txt\0A  lib/x/y.c\0"
        let c = FileBrowser.parsePorcelain(out, root: "/r")
        #expect(c["/r/src/app.swift"] == .modified)
        #expect(c["/r/src"] == .modified)
        #expect(c["/r/novo.txt"] == .untracked)
        #expect(c["/r/dst.txt"] == .renamed)
        #expect(c["/r/src.txt"] == nil)
        #expect(c["/r/lib/x/y.c"] == .added)
        #expect(c["/r/lib/x"] == .modified && c["/r/lib"] == .modified)
        #expect(c["/r"] == nil)
    }
}
