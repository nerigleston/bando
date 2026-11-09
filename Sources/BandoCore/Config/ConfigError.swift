import Foundation

public enum ConfigError: Error, Equatable, LocalizedError {
    case parse(file: String, detail: String)
    case missingField(section: String, field: String)
    case invalidRegex(section: String, field: String, pattern: String)
    case invalidValue(section: String, field: String, detail: String)
    case invalidSecretRef(String)
    case unknownAgent(String)
    case unknownProvider(String)
    case providerNotForAgent(provider: String, agent: String)

    public var errorDescription: String? {
        switch self {
        case .parse(let file, let detail):
            "Erro ao ler \(file): \(detail)"
        case .missingField(let section, let field):
            "[\(section)] precisa do campo \"\(field)\""
        case .invalidRegex(let section, let field, let pattern):
            "[\(section)] \(field) não é uma regex válida: \(pattern)"
        case .invalidValue(let section, let field, let detail):
            "[\(section)] \(field): \(detail)"
        case .invalidSecretRef(let raw):
            "Referência de segredo inválida: \(raw). Use keychain:<serviço>/<conta> ou env:<VAR>"
        case .unknownAgent(let id):
            "Agente desconhecido: \(id)"
        case .unknownProvider(let id):
            "Provider desconhecido: \(id)"
        case .providerNotForAgent(let p, let a):
            "O provider \(p) não está liberado para o agente \(a) (campo agents)"
        }
    }
}
