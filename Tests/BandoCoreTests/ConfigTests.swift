@testable import BandoCore
import Testing

@Suite("Configuração")
struct ConfigTests {
    @Test("presets carregam sem avisos")
    func presetsLoad() throws {
        let c = try BandoConfig.load(userAgents: nil, userProviders: nil)
        #expect(c.issues.isEmpty)
        #expect(c.agents["claude"]?.cmd == "claude")
        #expect(c.agents["agy"]?.status == .output)
        #expect(c.providers["openrouter"] != nil)
    }

    @Test("arquivo do usuário muda só os campos que define")
    func fieldLevelMerge() throws {
        let c = try BandoConfig.load(userAgents: """
        [agents.claude]
        args = ["--model", "x"]
        """, userProviders: nil)
        let claude = try c.agent("claude")
        #expect(claude.args == ["--model", "x"])
        #expect(claude.cmd == "claude")           // veio do preset
        #expect(claude.resume == ["--resume", "{native_id}"])
        #expect(c.userAgentIds == ["claude"])
    }

    @Test("comando de atualizar: o do preset, ou o de instalar de novo")
    func updateCommand() throws {
        let c = try BandoConfig.load(userAgents: nil, userProviders: nil)
        #expect(try c.agent("claude").updateCommand == "claude update")
        let codex = try c.agent("codex")
        #expect(codex.update == nil && codex.updateCommand == codex.install)
    }

    @Test("agente novo do usuário")
    func userAgent() throws {
        let c = try BandoConfig.load(userAgents: """
        [agents.minha]
        cmd = "minha-cli"
        status = "output"
        busy = 'trabalhando'
        """, userProviders: nil)
        let a = try c.agent("minha")
        #expect(a.name == "minha")
        #expect(a.promptVia == .keys)             // sem campo prompt
        #expect(a.idleAfter == 4)
    }

    @Test("entrada inválida vira aviso e não derruba as outras")
    func badEntryIsSkipped() throws {
        let c = try BandoConfig.load(userAgents: """
        [agents.sem-cmd]
        name = "Sem comando"

        [agents.regex-ruim]
        cmd = "x"
        busy = '(['

        [agents.boa]
        cmd = "boa"
        """, userProviders: nil)
        #expect(c.agents["boa"] != nil)
        #expect(c.agents["sem-cmd"] == nil)
        #expect(c.agents["regex-ruim"] == nil)
        #expect(Set(c.issues.map(\.section)) == ["agents.sem-cmd", "agents.regex-ruim"])
        #expect(c.issues.allSatisfy { $0.origin == .user })
    }

    @Test("enabled = false esconde preset")
    func disablePreset() throws {
        let c = try BandoConfig.load(userAgents: "[agents.pi]\nenabled = false", userProviders: nil)
        #expect(c.agents["pi"] == nil)
        #expect(c.issues.isEmpty)
    }

    @Test("campos desconhecidos são ignorados (arquivo de versão mais nova)")
    func unknownFieldsIgnored() throws {
        let c = try BandoConfig.load(userAgents: """
        [agents.claude]
        campo_do_futuro = true
        """, userProviders: nil)
        #expect(c.issues.isEmpty)
        #expect(c.agents["claude"] != nil)
    }

    @Test("TOML quebrado gera erro com o nome do arquivo")
    func parseError() {
        #expect(throws: ConfigError.self) {
            try BandoConfig.load(userAgents: "[agents.x\ncmd=", userProviders: nil, agentsFileName: "meu.toml")
        }
    }
}

@Suite("Providers")
struct ProviderTests {
    let toml = """
    [providers.or]
    name = "OR"
    env = { BASE = "x" }

    [providers.or.for.claude]
    env = { ANTHROPIC_AUTH_TOKEN = "keychain:bando/or" }

    [providers.or.for.codex]
    env  = { OR_KEY = "keychain:bando/or" }
    args = ["-c", "model_provider=\\"or\\""]
    """

