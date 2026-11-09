import AppKit
import BandoCore
import Sparkle
import SwiftUI
import UserNotifications

@main
struct BandoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    private let updater = Updater()

    var body: some Scene {
        WindowGroup("Bando", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    delegate.model = model
                    await model.start()
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Mostrar ou esconder a lateral") { model.showSidebar.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("Nova sessão") { model.openComposer() }.keyboardShortcut("n")
                Button("Adicionar projeto…") { model.showAddProject = true }.keyboardShortcut("o")
                Button("Importar workspace…") { model.showImportWorkspace = true }
            }
            CommandMenu("Sessão") {
                Button("Buscar sessão…") { model.showPalette = true }.keyboardShortcut("k")
                Button("Próxima esperando você") { model.selectNextWaiting() }.keyboardShortcut("j")
                Divider()
                ForEach(1...9, id: \.self) { i in
                    Button("Sessão \(i)") { model.selectIndex(i - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i)")))
                }
                Divider()
                Button("Parar") { if let id = model.selection { model.stopSession(id) } }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(model.selectedSession?.status.isLive != true)
                Button("Retomar") { if let id = model.selection { model.resumeSession(id) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.selectedSession == nil || model.selectedSession?.status.isLive == true)
                Button("Mostrar no Finder") { if let s = model.selectedSession { model.reveal(s) } }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Recarregar configuração") { Task { await model.reload() } }
            }
            CommandGroup(replacing: .help) {
                Button("Atalhos de teclado") { model.showShortcuts = true }.keyboardShortcut("/")
                Button("Documentação") { NSWorkspace.shared.open(HelpMenu.repo.appendingPathComponent("blob/main/README.md")) }
                Button("Reportar problema") { NSWorkspace.shared.open(HelpMenu.repo.appendingPathComponent("issues/new")) }
            }
            CommandGroup(after: .toolbar) {
                Button(model.gridMode ? "Mostrar uma sessão" : "Mostrar grade") { model.toggleGrid() }
                    .keyboardShortcut("g", modifiers: [.command, .option])
                ForEach(Array(GridPreset.all.enumerated()), id: \.element) { i, g in
                    Button("Grade \(g.label)") { model.setGrid(cols: g.cols, rows: g.rows) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
                }
                Button("Igualar tamanhos da grade") { model.equalize(columns: true); model.equalize(columns: false) }
                Button("Detalhes da sessão") { model.showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
                Button("Aumentar fonte do terminal") { model.fontSize = min(model.fontSize + 1, 24) }
                    .keyboardShortcut("+")
                Button("Diminuir fonte do terminal") { model.fontSize = max(model.fontSize - 1, 9) }
                    .keyboardShortcut("-")
            }
        }

        Window("Uso e custo", id: "usage") {
            UsageWindow().environment(model)
        }
        .keyboardShortcut("u", modifiers: [.command, .shift])
        .defaultSize(width: 820, height: 760)

        Window("Relatórios", id: "reports") {
            ReportsWindow().environment(model)
        }
        .keyboardShortcut("r", modifiers: [.command, .option])
        .defaultSize(width: 1000, height: 820)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Fecha o app sem matar as sessões (elas vivem no tmux) e trata cliques nas
/// notificações.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["session"] as? String
        await open(session: id)
    }

    func open(session id: String?) {
        NSApp.activate()
        if let id { model?.select(id) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Sparkle só liga quando o app roda empacotado (Info.plist com SUFeedURL).
@MainActor
final class Updater {
    let controller: SPUStandardUpdaterController?

    init() {
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String != nil
        controller = hasFeed
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }
}

struct CheckForUpdatesButton: View {
    let updater: Updater

    var body: some View {
        Button("Procurar atualizações…") { updater.controller?.checkForUpdates(nil) }
            .disabled(updater.controller == nil)
    }
}
