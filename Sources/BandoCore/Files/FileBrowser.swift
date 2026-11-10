import Foundation

/// Um item de pasta no painel de arquivos.
public struct FileNode: Identifiable, Hashable, Sendable {
    /// Caminho absoluto.
    public var id: String { path }
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64

    public init(path: String, name: String, isDirectory: Bool, size: Int64) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
    }
}

/// O que o painel mostra ao abrir um arquivo.
public enum FileContent: Equatable, Sendable {
    case text(String)
    case binary(size: Int64)
    case tooLarge(size: Int64)
}

/// Estado do arquivo no git, para marcar na árvore.
public enum FileChange: String, Sendable {
    case modified, added, deleted, untracked, renamed
}

/// Leitura de pastas e arquivos do worktree para o painel de arquivos.
/// Só lê: o painel não escreve, renomeia nem apaga nada.
public enum FileBrowser {
    /// Nomes que nunca aparecem na árvore, mesmo fora do `.gitignore`.
    public static let alwaysHidden: Set<String> = [".git", ".DS_Store"]

    /// Arquivo maior que isto não é aberto no painel.
    public static let maxBytes: Int64 = 2 * 1024 * 1024

    /// Itens da pasta: pastas primeiro, depois arquivos, em ordem alfabética
    /// sem diferenciar maiúsculas. Esconde `alwaysHidden` e o que o git ignora.
    public static func list(_ directory: String, git: Git? = try? Git()) throws -> [FileNode] {
        let url = URL(fileURLWithPath: directory)
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)
        var nodes: [FileNode] = []
        for u in urls where !alwaysHidden.contains(u.lastPathComponent) {
            let v = try? u.resourceValues(forKeys: Set(keys))
            // Link para pasta conta como pasta; o tamanho é o do próprio arquivo.
            var isDir = v?.isDirectory ?? false
            if v?.isSymbolicLink == true {
                var d: ObjCBool = false
                isDir = FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
            }
            nodes.append(FileNode(path: u.path, name: u.lastPathComponent, isDirectory: isDir,
                                  size: Int64(v?.fileSize ?? 0)))
        }
        if let git, !nodes.isEmpty {
            let ignored = ignoredNames(nodes.map(\.name), in: directory, git: git)
            nodes.removeAll { ignored.contains($0.name) }
        }
        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Nomes que o `.gitignore` esconde, com um único `git check-ignore` por pasta.
    /// Fora de um repositório, nenhum.
    static func ignoredNames(_ names: [String], in directory: String, git: Git) -> Set<String> {
        guard let r = try? Shell.run(git.executable, ["check-ignore", "--stdin"], cwd: directory,
                                     input: names.joined(separator: "\n") + "\n") else { return [] }
        // Status 1 = nenhum ignorado; 128 = fora de um repositório.
        guard r.status == 0 else { return [] }
        return Set(r.stdout.split(separator: "\n").map { String($0) })
    }

    /// Conteúdo para mostrar. Binário é detectado por byte zero no começo.
    public static func read(_ path: String, maxBytes: Int64 = maxBytes) throws -> FileContent {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if size > maxBytes { return .tooLarge(size: size) }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        if data.prefix(8000).contains(0) { return .binary(size: size) }
        return .text(String(decoding: data, as: UTF8.self))
    }

    public enum WriteError: Error, LocalizedError, Equatable {
        case changedOnDisk
        public var errorDescription: String? {
            switch self {
            case .changedOnDisk: "O arquivo mudou no disco depois que você abriu."
            }
        }
    }

    /// O arquivo é texto UTF-8 válido (dá para editar e salvar sem estragar bytes).
    public static func isUTF8Text(_ path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return false }
        return !data.prefix(8000).contains(0) && String(data: data, encoding: .utf8) != nil
    }

    /// Salva o texto. Com `expecting`, recusa se o conteúdo no disco não for mais
    /// esse (o agente pode ter editado). Mantém as permissões (um script continua
    /// executável).
    public static func write(_ text: String, to path: String, expecting original: String? = nil) throws {
        let url = URL(fileURLWithPath: path)
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        if let original {
            let current = try Data(contentsOf: url)
            if String(decoding: current, as: UTF8.self) != original { throw WriteError.changedOnDisk }
        }
        try Data(text.utf8).write(to: url, options: .atomic)
        if let perms = attrs[.posixPermissions] {
            try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: path)
        }
    }

    /// Mudanças do worktree pelo git, com caminho absoluto. Uma pasta aparece
    /// como `.modified` quando algum arquivo dentro dela mudou.
    public static func changes(in worktree: String, git: Git? = try? Git()) -> [String: FileChange] {
        guard let git, let root = git.repositoryRoot(of: worktree),
              let r = try? Shell.run(git.executable, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], cwd: root),
              r.ok else { return [:] }
        return parsePorcelain(r.stdout, root: root)
    }

    static func parsePorcelain(_ out: String, root: String) -> [String: FileChange] {
        var result: [String: FileChange] = [:]
        var entries = out.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let entry = entries.popFirst() {
            guard entry.count > 3 else { continue }
            let code = entry.prefix(2)
            let rel = String(entry.dropFirst(3))
            let change: FileChange
            if code == "??" { change = .untracked }
            else if code.contains("R") { change = .renamed; _ = entries.popFirst() }  // o nome antigo vem em seguida
            else if code.contains("A") { change = .added }
            else if code.contains("D") { change = .deleted }
            else { change = .modified }
            let path = root + "/" + rel
            result[path] = change
            var parent = (path as NSString).deletingLastPathComponent
            while parent.count > root.count, result[parent] == nil {
                result[parent] = .modified
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return result
    }
}
