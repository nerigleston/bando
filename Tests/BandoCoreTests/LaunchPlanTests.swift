@testable import BandoCore
import Foundation
import Testing

@Suite("Montagem do comando")
struct LaunchPlanTests {
    let config = try! BandoConfig.load(userAgents: nil, userProviders: nil)

    @Test("Claude com provider, modelo e prompt")
    func claudeOpenRouter() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("claude"), provider: config.provider("openrouter"),
            model: "z-ai/glm-5", prompt: "faça X", sessionId: "s1"
        ))
        #expect(plan.argv == ["claude", "--model", "z-ai/glm-5", "faça X"])
        #expect(plan.env["ANTHROPIC_BASE_URL"] == .literal("https://openrouter.ai/api"))
        #expect(plan.env["ANTHROPIC_AUTH_TOKEN"] == .keychain(service: "bando", account: "openrouter"))
        #expect(plan.env["BANDO_SESSION_ID"] == .literal("s1"))
        #expect(plan.pendingKeys == nil)
    }

    @Test("grupo com placeholder sem valor some inteiro")
    func dropsEmptyGroups() throws {
        let plan = try LaunchPlan.build(LaunchRequest(agent: config.agent("claude")))
        #expect(plan.argv == ["claude"])
    }

    @Test("retomar e continuar")
    func resumeAndContinue() throws {
        let codex = try config.agent("codex")
        #expect(try LaunchPlan.build(LaunchRequest(agent: codex, mode: .resume(nativeId: "abc"))).argv == ["codex", "resume", "abc"])
        #expect(try LaunchPlan.build(LaunchRequest(agent: codex, mode: .continueLast)).argv == ["codex", "resume", "--last"])
    }

    @Test("agente sem flag de prompt recebe o texto pelo teclado")
    func promptViaKeys() throws {
        let c = try BandoConfig.load(userAgents: "[agents.k]\ncmd = \"k\"", userProviders: nil)
        let plan = try LaunchPlan.build(LaunchRequest(agent: c.agent("k"), prompt: "olá"))
        #expect(plan.argv == ["k"])
        #expect(plan.pendingKeys == "olá")
    }

    @Test("provider não liberado para o agente é recusado")
    func providerMismatch() throws {
        #expect(throws: ConfigError.providerNotForAgent(provider: "openrouter", agent: "agy")) {
            try LaunchPlan.build(LaunchRequest(agent: config.agent("agy"), provider: config.provider("openrouter")))
        }
    }

    @Test("cmd com $VAR e palavras extras")
    func cmdExpansion() throws {
        let c = try BandoConfig.load(userAgents: "[agents.g]\ncmd = \"$MEUBIN session\"", userProviders: nil)
        let plan = try LaunchPlan.build(LaunchRequest(agent: c.agent("g")), environment: ["MEUBIN": "/opt/goose"])
        #expect(plan.argv == ["/opt/goose", "session"])
    }

    @Test("chaves que não são placeholder ficam intactas")
    func keepsBraces() throws {
        #expect(try LaunchPlan.expandGroup(["{\"a\":1}", "{model}"], ["model": "m"]) == ["{\"a\":1}", "m"])
    }

    @Test("segredos resolvidos só no fim, com erro claro se faltar")
    func resolveSecrets() throws {
        let plan = LaunchPlan(argv: ["x"], env: [
            "A": .literal("1"),
            "B": .environment("MINHA"),
            "C": .keychain(service: "bando", account: "t"),
        ], pendingKeys: nil)
        let store = MemoryStore(["bando/t": "segredo"])
        let env = try plan.resolvedEnvironment(store: store, environment: ["MINHA": "v"])
        #expect(env == ["A": "1", "B": "v", "C": "segredo"])
        #expect(throws: SecretError.missing("bando/t")) {
            try plan.resolvedEnvironment(store: MemoryStore([:]), environment: [:])
        }
    }
}

final class MemoryStore: SecretStore, @unchecked Sendable {
    var items: [String: String]
    init(_ items: [String: String]) { self.items = items }
    func read(service: String, account: String) throws -> String? { items["\(service)/\(account)"] }
    func write(_ value: String, service: String, account: String) throws { items["\(service)/\(account)"] = value }
    func delete(service: String, account: String) throws { items["\(service)/\(account)"] = nil }
}

@Suite("Catálogo")
struct CatalogTests {
    let config = try! BandoConfig.load(userAgents: nil, userProviders: nil)

