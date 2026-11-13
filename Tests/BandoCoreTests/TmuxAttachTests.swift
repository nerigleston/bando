@testable import BandoCore
import Testing

@Suite("Anexar ao tmux")
struct TmuxAttachTests {
    static let hasTmux = ExecutableLocator.shared.locate("tmux") != nil

    @Test("no servidor do Bando liga os links OSC 8 antes de anexar", .enabled(if: TmuxAttachTests.hasTmux))
    func bandoServerEnablesHyperlinks() throws {
        let argv = try Tmux().attachCommand("bando_x")
        #expect(Array(argv.dropFirst()) == ["-L", "bando", "set-option", "-s", "terminal-features[90]", "xterm*:hyperlinks",
                                             ";", "attach-session", "-t", "=bando_x"])
    }

    @Test("no servidor padrão do usuário só anexa", .enabled(if: TmuxAttachTests.hasTmux))
    func defaultServerUntouched() throws {
        let argv = try Tmux(server: "default").attachCommand("xirp-1")
        #expect(Array(argv.dropFirst()) == ["attach-session", "-t", "=xirp-1"])
    }
}
