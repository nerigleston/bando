import Foundation

/// Operações de git usadas pelas sessões.
public struct Git: Sendable {
    public let executable: String

    public init() throws {
        guard let git = ExecutableLocator.shared.locate("git") else { throw BandoError.notFound("git") }
        executable = git
    }

    /// Raiz do repositório que contém `path`, ou nil.
    public func repositoryRoot(of path: String) -> String? {
        guard let r = try? Shell.run(executable, ["rev-parse", "--show-toplevel"], cwd: path), r.ok else { return nil }
        return r.trimmed
    }

    /// Repositório principal, mesmo quando `path` é um worktree (o
    /// `--show-toplevel` devolveria a raiz do worktree, e cada worktree viraria
    /// um projeto). Nil fora de um repositório.
    public func mainRepositoryRoot(of path: String) -> String? {
        guard let top = repositoryRoot(of: path) else { return nil }
        guard let r = try? Shell.run(executable, ["rev-parse", "--path-format=absolute", "--git-common-dir"], cwd: path), r.ok
        else { return top }
        let common = URL(fileURLWithPath: r.trimmed).standardizedFileURL
        // Repositório normal ou worktree: o diretório comum é <repo>/.git.
        return common.lastPathComponent == ".git" ? common.deletingLastPathComponent().path : top
    }

    /// Branch atual (nil se HEAD destacado).
    public func currentBranch(_ repo: String) -> String? {
        guard let r = try? Shell.run(executable, ["symbolic-ref", "--quiet", "--short", "HEAD"], cwd: repo), r.ok else { return nil }
        return r.trimmed
    }

    public func branchExists(_ repo: String, _ branch: String) -> Bool {
        (try? Shell.run(executable, ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"], cwd: repo))?.ok ?? false
    }

    /// Cria o worktree. Se o branch já existe, usa ele; senão cria a partir de `base`.
    public func addWorktree(repo: String, path: String, branch: String, base: String?) throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        if branchExists(repo, branch) {
            try Shell.check(executable, ["worktree", "add", path, branch], cwd: repo)
        } else {
            var args = ["worktree", "add", "-b", branch, path]
            if let base { args.append(base) }
            try Shell.check(executable, args, cwd: repo)
        }
    }

    /// Copia para o worktree novo os arquivos de ambiente que o git ignora
    /// (`.env`, `.env.local`, `.env-all`...) e que, por isso, o `git worktree`
    /// não leva. Procura em todo o repositório, menos dentro de pastas
    /// ignoradas (`node_modules` etc.). Não sobrescreve. Devolve os caminhos
    /// relativos copiados.
    @discardableResult
    public func copyEnvFiles(from repo: String, to worktree: String) -> [String] {
        guard let root = repositoryRoot(of: repo),
              let r = try? Shell.run(executable, ["ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory"], cwd: root),
              r.ok else { return [] }
        let fm = FileManager.default
        var copied: [String] = []
        for rel in r.stdout.split(separator: "\0").map(String.init) where Self.isEnvFile(rel) {
            let src = URL(fileURLWithPath: root).appendingPathComponent(rel)
            let dst = URL(fileURLWithPath: worktree).appendingPathComponent(rel)
            guard !fm.fileExists(atPath: dst.path),
                  let size = (try? fm.attributesOfItem(atPath: src.path))?[.size] as? NSNumber,
                  size.int64Value <= 1_000_000 else { continue }
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.copyItem(at: src, to: dst)) != nil { copied.append(rel) }
        }
        return copied
    }

    /// `.env` ou variações (`.env.local`, `.env-all`, `.env_prod`). Pasta não conta.
    static func isEnvFile(_ rel: String) -> Bool {
        guard !rel.hasSuffix("/") else { return false }
        let name = (rel as NSString).lastPathComponent
        return name == ".env" || [".env.", ".env-", ".env_"].contains { name.hasPrefix($0) }
    }

