import BandoCore
import Charts
import SwiftUI

// MARK: - Janela de contexto (cabeçalho da sessão)

struct ContextRing: View {
    @Environment(AppModel.self) private var model
    let session: Session
    @State private var open = false

    var body: some View {
        let p = model.palette
        if let c = model.contexts[session.id] {
            Button { open.toggle() } label: {
                ZStack {
                    Circle().stroke(p.border, lineWidth: 2)
                    Circle().trim(from: 0, to: c.fraction)
                        .stroke(color(c.fraction), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 13, height: 13)
                .padding(5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerCursor()
            .help(String(format: "Janela de contexto: %.0f%%", c.fraction * 100))
            .popover(isPresented: $open, arrowEdge: .bottom) { ContextPopover(summary: c).environment(\.palette, p) }
        }
    }

    func color(_ f: Double) -> Color { f < 0.5 ? .green : (f < 0.8 ? .orange : .red) }
}

// MARK: - Compressão (cabeçalho da sessão)

/// Selo da compressão: nome do compressor e quanto deixou de ir ao modelo.
/// Só aparece em sessão criada com compressor.
struct CompressionBadge: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        let p = model.palette
        if let id = session.compressor {
            let name = model.config?.compressors[id]?.name ?? id
            let s = model.compression[session.id]
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 9, weight: .semibold))
                Text(label(name, s)).font(.system(size: 11)).monospacedDigit().lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(p.secondary)
            .padding(.horizontal, 7).frame(height: 20)
            .background(Capsule().strokeBorder(p.border))
            .help(help(name, s))
        }
    }

    func label(_ name: String, _ s: CompressorSavings?) -> String {
        guard let s, s.saved > 0 else { return name }
        return "\(name) −\(compact(s.saved)) (\(String(format: "%.0f", s.fraction * 100))%)"
    }

    func help(_ name: String, _ s: CompressorSavings?) -> String {
        guard let s, s.requests > 0 else {
            return "Compressão ligada: \(name). A economia aparece depois do primeiro pedido ao modelo."
        }
        return "Compressão ligada: \(name). \(s.requests) pedido(s): \(compact(s.before)) → \(compact(s.after)) tokens de entrada (\(String(format: "%.1f", s.fraction * 100))% a menos, soma de todos os pedidos)."
    }
}

struct ContextPopover: View {
    @Environment(\.palette) private var p
    let summary: ContextSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Janela de contexto").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(compact(summary.contextTokens)) / \(compact(summary.contextWindow)) (\(String(format: "%.1f", summary.fraction * 100))%)")
                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(p.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.hover)
                    Capsule().fill(summary.fraction < 0.5 ? Color.green : (summary.fraction < 0.8 ? .orange : .red))
                        .frame(width: g.size.width * summary.fraction)
                }
            }
            .frame(height: 6)
            if summary.fraction >= 0.5 {
                Label("A janela está enchendo. Em conversas longas o agente pode perder o contexto mais antigo.",
                      systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                    .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            row("Modelo", summary.model ?? "?")
            row("Janela", "\(compact(summary.contextWindow)) tokens")
            row("Respostas", "\(summary.turns)")
            row("Entrada", compact(summary.total.input))
            row("Saída", compact(summary.total.output))
            row("Cache (escrita / leitura)", "\(compact(summary.total.cacheWrite)) / \(compact(summary.total.cacheRead))")
            row("Custo estimado", String(format: "US$ %.2f", summary.cost))
        }
        .padding(14)
        .frame(width: 320)
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundStyle(p.secondary)
            Spacer()
            Text(v).font(.system(size: 12, design: .monospaced))
        }
    }
}

func compact(_ n: Int) -> String {
    let d = Double(n)
    if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
    if d >= 1_000 { return String(format: "%.1fk", d / 1_000) }
    return "\(n)"
}

func duration(_ s: Double) -> String {
    if s >= 3600 { return String(format: "%dh %02dmin", Int(s) / 3600, Int(s) % 3600 / 60) }
    return "\(Int(s) / 60) min"
}

// MARK: - Cartões e caixas

struct StatCard: View {
    @Environment(\.palette) private var p
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 12)).foregroundStyle(p.secondary)
                .labelStyle(TintedIconLabel(tint: tint))
            Text(value).font(.system(size: 22, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
            if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(p.tertiary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(p.hover))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.border))
    }
}

struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.foregroundStyle(tint); configuration.title }
    }
}

struct Panel<Content: View>: View {
    @Environment(\.palette) private var p
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(p.hover))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.border))
    }
}

// MARK: - Uso e custo

