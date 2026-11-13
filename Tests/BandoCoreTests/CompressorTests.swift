@testable import BandoCore
import Foundation
import Testing

@Suite("Compressor opcional")
struct CompressorTests {
    let config = try! BandoConfig.load(userAgents: nil, userProviders: nil)

    @Test("sem compressor o plano não muda")
    func offByDefault() throws {
        let plan = try LaunchPlan.build(LaunchRequest(agent: config.agent("claude")))
        #expect(plan.proxy == nil)
        #expect(plan.env["ANTHROPIC_BASE_URL"] == nil)
    }

    @Test("Claude Code sem provider aponta para o proxy e o proxy fica no destino padrão")
    func claudeDefault() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("claude"), compressor: config.compressor("headroom")
        ))
        #expect(plan.env["ANTHROPIC_BASE_URL"] == .literal("http://127.0.0.1:{port}"))
        #expect(plan.proxy?.argv == ["headroom", "proxy", "--host", "127.0.0.1", "--port", "{port}"])
        #expect(plan.proxy?.env["HEADROOM_BEACON"] == "off")
    }

    @Test("Claude Code com provider: a URL do provider vira o destino do proxy")
    func claudeProvider() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("claude"), provider: config.provider("openrouter"),
            compressor: config.compressor("headroom")
        ))
        #expect(plan.env["ANTHROPIC_BASE_URL"] == .literal("http://127.0.0.1:{port}"))
        #expect(plan.env["ANTHROPIC_AUTH_TOKEN"] == .keychain(service: "bando", account: "openrouter"))
        #expect(plan.proxy?.argv.suffix(2) == ["--anthropic-api-url", "https://openrouter.ai/api"])
    }

    @Test("Codex sem provider recebe openai_base_url antes do subcomando")
    func codexDefault() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("codex"), mode: .resume(nativeId: "abc"),
            compressor: config.compressor("headroom")
        ))
        #expect(plan.argv == ["codex", "-c", "openai_base_url=\"http://127.0.0.1:{port}/v1\"", "resume", "abc"])
        #expect(plan.proxy?.argv.contains("--openai-api-url") == false)
    }

    @Test("Codex com Venice: base_url troca para o proxy e o destino perde o /v1")
    func codexVenice() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("codex"), provider: config.provider("venice"),
            compressor: config.compressor("headroom")
        ))
        #expect(plan.argv.contains("model_providers.venice.base_url=\"http://127.0.0.1:{port}/v1\""))
        #expect(!plan.argv.contains { $0.contains("api.venice.ai") })
        #expect(!plan.argv.contains { $0.hasPrefix("openai_base_url") })
        #expect(plan.argv.contains("service_tier=\"auto\""))
        #expect(plan.proxy?.argv.suffix(2) == ["--openai-api-url", "https://api.venice.ai/api"])
        #expect(plan.env["VENICE_API_KEY"] == .keychain(service: "bando", account: "venice"))
    }

    @Test("a porta escolhida entra no agente e no proxy")
    func bindsPort() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("codex"), provider: config.provider("venice"),
            compressor: config.compressor("headroom")
        )).binding(port: 51234)
        #expect(plan.argv.contains("model_providers.venice.base_url=\"http://127.0.0.1:51234/v1\""))
        #expect(plan.proxy?.argv.contains("51234") == true)
        #expect(!(plan.argv + (plan.proxy?.argv ?? [])).contains { $0.contains("{port}") })

        let claude = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("claude"), compressor: config.compressor("headroom")
        )).binding(port: 51234)
        #expect(claude.env["ANTHROPIC_BASE_URL"] == .literal("http://127.0.0.1:51234"))
    }

    @Test("agente sem configuração no compressor é recusado")
    func unsupportedAgent() throws {
        #expect(throws: ConfigError.compressorNotForAgent(compressor: "headroom", agent: "gemini")) {
            try LaunchPlan.build(LaunchRequest(agent: config.agent("gemini"), compressor: config.compressor("headroom")))
        }
    }

    @Test("provider que não passa pelo proxy é recusado")
    func blockedProvider() throws {
        var provider = try config.provider("openrouter")
        provider.variants["claude"]?.env["CLAUDE_CODE_USE_BEDROCK"] = .literal("1")
        #expect(throws: ConfigError.compressorBlocked(compressor: "headroom", variable: "CLAUDE_CODE_USE_BEDROCK")) {
            try LaunchPlan.build(LaunchRequest(
                agent: config.agent("claude"), provider: provider, compressor: config.compressor("headroom")
            ))
        }
    }

    @Test("todo compressor aponta para agentes que existem no catálogo")
    func compressorsReferenceKnownAgents() {
        #expect(!config.compressors.isEmpty)
        for c in config.compressors.values {
            for agent in c.supportedAgents { #expect(config.agents[agent] != nil, "\(c.id) cita \(agent)") }
        }
    }
}