    /// O branch já foi enviado (tem upstream configurado).
    public func hasUpstream(_ repo: String, branch: String) -> Bool {
        (try? Shell.run(executable, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "\(branch)@{upstream}"], cwd: repo))?.ok ?? false
    }

    /// Renomeia o branch (vale também para o que está aberto num worktree).
    public func renameBranch(_ repo: String, from old: String, to new: String) throws {
        try Shell.check(executable, ["branch", "-m", old, new], cwd: repo)
    }

    /// Mudanças não commitadas (inclui arquivos novos).
    public func hasUncommittedChanges(_ worktree: String) -> Bool {
        guard let r = try? Shell.run(executable, ["status", "--porcelain"], cwd: worktree), r.ok else { return false }
        return !r.trimmed.isEmpty
    }

    /// Commits do branch que não estão no upstream (ou, sem upstream, que não
    /// estão em `base`). Zero quando não dá para saber.
    public func unpushedCommits(_ worktree: String, base: String?) -> Int {
        if let r = try? Shell.run(executable, ["rev-list", "--count", "@{upstream}..HEAD"], cwd: worktree), r.ok {
            return Int(r.trimmed) ?? 0
        }
        guard let base, let r = try? Shell.run(executable, ["rev-list", "--count", "\(base)..HEAD"], cwd: worktree), r.ok else {
            return 0
        }
        return Int(r.trimmed) ?? 0
    }

    public func removeWorktree(repo: String, path: String, force: Bool) throws {
        var args = ["worktree", "remove", path]
        if force { args.insert("--force", at: 2) }
        try Shell.check(executable, args, cwd: repo)
    }

    public func deleteBranch(repo: String, branch: String, force: Bool) throws {
        try Shell.check(executable, ["branch", force ? "-D" : "-d", branch], cwd: repo)
    }

    /// Quantidade de arquivos alterados desde `since` (para decidir review vs idle).
    public func changedFileCount(_ worktree: String) -> Int {
        guard let r = try? Shell.run(executable, ["status", "--porcelain"], cwd: worktree), r.ok else { return 0 }
        return r.trimmed.split(separator: "\n").count
    }
}

/// Nome de branch e pasta a partir de um texto livre.
public enum Slug {
    /// Palavras que não dizem nada num nome de branch ("veja", "quero", "o", "pfvr"...).
    static let filler: Set<String> = [
        "a", "o", "as", "os", "um", "uma", "uns", "umas", "de", "da", "do", "das", "dos", "e", "ou", "que",
        "em", "no", "na", "nos", "nas", "com", "para", "pra", "pro", "por", "pelo", "pela", "se", "me", "te",
        "eu", "voce", "vc", "isso", "isto", "esse", "essa", "este", "esta", "aqui", "ai", "agora", "entao",
        "tbm", "tambem", "so", "mais", "muito", "bem", "ja", "ainda", "pfvr", "pfv", "favor", "porfavor",
        "veja", "ve", "ver", "olha", "olhe", "quero", "queria", "preciso", "precisa", "pode", "poderia",
        "consegue", "ajuda", "ajude", "faz", "faca", "fazer", "tipo", "ok", "oi", "ola", "bom", "dia",
        "the", "an", "to", "of", "in", "on", "for", "and", "or", "is", "it", "this", "that", "please", "pls",
        "can", "you", "could", "would", "i", "we", "my", "check", "look", "want", "need",
    ]

    /// Resumo para branch e pasta: até 5 palavras que contam, até 32 caracteres.
    /// "veja o veniti pfvr, quero que seja irreconhecível" → "veniti-seja-irreconhecivel".
    public static func summary(_ text: String, maxWords: Int = 5, maxLength: Int = 32) -> String {
        let words = make(text, maxLength: 400).split(separator: "-").map(String.init)
        var kept: [String] = []
        var length = 0
        for w in words where !filler.contains(w) {
            if kept.count == maxWords || length + w.count + (kept.isEmpty ? 0 : 1) > maxLength { break }
            length += w.count + (kept.isEmpty ? 0 : 1)
            kept.append(w)
        }
        return kept.isEmpty ? make(text, maxLength: maxLength) : kept.joined(separator: "-")
    }

    public static func make(_ text: String, maxLength: Int = 40) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        var out = ""
        var lastDash = true
        for ch in folded.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                out.append(ch)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
            if out.count >= maxLength { break }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "sessao" : out
    }
}
