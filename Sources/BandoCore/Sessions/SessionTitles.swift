import Foundation

/// Nome das sessões, em três passos:
/// 1. provisório na hora: começo da primeira linha da tarefa;
/// 2. o título que o Claude Code grava no transcript (`custom-title` do /rename
///    ou `ai-title`, que ele mesmo gera);
/// 3. sem isso, um título curto pedido a um modelo pequeno pela CLI do Claude
///    (`claude -p`), sem ferramentas e sem salvar sessão.
/// Nome dado pelo usuário (`customName`) nunca é trocado.
public enum SessionTitles {
    /// Modelo do título. `BANDO_TITLE_MODEL` troca; `BANDO_AI_TITLES=0` desliga o passo 3.
    public static var model: String { ProcessInfo.processInfo.environment["BANDO_TITLE_MODEL"] ?? "claude-haiku-4-5" }
    static var generationEnabled: Bool {
        !["0", "false", "no", "off", "nao", "não"].contains((ProcessInfo.processInfo.environment["BANDO_AI_TITLES"] ?? "").lowercased())
    }
    static let budgetUSD = "0.02"
    static let timeout: TimeInterval = 60

    static let system = """
    Você dá nome a sessões de programação. Recebe a tarefa que a pessoa pediu ao agente e \
    responde só com um título de 3 a 6 palavras que diga o objetivo. Escreva no idioma da tarefa, \
    com maiúscula só na primeira palavra e em nomes próprios. Sem aspas, sem ponto final, sem \
    explicação. Não use nome de branch, número de PR nem hash de commit.
    """

    // MARK: 1. Provisório

    /// Primeira linha, até 6 palavras e 50 caracteres, com a primeira letra maiúscula.
    public static func provisional(_ prompt: String) -> String {
        let firstLine = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var text = firstLine.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
        if text.count > 50 { text = String(text.prefix(47)) + "…" }
        guard let first = text.first else { return prompt.prefix(60).trimmingCharacters(in: .whitespaces) }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: 2. Título do Claude Code

    /// `custom-title` (renomeado no Claude Code) vence `ai-title`; vale o último de cada.
    public static func claudeTitle(nativeId: String) -> String? {
        guard let url = ClaudeTranscript.file(for: nativeId) else { return nil }
        var custom: String?, ai: String?
        let key = Data("-title\"".utf8)
        ClaudeTranscript.forEachLine(url) { line in
            // Filtro barato antes do JSON: só linhas de título interessam.
            guard line.count < 4096, line.range(of: key) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return true }
            switch obj["type"] as? String {
            case "custom-title": custom = (obj["customTitle"] as? String) ?? custom
            case "ai-title": ai = (obj["aiTitle"] as? String) ?? ai
            default: break
            }
            return true
        }
        return (custom ?? ai).flatMap(clean)
    }

    /// Primeira mensagem do usuário na conversa do Claude Code: a tarefa de
    /// quem abriu a sessão vazia e escreveu direto no agente.
    public static func firstUserMessage(nativeId: String) -> String? {
        guard let url = ClaudeTranscript.file(for: nativeId) else { return nil }
        var found: String?
        let userKey = Data("\"type\":\"user\"".utf8)
        ClaudeTranscript.forEachLine(url) { line in
            guard line.range(of: userKey) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  obj["type"] as? String == "user", obj["isSidechain"] as? Bool != true, obj["isMeta"] as? Bool != true,
                  let message = obj["message"] as? [String: Any] else { return true }
            var text: String?
            if let t = message["content"] as? String { text = t }
            else if let blocks = message["content"] as? [[String: Any]] {
                text = blocks.first { $0["type"] as? String == "text" }?["text"] as? String
            }
            // Comandos e avisos do próprio Claude Code vêm entre tags (<command-name> …);
            // resumo de conversa retomada também não é tarefa.
            if let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !t.hasPrefix("<"),
               !t.hasPrefix("This session is being continued"), !t.hasPrefix("Caveat:") {
                found = t
                return false   // achou: para de ler
            }
            return true
        }
        return found
    }

