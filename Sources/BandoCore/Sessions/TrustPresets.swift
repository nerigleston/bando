import Foundation

/// Pergunta "confia nesta pasta?" que alguns agentes fazem a cada worktree
/// novo. Quando o repositório principal já é confiável para o agente, o
/// worktree tem o mesmo código: o Bando responde sim por você.
///
/// O Bando só lê a configuração do agente; nunca grava nela.
public enum TrustAdapter: String, Codable, Sendable {
    case claude

    /// Texto da pergunta na tela.
    var prompt: Regex<AnyRegexOutput> {
        switch self {
        case .claude: try! Regex("trust this folder|Do you trust the files")
        }
    }

    /// Teclas que confirmam (a opção "sim" já vem marcada).
    var confirmKey: String { "Enter" }

    /// `path` (ou uma pasta acima dele) é confiável para o agente.
    /// `env` é o ambiente da sessão (o provider pode trocar a pasta de config).
    func isTrusted(_ path: String, env: [String: String]) -> Bool {
        switch self {
        case .claude:
            // O Claude guarda a confiança em ~/.claude.json, ou em
            // $CLAUDE_CONFIG_DIR/.claude.json com outra conta, e vale para as subpastas.
            let file = env["CLAUDE_CONFIG_DIR"].map { ($0 as NSString).expandingTildeInPath + "/.claude.json" }
                ?? NSHomeDirectory() + "/.claude.json"
            guard let data = FileManager.default.contents(atPath: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let projects = json["projects"] as? [String: Any] else { return false }
            return Self.trustedAncestor(of: path) { (projects[$0] as? [String: Any])?["hasTrustDialogAccepted"] as? Bool == true }
        }
    }

    /// Sobe de `path` até a raiz e devolve se alguma pasta passa no teste.
    /// Confere o caminho como veio e o real (sem links: /tmp é /private/tmp),
    /// porque o agente pode ter gravado qualquer um dos dois.
    static func trustedAncestor(of path: String, _ trusted: (String) -> Bool) -> Bool {
        // realpath: o resolvingSymlinksInPath do Foundation tira o /private em vez de pôr.
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let real = realpath(path, &buf).map { String(cString: $0) }
        let starts = Set([URL(fileURLWithPath: path).standardizedFileURL.path] + (real.map { [$0] } ?? []))
        for start in starts {
            var p = start
            while true {
                if trusted(p) || trusted(p.precomposedStringWithCanonicalMapping) { return true }
                let parent = (p as NSString).deletingLastPathComponent
                if parent == p || parent.isEmpty { break }
                p = parent
            }
        }
        return false
    }
}
