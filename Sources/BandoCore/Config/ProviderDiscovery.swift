import Foundation

/// Estado de conexão de um provider na máquina atual.
public enum ProviderConnectionState: String, Sendable, Equatable {
    /// Pronto para uso (chave no Keychain, variável de ambiente, servidor local ativo ou conta nativa).
    case connected
    /// Servidor local (Ollama, LM Studio, etc.) sem resposta no momento.
    case localOffline
    /// Falta chave no Keychain ou variável de ambiente.
    case disconnected

    public var isConnected: Bool { self == .connected }

    public var label: String {
        switch self {
        case .connected: "conectado"
        case .localOffline: "offline"
        case .disconnected: "sem chave"
        }
    }
}

/// Descobre providers conectados e consolida a lista de modelos por provider.
public enum ProviderDiscovery {
    private static let localDefaultEndpoints: [String: String] = [
        "ollama": "http://127.0.0.1:11434/api/tags",
        "lmstudio": "http://127.0.0.1:1234/v1/models",
        "vllm": "http://127.0.0.1:8000/v1/models",
        "llamacpp": "http://127.0.0.1:8080/v1/models",
        "jan": "http://127.0.0.1:1337/v1/models",
        "localai": "http://127.0.0.1:8080/v1/models",
    ]

    /// Referências `keychain:<serviço>/<conta>` declaradas no provider e nas variantes.
    public static func keychainRefs(for provider: ProviderDefinition) -> [(service: String, account: String)] {
        var values = Array(provider.env.values)
        for v in provider.variants.values { values += v.env.values }
        var seen = Set<String>()
        var out: [(String, String)] = []
        for v in values {
            if case .keychain(let svc, let acc) = v, seen.insert("\(svc)/\(acc)").inserted {
                out.append((svc, acc))
            }
        }
        return out
    }

    /// Variáveis `env:<VAR>` exigidas pelo provider.
    public static func envRefs(for provider: ProviderDefinition) -> [String] {
        var values = Array(provider.env.values)
        for v in provider.variants.values { values += v.env.values }
        var seen = Set<String>()
        var out: [String] = []
        for v in values {
            if case .environment(let name) = v, seen.insert(name).inserted {
                out.append(name)
            }
        }
        return out
    }

    public static func isLocalProvider(_ provider: ProviderDefinition) -> Bool {
        if localDefaultEndpoints[provider.id] != nil { return true }
        var values = Array(provider.env.values)
        for v in provider.variants.values { values += v.env.values }
        return values.contains {
            if case .literal(let s) = $0 {
                return s.contains("localhost") || s.contains("127.0.0.1")
            }
            return false
        }
    }

    /// Avalia o estado de conexão de forma síncrona (Keychain + ambiente).
    /// Para servidores locais, assume `.localOffline` até o probe local confirmar.
    public static func connectionState(
        for provider: ProviderDefinition,
        store: SecretStore,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        reachableLocals: Set<String> = []
    ) -> ProviderConnectionState {
        if provider.id == "default" { return .connected }

        let kc = keychainRefs(for: provider)
        if !kc.isEmpty {
            return kc.allSatisfy({ store.exists(service: $0.service, account: $0.account) }) ? .connected : .disconnected
        }

        let envs = envRefs(for: provider)
        if !envs.isEmpty {
            return envs.allSatisfy({ !(environment[$0] ?? "").isEmpty }) ? .connected : .disconnected
        }

        if isLocalProvider(provider) {
            return reachableLocals.contains(provider.id) ? .connected : .localOffline
        }

        return .connected
    }

    /// Consulta servidores locais ativos (Ollama, LM Studio, vLLM, etc.) para
    /// saber quais estão respondendo e quais modelos carregam agora.
    public static func probeLocalServers(for providers: [ProviderDefinition]) async -> (reachable: Set<String>, models: [String: [String]]) {
        let localTargets = providers.compactMap { p -> (String, URL)? in
            guard let raw = localEndpointURL(for: p), let url = URL(string: raw) else { return nil }
            return (p.id, url)
        }
        guard !localTargets.isEmpty else { return ([], [:]) }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 0.7
        cfg.timeoutIntervalForResource = 0.9
        let session = URLSession(configuration: cfg)

        return await withTaskGroup(of: (String, [String]?)?.self) { group in
            for (id, url) in localTargets {
                group.addTask {
                    guard let (data, resp) = try? await session.data(from: url),
                          let http = resp as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode) else { return nil }
                    let models = parseModelList(data)
                    return (id, models)
                }
            }
            var reachable: Set<String> = []
            var models: [String: [String]] = [:]
            for await item in group {
                guard let (id, list) = item else { continue }
                reachable.insert(id)
                if let list, !list.isEmpty { models[id] = list }
            }
            return (reachable, models)
        }
    }

    static func localEndpointURL(for provider: ProviderDefinition) -> String? {
        if let known = localDefaultEndpoints[provider.id] { return known }
        var values = Array(provider.env.values)
        for v in provider.variants.values { values += v.env.values }
        for v in values {
            guard case .literal(let raw) = v,
                  raw.hasPrefix("http://localhost") || raw.hasPrefix("http://127.0.0.1") else { continue }
            var base = raw
            while base.hasSuffix("/") { base.removeLast() }
            if base.hasSuffix("/v1") { return base + "/models" }
            return base + "/v1/models"
        }
        return nil
    }

    /// Extrai IDs de modelo no formato Ollama (`/api/tags`) ou OpenAI (`/v1/models`).
    public static func parseModelList(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        if let list = json["models"] as? [[String: Any]] {
            return list.compactMap { $0["name"] as? String ?? $0["model"] as? String }
        }
        if let list = json["data"] as? [[String: Any]] {
            return list.compactMap { $0["id"] as? String }
        }
        return []
    }

    /// Lista consolidada de modelos disponíveis para `(agente, provider)`.
    /// Mescla descoberta ao vivo + catálogo do provider (ou modelos nativos do agente quando `default`).
    public static func models(
        for agentId: String,
        providerId: String,
        config: BandoConfig,
        discovered: [String: [String]] = [:]
    ) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        func append(_ items: [String]) {
            for item in items where !item.isEmpty && seen.insert(item).inserted {
                result.append(item)
            }
        }

        if providerId == "default" {
            if let agent = config.agents[agentId], !agent.models.isEmpty {
                append(agent.models)
            }
            if let nativeProvider = nativeProviderId(for: agentId),
               let p = config.providers[nativeProvider] {
                append(p.models)
            }
            return result
        }

        if let live = discovered[providerId] { append(live) }
        if let p = config.providers[providerId] { append(p.models) }
        return result
    }

    private static func nativeProviderId(for agentId: String) -> String? {
        switch agentId {
        case "claude": "anthropic"
        case "codex": "openai"
        case "gemini": "google-gemini"
        case "qwen": "dashscope"
        default: nil
        }
    }
}
