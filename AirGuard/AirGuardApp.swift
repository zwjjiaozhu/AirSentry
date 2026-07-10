import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers
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
    @StateObject private var floatingBallController: FloatingBallController
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
        _floatingBallController = StateObject(wrappedValue: FloatingBallController(settings: settings, screenshotCaptureController: screenshotCaptureController))
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
                .environmentObject(screenshotCaptureController)
                .frame(width: 400)
        } label: {
            MenuBarStatusLabel(settings: settings, monitorStore: monitorStore)
                .background(FinderAuthorizationSettingsWindowBridge())
                .background(FloatingBallSettingsWindowBridge())
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(alertManager)
                .environmentObject(agentMonitorStore)
                .frame(width: 860, height: 600)
        }

        Window("六边形工具箱-AirSentry", id: "toolbox") {
            ToolboxView()
                .environmentObject(settings)
                .environmentObject(appLauncherStore)
                .environmentObject(screenshotCaptureController)
        }
        .defaultSize(width: 900, height: 650)
    }

}

private final class AirSentryAppDelegate: NSObject, NSApplicationDelegate {
    /// 统一记录所有 Finder 扩展信号的日志
    private let finderLog = LogArchiver.shared

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

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleFinderOpenTerminalNotification(_:)),
            name: .airSentryFinderOpenTerminalRequest,
            object: nil
        )

        // 统一接收所有菜单动作信号（openWith / airdrop 等）
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleFinderActionNotification(_:)),
            name: .airSentryFinderActionRequest,
            object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        activateFinderExtensionIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: .airSentryFinderNewFileRequest,
            object: nil
        )
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: .airSentryFinderOpenTerminalRequest,
            object: nil
        )
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: .airSentryFinderActionRequest,
            object: nil
        )
    }

    // MARK: - Finder Extension Auto-Activation

    /// 在主应用启动时自动注册并激活 Finder Sync 扩展，
    /// 解决双击打开应用或杀掉重启后扩展未被加载的问题。
    private func activateFinderExtensionIfNeeded() {
        // App Sandbox 环境下无法执行 pluginkit/lsregister，跳过
        // App Store 版本依赖系统安装流程自动注册扩展
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else {
            NSLog("AirSentry: skipping Finder extension activation in sandboxed environment")
            return
        }

        // 仅当应用安装于 /Applications 时才激活扩展，
        // 避免从 Xcode DerivedData 或构建目录启动时产生重复注册条目
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasPrefix("/Applications/") else {
            NSLog("AirSentry: skipping Finder extension activation (app not in /Applications: %{public}@)", bundlePath)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            guard let pluginsURL = Bundle.main.builtInPlugInsURL,
                  let extensionURL = Self.findAppExtension(in: pluginsURL) else {
                NSLog("AirSentry: Finder extension not found in app bundle")
                return
            }

            // 1. 向 LaunchServices 重新注册，确保系统识别到扩展二进制
            let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            if FileManager.default.fileExists(atPath: lsregister) {
                let registerProc = Process()
                registerProc.executableURL = URL(fileURLWithPath: lsregister)
                registerProc.arguments = ["-f", Bundle.main.bundlePath]
                try? registerProc.run()
                registerProc.waitUntilExit()
                NSLog("AirSentry: LaunchServices registration completed")
            }

            // 2. 读取扩展的 Bundle Identifier
            guard let extBundle = Bundle(url: extensionURL),
                  let bundleID = extBundle.bundleIdentifier else {
                NSLog("AirSentry: could not read Finder extension bundle identifier")
                return
            }

            // 3. 使用 pluginkit 启用扩展（幂等操作，已启用时无副作用）
            let pluginkit = Process()
            pluginkit.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            pluginkit.arguments = ["-e", "use", "-i", bundleID]
            do {
                try pluginkit.run()
                pluginkit.waitUntilExit()
                if pluginkit.terminationStatus == 0 {
                    NSLog("AirSentry: Finder extension activated (bundleID=%{public}@)", bundleID)
                } else {
                    NSLog("AirSentry: pluginkit exited with status %d for bundleID=%{public}@",
                          pluginkit.terminationStatus, bundleID)
                }
            } catch {
                NSLog("AirSentry: failed to run pluginkit: %{public}@", error.localizedDescription)
            }
        }
    }

    /// 在 PlugIns 目录中查找 .appex 扩展包
    private static func findAppExtension(in pluginsURL: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: pluginsURL,
                                                          includingPropertiesForKeys: nil) else {
            return nil
        }
        return contents.first { $0.pathExtension == "appex" }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NSLog("AirSentry received URL via NSApplicationDelegate: %{public}@", url.absoluteString)
            FinderURLRouter.route(url)
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            NSLog("AirSentry received malformed URL AppleEvent")
            return
        }

        NSLog("AirSentry received URL via AppleEvent: %{public}@", url.absoluteString)
        FinderURLRouter.route(url)
    }

    @objc private func handleFinderNewFileNotification(_ notification: Notification) {
        FinderNewFileRequestHandler.logArchiver.info("notification received")
        guard let message = notification.object as? String,
              let data = message.data(using: .utf8),
              let request = try? JSONDecoder().decode(FinderNewFileRequest.self, from: data) else {
            FinderNewFileRequestHandler.logArchiver.error("malformed notification")
            finderLog.error("[NewFile] malformed notification")
            NSLog("AirSentry received malformed Finder new file notification")
            return
        }

        FinderNewFileRequestHandler.logArchiver.info("templateId=\(request.templateId), path=\(request.path)")
        finderLog.info("[NewFile] received, templateId=\(request.templateId), path=\(request.path)")
        let contents = FinderNewFileService.contents(forTemplateId: request.templateId)
        FinderNewFileRequestHandler.handle(path: request.path, contents: contents)
    }

    @objc private func handleFinderOpenTerminalNotification(_ notification: Notification) {
        guard let directoryPath = notification.object as? String else {
            finderLog.error("[OpenTerminal] malformed notification: object is nil")
            return
        }
        finderLog.info("[OpenTerminal] received, path=\(directoryPath)")
        FinderOpenTerminalRequestHandler.handle(directoryPath: directoryPath)
    }

    /// 统一接收 Finder 扩展的菜单动作信号，先打日志再分发
    @objc private func handleFinderActionNotification(_ notification: Notification) {
        guard let message = notification.object as? String,
              let data = message.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let action = payload["action"],
              let path = payload["path"] else {
            finderLog.error("[Action] malformed notification: could not parse JSON payload")
            NSLog("AirSentry received malformed Finder action notification")
            return
        }
        let extra = payload["extra"]

        // 统一打日志
        finderLog.info("[\(action)] received, path=\(path)\(extra.map { ", extra=\($0)" } ?? "")")

        // 分发到对应处理器
        switch action {
        case "openWith":
            FinderOpenWithRequestHandler.handle(path: path, bundleID: extra)
        case "airdrop":
            FinderShareRequestHandler.handleAirdrop(path: path)
        case "openFolder":
            FinderUtilityHandler.openFolder(path: path)
        case "copyPath":
            FinderUtilityHandler.copyToClipboard(text: path, label: "path")
        case "copyName":
            FinderUtilityHandler.copyToClipboard(text: path, label: "name")
        case "toggleShowHidden":
            FinderUtilityHandler.toggleShowHidden()
        case "toggleHideDesktop":
            FinderUtilityHandler.toggleHideDesktop()
        default:
            finderLog.warning("[\(action)] unknown action, ignored")
        }
    }
}

