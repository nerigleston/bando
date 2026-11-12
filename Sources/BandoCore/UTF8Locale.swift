import Foundation

/// Locale UTF-8 para os processos das sessões.
///
/// App aberto pelo Finder ou pelo Dock não recebe `LANG`. Sem ele, o agente
/// roda sem locale e o `pbcopy` grava o texto como Mac Roman: "só" vira "s√≥"
/// ao colar fora do Bando. Por isso toda sessão recebe um `LANG` UTF-8.
public enum UTF8Locale {
    /// O `LANG` atual se já for UTF-8; senão o idioma do macOS em UTF-8
    /// (ex.: `pt_BR.UTF-8`), ou `en_US.UTF-8` se esse não existir.
    public static func lang(env: [String: String] = ProcessInfo.processInfo.environment,
                            preferred: String = Locale.current.identifier,
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: "/usr/share/locale/\($0)") }) -> String {
        if let current = env["LANG"], isUTF8(current) { return current }
        // "pt_BR@rg=brzzzz" → "pt_BR"
        let base = preferred.split(separator: "@").first.map(String.init) ?? preferred
        let candidate = base + ".UTF-8"
        return exists(candidate) ? candidate : "en_US.UTF-8"
    }

    public static func isUTF8(_ value: String) -> Bool {
        let v = value.uppercased()
        return v.contains("UTF-8") || v.contains("UTF8")
    }
}
