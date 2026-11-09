import Foundation

/// Acha executáveis do jeito que o terminal do usuário acharia.
///
/// Um app aberto pelo Finder herda um PATH mínimo. Por isso o PATH vem do shell
/// de login (lido uma vez) mais pastas comuns de instalação de CLIs.
public final class ExecutableLocator: @unchecked Sendable {
    public static let shared = ExecutableLocator()

    private let lock = NSLock()
    private var cachedDirs: [String]?
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    /// Pastas de busca, sem repetição, na ordem de prioridade.
    public var searchDirectories: [String] {
        lock.lock(); defer { lock.unlock() }
        if let cachedDirs { return cachedDirs }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs: [String] = []
        dirs += (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += Self.loginShellPath(shell: environment["SHELL"]).split(separator: ":").map(String.init)
        dirs += [
            "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.bun/bin", "\(home)/.cargo/bin", "\(home)/go/bin",
            "\(home)/.opencode/bin", "\(home)/.npm-global/bin",
            "/usr/bin", "/bin",
        ]
        var seen = Set<String>()
        let result = dirs.filter { !$0.isEmpty && seen.insert($0).inserted }
        cachedDirs = result
        return result
    }

    /// PATH completo para passar aos processos filhos (agentes).
    public var pathValue: String { searchDirectories.joined(separator: ":") }

    /// Caminho absoluto de `name`, ou nil se não achar. Aceita caminho absoluto
    /// e `~/`.
    public func locate(_ name: String) -> String? {
        let fm = FileManager.default
        if name.hasPrefix("/") || name.hasPrefix("~/") {
            let path = (name as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: path) ? path : nil
        }
        for dir in searchDirectories {
            let path = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Primeira linha não vazia de `<exe> <args>`, com limite de tempo.
    public func version(of executable: String, args: [String], timeout: TimeInterval = 5) -> String? {
        guard !args.isEmpty else { return nil }
        guard let out = Self.run(executable, args, timeout: timeout, environment: ["PATH": pathValue, "NO_COLOR": "1"]) else {
            return nil
        }
        return out
            .replacingOccurrences(of: #"\u{1B}\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // Ignora avisos de runtime (ex.: "(node:123) Warning: ...") que
            // algumas CLIs imprimem antes da versão.
            .first { !$0.isEmpty && !$0.hasPrefix("(node:") && !$0.localizedCaseInsensitiveContains("warning") }
    }

    static func loginShellPath(shell: String?) -> String {
        let shell = shell.flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        // -l carrega o perfil de login (onde ficam brew shellenv, nvm etc.).
        return run(shell, ["-l", "-c", "printf '%s' \"$PATH\""], timeout: 3, environment: nil) ?? ""
    }

    /// Roda um processo e devolve stdout (com stderr junto). Nil em erro ou timeout.
    static func run(_ executable: String, _ args: [String], timeout: TimeInterval, environment: [String: String]?) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let environment {
            var env = ProcessInfo.processInfo.environment
            env.merge(environment) { _, new in new }
            process.environment = env
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        // Lê enquanto roda para não travar com saída grande.
        let output = LockedBox(Data())
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            output.value = pipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 1)
            return nil
        }
        _ = readDone.wait(timeout: .now() + 1)
        return String(data: output.value, encoding: .utf8)
    }
}

/// Estado de instalação de um agente.
public struct AgentAvailability: Sendable {
    public var agent: AgentDefinition
    public var path: String?
    public var version: String?
    public var isInstalled: Bool { path != nil }
}

extension AgentDefinition {
    /// Primeira palavra de `cmd`, com `$VAR` expandido. Ex.: "goose session" → "goose".
    public func executableName(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let expanded = LaunchPlan.expandEnvironment(cmd, environment: environment)
        return expanded.split(separator: " ").first.map(String.init) ?? expanded
    }

    public func availability(locator: ExecutableLocator = .shared, probeVersion: Bool = true) -> AgentAvailability {
        let path = locator.locate(executableName())
        let version = (probeVersion && path != nil) ? locator.version(of: path!, args: versionArgs) : nil
        return AgentAvailability(agent: self, path: path, version: version)
    }
}

/// Valor mutável compartilhado entre threads, protegido por lock.
public final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    public init(_ value: T) { _value = value }
    public var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
    public func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&_value); lock.unlock() }
}
