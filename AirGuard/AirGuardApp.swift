import AppKit
import Carbon
import SwiftUI
import UserNotifications

@main
struct AirGuardApp: App {
    @NSApplicationDelegateAdaptor(AirSentryAppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings()
    @StateObject private var alertManager = AlertManager()
    @StateObject private var monitorStore: MonitorStore
    @StateObject private var agentMonitorStore: AgentMonitorStore
    @StateObject private var inputMethodShortcutController: InputMethodShortcutController
    @StateObject private var appLauncherStore: AppLauncherStore
    @StateObject private var appLauncherShortcutManager: AppLauncherShortcutManager
    @StateObject private var screenshotCaptureController: ScreenshotCaptureController
    @StateObject private var screenshotShortcutManager: ScreenshotShortcutManager
    @StateObject private var translationStore: TranslationStore
    @StateObject private var translationShortcutManager: TranslationShortcutManager
    private let appLauncherPanelController: AppLauncherPanelController
    private let translationPanelController: TranslationPanelController

    init() {
        let settings = AppSettings()
        let alertManager = AlertManager()
        let appLauncherStore = AppLauncherStore()
        let appLauncherPanelController = AppLauncherPanelController(store: appLauncherStore)
        let screenshotCaptureController = ScreenshotCaptureController()
        let translationStore = TranslationStore(settings: settings)
        let translationPanelController = TranslationPanelController(settings: settings, store: translationStore)
        _settings = StateObject(wrappedValue: settings)
        _alertManager = StateObject(wrappedValue: alertManager)
        _monitorStore = StateObject(wrappedValue: MonitorStore(settings: settings, alertManager: alertManager))
        _agentMonitorStore = StateObject(wrappedValue: AgentMonitorStore(settings: settings))
        _inputMethodShortcutController = StateObject(wrappedValue: InputMethodShortcutController(settings: settings))
        _appLauncherStore = StateObject(wrappedValue: appLauncherStore)
        _appLauncherShortcutManager = StateObject(wrappedValue: AppLauncherShortcutManager(settings: settings) {
            appLauncherPanelController.toggle()
        })
        _screenshotCaptureController = StateObject(wrappedValue: screenshotCaptureController)
        _screenshotShortcutManager = StateObject(wrappedValue: ScreenshotShortcutManager(settings: settings, captureController: screenshotCaptureController))
        _translationStore = StateObject(wrappedValue: translationStore)
        _translationShortcutManager = StateObject(wrappedValue: TranslationShortcutManager(settings: settings) {
            translationPanelController.toggle()
        })
        self.appLauncherPanelController = appLauncherPanelController
        self.translationPanelController = translationPanelController
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView()
                .environmentObject(settings)
                .environmentObject(alertManager)
                .environmentObject(monitorStore)
                .environmentObject(agentMonitorStore)
                .frame(width: 400)
        } label: {
            MenuBarStatusLabel(settings: settings, monitorStore: monitorStore)
                .background(FinderAuthorizationSettingsWindowBridge())
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(alertManager)
                .environmentObject(agentMonitorStore)
                .frame(width: 860, height: 600)
        }

        Window("工具箱", id: "toolbox") {
            ToolboxView()
                .environmentObject(settings)
                .environmentObject(appLauncherStore)
                .environmentObject(screenshotCaptureController)
        }
        .defaultSize(width: 900, height: 650)
    }

}

private final class AirSentryAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleFinderNewFileNotification(_:)),
            name: .airSentryFinderNewFileRequest,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: .airSentryFinderNewFileRequest,
            object: nil
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NSLog("AirSentry received URL via NSApplicationDelegate: %{public}@", url.absoluteString)
            FinderNewFileRequestHandler.handle(url)
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            NSLog("AirSentry received malformed URL AppleEvent")
            return
        }

        NSLog("AirSentry received URL via AppleEvent: %{public}@", url.absoluteString)
        FinderNewFileRequestHandler.handle(url)
    }

    @objc private func handleFinderNewFileNotification(_ notification: Notification) {
        guard let message = notification.object as? String,
              let data = message.data(using: .utf8),
              let request = try? JSONDecoder().decode(FinderNewFileDistributedRequest.self, from: data) else {
            NSLog("AirSentry received malformed Finder new file notification")
            return
        }

        FinderNewFileRequestHandler.handle(path: request.path, contents: request.decodedContents)
    }
}

private enum FinderNewFileRequestHandler {
    static func handle(_ url: URL) {
        guard url.scheme == "airsentry",
              url.host == "finder",
              url.path == "/new-file",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let requestedPath = components.queryValue(named: "path") else {
            NSLog("AirSentry ignored unsupported URL: %{public}@", url.absoluteString)
            return
        }

        let contents = components.queryValue(named: "contents")
            .flatMap { Data(base64Encoded: $0) } ?? Data()
        handle(path: requestedPath, contents: contents)
    }

