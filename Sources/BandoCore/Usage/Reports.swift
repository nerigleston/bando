import Foundation
import GRDB

/// Período de um relatório.
public struct ReportPeriod: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable { case day, week, month, custom }

    public var kind: Kind
    public var start: Date
    /// Exclusivo.
    public var end: Date

    public init(kind: Kind, start: Date, end: Date) { self.kind = kind; self.start = start; self.end = end }

    public static func containing(_ date: Date, kind: Kind, calendar: Calendar = .current) -> ReportPeriod {
        switch kind {
        case .day:
            let s = calendar.startOfDay(for: date)
            return ReportPeriod(kind: .day, start: s, end: calendar.date(byAdding: .day, value: 1, to: s)!)
        case .week:
            let s = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            return ReportPeriod(kind: .week, start: s, end: calendar.date(byAdding: .day, value: 7, to: s)!)
        case .month, .custom:
            let i = calendar.dateInterval(of: .month, for: date)!
            return ReportPeriod(kind: .month, start: i.start, end: i.end)
        }
    }

    /// Período anterior ou seguinte do mesmo tipo.
    public func shifted(by n: Int, calendar: Calendar = .current) -> ReportPeriod {
        switch kind {
        case .day: return .containing(calendar.date(byAdding: .day, value: n, to: start)!, kind: .day, calendar: calendar)
        case .week: return .containing(calendar.date(byAdding: .day, value: 7 * n, to: start)!, kind: .week, calendar: calendar)
        case .month: return .containing(calendar.date(byAdding: .month, value: n, to: start)!, kind: .month, calendar: calendar)
        case .custom:
            let length = end.timeIntervalSince(start)
            return ReportPeriod(kind: .custom, start: start.addingTimeInterval(length * Double(n)),
                                end: end.addingTimeInterval(length * Double(n)))
        }
    }

    /// Dias do período (início de cada dia).
    public func days(calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        var d = calendar.startOfDay(for: start)
        while d < end { out.append(d); d = calendar.date(byAdding: .day, value: 1, to: d)! }
        return out
    }
}

/// Números de um período, prontos para os gráficos.
public struct Report: Sendable {
    public struct ModelCost: Sendable, Identifiable {
        public var id: String { "\(agent ?? "?")/\(model)" }
        public var agent: String?
        public var model: String
        public var cost: Double
        public var input: Int, output: Int, cacheRead: Int, cacheWrite: Int
        public var turns: Int
    }
    public struct DayValue: Sendable, Identifiable {
        public var id: String { "\(day.timeIntervalSince1970)-\(series)" }
        public var day: Date
        public var series: String
        public var value: Double
    }
    public struct ProjectTime: Sendable, Identifiable {
        public var id: String { project }
        public var project: String
        public var seconds: Double
        public var waitingSeconds: Double
        public var sessions: Int
        public var cost: Double
    }
    public struct PR: Sendable, Identifiable {
        public var id: String
        public var title: String
        public var mergedAt: Date
    }

    public var period: ReportPeriod
    public var agentSeconds: Double = 0
    public var waitingSeconds: Double = 0
    public var sessionsCreated = 0
    public var sessionsActive = 0
    public var cost: Double = 0
    public var tokens = TokenUsage()
    public var costByModel: [ModelCost] = []
    public var costByDay: [DayValue] = []
    public var tokensByDay: [DayValue] = []
    public var sessionsByDay: [DayValue] = []
    public var projects: [ProjectTime] = []
    /// 7 × 24 (domingo = 0), segundos de agente trabalhando.
    public var heatmap: [[Double]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)
    public var mergedPRs: [PR] = []

    public var topProject: ProjectTime? { projects.max { $0.seconds < $1.seconds } }

    /// Janela de 3 horas com mais tempo de agente.
    public var peakWindow: (startHour: Int, seconds: Double)? {
        var byHour = [Double](repeating: 0, count: 24)
        for day in heatmap { for h in 0..<24 { byHour[h] += day[h] } }
        guard byHour.contains(where: { $0 > 0 }) else { return nil }
        var windows = [Double](repeating: 0, count: 22)
        for h in 0..<22 { windows[h] = byHour[h] + byHour[h + 1] + byHour[h + 2] }
        let best = windows.indices.max { windows[$0] < windows[$1] }!
        return (best, windows[best])
    }

