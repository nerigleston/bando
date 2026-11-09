import Foundation
import Security

/// Lê e grava segredos. A implementação real usa o Keychain; os testes usam
/// uma em memória.
public protocol SecretStore: Sendable {
    func read(service: String, account: String) throws -> String?
    func write(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

public enum SecretError: Error, LocalizedError, Equatable {
    case keychain(OSStatus)
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "código \(status)"
            return "Erro no Keychain: \(msg)"
        case .missing(let what):
            return "Segredo não encontrado: \(what). Cadastre com: bando secret set \(what)"
        }
    }
}

/// Keychain do macOS (itens "senha genérica").
public struct KeychainStore: SecretStore {
    public init() {}

    private func query(_ service: String, _ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read(service: String, account: String) throws -> String? {
        var q = query(service, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw SecretError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(service, account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(service, account)
            q[kSecValueData as String] = data
            q[kSecAttrLabel as String] = "Bando: \(service)/\(account)"
            let add = SecItemAdd(q as CFDictionary, nil)
            guard add == errSecSuccess else { throw SecretError.keychain(add) }
        } else if status != errSecSuccess {
            throw SecretError.keychain(status)
        }
    }

    public func delete(service: String, account: String) throws {
        let status = SecItemDelete(query(service, account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretError.keychain(status) }
    }
}

extension LaunchPlan {
    /// Resolve as referências de segredo. Só deve ser chamado pelo `bando run`,
    /// imediatamente antes do `exec` do agente.
    public func resolvedEnvironment(store: SecretStore, environment: [String: String]) throws -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in env {
            switch value {
            case .literal(let v):
                out[key] = v
            case .environment(let name):
                out[key] = environment[name] ?? ""
            case .keychain(let service, let account):
                guard let secret = try store.read(service: service, account: account) else {
                    throw SecretError.missing("\(service)/\(account)")
                }
                out[key] = secret
            }
        }
        return out
    }
}
