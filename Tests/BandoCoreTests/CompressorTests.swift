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
        #expect(plan.proxy?.argv == ["headroom", "proxy", "--host", "127.0.0.1", "--port", "{port}", "--log-file", "{stats}"])
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

    @Test("o proxy grava o JSONL de economia no arquivo da sessão")
    func statsFile() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("claude"), compressor: config.compressor("headroom")
        )).binding(port: 4000, statsFile: "/tmp/s1.compressor.jsonl")
        #expect(plan.proxy?.argv.suffix(2) == ["--log-file", "/tmp/s1.compressor.jsonl"])
        #expect(!(plan.proxy?.argv ?? []).contains { $0.contains("{stats}") })
    }

    @Test("leitura incremental: só linhas novas, linha incompleta espera, arquivo recriado recomeça")
    func savingsReader() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bando-savings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s.jsonl")
        var reader = CompressorSavingsReader(file: file, beforeKey: "input_tokens_original", afterKey: "input_tokens_optimized")
        #expect(reader.update() == CompressorSavings())

        let l1 = #"{"input_tokens_original": 1000, "input_tokens_optimized": 900, "model": "x"}"#
        let l2 = #"{"input_tokens_original": 2000, "input_tokens_optimized": 1000}"#
        try "\(l1)\n{\"input_tokens_orig".write(to: file, atomically: false, encoding: .utf8)
        #expect(reader.update() == CompressorSavings(requests: 1, before: 1000, after: 900))

        // Completa a linha cortada e acrescenta outra; uma linha sem os campos é ignorada.
        let h = try FileHandle(forWritingTo: file)
        try h.seekToEnd()
        try h.write(contentsOf: Data("inal\": 500, \"input_tokens_optimized\": 500}\n\(l2)\n{\"outro\": 1}\n".utf8))
        try h.close()
        let total = reader.update()
        #expect(total == CompressorSavings(requests: 3, before: 3500, after: 2400))
        #expect(total.saved == 1100)
        #expect(abs(total.fraction - 1100.0 / 3500.0) < 0.0001)

        try "\(l2)\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(reader.update() == CompressorSavings(requests: 1, before: 2000, after: 1000))
    }

    @Test("todo compressor aponta para agentes que existem no catálogo")
    func compressorsReferenceKnownAgents() {
        #expect(!config.compressors.isEmpty)
        for c in config.compressors.values {
            for agent in c.supportedAgents { #expect(config.agents[agent] != nil, "\(c.id) cita \(agent)") }
        }
    }
}