    /// Nome de quem nasceu sem tarefa ("sessão 4f66").
    public static func isPlaceholder(_ name: String) -> Bool {
        name.range(of: #"^sessão [0-9a-f]{4}$"#, options: .regularExpression) != nil
    }

    // MARK: 3. Gerado

    /// Pede o título à CLI do Claude. Nil se a CLI não existir, falhar ou devolver algo inválido.
    public static func generate(task: String) -> String? {
        guard generationEnabled, let claude = ExecutableLocator.shared.locate("claude") else { return nil }
        let clipped = task.count > 4000 ? String(task.prefix(4000)) + "…" : task
        let args = ["-p", "--output-format", "json", "--model", model, "--tools", "",
                    "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config",
                    "--system-prompt", system, "--max-budget-usd", budgetUSD]
        guard let out = run(claude, args, input: "Tarefa:\n\n\(clipped)"),
              let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
              obj["is_error"] as? Bool != true, let text = obj["result"] as? String else { return nil }
        return normalize(text)
    }

    /// Resposta do modelo virando título: uma linha, 2 a 8 palavras, sem desculpas.
    static func normalize(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isNewline), var c = clean(t), !c.hasSuffix("…"), !c.hasSuffix("...") else { return nil }
        while let last = c.last, ".!?".contains(last) { c.removeLast() }
        let words = c.split(whereSeparator: \.isWhitespace)
        guard (2...8).contains(words.count) else { return nil }
        let refusal = #"^(desculp|sinto muito|não (posso|consigo)|nao (posso|consigo)|i('m| am)?\b|sorry|unfortunately|unable|cannot|can't)"#
        guard c.lowercased().range(of: refusal, options: .regularExpression) == nil else { return nil }
        return c
    }

    /// Tira aspas, ponto final e caracteres de controle; corta em 60 caracteres.
    static func clean(_ text: String) -> String? {
        var t = String(text.prefix(300).unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let f = t.first, "\"'“‘`".contains(f) { t.removeFirst() }
        while let l = t.last, "\"'”’`.".contains(l) { t.removeLast() }
        t = t.trimmingCharacters(in: .whitespaces)
        guard t.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        return t.count > 60 ? String(t.prefix(57)) + "…" : t
    }

    /// Processo com limite de tempo (o `claude -p` pode travar sem rede).
    static func run(_ exe: String, _ args: [String], input: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExecutableLocator.shared.pathValue
        env.removeValue(forKey: "BANDO_SESSION_ID")   // não acionar os hooks do Bando
        p.environment = env
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardInput = inp; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        inp.fileHandleForWriting.write(Data(input.utf8)); try? inp.fileHandleForWriting.close()
        let done = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global().async { data = out.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return nil }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

extension SessionService {
    /// Atualiza o nome automático da sessão. `regenerate` pede um título novo ao
    /// modelo mesmo se já houver um (menu "Gerar nome de novo").
    /// Devolve o nome novo, ou nil se nada mudou. Bloqueia (rode fora da main thread).
    /// `allowGenerate: false` só lê o título do transcript (barato; usado a cada
    /// fim de resposta), sem chamar o modelo.
    @discardableResult
    public func refreshTitle(_ id: String, regenerate: Bool = false, allowGenerate: Bool = true) throws -> String? {
        guard let s = try store.session(id), !s.customName else { return nil }
        var title: String?
        // Só existe transcript para agentes que o gravam (hoje, o Claude Code).
        if !regenerate, let native = s.nativeId { title = SessionTitles.claudeTitle(nativeId: native) }
        // Sessão aberta vazia: a tarefa é a primeira mensagem escrita no agente, e o
        // título é gerado uma vez (no fim da primeira resposta), mesmo nos ganchos baratos.
        let placeholder = SessionTitles.isPlaceholder(s.name)
        var task = s.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if task?.isEmpty != false, let native = s.nativeId { task = SessionTitles.firstUserMessage(nativeId: native) }
        if title == nil, allowGenerate || regenerate || placeholder, let task, !task.isEmpty {
            // Só gera se o nome ainda é o provisório (ou se pediram de novo).
            if regenerate || placeholder || s.name == SessionTitles.provisional(task) || s.name == String(task.prefix(60)) {
                title = SessionTitles.generate(task: task)
            }
        }
        guard let title, title != s.name else { return nil }
        // Confere de novo: o usuário pode ter renomeado enquanto o modelo pensava.
        guard let now = try store.session(id), !now.customName else { return nil }
        try update(id) { $0.name = title }
        return title
    }
}
