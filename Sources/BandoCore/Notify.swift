import Foundation

/// Aviso entre processos (CLI ↔ app) por Darwin notification. Não carrega
/// dados: quem recebe relê o banco.
public enum ChangeNotifier {
    public static let name = "io.github.nerigleston.bando.changed"

    public static func post() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Chama `handler` (na main queue) a cada aviso. Guarde o token retornado.
    public static func observe(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        let box = HandlerBox(handler)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center, Unmanaged.passUnretained(box).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<HandlerBox>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { box.handler() }
            },
            name as CFString, nil, .deliverImmediately)
        return box
    }

    final class HandlerBox: @unchecked Sendable {
        let handler: @Sendable () -> Void
        init(_ handler: @escaping @Sendable () -> Void) { self.handler = handler }
        deinit {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), nil, nil)
        }
    }
}

/// Notificação para o usuário. Se o app estiver aberto, ele mesmo notifica
/// (e só quando você não está olhando a sessão); senão o CLI usa osascript.
public enum UserNotifier {
    public static func appIsRunning(paths: BandoPaths) -> Bool {
        let pidFile = paths.stateDir.appendingPathComponent("app.pid")
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return kill(pid, 0) == 0
    }

    public static func notify(title: String, body: String, paths: BandoPaths) {
        guard !appIsRunning(paths: paths) else { return }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(esc(body))\" with title \"\(esc(title))\""
        _ = try? Shell.run("/usr/bin/osascript", ["-e", script])
    }
}