    static func handle(path: String, contents: Data) {
        let requestedURL = URL(fileURLWithPath: path)
        NSLog("AirSentry handling Finder new file request at %{public}@", requestedURL.path)

        switch FinderNewFileService.createFile(at: requestedURL, contents: contents) {
        case .created:
            return
        case .unauthorized:
            NSSound.beep()
            NSLog("AirSentry failed to create Finder file because target is not authorized: %{public}@", requestedURL.path)
            FinderNewFilePermissionPrompter.showUnauthorizedFolderAlert(for: requestedURL)
        case .writeFailed:
            NSSound.beep()
            NSLog("AirSentry failed to create Finder file after authorization matched: %{public}@", requestedURL.path)
            FinderNewFilePermissionPrompter.showWriteFailedAlert(for: requestedURL)
            return
        }
    }
}

private enum FinderNewFilePermissionPrompter {
    static func showUnauthorizedFolderAlert(for requestedURL: URL) {
        showAlert(
            messageText: "AirSentry 没有此文件夹的新建文件权限",
            informativeText: "请在工具箱的“超级右键 > 文件夹授权”中添加目标目录或它的上级目录。\n\n目标位置：\(requestedURL.deletingLastPathComponent().path)"
        )
    }

    static func showWriteFailedAlert(for requestedURL: URL) {
        showAlert(
            messageText: "AirSentry 未能在目标位置写入文件",
            informativeText: "目标目录可能不可写、位于受保护位置，或授权已经失效。请在工具箱的“超级右键 > 文件夹授权”中重新添加该目录或它的上级目录。\n\n目标位置：\(requestedURL.deletingLastPathComponent().path)"
        )
    }

    private static func showAlert(messageText: String, informativeText: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.addButton(withTitle: "打开授权设置")
            alert.addButton(withTitle: "取消")

            if alert.runModal() == .alertFirstButtonReturn {
                NotificationCenter.default.post(name: .airSentryOpenFinderAuthorizationSettings, object: nil)
            }
        }
    }
}

private struct FinderNewFileDistributedRequest: Codable {
    let path: String
    let contents: String

    var decodedContents: Data {
        Data(base64Encoded: contents) ?? Data()
    }
}

private extension Notification.Name {
    static let airSentryFinderNewFileRequest = Notification.Name("AirSentry.Finder.NewFileRequest")
    static let airSentryOpenFinderAuthorizationSettings = Notification.Name("AirSentry.OpenFinderAuthorizationSettings")
    static let airSentrySelectSuperRightClickToolboxSection = Notification.Name("AirSentry.SelectSuperRightClickToolboxSection")
}

private struct FinderAuthorizationSettingsWindowBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .airSentryOpenFinderAuthorizationSettings)) { _ in
                openWindow(id: "toolbox")
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .airSentrySelectSuperRightClickToolboxSection, object: nil)

                [0.05, 0.15, 0.35].forEach { delay in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        bringToolboxWindowToFront()
                        NotificationCenter.default.post(name: .airSentrySelectSuperRightClickToolboxSection, object: nil)
                    }
                }
            }
    }

    private func bringToolboxWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)

        guard let toolboxWindow = NSApp.windows.first(where: { $0.title == "工具箱" }) else {
            return
        }

        toolboxWindow.deminiaturize(nil)
        toolboxWindow.orderFrontRegardless()
        toolboxWindow.makeKeyAndOrderFront(nil)
    }
}

private extension URLComponents {
    func queryValue(named name: String) -> String? {
        queryItems?.first { $0.name == name }?.value
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitorStore: MonitorStore

    private var snapshot: SystemSnapshot {
        monitorStore.snapshot
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.thermal.level.symbolName)

            Text(title)
                .monospacedDigit()
        }
        .help(helpText)
    }

    private var title: String {
        if settings.menuBarShowsTemperature,
           let temperature = snapshot.thermal.temperatureCelsius {
            return temperature.formatted(.number.precision(.fractionLength(0))) + "°"
        }

        return snapshot.thermal.level.shortTitle
    }

    private var helpText: String {
        if let temperature = snapshot.thermal.temperatureCelsius {
            return "当前温度 \(temperature.formatted(.number.precision(.fractionLength(0))))°C，状态：\(snapshot.thermal.level.title)"
        }

        return "当前状态：\(snapshot.thermal.level.title)。真实温度暂不可用。"
    }
}