    /// Dia da semana com mais tempo de agente (domingo = 0).
    public var busiestWeekday: Int? {
        let totals = heatmap.map { $0.reduce(0, +) }
        guard totals.contains(where: { $0 > 0 }) else { return nil }
        return totals.indices.max { totals[$0] < totals[$1] }
    }
}

/// Calcula relatórios a partir do banco (eventos, uso, PRs).
public struct ReportService {
    let store: BandoStore
    let calendar: Calendar

    public init(store: BandoStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public func report(_ period: ReportPeriod) throws -> Report {
        var r = Report(period: period)
        let days = period.days(calendar: calendar)

        try store.pool.read { db in
            let projects = Dictionary(uniqueKeysWithValues: try Project.fetchAll(db).map { ($0.id, $0.name) })
            let sessions = Dictionary(uniqueKeysWithValues: try Session.fetchAll(db).map { ($0.id, $0) })

            // Sessões criadas no período, por dia.
            let created = sessions.values.filter { $0.createdAt >= period.start && $0.createdAt < period.end }
            r.sessionsCreated = created.count
            r.sessionsByDay = days.map { d in
                let next = calendar.date(byAdding: .day, value: 1, to: d)!
                return Report.DayValue(day: d, series: "Sessões", value: Double(created.filter { $0.createdAt >= d && $0.createdAt < next }.count))
            }

            // Tempo: intervalos entre eventos de estado de cada sessão.
            // Busca um pouco antes do início para saber o estado em que cada sessão entrou no período.
            let events = try SessionEvent
                .filter(Column("status") != nil && Column("at") < period.end && Column("kind") != "import:xirp")
                .order(Column("sessionId"), Column("at"))
                .fetchAll(db)
            var bySession: [String: [SessionEvent]] = [:]
            for e in events { bySession[e.sessionId, default: []].append(e) }
            var projectTime: [String: (Double, Double, Set<String>)] = [:]
            var active = Set<String>()
            let now = Date()
            for (sid, list) in bySession {
                for (i, e) in list.enumerated() {
                    guard let status = e.status, status == .working || status == .waiting else { continue }
                    let next = i + 1 < list.count ? list[i + 1].at : min(now, period.end)
                    let from = max(e.at, period.start), to = min(next, period.end)
                    guard to > from else { continue }
                    // Intervalo aberto e muito longo (ex.: sessão importada sem fim) é limitado a 12 h.
                    let seconds = min(to.timeIntervalSince(from), 12 * 3600)
                    let pname = sessions[sid].flatMap { projects[$0.projectId] } ?? "Sem projeto"
                    var pt = projectTime[pname] ?? (0, 0, [])
                    if status == .working {
                        r.agentSeconds += seconds
                        pt.0 += seconds
                        addToHeatmap(&r.heatmap, from: from, seconds: seconds)
                    } else {
                        r.waitingSeconds += seconds
                        pt.1 += seconds
                    }
                    pt.2.insert(sid)
                    projectTime[pname] = pt
                    active.insert(sid)
                }
            }
            // Sessões importadas do Xirp não têm eventos de estado: o tempo
            // vem do ritmo das respostas (pausas acima de 5 min não contam).
            let imported = Set(sessions.values.filter { $0.xirpId != nil }.map(\.id))
            let turns = try UsageRecord
                .filter(Column("at") >= period.start && Column("at") < period.end && Column("sessionId") != nil)
                .order(Column("sessionId"), Column("at"))
                .fetchAll(db)
            var lastAt: [String: Date] = [:]
            for u in turns {
                guard let sid = u.sessionId, imported.contains(sid), bySession[sid] == nil else { continue }
                let gap = lastAt[sid].map { u.at.timeIntervalSince($0) } ?? 60
                let seconds = gap <= 300 ? gap : 60
                lastAt[sid] = u.at
                r.agentSeconds += seconds
                addToHeatmap(&r.heatmap, from: u.at.addingTimeInterval(-seconds), seconds: seconds)
                let pname = sessions[sid].flatMap { projects[$0.projectId] } ?? "Sem projeto"
                var pt = projectTime[pname] ?? (0, 0, [])
                pt.0 += seconds
                pt.2.insert(sid)
                projectTime[pname] = pt
                active.insert(sid)
            }
            r.sessionsActive = active.count

            // Custo e tokens.
            let usage = try UsageRecord
                .filter(Column("at") >= period.start && Column("at") < period.end)
                .fetchAll(db)
            var byModel: [String: Report.ModelCost] = [:]
            var costDay: [String: Double] = [:]
            var tokenDay: [String: Double] = [:]
            var projectCost: [String: Double] = [:]
            for u in usage {
                r.cost += u.costUsd
                r.tokens = r.tokens + TokenUsage(input: u.inputTokens, output: u.outputTokens, cacheWrite5m: u.cacheWrite, cacheRead: u.cacheRead)
                let model = (u.model ?? "desconhecido").replacingOccurrences(of: "claude-", with: "")
                let key = "\(u.agent ?? "?")/\(model)"
                var m = byModel[key] ?? Report.ModelCost(agent: u.agent, model: model, cost: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, turns: 0)
                m.cost += u.costUsd; m.input += u.inputTokens; m.output += u.outputTokens
                m.cacheRead += u.cacheRead; m.cacheWrite += u.cacheWrite; m.turns += 1
                byModel[key] = m
                let day = calendar.startOfDay(for: u.at)
                costDay["\(day.timeIntervalSince1970)|\(model)", default: 0] += u.costUsd
                tokenDay["\(day.timeIntervalSince1970)|\(model)", default: 0] += Double(u.inputTokens + u.outputTokens + u.cacheWrite)
                if let sid = u.sessionId, let s = sessions[sid] {
                    projectCost[projects[s.projectId] ?? "Sem projeto", default: 0] += u.costUsd
                }
            }
            r.costByModel = byModel.values.sorted { $0.cost > $1.cost }
            func series(_ dict: [String: Double]) -> [Report.DayValue] {
                dict.map { key, value in
                    let parts = key.split(separator: "|", maxSplits: 1)
                    return Report.DayValue(day: Date(timeIntervalSince1970: Double(parts[0]) ?? 0), series: String(parts[1]), value: value)
                }.sorted { ($0.day, $0.series) < ($1.day, $1.series) }
            }
            r.costByDay = series(costDay)
            r.tokensByDay = series(tokenDay)

            let names = Set(projectTime.keys).union(projectCost.keys)
            r.projects = names.map { n in
                let t = projectTime[n] ?? (0, 0, [])
                return Report.ProjectTime(project: n, seconds: t.0, waitingSeconds: t.1, sessions: t.2.count, cost: projectCost[n] ?? 0)
            }.sorted { ($0.seconds, $0.cost) > ($1.seconds, $1.cost) }

            r.mergedPRs = try PullRequestRecord
                .filter(Column("mergedAt") >= period.start && Column("mergedAt") < period.end)
                .order(Column("mergedAt").desc)
                .fetchAll(db)
                .map { pr in
                    let repo = [pr.repoOwner, pr.repoName].compactMap { $0 }.joined(separator: "/")
                    return Report.PR(id: pr.id, title: "\(repo) #\(pr.number ?? 0)", mergedAt: pr.mergedAt ?? period.start)
                }
        }
        return r
    }

    /// Espalha um intervalo pelas células (dia da semana × hora).
    func addToHeatmap(_ map: inout [[Double]], from: Date, seconds: Double) {
        var cursor = from
        var left = seconds
        while left > 0 {
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)!.start
            let hourEnd = hourStart.addingTimeInterval(3600)
            let chunk = min(left, hourEnd.timeIntervalSince(cursor))
            let weekday = calendar.component(.weekday, from: cursor) - 1
            let hour = calendar.component(.hour, from: cursor)
            map[weekday][hour] += chunk
            left -= chunk
            cursor = hourEnd
        }
    }
}