private enum FinderNewFileRequestHandler {
    static let logArchiver = LogArchiver.shared

    static func handle(_ url: URL) {
        guard url.scheme == "airsentry",
              url.host == "finder",
              url.path == "/new-file",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let templateId = components.queryValue(named: "templateId"),
              let requestedPath = components.queryValue(named: "path") else {
            NSLog("AirSentry ignored unsupported URL: %{public}@", url.absoluteString)
            return
        }

        // 根据 templateId 查找模板内容
        let contents = FinderNewFileService.contents(forTemplateId: templateId)
        handle(path: requestedPath, contents: contents)
    }

    static func handle(path: String, contents: Data) {
        let requestedURL = URL(fileURLWithPath: path)
        logArchiver.info("path=\(requestedURL.path), contentsSize=\(contents.count)")
        NSLog("AirSentry handling Finder new file request at %{public}@", requestedURL.path)

        switch FinderNewFileService.createFile(at: requestedURL, contents: contents) {
        case .created(let fileURL):
            logArchiver.info("created \(fileURL.path)")
            return
        case .unauthorized:
            logArchiver.error("unauthorized for \(requestedURL.path)")
            NSSound.beep()
            NSLog("AirSentry failed to create Finder file because target is not authorized: %{public}@", requestedURL.path)
            FinderNewFilePermissionPrompter.showUnauthorizedFolderAlert(for: requestedURL)
        case .writeFailed(let fileURL):
            logArchiver.error("writeFailed at \(fileURL.path)")
            NSSound.beep()
            NSLog("AirSentry failed to create Finder file after authorization matched: %{public}@", requestedURL.path)
            FinderNewFilePermissionPrompter.showWriteFailedAlert(for: requestedURL)
            return
        }
    }
}

