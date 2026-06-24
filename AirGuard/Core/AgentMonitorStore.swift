import Combine
import Foundation
import AppKit

@MainActor
final class AgentMonitorStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var installationStatus = AgentHookInstallationStatus()
    @Published private(set) var listenerError: String?
    let nowPlayingStore = NowPlayingStore()

    private let settings: AppSettings
    private let hookManager = AgentHookManager()
    private let token: String
    private var server: AgentEventServer?
    private var cleanupTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private lazy var windowController = NotchWindowController(store: self, settings: settings)

    init(settings: AppSettings) {
        self.settings = settings
        token = Self.loadOrCreateToken()
        installationStatus = hookManager.status()
        bindSettings()
        updateListener()
        _ = windowController
    }

    var primarySession: AgentSession? {
        sessions.sorted {
            if $0.state.priority != $1.state.priority {
                return $0.state.priority > $1.state.priority
            }
            return $0.updatedAt > $1.updatedAt
        }.first
    }

    var isListening: Bool {
        server != nil && listenerError == nil
    }

    func installHooks() {
        do {
            installationStatus = try hookManager.install(
                token: token,
                codex: settings.codexMonitoringEnabled,
                claude: settings.claudeMonitoringEnabled
            )
        } catch {
            installationStatus.lastError = "安装失败：\(error.localizedDescription)"
        }
    }

    func uninstallHooks() {
        do {
            installationStatus = try hookManager.uninstall()
            sessions.removeAll()
        } catch {
            installationStatus.lastError = "卸载失败：\(error.localizedDescription)"
        }
    }

    func sendTestEvent() {
        accept(AgentEvent(
            provider: settings.codexMonitoringEnabled ? .codex : .claude,
            sessionID: "airsentry-preview",
            project: "预览项目",
            workingDirectory: FileManager.default.currentDirectoryPath,
            state: .waitingForApproval,
            action: "需要用户确认"
        ))
    }

    private func bindSettings() {
        Publishers.CombineLatest3(
            settings.$agentNotchEnabled,
            settings.$codexMonitoringEnabled,
            settings.$claudeMonitoringEnabled
        )
        .removeDuplicates { $0 == $1 }
        .dropFirst()
        .sink { [weak self] _ in self?.updateListener() }
        .store(in: &cancellables)
    }

    private func updateListener() {
        guard settings.agentNotchEnabled else {
            server?.stop()
            server = nil
            sessions.removeAll()
            listenerError = nil
            return
        }

        guard server == nil else { return }
        let server = AgentEventServer(
            token: token,
            onEvent: { [weak self] event in
                Task { @MainActor in self?.accept(event) }
            },
            onFailure: { [weak self] error in
                Task { @MainActor in
                    self?.listenerError = "无法启动本机事件监听：\(error.localizedDescription)"
                    self?.server = nil
                }
            }
        )
        do {
            try server.start()
            self.server = server
            listenerError = nil
        } catch {
            listenerError = "无法启动本机事件监听：\(error.localizedDescription)"
        }
    }

    private func accept(_ event: AgentEvent) {
        guard settings.agentNotchEnabled else { return }
        guard event.provider != .codex || settings.codexMonitoringEnabled else { return }
        guard event.provider != .claude || settings.claudeMonitoringEnabled else { return }

        if let index = sessions.firstIndex(where: { $0.id == event.sessionID && $0.provider == event.provider }) {
            sessions[index].project = event.project ?? sessions[index].project
            sessions[index].workingDirectory = event.workingDirectory ?? sessions[index].workingDirectory
            sessions[index].state = event.state
            sessions[index].action = event.action
            sessions[index].updatedAt = event.timestamp
        } else {
            sessions.append(AgentSession(
                id: event.sessionID,
                provider: event.provider,
                project: event.project,
                workingDirectory: event.workingDirectory,
                state: event.state,
                action: event.action,
                updatedAt: event.timestamp
            ))
        }
        scheduleCleanup()
    }

    func openSession(_ session: AgentSession) {
        if session.provider == .codex,
           let codex = NSWorkspace.shared.runningApplications.first(where: {
               $0.localizedName?.localizedCaseInsensitiveContains("Codex") == true
           }) {
            codex.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        guard let workingDirectory = session.workingDirectory,
              FileManager.default.fileExists(atPath: workingDirectory) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", workingDirectory]
        try? process.run()
    }

    private func scheduleCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.removeExpiredSessions() }
        }
    }

    private func removeExpiredSessions() {
        let now = Date()
        sessions.removeAll { session in
            let age = now.timeIntervalSince(session.updatedAt)
            switch session.state {
            case .completed: return age >= settings.agentCompletionDisplayDuration
            case .failed: return age >= max(settings.agentCompletionDisplayDuration, 8)
            case .working, .waitingForApproval: return age >= 60 * 60 * 8
            }
        }
        if sessions.isEmpty {
            cleanupTimer?.invalidate()
            cleanupTimer = nil
        }
    }

    private static func loadOrCreateToken() -> String {
        let key = "agentEventServerToken"
        if let token = UserDefaults.standard.string(forKey: key), !token.isEmpty {
            return token
        }
        let token = UUID().uuidString + UUID().uuidString
        UserDefaults.standard.set(token, forKey: key)
        return token
    }
}