    @Test("variante por agente soma ao env base")
    func variants() throws {
        let c = try BandoConfig.load(userAgents: nil, userProviders: toml)
        let p = try c.provider("or")
        #expect(p.supportedAgents == ["claude", "codex"])
        #expect(p.supports(agent: "gemini") == false)
        let claude = try #require(p.settings(for: "claude"))
        #expect(claude.env["BASE"] == .literal("x"))
        #expect(claude.env["ANTHROPIC_AUTH_TOKEN"] == .keychain(service: "bando", account: "or"))
        #expect(claude.args.isEmpty)
        #expect(p.settings(for: "codex")?.args == ["-c", "model_provider=\"or\""])
    }

    @Test("referências de segredo")
    func secretRefs() throws {
        #expect(try SecretValue(parsing: "keychain:a/b") == .keychain(service: "a", account: "b"))
        #expect(try SecretValue(parsing: "env:HOME") == .environment("HOME"))
        #expect(try SecretValue(parsing: "texto") == .literal("texto"))
        #expect(throws: ConfigError.self) { try SecretValue(parsing: "keychain:sem-conta") }
        #expect(SecretValue.keychain(service: "a", account: "b").description == "Keychain a/b")
    }

    @Test("nome de variável inválido vira aviso")
    func badEnvName() throws {
        let c = try BandoConfig.load(userAgents: nil, userProviders: "[providers.x]\nenv = { \"1X\" = \"a\" }")
        #expect(c.providers["x"] == nil)
        #expect(c.issues.first?.section == "providers.x")
    }
}

@Suite("Temas")
struct ThemeTests {
    @Test("catálogo carrega 15 temas sem avisos, com claro e escuro padrão")
    func catalog() throws {
        let c = try BandoConfig.load(userAgents: nil, userProviders: nil)
        #expect(c.issues.isEmpty)
        #expect(c.themes.count == 15)
        #expect(c.themes[BandoConfig.defaultDarkTheme]?.appearance == .dark)
        #expect(c.themes[BandoConfig.defaultLightTheme]?.appearance == .light)
        #expect(c.themes.values.allSatisfy { $0.ansi.count == 16 })
    }

    @Test("logo segue a aparência do tema")
    func logo() throws {
        let c = try BandoConfig.load(userAgents: nil, userProviders: nil)
        #expect(c.themes["dracula"]?.logoResource == "bando-completo-branco")
        #expect(c.themes["github-claro"]?.logoResource == "bando-completo-preto")
    }

    @Test("tema do usuário herda de outro com base")
    func base() throws {
        let c = try BandoConfig.load(userAgents: nil, userProviders: nil, userThemes: """
        [themes.meu]
        base = "dracula"
        name = "Meu"
        background = "#000000"
        """)
        let t = try #require(c.themes["meu"])
        #expect(t.background == RGB(hex: "#000000"))
        #expect(t.foreground == c.themes["dracula"]?.foreground)
        #expect(t.appearance == .dark)
        #expect(c.userThemeIds == ["meu"])
    }

    @Test("cor inválida vira aviso")
    func invalid() throws {
        let c = try BandoConfig.load(userAgents: nil, userProviders: nil, userThemes: "[themes.nord]\nbackground = \"azul\"")
        #expect(c.themes["nord"] == nil)
        #expect(c.issues.first?.section == "themes.nord")
    }

    @Test("seguir o sistema escolhe claro ou escuro")
    func system() throws {
        let c = try BandoConfig.load(userAgents: nil, userProviders: nil)
        #expect(c.theme(preference: "system", systemIsDark: true, light: "github-claro", dark: "nord").id == "nord")
        #expect(c.theme(preference: "system", systemIsDark: false, light: "github-claro", dark: "nord").id == "github-claro")
        #expect(c.theme(preference: "dracula", systemIsDark: false, light: "x", dark: "y").id == "dracula")
        #expect(c.theme(preference: "nao-existe", systemIsDark: true, light: "x", dark: "y").id == BandoConfig.defaultDarkTheme)
    }
}