private enum FinderOpenTerminalRequestHandler {
    static func handle(_ url: URL) {
        guard url.scheme == "airsentry",
              url.host == "finder",
              url.path == "/open-terminal",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let requestedPath = components.queryValue(named: "path") else {
            NSLog("AirSentry ignored unsupported open-terminal URL: %{public}@", url.absoluteString)
            return
        }

        handle(directoryPath: requestedPath)
    }

    static func handle(directoryPath: String) {
        NSLog("AirSentry handling open terminal request at %{public}@", directoryPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", directoryPath]
        do {
            try process.run()
        } catch {
            NSLog("AirSentry failed to open terminal: %{public}@", error.localizedDescription)
        }
    }
}

private enum FinderURLRouter {
    static func route(_ url: URL) {
        guard url.scheme == "airsentry", url.host == "finder" else {
            NSLog("AirSentry ignored non-finder URL: %{public}@", url.absoluteString)
            return
        }
        switch url.path {
        case "/new-file":
            FinderNewFileRequestHandler.handle(url)
        case "/open-terminal":
            FinderOpenTerminalRequestHandler.handle(url)
        case "/openWith":
            FinderOpenWithRequestHandler.handle(url)
        case "/airdrop":
            FinderShareRequestHandler.handleAirdrop(url)
        case "/openFolder":
            if let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryValue(named: "path") {
                FinderUtilityHandler.openFolder(path: path)
            }
        case "/copyPath", "/copyName":
            if let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryValue(named: "path") {
                let label = url.path == "/copyPath" ? "path" : "name"
                FinderUtilityHandler.copyToClipboard(text: path, label: label)
            }
        case "/toggleShowHidden":
            FinderUtilityHandler.toggleShowHidden()
        case "/toggleHideDesktop":
            FinderUtilityHandler.toggleHideDesktop()
        default:
            NSLog("AirSentry ignored unknown finder URL path: %{public}@", url.path)
        }
    }
}

private enum FinderOpenWithRequestHandler {
    static func handle(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryValue(named: "path") else {
            NSLog("AirSentry ignored malformed openWith URL: %{public}@", url.absoluteString)
            return
        }
        let bundleID = components.queryValue(named: "extra")
        handle(path: path, bundleID: bundleID)
    }

    static func handle(path: String, bundleID: String?) {
        NSLog("AirSentry handling openWith: path=%{public}@, bundleID=%{public}@", path, bundleID ?? "(choose)")
        let fileURL = URL(fileURLWithPath: path)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            if let bundleID = bundleID, !bundleID.isEmpty {
                // 用指定应用打开
                let workspace = NSWorkspace.shared
                let config = NSWorkspace.OpenConfiguration()
                if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                    workspace.open([fileURL], withApplicationAt: appURL, configuration: config) { app, error in
                        if let error = error {
                            NSLog("AirSentry failed to open with app %{public}@: %{public}@", bundleID, error.localizedDescription)
                            NSSound.beep()
                        }
                    }
                } else {
                    NSLog("AirSentry could not find app with bundleID: %{public}@", bundleID)
                    NSSound.beep()
                    showAppNotFoundAlert(bundleID: bundleID)
                }
            } else {
                // 选择其他应用：弹出系统打开方式面板
                let panel = NSOpenPanel()
                panel.title = "选择应用打开"
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.allowedContentTypes = [.application]
                panel.message = "请选择要打开 \(fileURL.lastPathComponent) 的应用："
                if panel.runModal() == .OK, let appURL = panel.url {
                    let config = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config) { _, error in
                        if let error = error {
                            NSLog("AirSentry failed to open with chosen app: %{public}@", error.localizedDescription)
                            NSSound.beep()
                        }
                    }
                }
            }
        }
    }

    private static func showAppNotFoundAlert(bundleID: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "未找到应用"
        var appName = bundleID
        switch bundleID {
        case "com.googlecode.iterm2": appName = "iTerm2"
        case "com.microsoft.VSCode": appName = "Visual Studio Code"
        case "com.sublimetext.4": appName = "Sublime Text"
        default: break
        }
        alert.informativeText = "未检测到已安装的 \(appName)（\(bundleID)）。请确认该应用已安装后重试。"
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}

