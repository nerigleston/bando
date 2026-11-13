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
                Button("Parar…") { if let id = model.selection { model.requestStop([id]) } }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(model.selectedSession?.status.isLive != true)
                Button("Retomar") { if let id = model.selection { model.resumeSession(id) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.selectedSession == nil || model.selectedSession?.status.isLive == true)
                Button("Mostrar no Finder") { if let s = model.selectedSession { model.reveal(s) } }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button(model.showFiles ? "Esconder arquivos" : "Mostrar arquivos") { model.showFiles.toggle() }
                    .keyboardShortcut("e", modifiers: .command)
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
        ImagePaste.install()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["update"] != nil {
            await MainActor.run {
                NSApp.activate()
                NotificationCenter.default.post(name: Updater.showUpdate, object: nil)
            }
            return
        }
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
///
/// Para a versão nova aparecer logo depois de publicada, além da checagem do
/// Sparkle (a cada hora), o app consulta o appcast ao voltar para a frente e a
/// cada 15 minutos. É um GET de poucos KB; sem versão nova, nada aparece.
///
/// Versão nova encontrada com o app fora de foco: o Sparkle não interrompe e o
/// Bando manda uma notificação do macOS; clicar nela abre a janela "Instalar".
@MainActor
final class Updater: NSObject, ObservableObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    static let showUpdate = Notification.Name("bando.showUpdate")
    /// Versão baixada e pronta (object: String). O AppModel mostra no rodapé.
    static let updateReady = Notification.Name("bando.updateReady")
    nonisolated private static let notificationId = "bando-update"
    private(set) var controller: SPUStandardUpdaterController?
    /// Versão já baixada (modo automático) esperando para instalar, e como
    /// instalar agora sem esperar o app fechar.
    @Published private(set) var readyVersion: String?
    private var installNow: (() -> Void)?
    private var timer: Timer?
    private var lastCheck = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String != nil
        guard hasFeed else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        observers.append(NotificationCenter.default.addObserver(forName: Self.showUpdate, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let installNow = self.installNow { installNow() } else { self.controller?.checkForUpdates(nil) }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkQuietly(minInterval: 5 * 60) }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkQuietly(minInterval: 10 * 60) }
        }
        timer?.tolerance = 60
        // Reabriu no meio de "atualizar até a última": procura a próxima já.
        if UserDefaults.standard.bool(forKey: Self.chainKey) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                MainActor.assumeIsolated {
                    guard let updater = self?.controller?.updater, updater.canCheckForUpdates else {
                        UserDefaults.standard.removeObject(forKey: Self.chainKey); return
                    }
                    updater.checkForUpdatesInBackground()
                }
            }
        }
    }

    /// Checagem em segundo plano: só mostra algo se houver versão nova.
    /// Com uma versão já baixada o Sparkle não consulta o appcast de novo até
    /// reiniciar (só retoma a baixada); aí o Bando mesmo confere se saiu outra.
    private func checkQuietly(minInterval: TimeInterval) {
        guard Date().timeIntervalSince(lastCheck) >= minInterval else { return }
        if readyVersion != nil {
            lastCheck = Date()
            checkFeedForNewer()
            return
        }
        guard let updater = controller?.updater, updater.canCheckForUpdates else { return }
        lastCheck = Date()
        updater.checkForUpdatesInBackground()
    }

    /// Versão mais nova no appcast do que a baixada (o aviso passa a mostrar esta).
    @Published private(set) var newerVersion: String?
    /// Versão mostrada no aviso e no menu: a mais nova conhecida.
    var offeredVersion: String? { newerVersion ?? readyVersion }

    /// Lê o appcast (poucos KB) e guarda a maior versão, se passar da baixada.
    private func checkFeedForNewer() {
        guard let ready = readyVersion,
              let feed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:)) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: feed) else { return }
            let latest = Self.versions(inAppcast: String(decoding: data, as: UTF8.self)).max(by: Self.isOlder)
            await MainActor.run {
                guard let self, let latest, Self.isOlder(ready, latest), latest != self.newerVersion else { return }
                self.newerVersion = latest
                NotificationCenter.default.post(name: Self.updateReady, object: latest)
            }
        }
    }

    nonisolated static func versions(inAppcast xml: String) -> [String] {
        xml.matches(of: /<sparkle:shortVersionString>([0-9][0-9.]*)</).map { String($0.output.1) }
    }

    /// "0.1.31" < "0.1.34", comparando número a número.
    nonisolated static func isOlder(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    /// Pedido de atualizar até a última, guardado entre reinícios: a versão
    /// baixada instala, o app reabre e a mais nova instala sem outro clique.
    nonisolated private static let chainKey = "bando.updateToLatest"

    /// Reinicia e instala a versão já baixada. Se o appcast já tem outra mais
    /// nova, emenda a instalação dela depois de reabrir.
    func installReadyUpdate() {
        if newerVersion != nil { UserDefaults.standard.set(true, forKey: Self.chainKey) }
        installNow?()
    }

    // MARK: Atualização baixada em segundo plano (SPUUpdaterDelegate)

    /// No modo "baixar e instalar automaticamente" o Sparkle só instalaria ao
    /// fechar o app, sem avisar. O Bando avisa por notificação e pelo menu, e
    /// um clique reinicia e instala na hora.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let version = item.displayVersionString
        // O Sparkle chama os delegates na main thread.
        nonisolated(unsafe) let install = immediateInstallHandler
        // Clique anterior pediu a última versão: instala agora, sem perguntar de novo.
        if UserDefaults.standard.bool(forKey: Self.chainKey) {
            UserDefaults.standard.removeObject(forKey: Self.chainKey)
            DispatchQueue.main.async { install() }
            return true
        }
        MainActor.assumeIsolated {
            self.installNow = install
            self.readyVersion = version
            self.newerVersion = nil
            NotificationCenter.default.post(name: Self.updateReady, object: version)
        }
        Task { @MainActor in
            let content = UNMutableNotificationContent()
            content.title = "Bando \(version) pronto para instalar"
            content.body = "Clique para reiniciar e instalar agora. As sessões continuam no tmux."
            content.userInfo = ["update": version]
            let request = UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
        return true
    }

    // MARK: Lembrete gentil (SPUStandardUserDriverDelegate)

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Com o app em foco, o Sparkle mostra a janela na hora; fora de foco, quem
    /// avisa é a notificação abaixo.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !state.userInitiated, !handleShowingUpdate else { return }
        let version = update.displayVersionString
        Task { @MainActor in
            NSApp.requestUserAttention(.informationalRequest)
            let content = UNMutableNotificationContent()
            content.title = "Bando \(version) disponível"
            content.body = "Clique para ver as novidades e instalar. As sessões continuam rodando."
            content.userInfo = ["update": version]
            let request = UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: Updater

    var body: some View {
        if let v = updater.offeredVersion {
            Button("Reiniciar e instalar a \(v)") { updater.installReadyUpdate() }
        }
        Button("Procurar atualizações…") { updater.controller?.checkForUpdates(nil) }
            .disabled(updater.controller == nil)
    }
}
