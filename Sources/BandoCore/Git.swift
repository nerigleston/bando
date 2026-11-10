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