struct UsageWindow: View {
    @Environment(AppModel.self) private var model
    @State private var range = 30
    @State private var metric = 0  // 0 custo, 1 tokens
    @State private var data: Report?
    @State private var today: Double = 0
    @State private var week: Double = 0
    @State private var month: Double = 0
    @State private var loading = false

    var body: some View {
        let p = model.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Valores estimados com a tabela de preços (\(model.prices.remoteUpdatedAt.map { "fonte remota de \($0)" } ?? "catálogo do Bando")). Os dados ficam no seu banco local.")
                        .font(.system(size: 11.5)).foregroundStyle(p.tertiary)
                    Spacer()
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).pointerCursor().disabled(loading)
                }
                HStack(spacing: 10) {
                    StatCard(symbol: "dollarsign", tint: .green, title: "Hoje", value: money(today))
                    StatCard(symbol: "chart.line.uptrend.xyaxis", tint: .cyan, title: "Últimos 7 dias", value: money(week))
                    StatCard(symbol: "calendar", tint: .orange, title: "Últimos 30 dias", value: money(month))
                }
                Panel(title: metric == 0 ? "CUSTO POR DIA" : "TOKENS POR DIA") {
                    HStack {
                        Text(metric == 0 ? "\(money(data?.cost ?? 0)) em \(range) dias" : "\(compact(totalTokens)) tokens em \(range) dias")
                            .font(.system(size: 13)).foregroundStyle(p.secondary)
                        Spacer()
                        Picker("", selection: $metric) { Text("Custo").tag(0); Text("Tokens").tag(1) }
                            .pickerStyle(.segmented).frame(width: 150).labelsHidden()
                        Picker("", selection: $range) { Text("7d").tag(7); Text("30d").tag(30); Text("90d").tag(90) }
                            .pickerStyle(.segmented).frame(width: 150).labelsHidden()
                    }
                    Chart(metric == 0 ? (data?.costByDay ?? []) : (data?.tokensByDay ?? [])) { v in
                        BarMark(x: .value("Dia", v.day, unit: .day), y: .value(metric == 0 ? "US$" : "Tokens", v.value))
                            .foregroundStyle(by: .value("Modelo", v.series))
                    }
                    .chartLegend(position: .top, alignment: .leading)
                    .frame(height: 240)
                }
                Panel(title: "CUSTO POR AGENTE E MODELO") {
                    let rows = data?.costByModel ?? []
                    let maxCost = rows.map(\.cost).max() ?? 1
                    if rows.isEmpty {
                        Text("Sem uso registrado no período.").font(.system(size: 12.5)).foregroundStyle(p.secondary)
                    }
                    ForEach(Dictionary(grouping: rows, by: { $0.agent ?? "?" }).sorted { $0.key < $1.key }, id: \.key) { agent, items in
                        Text(model.config?.agents[agent]?.name.uppercased() ?? agent.uppercased())
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(p.tertiary).padding(.top, 4)
                        ForEach(items) { m in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.model).font(.system(size: 13, design: .monospaced))
                                    Text("\(compact(m.input)) entrada · \(compact(m.output)) saída · \(compact(m.cacheWrite)) cache-e · \(compact(m.cacheRead)) cache-l")
                                        .font(.system(size: 11)).foregroundStyle(p.tertiary)
                                }
                                Spacer()
                                Capsule().fill(p.border).frame(width: 100, height: 5)
                                    .overlay(alignment: .leading) { Capsule().fill(p.accent).frame(width: 100 * m.cost / maxCost, height: 5) }
                                Text(money(m.cost)).font(.system(size: 13, design: .monospaced)).frame(width: 90, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(minWidth: 760, minHeight: 620)
        .background(model.palette.panel)
        .environment(\.palette, model.palette)
        .preferredColorScheme(model.palette.isDark ? .dark : .light)
        .task(id: range) { await load() }
    }

    var totalTokens: Int { Int((data?.tokensByDay ?? []).reduce(0) { $0 + $1.value }) }

    func money(_ v: Double) -> String { String(format: "US$ %.2f", v) }

    func load() async {
        guard let store = model.service?.store else { return }
        loading = true
        let r = range
        let result = await Task.detached { () -> (Report?, Double, Double, Double) in
            try? UsageCollector(store: store).collectAll()
            let svc = ReportService(store: store)
            let now = Date()
            let cal = Calendar.current
            func span(_ days: Int) -> ReportPeriod {
                ReportPeriod(kind: .custom, start: cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now))!,
                             end: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!)
            }
            let main = try? svc.report(span(r))
            return (main, (try? svc.report(span(1)))?.cost ?? 0, (try? svc.report(span(7)))?.cost ?? 0, (try? svc.report(span(30)))?.cost ?? 0)
        }.value
        data = result.0; today = result.1; week = result.2; month = result.3
        loading = false
    }
}

