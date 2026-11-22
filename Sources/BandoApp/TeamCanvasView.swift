import AppKit
import BandoCore
import SwiftUI

/// Canvas interativo do Modo Orquestrador Multi-Agente.
///
/// Cada nó representa uma sessão (com agente, provider, modelo e papel próprios)
/// e renderiza o terminal `SwiftTerm` ao vivo quando a sessão está rodando no tmux.
struct TeamCanvasView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    @State private var zoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var newEdgeKind: TeamEdgeKind = .delegate
    @State private var connectingFromId: String?
    @State private var connectingCursor: CGPoint = .zero
    @State private var showNodeInspector = true
    @State private var showCommsFeed = true
    @State private var showAddMember = false
    @State private var showSaveTemplate = false
    @State private var dropTargeted = false
    @State private var canvasViewportSize: CGSize = CGSize(width: 900, height: 600)
    @State private var pulseClock = Date()

    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 2.5
    private let pulseWindowSeconds: TimeInterval = 12.0
    private let expandedSize = CGSize(width: 390, height: 290)
    private let collapsedSize = CGSize(width: 320, height: 124)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(p.border).frame(height: 1)
            if let team = model.activeTeam {
                HStack(spacing: 0) {
                    canvasArea(team: team)
                    if showNodeInspector, let selected = selectedSession(in: team) {
                        Rectangle().fill(p.border).frame(width: 1)
                        TeamNodeInspector(team: team, session: selected)
                            .frame(width: 290)
                    }
                }
                .sheet(isPresented: $showAddMember) {
                    AddTeamMemberSheet(team: team).environment(model).environment(\.palette, p)
                }
                .sheet(isPresented: $showSaveTemplate) {
                    SaveTeamTemplateSheet(team: team).environment(model).environment(\.palette, p)
                }
            } else {
                emptyTeams
            }
        }
        .background(p.panel)
    }

    // MARK: - Barra superior

    var toolbar: some View {
        let team = model.activeTeam
        return HStack(spacing: 8) {
            Menu {
                ForEach(model.teams) { t in
                    Button {
                        model.openCanvas(teamId: t.id)
                    } label: {
                        let proj = model.project(t.projectId)?.name ?? ""
                        Label("\(t.name) (\(proj))", systemImage: t.id == team?.id ? "checkmark" : "point.3.connected.trianglepath.dotted")
                    }
                }
                if !model.teams.isEmpty { Divider() }
                Button { model.showNewTeam = true } label: {
                    Label("Nova equipe…", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 12))
                    Text(team?.name ?? "Equipes").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    if let team, let proj = model.project(team.projectId) {
                        Text("· \(proj.name)").font(.system(size: 12)).foregroundStyle(p.secondary).lineLimit(1)
                    }
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(p.tertiary)
                }
                .foregroundStyle(p.text)
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(p.hover))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.border))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().pointerCursor()

            if let team {
                Button { showAddMember = true } label: {
                    Label("Agente", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(p.border))
                }
                .buttonStyle(.plain).pointerCursor()
                .help("Adicionar especialista ao Canvas")

                Picker("", selection: $newEdgeKind) {
                    ForEach(TeamEdgeKind.allCases, id: \.self) { k in Text(k.label).tag(k) }
                }
                .pickerStyle(.segmented).frame(width: 230)
                .help("Tipo de conexão ao arrastar da porta direita de um nó para outro")

                Spacer(minLength: 6)

                let members = model.teamSessions(team.id)
                let anyLive = members.contains { $0.status.isLive }
                if anyLive {
                    IconButton(symbol: "stop.circle", help: "Parar todos os agentes da equipe", size: 14) {
                        model.stopTeam(team.id)
                    }
                } else {
                    Button { model.startTeam(team.id) } label: {
                        Label("Iniciar equipe", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(AccentButtonStyle())
                }

                IconButton(symbol: "wand.and.stars", help: "Auto-organizar nós no Canvas", size: 14) {
                    model.autoLayoutTeam(team.id)
                    pan = .zero
                }
                HStack(spacing: 2) {
                    IconButton(symbol: "minus.magnifyingglass", help: "Diminuir zoom", size: 13) {
                        applyZoom(to: zoom - 0.15, anchor: CGPoint(x: canvasViewportSize.width / 2, y: canvasViewportSize.height / 2))
                    }
                    Text("\(Int(zoom * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(p.secondary)
                        .frame(width: 38)
                    IconButton(symbol: "plus.magnifyingglass", help: "Aumentar zoom", size: 13) {
                        applyZoom(to: zoom + 0.15, anchor: CGPoint(x: canvasViewportSize.width / 2, y: canvasViewportSize.height / 2))
                    }
                    IconButton(symbol: "viewfinder", help: "Centralizar equipe na tela", size: 13) {
                        fitTeamInView(team)
                    }
                    IconButton(symbol: "1.magnifyingglass", help: "Zoom 100%", size: 13) {
                        applyZoom(to: 1.0, anchor: CGPoint(x: canvasViewportSize.width / 2, y: canvasViewportSize.height / 2))
                    }
                }
                IconButton(symbol: "square.and.arrow.down", help: "Salvar topologia como template TOML", size: 14) {
                    showSaveTemplate = true
                }
                IconButton(symbol: "sidebar.right", help: "Inspector do nó selecionado", size: 14) {
                    showNodeInspector.toggle()
                }
                IconButton(symbol: "trash", help: "Apagar equipe e worktrees", size: 14) {
                    model.deleteTeam(team.id)
                }
            } else {
                Spacer()
                Button("Nova equipe") { model.showNewTeam = true }.buttonStyle(AccentButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(p.card)
    }

    // MARK: - Área do Canvas

    func canvasArea(team: TeamRecord) -> some View {
        let members = model.teamSessions(team.id)
        let edges = model.edges(for: team.id)

        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Fundo pontilhado + arraste para mover a câmera (pan).
                DottedCanvasBackground(spacing: 24 * zoom, color: p.border.opacity(1.6), offset: pan)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.canvasSelectedSessionId = nil
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                    .gesture(DragGesture(minimumDistance: 4)
                        .onChanged { g in
                            if panStart == nil { panStart = pan }
                            pan = CGSize(width: (panStart?.width ?? 0) + g.translation.width,
                                         height: (panStart?.height ?? 0) + g.translation.height)
                        }
                        .onEnded { _ in panStart = nil })

                // Arestas (fios estáticos sempre leves; camada animada montada só quando ativa).
                let animateEdges = shouldAnimateEdges(edges: edges, members: members, now: pulseClock)
                Canvas { ctx, _ in
                    for edge in edges {
                        guard let from = members.first(where: { $0.id == edge.fromSessionId }),
                              let to = members.first(where: { $0.id == edge.toSessionId }) else { continue }
                        let start = outputPortScreenPoint(for: from)
                        let end = inputPortScreenPoint(for: to)
                        let anim = edgeAnimationState(edge: edge, from: from, to: to, now: pulseClock)
                        let active = from.status == .working || to.status == .working || (anim?.pulsing ?? false)
                        let color = edgeColor(edge, active: active, waiting: from.status == .waiting || to.status == .waiting)
                        let reverseArrow = edge.lastDirection == .reverse || edge.lastDirection == .bidirectional
                        drawWire(
                            in: &ctx,
                            from: start,
                            to: end,
                            color: color,
                            dashed: edge.kind == .delegate,
                            active: active,
                            reverseArrow: reverseArrow
                        )
                    }
                    if let fromId = connectingFromId,
                       let from = members.first(where: { $0.id == fromId }) {
                        let start = outputPortScreenPoint(for: from)
                        drawWire(in: &ctx, from: start, to: connectingCursor, color: p.accent, dashed: true, active: true, reverseArrow: false)
                    }
                }
                .allowsHitTesting(false)

                if animateEdges {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        Canvas { ctx, _ in
                            let now = timeline.date
                            for edge in edges {
                                guard let from = members.first(where: { $0.id == edge.fromSessionId }),
                                      let to = members.first(where: { $0.id == edge.toSessionId }) else { continue }
                                guard let anim = edgeAnimationState(edge: edge, from: from, to: to, now: now) else { continue }
                                drawBeads(
                                    in: &ctx,
                                    from: outputPortScreenPoint(for: from),
                                    to: inputPortScreenPoint(for: to),
                                    forward: anim.forward,
                                    reverse: anim.reverse,
                                    speed: anim.speed,
                                    now: now
                                )
                            }
                        }
                    }
                    .id("beads-\(model.canvasFocusEpoch)")
                    .allowsHitTesting(false)
                }

                Color.clear
                    .frame(width: 0, height: 0)
                    .task(id: pulseExpirationKey(edges: edges)) {
                        pulseClock = Date()
                        if let deadline = latestPulseDeadline(edges: edges, now: pulseClock) {
                            let delay = max(0.05, deadline.timeIntervalSinceNow)
                            try? await Task.sleep(for: .seconds(delay))
                            pulseClock = Date()
                        }
                    }
                    .onChange(of: model.canvasFocusEpoch) { _, _ in pulseClock = Date() }
                    .onChange(of: edges) { _, _ in pulseClock = Date() }
                    .onChange(of: members.map(\.status)) { _, _ in pulseClock = Date() }

                // Rótulos clicáveis no ponto médio das arestas.
                ForEach(edges) { edge in
                    if let from = members.first(where: { $0.id == edge.fromSessionId }),
                       let to = members.first(where: { $0.id == edge.toSessionId }) {
                        let mid = midPoint(outputPortScreenPoint(for: from), inputPortScreenPoint(for: to))
                        let isPulsing = isEdgePulsing(edge, now: pulseClock)
                        EdgeBadge(edge: edge, isPulsing: isPulsing) { model.disconnectTeamEdge(edge.id) }
                            .position(mid)
                    }
                }

                // Cartões dos nós (com TerminalPane ao vivo dentro de cada nó ativo).
                ForEach(members) { session in
                    let size = nodeScreenSize(for: session)
                    let origin = nodeScreenOrigin(for: session)
                    TeamNodeCard(
                        session: session,
                        team: team,
                        size: size,
                        baseOrigin: CGPoint(x: basePosition(for: session).x, y: basePosition(for: session).y),
                        baseSize: nodeBaseSize(for: session),
                        zoom: zoom,
                        collapsed: model.canvasCollapsedTerminals.contains(session.id),
                        isSelected: model.canvasSelectedSessionId == session.id,
                        onSelect: { model.canvasSelectedSessionId = session.id },
                        onToggleCollapse: {
                            if model.canvasCollapsedTerminals.contains(session.id) {
                                model.canvasCollapsedTerminals.remove(session.id)
                            } else {
                                model.canvasCollapsedTerminals.insert(session.id)
                            }
                        },
                        onDragChanged: { nx, ny in
                            model.previewCanvasFrame(session.id, x: nx, y: ny, width: session.canvasWidth, height: session.canvasHeight)
                        },
                        onDragEnded: { nx, ny in
                            model.moveCanvasNode(session.id, x: nx, y: ny)
                        },
                        onResizeChanged: { x, y, w, h in
                            model.previewCanvasFrame(session.id, x: x, y: y, width: w, height: h)
                        },
                        onResizeEnded: { x, y, w, h in
                            model.commitCanvasFrame(session.id, x: x, y: y, width: w, height: h)
                        },
                        onResetSize: {
                            let base = basePosition(for: session)
                            model.commitCanvasFrame(session.id, x: base.x, y: base.y, width: nil, height: nil)
                        },
                        onConnectDragChanged: { cursorInCanvas in
                            connectingFromId = session.id
                            connectingCursor = cursorInCanvas
                        },
                        onConnectDragEnded: { dropPoint in
                            defer { connectingFromId = nil }
                            if let target = members.first(where: { $0.id != session.id && nodeScreenRect(for: $0).contains(dropPoint) }) {
                                model.connectTeamNodes(teamId: team.id, from: session.id, to: target.id, kind: newEdgeKind)
                            }
                        }
                    )
                    .id("canvas-node-\(session.id)")
                    .offset(x: origin.x, y: origin.y)
                }

                // Meta do objetivo no canto superior esquerdo (discreto).
                if let goal = team.goal, !goal.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "target").font(.system(size: 11)).foregroundStyle(p.accent)
                        Text(goal).font(.system(size: 11.5)).foregroundStyle(p.secondary).lineLimit(2)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(p.card.opacity(0.92)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.border))
                    .frame(maxWidth: min(geo.size.width * 0.55, 520), alignment: .leading)
                    .padding(12)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(CanvasTrackpadOverlay(
                onPan: { delta in
                    pan.width += delta.width
                    pan.height += delta.height
                },
                onMagnify: { deltaFactor, cursor in
                    applyZoom(to: zoom * (1 + deltaFactor), anchor: cursor)
                }
            ))
            .coordinateSpace(name: "teamCanvas")
            .clipped()
            .onAppear { canvasViewportSize = geo.size }
            .onChange(of: geo.size) { _, newSize in canvasViewportSize = newSize }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(p.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .padding(8).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                TeamCommunicationFeed(
                    events: model.teamActivity(for: team.id),
                    expanded: $showCommsFeed,
                    onSelectSession: { sid in model.canvasSelectedSessionId = sid }
                )
                .padding(12)
            }
            .dropDestination(for: String.self) { payloads, location in
                var attached = false
                for item in payloads where !item.hasPrefix("project:") {
                    if model.session(item) != nil {
                        let canvasPt = CGPoint(x: (location.x - pan.width) / zoom, y: (location.y - pan.height) / zoom)
                        model.attachSession(item, to: team.id, at: canvasPt)
                        attached = true
                    }
                }
                return attached
            } isTargeted: { dropTargeted = $0 }
        }
    }

    func applyZoom(to target: CGFloat, anchor: CGPoint) {
        let clamped = min(max(target, minZoom), maxZoom)
        guard clamped != zoom else { return }
        let ratio = clamped / zoom
        pan = CGSize(
            width: anchor.x - (anchor.x - pan.width) * ratio,
            height: anchor.y - (anchor.y - pan.height) * ratio
        )
        zoom = clamped
    }

    func fitTeamInView(_ team: TeamRecord) {
        let members = model.teamSessions(team.id)
        guard !members.isEmpty else { zoom = 1.0; pan = .zero; return }
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for s in members {
            let pos = basePosition(for: s)
            let sz = nodeBaseSize(for: s)
            minX = min(minX, pos.x)
            minY = min(minY, pos.y)
            maxX = max(maxX, pos.x + Double(sz.width))
            maxY = max(maxY, pos.y + Double(sz.height))
        }
        let contentW = max(maxX - minX, 100)
        let contentH = max(maxY - minY, 100)
        let pad: CGFloat = 60
        let availW = max(canvasViewportSize.width - pad * 2, 200)
        let availH = max(canvasViewportSize.height - pad * 2, 200)
        let targetZoom = min(max(min(availW / contentW, availH / contentH), minZoom), 1.0)
        zoom = targetZoom
        pan = CGSize(
            width: (canvasViewportSize.width - contentW * targetZoom) / 2 - minX * targetZoom,
            height: (canvasViewportSize.height - contentH * targetZoom) / 2 - minY * targetZoom
        )
    }

    func selectedSession(in team: TeamRecord) -> Session? {
        let members = model.teamSessions(team.id)
        if let id = model.canvasSelectedSessionId, let s = members.first(where: { $0.id == id }) { return s }
        return members.first(where: \.isOrchestrator) ?? members.first
    }

    func basePosition(for s: Session) -> (x: Double, y: Double) {
        (s.canvasX ?? 100, s.canvasY ?? 100)
    }

    func nodeBaseSize(for s: Session) -> CGSize {
        let collapsed = model.canvasCollapsedTerminals.contains(s.id) || !model.canAttach(s)
        if collapsed { return collapsedSize }
        return CGSize(
            width: max(s.canvasWidth ?? expandedSize.width, 260),
            height: max(s.canvasHeight ?? expandedSize.height, 180)
        )
    }

    func nodeScreenSize(for s: Session) -> CGSize {
        let base = nodeBaseSize(for: s)
        return CGSize(width: base.width * zoom, height: base.height * zoom)
    }

    func nodeScreenOrigin(for s: Session) -> CGPoint {
        let b = basePosition(for: s)
        return CGPoint(x: CGFloat(b.x) * zoom + pan.width, y: CGFloat(b.y) * zoom + pan.height)
    }

    func nodeScreenRect(for s: Session) -> CGRect {
        CGRect(origin: nodeScreenOrigin(for: s), size: nodeScreenSize(for: s))
    }

    func outputPortScreenPoint(for s: Session) -> CGPoint {
        let r = nodeScreenRect(for: s)
        return CGPoint(x: r.maxX, y: r.midY)
    }

    func inputPortScreenPoint(for s: Session) -> CGPoint {
        let r = nodeScreenRect(for: s)
        return CGPoint(x: r.minX, y: r.midY)
    }

    func midPoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    func edgeColor(_ edge: TeamEdgeRecord, active: Bool, waiting: Bool) -> Color {
        if waiting { return StateColor.waiting }
        if active { return p.accent }
        let interacted = edge.interactionCount > 0
        switch edge.kind {
        case .delegate: return p.secondary.opacity(interacted ? 0.85 : 0.6)
        case .sequence: return StateColor.cyan.opacity(interacted ? 0.9 : 0.7)
        case .handoff: return StateColor.working.opacity(interacted ? 0.95 : 0.75)
        }
    }

    func drawWire(in ctx: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color, dashed: Bool, active: Bool, reverseArrow: Bool) {
        let dx = max(abs(to.x - from.x) * 0.5, 60)
        var path = Path()
        path.move(to: from)
        path.addCurve(to: to, control1: CGPoint(x: from.x + dx, y: from.y), control2: CGPoint(x: to.x - dx, y: to.y))
        let style = StrokeStyle(lineWidth: active ? 2.4 : 1.7, lineCap: .round, dash: dashed ? [6, 5] : [])
        ctx.stroke(path, with: .color(color), style: style)

        // Ponta da seta na entrada do nó destino.
        let arrowLen: CGFloat = 8
        let tip = to
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - arrowLen, y: tip.y - 4.5))
        head.addLine(to: CGPoint(x: tip.x - arrowLen, y: tip.y + 4.5))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))

        // Ponta sutil de retorno no nó de origem quando houve resposta/leitura reversa.
        if reverseArrow {
            var rev = Path()
            rev.move(to: from)
            rev.addLine(to: CGPoint(x: from.x + arrowLen, y: from.y - 4.0))
            rev.addLine(to: CGPoint(x: from.x + arrowLen, y: from.y + 4.0))
            rev.closeSubpath()
            ctx.fill(rev, with: .color(StateColor.cyan.opacity(0.9)))
        }
    }

    private struct EdgeAnimationState {
        let forward: Bool
        let reverse: Bool
        let speed: Double
        let pulsing: Bool
    }

    private func isEdgePulsing(_ edge: TeamEdgeRecord, now: Date) -> Bool {
        guard let lastAt = edge.lastActivityAt else { return false }
        return now.timeIntervalSince(lastAt) < pulseWindowSeconds
    }

    private func latestPulseDeadline(edges: [TeamEdgeRecord], now: Date) -> Date? {
        edges
            .compactMap(\.lastActivityAt)
            .map { $0.addingTimeInterval(pulseWindowSeconds) }
            .filter { $0 > now }
            .max()
    }

    private func pulseExpirationKey(edges: [TeamEdgeRecord]) -> String {
        edges.map { "\($0.id):\($0.lastActivityAt?.timeIntervalSince1970 ?? 0):\($0.interactionCount)" }.joined(separator: "|")
    }

    private func shouldAnimateEdges(edges: [TeamEdgeRecord], members: [Session], now: Date) -> Bool {
        edges.contains { edge in
            guard let from = members.first(where: { $0.id == edge.fromSessionId }),
                  let to = members.first(where: { $0.id == edge.toSessionId }) else { return false }
            return edgeAnimationState(edge: edge, from: from, to: to, now: now) != nil
        }
    }

    private func edgeAnimationState(edge: TeamEdgeRecord, from: Session, to: Session, now: Date) -> EdgeAnimationState? {
        let pulsing = isEdgePulsing(edge, now: now)
        let working = from.status == .working || to.status == .working
        guard pulsing || working else { return nil }

        let dir = edge.lastDirection
        var forward = dir == .forward || dir == .bidirectional
        var reverse = dir == .reverse || dir == .bidirectional

        // Enquanto um ou ambos os nós estão trabalhando mesmo sem direção registrada ainda,
        // indica o sentido ativo do trabalho na aresta.
        if from.status == .working && to.status == .working {
            forward = true
            reverse = true
        } else if !forward && !reverse {
            if to.status == .working {
                forward = true
            } else if from.status == .working {
                reverse = true
            }
        }
        guard forward || reverse else { return nil }
        return EdgeAnimationState(
            forward: forward,
            reverse: reverse,
            speed: pulsing ? 0.55 : 0.28,
            pulsing: pulsing
        )
    }

    private func bezierPoint(from: CGPoint, to: CGPoint, t: CGFloat) -> CGPoint {
        let dx = max(abs(to.x - from.x) * 0.5, 60)
        let c1 = CGPoint(x: from.x + dx, y: from.y)
        let c2 = CGPoint(x: to.x - dx, y: to.y)
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        let uuu = uu * u
        let ttt = tt * t
        let x = uuu * from.x + 3 * uu * t * c1.x + 3 * u * tt * c2.x + ttt * to.x
        let y = uuu * from.y + 3 * uu * t * c1.y + 3 * u * tt * c2.y + ttt * to.y
        return CGPoint(x: x, y: y)
    }

    private func drawBeads(in ctx: inout GraphicsContext, from: CGPoint, to: CGPoint, forward: Bool, reverse: Bool, speed: Double, now: Date) {
        let elapsed = now.timeIntervalSinceReferenceDate * speed
        let beadOffsets: [Double] = [0.0, 0.33, 0.66]

        if forward {
            for offset in beadOffsets {
                let raw = (elapsed + offset).truncatingRemainder(dividingBy: 1.0)
                let t = CGFloat(raw < 0 ? raw + 1 : raw)
                let pt = bezierPoint(from: from, to: to, t: t)
                drawSingleBead(in: &ctx, at: pt, color: p.accent)
            }
        }

        if reverse {
            for offset in beadOffsets {
                let raw = (elapsed + offset + 0.16).truncatingRemainder(dividingBy: 1.0)
                let t = CGFloat(1.0 - (raw < 0 ? raw + 1 : raw))
                let pt = bezierPoint(from: from, to: to, t: t)
                drawSingleBead(in: &ctx, at: pt, color: StateColor.cyan)
            }
        }
    }

    private func drawSingleBead(in ctx: inout GraphicsContext, at pt: CGPoint, color: Color) {
        let haloRadius: CGFloat = 6.0
        let coreRadius: CGFloat = 3.2
        ctx.fill(
            Path(ellipseIn: CGRect(x: pt.x - haloRadius, y: pt.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)),
            with: .color(color.opacity(0.28))
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: pt.x - coreRadius, y: pt.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
            with: .color(color)
        )
    }

    var emptyTeams: some View {
        VStack(spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(p.tertiary)
            Text("Nenhuma equipe multi-agente ainda")
                .font(.system(size: 15, weight: .bold))
            Text("Crie uma equipe com orquestrador e especialistas usando agentes, providers e modelos diferentes no mesmo projeto.")
                .font(.system(size: 12.5))
                .foregroundStyle(p.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Criar primeira equipe") { model.showNewTeam = true }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cartão do Nó com Terminal ao Vivo

private struct TeamNodeCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    let session: Session
    let team: TeamRecord
    let size: CGSize
    let baseOrigin: CGPoint
    let baseSize: CGSize
    let zoom: CGFloat
    let collapsed: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleCollapse: () -> Void
    let onDragChanged: (Double, Double) -> Void
    let onDragEnded: (Double, Double) -> Void
    let onResizeChanged: (Double, Double, Double, Double) -> Void
    let onResizeEnded: (Double, Double, Double, Double) -> Void
    let onResetSize: () -> Void
    let onConnectDragChanged: (CGPoint) -> Void
    let onConnectDragEnded: (CGPoint) -> Void

    @State private var dragStartOrigin: CGPoint?
    @State private var hovering = false

    var body: some View {
        let canAttach = model.canAttach(session)
        let showLiveTerminal = canAttach && !collapsed
        let border = borderStyle

        VStack(spacing: 0) {
            // Cabeçalho arrastável do nó.
            header(canAttach: canAttach)
            Rectangle().fill(p.border).frame(height: 1)

            if showLiveTerminal, let tmux = try? Tmux(server: session.tmuxServer) {
                TerminalPane(
                    argv: tmux.attachCommand(session.tmuxName),
                    cwd: session.worktreePath,
                    theme: model.theme,
                    fontSize: max(Double((model.fontSize - 1) * zoom), 8),
                    focused: isSelected,
                    onFocus: onSelect
                )
                .id("canvas-term-\(session.id)")
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(model.theme?.background.color ?? p.panel)
            } else {
                summaryBody
            }

            if let lastComm = model.latestTeamInteraction(for: session.id, in: team.id),
               let detail = lastComm.detail, !detail.isEmpty {
                Rectangle().fill(p.border).frame(height: 1)
                HStack(spacing: 5) {
                    Image(systemName: lastComm.kind == "team-return" ? "checkmark.circle.fill" : (lastComm.kind == "team-read" ? "eye.fill" : "arrow.turn.down.right"))
                        .font(.system(size: 9))
                        .foregroundStyle(lastComm.kind == "team-read" ? StateColor.cyan : (lastComm.kind == "team-return" ? StateColor.working : p.accent))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(p.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(relativeTime(lastComm.at))
                        .font(.system(size: 9.5))
                        .foregroundStyle(p.tertiary)
                }
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(p.panel.opacity(0.6))
            }
        }
        .frame(width: size.width, height: size.height)
        .background(p.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border.0, lineWidth: border.1))
        .shadow(color: .black.opacity(isSelected ? 0.3 : 0.14), radius: isSelected ? 12 : 6, y: 3)
        // Alças de redimensionamento nas 4 bordas e nos 4 cantos.
        .overlay {
            if !collapsed && canAttach {
                NodeResizeHandles(
                    baseOrigin: baseOrigin,
                    baseSize: baseSize,
                    zoom: zoom,
                    onChanged: onResizeChanged,
                    onEnded: onResizeEnded,
                    onReset: onResetSize
                )
            }
        }
        // Porta de entrada (esquerda)
        .overlay(alignment: .leading) {
            Circle()
                .fill(p.card)
                .overlay(Circle().strokeBorder(p.border.opacity(2.5), lineWidth: 1.5))
                .frame(width: 10, height: 10)
                .offset(x: -5)
                .allowsHitTesting(false)
        }
        // Porta de saída arrastável para criar ligações (direita — acima das alças de borda)
        .overlay(alignment: .trailing) {
            Circle()
                .fill(p.accent)
                .overlay(Circle().strokeBorder(p.card, lineWidth: 1.5))
                .frame(width: 12, height: 12)
                .offset(x: 6)
                .contentShape(Rectangle().size(width: 24, height: 24))
                .pointerCursor()
                .help("Arraste até outro nó para conectar")
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("teamCanvas"))
                    .onChanged { g in onConnectDragChanged(g.location) }
                    .onEnded { g in onConnectDragEnded(g.location) })
        }
        .onHover { hovering = $0 }
        .onTapGesture { onSelect() }
    }

    func header(canAttach: Bool) -> some View {
        let agentName = model.config?.agents[session.agent]?.name ?? session.agent
        let providerName = session.provider.flatMap { model.config?.providers[$0]?.name ?? $0 }
        let runtimeText = [agentName, providerName, session.model].compactMap { $0 }.joined(separator: " · ")

        return HStack(spacing: 6) {
            if session.isOrchestrator {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(StateColor.waiting)
                    .help("Sessão Orquestradora")
            }
            StatusIcon(status: session.status, size: 11)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(session.roleTitle ?? session.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(p.text)
                        .lineLimit(1)
                    if session.worktreeSourceId != nil {
                        Text("compartilhado")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(StateColor.cyan)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(StateColor.cyan.opacity(0.12)))
                    }
                }
                Text(runtimeText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            ContextRing(session: session).scaleEffect(0.8).fixedSize()
            Text(StateColor.label(session.status))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StateColor.dot(session.status) ?? p.tertiary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill((StateColor.dot(session.status) ?? p.tertiary).opacity(0.14)))
                .lineLimit(1)
            if hovering || isSelected {
                HStack(spacing: 1) {
                    if canAttach {
                        IconButton(symbol: collapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                                   help: collapsed ? "Expandir terminal" : "Recolher terminal", size: 11, action: onToggleCollapse)
                    }
                    IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Abrir sessão em tela cheia", size: 11) {
                        model.openAlone(session.id)
                    }
                    if session.status.isLive {
                        IconButton(symbol: "stop.circle", help: "Parar", size: 11) { model.stopSession(session.id) }
                    } else if session.status != .queued {
                        IconButton(symbol: "play.circle", help: "Iniciar / Retomar", size: 11) {
                            model.delegateToNode(teamId: team.id, targetSessionId: session.id,
                                                 task: session.prompt ?? session.responsibilities ?? "Continue o trabalho conforme seu papel.")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(p.card)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("teamCanvas"))
            .onChanged { g in
                if dragStartOrigin == nil { dragStartOrigin = baseOrigin }
                let start = dragStartOrigin!
                onDragChanged(Double(start.x) + Double(g.translation.width / zoom),
                              Double(start.y) + Double(g.translation.height / zoom))
            }
            .onEnded { g in
                let start = dragStartOrigin ?? baseOrigin
                dragStartOrigin = nil
                onDragEnded(Double(start.x) + Double(g.translation.width / zoom),
                            Double(start.y) + Double(g.translation.height / zoom))
            })
        .onTapGesture(count: 2) { model.openAlone(session.id) }
        .onTapGesture { onSelect() }
    }

    var summaryBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let resp = session.responsibilities, !resp.isEmpty {
                Text(resp)
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.secondary)
                    .lineLimit(2)
            } else if let pmt = session.prompt, !pmt.isEmpty {
                Text(pmt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.secondary)
                    .lineLimit(2)
            } else {
                Text("Sem responsabilidade definida ainda.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.tertiary)
            }
            Spacer(minLength: 0)
            HStack {
                if let branch = session.branch {
                    Label(branch.replacingOccurrences(of: "bando/", with: ""), systemImage: "arrow.triangle.branch")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(p.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                if !model.canAttach(session) && session.status != .queued {
                    Button("Iniciar") {
                        model.delegateToNode(teamId: team.id, targetSessionId: session.id,
                                             task: session.prompt ?? session.responsibilities ?? "Inicie sua tarefa conforme o papel na equipe.")
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var borderStyle: (Color, CGFloat) {
        if isSelected { return (p.accent, 2) }
        switch session.status {
        case .waiting: return (StateColor.waiting.opacity(0.75), 1.5)
        case .error: return (StateColor.failed.opacity(0.7), 1.5)
        case .working: return (StateColor.working.opacity(0.5), 1.2)
        default: return (p.border.opacity(1.5), 1)
        }
    }
}

// MARK: - Inspector do Nó no Canvas

private struct TeamNodeInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    let team: TeamRecord
    let session: Session

    @State private var roleTitle = ""
    @State private var responsibilities = ""
    @State private var isOrchestrator = false
    @State private var agent = ""
    @State private var provider = "default"
    @State private var modelName = ""
    @State private var quickTask = ""
    @State private var connectTargetId: String?
    @State private var connectKind: TeamEdgeKind = .delegate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    FieldLabel("Nó selecionado")
                    Spacer()
                    Text(session.shortId).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.tertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Papel")
                    TextField("Título do papel", text: $roleTitle).fieldBox(height: 28)
                    Toggle("Sessão Orquestradora", isOn: $isOrchestrator)
                        .toggleStyle(.switch).controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Responsabilidades")
                    TextEditor(text: $responsibilities)
                        .font(.system(size: 12)).scrollContentBackground(.hidden)
                        .padding(.vertical, 4).frame(minHeight: 70, maxHeight: 130).fieldBox(height: nil)
                }

                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Agente / Provider / Modelo")
                    SelectField(selection: $agent, options: agents.map { ($0.agent.id, $0.agent.name) })
                    ProviderField(agentId: agent, selection: $provider)
                    ModelField(agentId: agent, providerId: provider, text: $modelName, placeholder: "padrão")
                }

                HStack {
                    Button("Salvar alterações") { saveChanges() }
                        .buttonStyle(AccentButtonStyle())
                    if session.status.isLive && (agent != session.agent || (provider == "default" ? nil : provider) != session.provider || (modelName.isEmpty ? nil : modelName) != session.model) {
                        Button("Aplicar e trocar") {
                            saveChanges()
                            model.swapAgent(
                                session.id,
                                agent: agent,
                                provider: provider == "default" ? nil : provider,
                                model: modelName.isEmpty ? nil : modelName,
                                handoff: model.handoffDefault
                            )
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }
                }

                DialogDivider()

                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Enviar / delegar tarefa")
                    TextEditor(text: $quickTask)
                        .font(.system(size: 12)).scrollContentBackground(.hidden)
                        .padding(.vertical, 4).frame(minHeight: 54, maxHeight: 100).fieldBox(height: nil)
                    Button("Enviar para este agente") {
                        let t = quickTask.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        model.delegateToNode(teamId: team.id, targetSessionId: session.id, task: t)
                        quickTask = ""
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(quickTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                DialogDivider()

                let peers = model.teamSessions(team.id).filter { $0.id != session.id }
                if !peers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel("Conectar com outro nó")
                        SelectField(selection: $connectTargetId, options: peers.map { (Optional($0.id), $0.roleTitle ?? $0.name) })
                        HStack {
                            SelectField(selection: $connectKind, options: TeamEdgeKind.allCases.map { ($0, $0.label) })
                            Button("Ligar") {
                                if let target = connectTargetId {
                                    model.connectTeamNodes(teamId: team.id, from: session.id, to: target, kind: connectKind)
                                }
                            }
                            .buttonStyle(OutlineButtonStyle())
                            .disabled(connectTargetId == nil)
                        }
                    }
                }

                let relatedEdges = model.edges(for: team.id).filter { $0.fromSessionId == session.id || $0.toSessionId == session.id }
                if !relatedEdges.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel("Ligações")
                        ForEach(relatedEdges) { edge in
                            let otherId = edge.fromSessionId == session.id ? edge.toSessionId : edge.fromSessionId
                            let other = model.session(otherId)?.roleTitle ?? model.session(otherId)?.name ?? otherId
                            let arrow = edge.fromSessionId == session.id ? "→" : "←"
                            HStack {
                                Text("\(arrow) \(other) (\(edge.kind.label))")
                                    .font(.system(size: 11.5)).lineLimit(1)
                                Spacer()
                                IconButton(symbol: "xmark", help: "Remover ligação", size: 10) {
                                    model.disconnectTeamEdge(edge.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(p.card)
        .onAppear(perform: syncFromSession)
        .onChange(of: session.id) { _, _ in syncFromSession() }
        .onChange(of: agent) { _, _ in
            if !providers.contains(where: { $0.id == provider }) { provider = "default" }
        }
    }

    func syncFromSession() {
        roleTitle = session.roleTitle ?? session.name
        responsibilities = session.responsibilities ?? ""
        isOrchestrator = session.isOrchestrator
        agent = session.agent
        provider = session.provider ?? "default"
        modelName = session.model ?? ""
        connectTargetId = model.teamSessions(team.id).first { $0.id != session.id }?.id
    }

    func saveChanges() {
        let pVal = provider == "default" ? nil : provider
        let mVal = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        model.updateTeamRole(
            sessionId: session.id,
            roleTitle: roleTitle,
            responsibilities: responsibilities,
            isOrchestrator: isOrchestrator,
            agent: agent,
            provider: pVal,
            model: mVal.isEmpty ? nil : mVal,
            compressor: session.compressor,
            clearProvider: pVal == nil,
            clearModel: mVal.isEmpty,
            clearCompressor: false
        )
    }

    var agents: [AgentAvailability] {
        model.availability.values.filter { $0.agent.id != "shell" }
            .sorted { ($0.isInstalled ? 0 : 1, $0.agent.name) < ($1.isInstalled ? 0 : 1, $1.agent.name) }
    }

    var providers: [ProviderDefinition] {
        (model.config?.providers(for: agent) ?? [])
            .sorted { ($0.id == "default" ? 0 : 1, $0.name) < ($1.id == "default" ? 0 : 1, $1.name) }
    }
}

// MARK: - Helpers visuais do Canvas

private struct TeamCommunicationFeed: View {
    @Environment(\.palette) private var p
    let events: [SessionEvent]
    @Binding var expanded: Bool
    let onSelectSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(events.isEmpty ? p.tertiary : p.accent)
                    Text("Comunicação")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.text)
                    Text("\(events.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(events.isEmpty ? p.tertiary : p.accent)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill((events.isEmpty ? p.tertiary : p.accent).opacity(0.14)))
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(p.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()

            if expanded {
                Rectangle().fill(p.border).frame(height: 1)
                if events.isEmpty {
                    Text("Nenhuma comunicação entre agentes registrada ainda.")
                        .font(.system(size: 11))
                        .foregroundStyle(p.tertiary)
                        .padding(10)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(events.prefix(15), id: \.id) { ev in
                                eventRow(ev)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 165)
                }
            }
        }
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 10).fill(p.card.opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.border.opacity(1.5)))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private func eventRow(_ ev: SessionEvent) -> some View {
        Button {
            onSelectSession(ev.sessionId)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(dotColor(for: ev.kind))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                Text(ev.detail ?? ev.kind)
                    .font(.system(size: 10.5))
                    .foregroundStyle(p.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(relativeTime(ev.at))
                    .font(.system(size: 9.5))
                    .foregroundStyle(p.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(p.panel.opacity(0.55)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func dotColor(for kind: String) -> Color {
        switch kind {
        case "team-delegate": return p.accent
        case "team-read": return StateColor.cyan
        case "team-return", "team-handoff": return StateColor.working
        default: return p.secondary
        }
    }
}

private struct EdgeBadge: View {
    @Environment(\.palette) private var p
    let edge: TeamEdgeRecord
    let isPulsing: Bool
    let onRemove: () -> Void
    @State private var hovering = false

    private var directionGlyph: String? {
        switch edge.lastDirection {
        case .forward: return "→"
        case .reverse: return "←"
        case .bidirectional: return "⇄"
        case nil: return nil
        }
    }

    private var directionColor: Color {
        switch edge.lastDirection {
        case .forward: return p.accent
        case .reverse: return StateColor.cyan
        case .bidirectional: return StateColor.working
        case nil: return p.secondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if isPulsing {
                Circle()
                    .fill(directionColor)
                    .frame(width: 5, height: 5)
            }
            Text(edge.kind.label)
                .font(.system(size: 10, weight: .medium))
            if let glyph = directionGlyph {
                Text(glyph)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(directionColor)
            }
            if edge.interactionCount > 0 {
                Text("· \(edge.interactionCount)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isPulsing ? p.text : p.secondary)
            }
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(hovering || isPulsing ? p.text : p.secondary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(p.card))
        .overlay(
            Capsule().strokeBorder(
                isPulsing ? directionColor.opacity(0.8) : p.border.opacity(1.5),
                lineWidth: isPulsing ? 1.2 : 1
            )
        )
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remover ligação", role: .destructive, action: onRemove)
        }
    }
}

private struct DottedCanvasBackground: View {
    let spacing: CGFloat
    let color: Color
    let offset: CGSize

    var body: some View {
        Canvas { ctx, size in
            let step = max(spacing, 10)
            var ox = offset.width.truncatingRemainder(dividingBy: step)
            if ox > 0 { ox -= step }
            var oy = offset.height.truncatingRemainder(dividingBy: step)
            if oy > 0 { oy -= step }
            var x = ox
            while x < size.width {
                var y = oy
                while y < size.height {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(color))
                    y += step
                }
                x += step
            }
        }
    }
}

/// Captura gestos nativos do trackpad do MacBook (rolagem com dois dedos para
/// arrastar o canvas e pinça para zoom centrado no cursor) sem conflitar com
/// o scroll interno quando um terminal está focado.
private struct CanvasTrackpadOverlay: NSViewRepresentable {
    var onPan: (CGSize) -> Void
    var onMagnify: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.start(on: view, onPan: onPan, onMagnify: onMagnify)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onPan = onPan
        context.coordinator.onMagnify = onMagnify
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var onPan: ((CGSize) -> Void)?
        var onMagnify: ((CGFloat, CGPoint) -> Void)?
        private var monitor: Any?

        func start(on view: NSView, onPan: @escaping (CGSize) -> Void, onMagnify: @escaping (CGFloat, CGPoint) -> Void) {
            self.onPan = onPan
            self.onMagnify = onMagnify
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self, weak view] event in
                guard let self, let view, let window = view.window, event.window === window,
                      window.attachedSheet == nil else { return event }
                let ptInView = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(ptInView) else { return event }

                // Coordenada SwiftUI (origem no canto superior esquerdo).
                let swiftPoint = CGPoint(x: ptInView.x, y: view.bounds.height - ptInView.y)

                if event.type == .magnify {
                    self.onMagnify?(event.magnification, swiftPoint)
                    return nil
                }

                // Scroll com dois dedos (pan) ou ⌘/⌥+scroll (zoom).
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let wantsZoom = modifiers.contains(.command) || modifiers.contains(.option)

                if !wantsZoom, Self.isOverFocusedTerminal(at: event.locationInWindow, in: window) {
                    return event
                }

                let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 14.0
                let dx = event.scrollingDeltaX * scale
                let dy = event.scrollingDeltaY * scale

                if wantsZoom {
                    let deltaZoom = dy * 0.008
                    if abs(deltaZoom) > 0.0001 {
                        self.onMagnify?(deltaZoom, swiftPoint)
                    }
                    return nil
                }

                if dx != 0 || dy != 0 {
                    self.onPan?(CGSize(width: dx, height: dy))
                }
                return nil
            }
        }

        private static func isOverFocusedTerminal(at windowPoint: NSPoint, in window: NSWindow) -> Bool {
            guard let contentView = window.contentView,
                  let firstHit = contentView.hitTest(windowPoint) else { return false }
            var hit: NSView? = firstHit
            while let current = hit {
                if current is BandoTerminalView {
                    return window.firstResponder === current
                }
                hit = current.superview
            }
            return false
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private extension CGFloat {
    func rounded(to places: Int) -> CGFloat {
        let p = pow(10.0, CGFloat(places))
        return (self * p).rounded() / p
    }
}

// MARK: - Alças de redimensionamento nas laterais e cantos do nó

private struct NodeResizeHandles: View {
    enum Edge: CaseIterable {
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight

        var isHorizontal: Bool { self == .left || self == .right }
        var isVertical: Bool { self == .top || self == .bottom }
        var isCorner: Bool { !isHorizontal && !isVertical }

        var affectsLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
        var affectsRight: Bool { self == .right || self == .topRight || self == .bottomRight }
        var affectsTop: Bool { self == .top || self == .topLeft || self == .topRight }
        var affectsBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }

        var cursor: NSCursor {
            if isHorizontal { return .resizeLeftRight }
            if isVertical { return .resizeUpDown }
            return .crosshair
        }
    }

    let baseOrigin: CGPoint
    let baseSize: CGSize
    let zoom: CGFloat
    let onChanged: (Double, Double, Double, Double) -> Void
    let onEnded: (Double, Double, Double, Double) -> Void
    let onReset: () -> Void

    @State private var hovered: Edge?
    @State private var activeStart: (x: Double, y: Double, w: Double, h: Double)?

    private let edgeThickness: CGFloat = 12
    private let cornerSize: CGFloat = 16
    private let minWidth: Double = 240
    private let minHeight: Double = 160

    var body: some View {
        ZStack {
            // Laterais esquerda e direita (altura com margem dos cantos).
            edgeBar(.left)
                .frame(width: edgeThickness)
                .padding(.vertical, cornerSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            edgeBar(.right)
                .frame(width: edgeThickness)
                .padding(.vertical, cornerSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            // Bordas superior e inferior.
            edgeBar(.top)
                .frame(height: edgeThickness)
                .padding(.horizontal, cornerSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            edgeBar(.bottom)
                .frame(height: edgeThickness)
                .padding(.horizontal, cornerSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            // 4 cantos.
            cornerHandle(.topLeft).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            cornerHandle(.topRight).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            cornerHandle(.bottomLeft).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            cornerHandle(.bottomRight).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .onDisappear {
            if hovered != nil {
                hovered = nil
                NSCursor.pop()
            }
        }
    }

    func edgeBar(_ edge: Edge) -> some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            if hovered == edge {
                RoundedRectangle(cornerRadius: 2)
                    .fill(StateColor.cyan.opacity(0.65))
                    .frame(width: edge.isHorizontal ? 3 : 48, height: edge.isVertical ? 3 : 48)
            }
        }
        .onHover { inside in updateHover(edge, inside: inside) }
        .onTapGesture(count: 2, perform: onReset)
        .gesture(resizeGesture(for: edge))
        .help("Arraste para redimensionar · clique duplo para restaurar")
    }

    func cornerHandle(_ edge: Edge) -> some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            if edge == .bottomRight {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(hovered == edge ? StateColor.cyan : Color.secondary.opacity(0.45))
                    .padding(3)
            } else if hovered == edge {
                Circle().fill(StateColor.cyan.opacity(0.75)).frame(width: 7, height: 7)
            }
        }
        .frame(width: cornerSize, height: cornerSize)
        .onHover { inside in updateHover(edge, inside: inside) }
        .onTapGesture(count: 2, perform: onReset)
        .gesture(resizeGesture(for: edge))
        .help("Arraste o canto para redimensionar · clique duplo para restaurar")
    }

    private func updateHover(_ edge: Edge, inside: Bool) {
        if inside {
            if hovered != edge {
                if hovered != nil { NSCursor.pop() }
                hovered = edge
                edge.cursor.push()
            }
        } else if hovered == edge {
            hovered = nil
            NSCursor.pop()
        }
    }

    private func resizeGesture(for edge: Edge) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("teamCanvas"))
            .onChanged { g in
                if activeStart == nil {
                    activeStart = (Double(baseOrigin.x), Double(baseOrigin.y), Double(baseSize.width), Double(baseSize.height))
                }
                let f = computeFrame(start: activeStart!, translation: g.translation, edge: edge)
                onChanged(f.x, f.y, f.w, f.h)
            }
            .onEnded { g in
                let start = activeStart ?? (Double(baseOrigin.x), Double(baseOrigin.y), Double(baseSize.width), Double(baseSize.height))
                activeStart = nil
                let f = computeFrame(start: start, translation: g.translation, edge: edge)
                onEnded(f.x, f.y, f.w, f.h)
            }
    }

    private func computeFrame(
        start: (x: Double, y: Double, w: Double, h: Double),
        translation: CGSize,
        edge: Edge
    ) -> (x: Double, y: Double, w: Double, h: Double) {
        let dx = Double(translation.width / zoom)
        let dy = Double(translation.height / zoom)
        var x = start.x, y = start.y, w = start.w, h = start.h

        if edge.affectsRight {
            w = max(start.w + dx, minWidth)
        }
        if edge.affectsLeft {
            let clampedDx = min(dx, start.w - minWidth)
            x = start.x + clampedDx
            w = start.w - clampedDx
        }
        if edge.affectsBottom {
            h = max(start.h + dy, minHeight)
        }
        if edge.affectsTop {
            let clampedDy = min(dy, start.h - minHeight)
            y = start.y + clampedDy
            h = start.h - clampedDy
        }
        return (x, y, w, h)
    }
}
