import Foundation

/// `bando hook <evento> --session <id>`: chamado pelos hooks dos agentes.
///
/// Precisa ser rápido e nunca falhar de um jeito que atrapalhe o agente: erros
/// vão para o log e o processo sai com 0.
public enum HookHandler {
    public static func handle(event: String, sessionId: String, payload: Data?, service: SessionService) {
        let json = payload.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        do {
            guard let session = try service.store.session(sessionId) else { return }
            // Sessão parada pelo usuário não volta a "trabalhando" por um hook atrasado.
            if session.status == .stopped { return }

            if let native = json["session_id"] as? String, !native.isEmpty, native != session.nativeId {
                try service.setNativeId(sessionId, nativeId: native)
            }

            switch event {
            case "start":
                try service.record(sessionId, kind: "hook:start")
            case "working":
                try service.transition(sessionId, to: .working, kind: "hook")
            case "waiting":
                try service.transition(sessionId, to: .waiting, kind: "hook", detail: waitingDetail(json))
            case "notification":
                // Claude: "permission_prompt" pede permissão; "idle_prompt" só
                // lembra que está esperando há tempo (já estamos ociosos).
                let type = json["notification_type"] as? String
                if type == "permission_prompt" || (type == nil && (json["message"] as? String)?.localizedCaseInsensitiveContains("permission") == true) {
                    try service.transition(sessionId, to: .waiting, kind: "hook", detail: json["message"] as? String)
                }
            case "turn-end":
                if let fresh = try service.store.session(sessionId) {
                    _ = try? UsageCollector(store: service.store).collect(fresh)
                }
                // Título que o Claude Code gravou (ai-title/custom-title), sem chamar modelo.
                if try service.refreshTitle(sessionId, allowGenerate: false) != nil { ChangeNotifier.post() }
                let changed = session.usesWorktree ? ((try? Git())?.changedFileCount(session.worktreePath) ?? 0) : 0
                try service.transition(sessionId, to: changed > 0 ? .review : .idle, kind: "hook",
                                       detail: changed > 0 ? "\(changed) arquivo(s) alterado(s)" : nil)
            default:
                try service.record(sessionId, kind: "hook:\(event)")
            }
        } catch {
            log(service.paths, "hook \(event) \(sessionId): \(error.localizedDescription)")
        }
    }

    static func waitingDetail(_ json: [String: Any]) -> String? {
        if let tool = json["tool_name"] as? String {
            if let input = json["tool_input"] as? [String: Any], let cmd = input["command"] as? String {
                return "\(tool): \(cmd.prefix(120))"
            }
            return "permissão: \(tool)"
        }
        return json["message"] as? String
    }

    static func log(_ paths: BandoPaths, _ line: String) {
        let url = paths.stateDir.appendingPathComponent("bando.log")
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