private enum FinderShareRequestHandler {

    // MARK: - 宿主窗口（分享面板需要窗口上下文才能显示）

    private final class HostingWindowController {
        static let shared = HostingWindowController()
        var window: NSWindow?

        func makeKeyWindow() -> NSWindow {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                win.setFrameOrigin(NSPoint(x: frame.midX, y: frame.midY))
            }
            win.orderFrontRegardless()
            self.window = win
            return win
        }

        func dismiss() {
            window?.close()
            window = nil
        }
    }

    // MARK: - 隔空投送

    static func handleAirdrop(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryValue(named: "path") else { return }
        performAirDrop(path: path)
    }

    static func handleAirdrop(path: String) {
        performAirDrop(path: path)
    }

    private static func performAirDrop(path: String) {
        NSLog("AirSentry performing AirDrop: %{public}@", path)
        let fileURL = URL(fileURLWithPath: path)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let service = NSSharingService(named: .sendViaAirDrop),
               service.canPerform(withItems: [fileURL]) {
                let hosting = HostingWindowController.shared
                let hostWindow = hosting.makeKeyWindow()
                let delegate = AirDropServiceDelegate(onFinish: { hosting.dismiss() })
                service.delegate = delegate
                objc_setAssociatedObject(service, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                service.perform(withItems: [fileURL])
                // 将服务附着到宿主窗口
                objc_setAssociatedObject(hostWindow, "service", service, .OBJC_ASSOCIATION_RETAIN)
            } else {
                NSSound.beep()
                NSLog("AirSentry: AirDrop not available for this file")
            }
        }
    }

    private final class AirDropServiceDelegate: NSObject, NSSharingServiceDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [onFinish] in onFinish() }
        }
        func sharingService(_ service: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            NSLog("AirSentry AirDrop failed: %{public}@", error.localizedDescription)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [onFinish] in onFinish() }
        }
    }
}

private enum FinderUtilityHandler {

    /// 在 Finder 中打开文件夹
    static func openFolder(path: String) {
        let url = URL(fileURLWithPath: path)
        DispatchQueue.main.async {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        }
    }

    /// 拷贝文本到剪贴板
    static func copyToClipboard(text: String, label: String) {
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            NSLog("AirSentry copied %{public}@: %{public}@", label, text)
        }
    }

    /// 切换隐藏文件可见性
    static func toggleShowHidden() {
        let current = UserDefaults.standard.bool(forKey: "AppleShowAllFiles")
        let newValue = !current
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", newValue ? "YES" : "NO"]
        try? process.run()
        process.waitUntilExit()
        relaunchFinder()
    }

    /// 切换桌面图标显示
    static func toggleHideDesktop() {
        let current: Bool
        if let val = UserDefaults.standard.object(forKey: "CreateDesktop") as? Bool {
            current = val
        } else {
            current = true
        }
        let newValue = !current
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", newValue ? "YES" : "NO"]
        try? process.run()
        process.waitUntilExit()
        relaunchFinder()
    }

    private static func relaunchFinder() {
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["Finder"]
        try? killall.run()
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

private struct FinderNewFileRequest: Codable {
    let templateId: String
    let path: String
}

extension Notification.Name {
    static let airSentryFinderNewFileRequest = Notification.Name("AirSentry.Finder.NewFileRequest")
    static let airSentryFinderOpenTerminalRequest = Notification.Name("AirSentry.Finder.OpenTerminalRequest")
    static let airSentryFinderActionRequest = Notification.Name("AirSentry.Finder.ActionRequest")
    static let airSentryOpenFinderAuthorizationSettings = Notification.Name("AirSentry.OpenFinderAuthorizationSettings")
    static let airSentrySelectSuperRightClickToolboxSection = Notification.Name("AirSentry.SelectSuperRightClickToolboxSection")
    static let openFloatingBallSettings = Notification.Name("AirSentry.OpenFloatingBallSettings")
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

private struct FloatingBallSettingsWindowBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openFloatingBallSettings)) { _ in
                openWindow(id: "toolbox")
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .selectToolboxSection, object: "floatingBall")

                [0.05, 0.15, 0.35].forEach { delay in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        bringToolboxWindowToFront()
                        NotificationCenter.default.post(name: .selectToolboxSection, object: "floatingBall")
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
