@testable import BandoCore
import Foundation
import Testing

@Suite("Modelo no formato do agente")
struct ModelPrefixTests {
    let config = try! BandoConfig.load(userAgents: nil, userProviders: nil)

    func json(_ value: SecretValue?) throws -> [String: Any] {
        guard case .literal(let text)? = value else { Issue.record("sem JSON"); return [:] }
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test("OpenCode com Ollama: servidor próprio e modelo com prefixo no JSON de configuração")
    func openCodeOllama() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("opencode"), provider: config.provider("ollama"),
            model: "huihui_ai/qwen3-abliterated:8b-v2", prompt: "oi"
        ))
        #expect(plan.argv == ["opencode", "--standalone", "--prompt", "oi"])
        let obj = try json(plan.env["OPENCODE_CONFIG_CONTENT"])
        #expect(obj["model"] as? String == "ollama/huihui_ai/qwen3-abliterated:8b-v2")
    }

    @Test("modelo que já tem o prefixo não ganha outro")
    func noDoublePrefix() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("opencode"), provider: config.provider("ollama"), model: "ollama/qwen3.5"
        ))
        #expect(try json(plan.env["OPENCODE_CONFIG_CONTENT"])["model"] as? String == "ollama/qwen3.5")
    }

    @Test("o modelo entra no mesmo JSON dos servidores MCP, sem apagar nada")
    func mergesWithMcp() throws {
        var mcp = McpLaunch()
        mcp.env["OPENCODE_CONFIG_CONTENT"] = .literal(#"{"mcp":{"github":{"type":"local"}}}"#)
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("opencode"), provider: config.provider("venice"), model: "kimi-k3-1-pro", mcp: mcp
        ))
        let obj = try json(plan.env["OPENCODE_CONFIG_CONTENT"])
        #expect(obj["model"] as? String == "venice/kimi-k3-1-pro")
        #expect((obj["mcp"] as? [String: Any])?["github"] != nil)
    }

    @Test("OpenCode sem modelo não recebe configuração de modelo")
    func openCodeWithoutModel() throws {
        let plan = try LaunchPlan.build(LaunchRequest(agent: config.agent("opencode")))
        #expect(plan.env["OPENCODE_CONFIG_CONTENT"] == nil)
    }

    @Test("Aider com Ollama: prefixo no argumento --model")
    func aiderOllama() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("aider"), provider: config.provider("ollama"), model: "qwen3.5"
        ))
        #expect(plan.argv.suffix(2) == ["--model", "ollama_chat/qwen3.5"])
    }

    @Test("provider sem prefixo deixa o modelo como está")
    func noPrefixWhenNotConfigured() throws {
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: config.agent("claude"), provider: config.provider("ollama"), model: "qwen3.5"
        ))
        #expect(plan.argv == ["claude", "--model", "qwen3.5"])
    }

    @Test("o usuário pode mudar o prefixo no providers.toml dele")
    func userOverridesPrefix() throws {
        let custom = try BandoConfig.load(userAgents: nil, userProviders: """
        [providers.ollama.for.opencode]
        model_prefix = "meu-ollama/"
        """)
        let plan = try LaunchPlan.build(LaunchRequest(
            agent: custom.agent("opencode"), provider: custom.provider("ollama"), model: "qwen3.5"
        ))
        #expect(try json(plan.env["OPENCODE_CONFIG_CONTENT"])["model"] as? String == "meu-ollama/qwen3.5")
    }
}
