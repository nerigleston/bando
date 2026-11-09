import Foundation

/// Execução de comandos externos (git, tmux) com saída capturada.
public enum Shell {
    public struct Result: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
        public var ok: Bool { status == 0 }
        public var trimmed: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @discardableResult
    public static func run(_ executable: String, _ args: [String], cwd: String? = nil,
                           env: [String: String]? = nil, input: String? = nil) throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ExecutableLocator.shared.pathValue
        if let env { environment.merge(env) { _, n in n } }
        p.environment = environment
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let inPipe = input.map { _ in Pipe() }
        p.standardInput = inPipe ?? FileHandle.nullDevice
        try p.run()
        if let input, let inPipe {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        // Lê as duas saídas em paralelo para não travar com saída grande.
        let errData = LockedBox(Data())
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData.value = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        return Result(status: p.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData.value, as: UTF8.self))
    }

    /// Roda e falha com erro legível se o status não for 0.
    @discardableResult
    public static func check(_ executable: String, _ args: [String], cwd: String? = nil) throws -> String {
        let r = try run(executable, args, cwd: cwd)
        guard r.ok else {
            let cmd = ([URL(fileURLWithPath: executable).lastPathComponent] + args).joined(separator: " ")
            throw BandoError.command(cmd, (r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return r.trimmed
    }
}