    @Test("fresh só entra em sessão nova")
    func freshArgs() throws {
        let letta = try config.agent("letta")
        #expect(try LaunchPlan.build(LaunchRequest(agent: letta)).argv == ["letta", "--new"])
        #expect(try LaunchPlan.build(LaunchRequest(agent: letta, mode: .resume(nativeId: "c1"))).argv == ["letta", "--conversation", "c1"])
    }

    @Test("forge vem desativado e o usuário pode ligar")
    func forgeDisabled() throws {
        #expect(config.agents["forge"] == nil)
        let on = try BandoConfig.load(userAgents: "[agents.forge]\nenabled = true", userProviders: nil)
        #expect(on.agents["forge"]?.cmd == "forge")
    }

    @Test("todo provider aponta para agentes que existem no catálogo")
    func providersReferenceKnownAgents() {
        let known = Set(config.agents.keys).union(["forge"])
        for p in config.providers.values {
            for a in p.supportedAgents {
                #expect(known.contains(a), "provider \(p.id) cita agente desconhecido \(a)")
            }
        }
    }

    @Test("Copilot usa --resume=<id> num argumento só")
    func copilotResume() throws {
        let plan = try LaunchPlan.build(LaunchRequest(agent: config.agent("copilot"), mode: .resume(nativeId: "x9")))
        #expect(plan.argv == ["copilot", "--resume=x9"])
    }
}

@Suite("MCP")
struct McpTests {
    let toml = """
    [mcp.gh]
    command = "npx"
    args = ["-y", "server-github"]
    env = { GITHUB_TOKEN = "keychain:bando/gh", MODE = "ro" }

    [mcp.docs]
    url = "https://exemplo.dev/mcp"
    headers = { Authorization = "keychain:bando/docs" }
    agents = ["claude"]

    [mcp.off]
    command = "x"
    enabled = false
    """
    var servers: [McpServer] {
        let c = try! BandoConfig.load(userAgents: nil, userProviders: nil, userMcp: toml)
        return c.mcp.values.sorted { $0.id < $1.id }
    }
    let dir = URL(fileURLWithPath: "/tmp/bando-teste")

    @Test("carrega, respeita enabled e filtro de agentes")
    func load() throws {
        #expect(servers.map(\.id) == ["docs", "gh"])
        #expect(servers[0].transport == .http)
        #expect(servers[0].applies(agent: "codex", project: nil) == false)
        #expect(servers[1].applies(agent: "codex", project: nil))
    }

    @Test("Claude: segredo vira ${VAR} e vai só no ambiente")
    func claude() throws {
        let l = McpLaunch.build(servers, adapter: .claude, runDir: dir, sessionId: "s")
        #expect(l.args.first == "--mcp-config")
        let json = l.args[1]
        #expect(json.contains("${BANDO_MCP_GH_GITHUB_TOKEN}"))
        #expect(json.contains("\"MODE\":\"ro\""))
        #expect(json.contains("${BANDO_MCP_DOCS_AUTHORIZATION}"))
        #expect(!json.contains("keychain"))
        #expect(l.env["BANDO_MCP_GH_GITHUB_TOKEN"] == .keychain(service: "bando", account: "gh"))
    }

    @Test("Codex: env_vars e env_http_headers, sem segredo nos argumentos")
    func codex() throws {
        let l = McpLaunch.build(servers, adapter: .codex, runDir: dir, sessionId: "s")
        let joined = l.args.joined(separator: " ")
        #expect(joined.contains(#"mcp_servers.gh={command="npx",args=["-y","server-github"],env={MODE="ro"},env_vars=["GITHUB_TOKEN"]}"#))
        #expect(joined.contains(#"env_http_headers={Authorization="BANDO_MCP_DOCS_AUTHORIZATION"}"#))
        #expect(l.env["GITHUB_TOKEN"] == .keychain(service: "bando", account: "gh"))
    }

    @Test("OpenCode")
    func others() throws {
        let o = McpLaunch.build(servers, adapter: .opencode, runDir: dir, sessionId: "s")
        guard case .literal(let content) = o.env["OPENCODE_CONFIG_CONTENT"] else { Issue.record("sem config"); return }
        #expect(content.contains("{env:BANDO_MCP_GH_GITHUB_TOKEN}"))
        #expect(content.contains(#""type":"remote""#))
    }

    @Test("servidor inválido vira aviso")
    func invalid() throws {
        let c = try BandoConfig.load(userAgents: nil, userProviders: nil, userMcp: "[mcp.x]\nname = \"sem comando\"")
        #expect(c.mcp.isEmpty)
        #expect(c.issues.first?.section == "mcp.x")
    }
}