// MARK: - Relatórios

struct ReportsWindow: View {
    @Environment(AppModel.self) private var model
    @State private var kind: ReportPeriod.Kind = .week
    @State private var period = ReportPeriod.containing(Date(), kind: .week)
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -13, to: Date())!
    @State private var customEnd = Date()
    @State private var report: Report?

    static let weekdays = ["D", "S", "T", "Q", "Q", "S", "S"]
    static let weekdayNames = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]

    var body: some View {
        let p = model.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let r = report {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        StatCard(symbol: "clock", tint: .cyan, title: "Tempo de agente", value: duration(r.agentSeconds),
                                 detail: r.waitingSeconds > 0 ? "\(duration(r.waitingSeconds)) esperando você" : "trabalhando ativamente")
                        StatCard(symbol: "waveform.path.ecg", tint: .green, title: "Sessões", value: "\(r.sessionsCreated)",
                                 detail: "\(r.sessionsActive) com atividade")
                        StatCard(symbol: "dollarsign", tint: .green, title: "Custo estimado", value: String(format: "US$ %.2f", r.cost),
                                 detail: "\(compact(r.tokens.input + r.tokens.output)) tokens de entrada e saída")
                        StatCard(symbol: "bolt", tint: .purple, title: "Horário de pico",
                                 value: r.peakWindow.map { "\($0.startHour)h às \($0.startHour + 3)h" } ?? "-")
                        StatCard(symbol: "folder", tint: .orange, title: "Projeto principal", value: r.topProject?.project ?? "-",
                                 detail: r.topProject.map { duration($0.seconds) })
                        StatCard(symbol: "calendar", tint: .pink, title: "Dia mais ativo",
                                 value: r.busiestWeekday.map { Self.weekdayNames[$0] } ?? "-")
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Panel(title: "Sessões por dia") {
                            Chart(r.sessionsByDay) { BarMark(x: .value("Dia", $0.day, unit: .day), y: .value("Sessões", $0.value)).foregroundStyle(p.accent) }
                                .frame(height: 180)
                        }
                        Panel(title: "Custo por dia") {
                            Chart(r.costByDay) { BarMark(x: .value("Dia", $0.day, unit: .day), y: .value("US$", $0.value)).foregroundStyle(by: .value("Modelo", $0.series)) }
                                .chartLegend(.hidden)
                                .frame(height: 180)
                        }
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Panel(title: "Projetos") {
                            if r.projects.isEmpty { Text("Sem atividade.").font(.system(size: 12.5)).foregroundStyle(p.secondary) }
                            ForEach(r.projects.prefix(10)) { proj in
                                HStack {
                                    Text(proj.project).font(.system(size: 12.5)).lineLimit(1)
                                    Spacer()
                                    Text(duration(proj.seconds)).font(.system(size: 12, design: .monospaced)).foregroundStyle(p.secondary)
                                    Text(String(format: "US$ %.0f", proj.cost)).font(.system(size: 12, design: .monospaced))
                                        .frame(width: 70, alignment: .trailing)
                                }
                            }
                        }
                        Panel(title: "Custo por modelo") {
                            ForEach(r.costByModel.prefix(6)) { m in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(m.model).font(.system(size: 12.5, design: .monospaced)).lineLimit(1)
                                        Spacer()
                                        Text(String(format: "US$ %.2f", m.cost)).font(.system(size: 12, design: .monospaced))
                                    }
                                    Capsule().fill(p.accent.opacity(0.8))
                                        .frame(width: max(4, 220 * m.cost / max(r.costByModel.first?.cost ?? 1, 0.01)), height: 4)
                                    Text("\(m.turns) respostas").font(.system(size: 11)).foregroundStyle(p.tertiary)
                                }
                            }
                        }
                        Panel(title: "PRs mergeados") {
                            if r.mergedPRs.isEmpty { Text("Nenhum PR mergeado.").font(.system(size: 12.5)).foregroundStyle(p.secondary) }
                            ForEach(r.mergedPRs.prefix(8)) { pr in
                                Text(pr.title).font(.system(size: 12.5, design: .monospaced))
                            }
                        }
                    }
                    Panel(title: "Mapa de atividade") { heatmap(r) }
                }
            }
            .padding(18)
        }
        .frame(minWidth: 900, minHeight: 680)
        .background(model.palette.panel)
        .environment(\.palette, model.palette)
        .preferredColorScheme(model.palette.isDark ? .dark : .light)
        .task(id: period) { await load() }
        .onChange(of: kind) { _, k in
            period = k == .custom ? customPeriod : ReportPeriod.containing(Date(), kind: k)
        }
    }

    var customPeriod: ReportPeriod {
        let cal = Calendar.current
        return ReportPeriod(kind: .custom, start: cal.startOfDay(for: customStart),
                            end: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customEnd))!)
    }

    var header: some View {
        let p = model.palette
        return HStack(spacing: 10) {
            Picker("", selection: $kind) {
                Text("Dia").tag(ReportPeriod.Kind.day); Text("Semana").tag(ReportPeriod.Kind.week)
                Text("Mês").tag(ReportPeriod.Kind.month); Text("Intervalo").tag(ReportPeriod.Kind.custom)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 300)
            Spacer()
            if kind == .custom {
                DatePicker("De", selection: $customStart, displayedComponents: .date).labelsHidden()
                Text("até").foregroundStyle(p.secondary)
                DatePicker("Até", selection: $customEnd, displayedComponents: .date).labelsHidden()
                Button("Aplicar") { period = customPeriod }
            } else {
                Button { period = period.shifted(by: -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless).pointerCursor()
                Text(label(period)).font(.system(size: 13, weight: .medium)).frame(minWidth: 180)
                Button { period = period.shifted(by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).pointerCursor().disabled(period.end > Date())
            }
            Menu {
                Button("Copiar como Markdown") { copyMarkdown() }
                Button("Salvar CSV dos projetos…") { saveCSV() }
            } label: { Image(systemName: "square.and.arrow.up") }
            .menuStyle(.borderlessButton).frame(width: 30)
        }
    }

    func label(_ p: ReportPeriod) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        switch p.kind {
        case .day: f.dateFormat = "EEEE, d 'de' MMMM"; return f.string(from: p.start)
        case .month: f.dateFormat = "MMMM 'de' yyyy"; return f.string(from: p.start).capitalized
        default:
            f.dateFormat = "d MMM"
            return "\(f.string(from: p.start)) a \(f.string(from: p.end.addingTimeInterval(-1)))"
        }
    }

    func heatmap(_ r: Report) -> some View {
        let p = model.palette
        let maxValue = max(r.heatmap.flatMap { $0 }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text("").frame(width: 14)
                ForEach(0..<24, id: \.self) { h in
                    Text(h % 3 == 0 ? "\(h)" : "").font(.system(size: 9)).foregroundStyle(p.tertiary).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<7, id: \.self) { d in
                HStack(spacing: 3) {
                    Text(Self.weekdays[d]).font(.system(size: 10)).foregroundStyle(p.tertiary).frame(width: 14)
                    ForEach(0..<24, id: \.self) { h in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(r.heatmap[d][h] > 0 ? Color.green.opacity(0.2 + 0.8 * r.heatmap[d][h] / maxValue) : p.border)
                            .frame(maxWidth: .infinity).frame(height: 14)
                            .help("\(Self.weekdayNames[d]) \(h)h: \(duration(r.heatmap[d][h]))")
                    }
                }
            }
        }
    }

    func load() async {
        guard let store = model.service?.store else { return }
        let p = period
        report = await Task.detached {
            try? UsageCollector(store: store).collectAll()
            return try? ReportService(store: store).report(p)
        }.value
    }

    func markdown() -> String {
        guard let r = report else { return "" }
        var lines = ["# Relatório Bando: \(label(period))", "",
                     "- Tempo de agente: \(duration(r.agentSeconds))",
                     "- Sessões: \(r.sessionsCreated) criadas, \(r.sessionsActive) com atividade",
                     String(format: "- Custo estimado: US$ %.2f", r.cost), "",
                     "| Projeto | Tempo | Esperando | Sessões | Custo |", "|---|---|---|---|---|"]
        for p in r.projects {
            lines.append("| \(p.project) | \(duration(p.seconds)) | \(duration(p.waitingSeconds)) | \(p.sessions) | " + String(format: "US$ %.2f |", p.cost))
        }
        return lines.joined(separator: "\n")
    }

    func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown(), forType: .string)
    }

    func saveCSV() {
        guard let r = report else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "bando-relatorio.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "projeto,segundos_agente,segundos_esperando,sessoes,custo_usd\n"
        for p in r.projects {
            csv += "\"\(p.project.replacingOccurrences(of: "\"", with: "\"\""))\",\(Int(p.seconds)),\(Int(p.waitingSeconds)),\(p.sessions),\(String(format: "%.4f", p.cost))\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
