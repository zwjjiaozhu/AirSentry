import Cocoa
import FinderSync
import os

final class FinderSync: FIFinderSync {
    
    // MARK: - 轻量模板元数据（不含 contents）
    
    /// 模板元数据（仅显示信息，不含文件内容）
    private struct TemplateMeta {
        let id: String
        let title: String
        let fileName: String
        let systemImage: String
    }
    
    /// 默认模板元数据
    private let defaultTemplateMetas: [TemplateMeta] = [
        TemplateMeta(id: "xlsx", title: "Excel 表格", fileName: "新建表格.xlsx", systemImage: "tablecells"),
        TemplateMeta(id: "pptx", title: "PowerPoint 演示", fileName: "新建演示.pptx", systemImage: "play.rectangle"),
        TemplateMeta(id: "docx", title: "Word 文档", fileName: "新建文档.docx", systemImage: "doc.richtext"),
        TemplateMeta(id: "txt", title: "纯文本", fileName: "新建文本.txt", systemImage: "doc.plaintext"),
        TemplateMeta(id: "md", title: "Markdown", fileName: "新建文档.md", systemImage: "number.square"),
        TemplateMeta(id: "csv", title: "CSV 表格", fileName: "新建表格.csv", systemImage: "list.bullet.rectangle"),
        TemplateMeta(id: "json", title: "JSON 配置", fileName: "新建配置.json", systemImage: "curlybraces.square"),
        TemplateMeta(id: "html", title: "HTML 页面", fileName: "新建页面.html", systemImage: "chevron.left.forwardslash.chevron.right")
    ]
    
    /// 默认启用的菜单项 ID
    private let defaultEnabledMenuItemIDs: Set<String> = ["newFile", "copyPath", "copyName", "openTerminal"]
    
    // MARK: - 缓存配置（避免重复读取）
    
    private var cachedEnabledMenuItemIDs: Set<String>?
    private var cachedTemplateMetas: [TemplateMeta]?
    private var lastConfigLoadTime: Date = .distantPast
    private let configCacheDuration: TimeInterval = 2.0
    
    // MARK: - 真实主目录（绕过沙盒容器路径）
    
    private static var realHomeDirectory: URL? {
        guard let pw = getpwuid(getuid()) else { return nil }
        return URL(fileURLWithFileSystemRepresentation: pw.pointee.pw_dir, isDirectory: true, relativeTo: nil)
    }
    
    // MARK: - 初始化
    
    override init() {
        super.init()
        let fm = FileManager.default
        var dirs: Set<URL> = [URL(fileURLWithPath: "/")]
        for searchPath: FileManager.SearchPathDirectory in [.desktopDirectory, .documentDirectory, .downloadsDirectory] {
            if let url = fm.urls(for: searchPath, in: .userDomainMask).first {
                dirs.insert(url)
            }
        }
        FIFinderSyncController.default().directoryURLs = dirs
        FinderExtensionLog.info("loaded")
    }
    
    // MARK: - 配置加载（从 JSON 文件读取）

    /// 加载轻量配置（缓存 2 秒，避免频繁读取）
    private func loadLightweightConfig() -> (enabledIDs: Set<String>, templates: [TemplateMeta]) {
        let now = Date()
        if now.timeIntervalSince(lastConfigLoadTime) < configCacheDuration,
           let cachedIDs = cachedEnabledMenuItemIDs,
           let cachedTemplates = cachedTemplateMetas {
            return (cachedIDs, cachedTemplates)
        }

        let config = SuperRightClickSharedConfig.load()

        let enabledIDs: Set<String>
        let templates: [TemplateMeta]

        if let config = config {
            enabledIDs = Set(config.enabledMenuItemIDs)
            templates = config.templates.map { meta in
                TemplateMeta(id: meta.id, title: meta.title, fileName: meta.fileName, systemImage: meta.systemImage)
            }
        } else {
            enabledIDs = defaultEnabledMenuItemIDs
            templates = defaultTemplateMetas
        }

        cachedEnabledMenuItemIDs = enabledIDs
        cachedTemplateMetas = templates.isEmpty ? defaultTemplateMetas : templates
        lastConfigLoadTime = now

        return (enabledIDs, cachedTemplateMetas ?? defaultTemplateMetas)
    }
    
    // MARK: - 菜单构建（轻量，不访问文件系统）
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        FinderExtensionLog.info("requested menu kind \(menuKind.rawValue)")
        
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }
        
        // 仅读取轻量配置，不访问文件系统
        let (enabledIDs, templateMetas) = loadLightweightConfig()
        
        let menu = NSMenu(title: "AirSentry")
        let rootItem = NSMenuItem(title: "AirSentry", action: nil, keyEquivalent: "")
        rootItem.image = menuImage(systemName: "filemenu.and.selection")
        let submenu = NSMenu(title: "AirSentry")
        
        // 1. 新建文件
        if enabledIDs.contains("newFile") && !templateMetas.isEmpty {
            let newFileItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
            newFileItem.image = menuImage(systemName: "doc.badge.plus")
            let newFileSubmenu = NSMenu(title: "新建文件")
            for meta in templateMetas {
                let item = NSMenuItem(title: meta.title, action: #selector(createNewFile(_:)), keyEquivalent: "")
                item.target = self
                item.image = menuImage(systemName: meta.systemImage)
                item.representedObject = meta.id
                newFileSubmenu.addItem(item)
            }
            newFileItem.submenu = newFileSubmenu
            submenu.addItem(newFileItem)
        }
        
        // 2. 其他应用打开（同组，无分隔线）
        if enabledIDs.contains("openWith") {
            let openWithItem = NSMenuItem(title: "其他应用打开", action: nil, keyEquivalent: "")
            openWithItem.image = menuImage(systemName: "app.badge")
            let openWithSubmenu = NSMenu(title: "其他应用打开")
            for (appName, bundleID, icon) in [
                ("Terminal", "com.apple.Terminal", "terminal"),
                ("iTerm", "com.googlecode.iterm2", "terminal.fill"),
                ("VS Code", "com.microsoft.VSCode", "chevron.left.forwardslash.chevron.right"),
                ("Sublime Text", "com.sublimetext.4", "doc.text"),
                ("选择其他应用…", "", "ellipsis.circle")
            ] {
                let item = NSMenuItem(title: appName, action: #selector(openWithApp(_:)), keyEquivalent: "")
                item.target = self
                item.image = menuImage(systemName: icon)
                item.representedObject = bundleID
                openWithSubmenu.addItem(item)
            }
            openWithItem.submenu = openWithSubmenu
            submenu.addItem(openWithItem)
        }
        
        // 3. 常用目录（同组，无分隔线）
        if enabledIDs.contains("favoriteFolders") {
            let foldersItem = NSMenuItem(title: "常用目录", action: nil, keyEquivalent: "")
            foldersItem.image = menuImage(systemName: "folder.badge.gearshape")
            let foldersSubmenu = NSMenu(title: "常用目录")
            for (name, path, icon) in [
                ("桌面", "~/Desktop", "desktopcomputer"),
                ("文稿", "~/Documents", "doc"),
                ("下载", "~/Downloads", "tray.and.arrow.down"),
                ("应用程序", "/Applications", "app"),
                ("拷贝当前路径", "", "doc.on.clipboard")
            ] {
                let item = NSMenuItem(title: name, action: #selector(favoriteFolderAction(_:)), keyEquivalent: "")
                item.target = self
                item.image = menuImage(systemName: icon)
                item.representedObject = path
                foldersSubmenu.addItem(item)
            }
            foldersItem.submenu = foldersSubmenu
            submenu.addItem(foldersItem)
        }
        
        // 4. 隔空投送
        if enabledIDs.contains("airdrop") {
            submenu.addItem(menuItem("隔空投送", systemImage: "airplayaudio", action: #selector(airdropAction)))
        }
        
        // 5. 拷贝路径
        if enabledIDs.contains("copyPath") {
            submenu.addItem(menuItem("拷贝路径", systemImage: "doc.on.clipboard", action: #selector(copySelectedPath)))
        }
        
        // 6. 拷贝名称
        if enabledIDs.contains("copyName") {
            submenu.addItem(menuItem("拷贝名称", systemImage: "tag", action: #selector(copySelectedName)))
        }
        
        // 7. 显示隐藏
        if enabledIDs.contains("showHidden") {
            submenu.addItem(menuItem("显示隐藏", systemImage: "eye", action: #selector(toggleShowHidden)))
        }
        
        // 8. 隐藏桌面
        if enabledIDs.contains("hideDesktop") {
            submenu.addItem(menuItem("隐藏桌面", systemImage: "desktopcomputer", action: #selector(toggleHideDesktop)))
        }
        
        rootItem.submenu = submenu
        menu.addItem(rootItem)
        return menu
    }
    
    // MARK: - 菜单动作（点击时才解析路径）
    
    @objc private func createNewFile(_ sender: NSMenuItem) {
        FinderExtensionLog.info("createNewFile called, title=\(sender.title)")
        
        // Finder Sync 不保留 representedObject，改用 title 查找模板
        let (_, templateMetas) = loadLightweightConfig()
        guard let meta = templateMetas.first(where: { $0.title == sender.title }) else {
            FinderExtensionLog.info("FAIL: no template for title=\(sender.title), available=\(templateMetas.map(\.title).joined(separator: ","))")
            NSSound.beep()
            return
        }
        let templateId = meta.id
        FinderExtensionLog.info("matched templateId=\(templateId)")
        
        guard let directoryURL = resolveTargetDirectoryForAction() else {
            FinderExtensionLog.info("FAIL: could not resolve target directory")
            NSSound.beep()
            return
        }
        FinderExtensionLog.info("directoryURL=\(directoryURL.path)")
        
        let fileURL = directoryURL.appendingPathComponent(meta.fileName)
        FinderExtensionLog.info("forwarding create: templateId=\(templateId), path=\(fileURL.path), isHostRunning=\(isHostAppRunning)")
        forwardFileCreationRequest(templateId: templateId, fileURL: fileURL)
    }
    
    @objc private func copySelectedPath() {
        guard let url = resolveTargetDirectoryForAction() else { return }
        FinderExtensionLog.info("copyPath: \(url.path)")
        forwardActionRequest(action: "copyPath", path: url.path, extra: nil)
    }
    
    @objc private func copySelectedName() {
        guard let url = resolveTargetDirectoryForAction() else { return }
        FinderExtensionLog.info("copyName: \(url.lastPathComponent)")
        forwardActionRequest(action: "copyName", path: url.lastPathComponent, extra: nil)
    }
    
    @objc private func openTerminal() {
        guard let directoryURL = resolveTargetDirectoryForAction() else {
            NSSound.beep()
            return
        }
        FinderExtensionLog.info("open terminal at \(directoryURL.path)")
        forwardOpenTerminalRequest(directoryPath: directoryURL.path)
    }
    
    @objc private func openWithApp(_ sender: NSMenuItem) {
        // 用 title 查找 bundleID（Finder Sync 不保留 representedObject）
        let bundleID: String
        switch sender.title {
        case "Terminal": bundleID = "com.apple.Terminal"
        case "iTerm": bundleID = "com.googlecode.iterm2"
        case "VS Code": bundleID = "com.microsoft.VSCode"
        case "Sublime Text": bundleID = "com.sublimetext.4"
        default: bundleID = ""
        }
        guard let targetURL = FIFinderSyncController.default().selectedItemURLs()?.first else {
            NSSound.beep()
            return
        }
        FinderExtensionLog.info("open with app=\(sender.title), bundleID=\(bundleID), target=\(targetURL.path)")
        forwardActionRequest(action: "openWith", path: targetURL.path, extra: bundleID)
    }
    
    @objc private func favoriteFolderAction(_ sender: NSMenuItem) {
        switch sender.title {
        case "拷贝当前路径":
            guard let url = resolveTargetDirectoryForAction() else { return }
            FinderExtensionLog.info("copyCurrentPath: \(url.path)")
            forwardActionRequest(action: "copyPath", path: url.path, extra: nil)
        default:
            guard let realHome = Self.realHomeDirectory else { return }
            let path: String
            switch sender.title {
            case "桌面": path = realHome.appendingPathComponent("Desktop").path
            case "文稿": path = realHome.appendingPathComponent("Documents").path
            case "下载": path = realHome.appendingPathComponent("Downloads").path
            case "应用程序": path = "/Applications"
            default: return
            }
            FinderExtensionLog.info("openFolder: \(path)")
            forwardActionRequest(action: "openFolder", path: path, extra: nil)
        }
    }
    
    @objc private func airdropAction() {
        guard let targetURL = FIFinderSyncController.default().selectedItemURLs()?.first else {
            NSSound.beep()
            return
        }
        FinderExtensionLog.info("airdrop: \(targetURL.path)")
        forwardActionRequest(action: "airdrop", path: targetURL.path, extra: nil)
    }
    
    @objc private func toggleShowHidden() {
        FinderExtensionLog.info("toggle show hidden files")
        forwardActionRequest(action: "toggleShowHidden", path: "", extra: nil)
    }
    
    @objc private func toggleHideDesktop() {
        FinderExtensionLog.info("toggle hide desktop icons")
        forwardActionRequest(action: "toggleHideDesktop", path: "", extra: nil)
    }
    
    // MARK: - 路径解析（仅在动作时调用）
    
    /// 解析目标目录（点击菜单项时调用，不检查 isPackage）
    private func resolveTargetDirectoryForAction() -> URL? {
        // 优先使用选中项
        if let selectedURL = FIFinderSyncController.default().selectedItemURLs()?.first {
            // 简单判断：如果有目录路径标识则直接使用，否则取父目录
            if selectedURL.hasDirectoryPath {
                return selectedURL
            }
            return selectedURL.deletingLastPathComponent()
        }
        
        // 回退到 targetedURL
        if let targetedURL = FIFinderSyncController.default().targetedURL() {
            if targetedURL.hasDirectoryPath {
                return targetedURL
            }
            return targetedURL.deletingLastPathComponent()
        }
        
        return nil
    }
    
    // MARK: - 请求转发
    
    private func forwardOpenTerminalRequest(directoryPath: String) {
        if isHostAppRunning {
            DistributedNotificationCenter.default().postNotificationName(
                .airSentryFinderOpenTerminalRequest,
                object: directoryPath,
                userInfo: nil,
                deliverImmediately: true
            )
            FinderExtensionLog.info("forwarded open terminal via notification: \(directoryPath)")
        } else {
            var components = URLComponents()
            components.scheme = "airsentry"
            components.host = "finder"
            components.path = "/open-terminal"
            components.queryItems = [URLQueryItem(name: "path", value: directoryPath)]
            
            if let url = components.url {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// 发送新建文件请求（只传 templateId + path）
    private func forwardFileCreationRequest(templateId: String, fileURL: URL) {
        if isHostAppRunning {
            let request = FinderNewFileRequest(templateId: templateId, path: fileURL.path)
            guard let data = try? JSONEncoder().encode(request),
                  let message = String(data: data, encoding: .utf8) else {
                return
            }
            
            DistributedNotificationCenter.default().postNotificationName(
                .airSentryFinderNewFileRequest,
                object: message,
                userInfo: nil,
                deliverImmediately: true
            )
            FinderExtensionLog.info("forwarded new file request via notification: templateId=\(templateId), path=\(fileURL.path)")
        } else {
            // URL Scheme 回退（主应用未运行时）
            var components = URLComponents()
            components.scheme = "airsentry"
            components.host = "finder"
            components.path = "/new-file"
            components.queryItems = [
                URLQueryItem(name: "templateId", value: templateId),
                URLQueryItem(name: "path", value: fileURL.path)
            ]
            
            if let url = components.url {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// 通用动作请求转发（openWith, airdrop 等）
    /// 统一用 JSON 编码到 object，避免 userInfo 跨进程不可靠
    private func forwardActionRequest(action: String, path: String, extra: String?) {
        let payload: [String: String] = extra != nil
            ? ["action": action, "path": path, "extra": extra!]
            : ["action": action, "path": path]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let message = String(data: data, encoding: .utf8) else {
            FinderExtensionLog.info("FAIL: could not encode action request: \(action)")
            return
        }

        if isHostAppRunning {
            DistributedNotificationCenter.default().postNotificationName(
                .airSentryFinderActionRequest,
                object: message,
                userInfo: nil,
                deliverImmediately: true
            )
            FinderExtensionLog.info("forwarded \(action) via notification: \(path)\(extra.map { ", extra=\($0)" } ?? "")")
        } else {
            var components = URLComponents()
            components.scheme = "airsentry"
            components.host = "finder"
            components.path = "/\(action)"
            var queryItems = [URLQueryItem(name: "path", value: path)]
            if let extra = extra {
                queryItems.append(URLQueryItem(name: "extra", value: extra))
            }
            components.queryItems = queryItems
            if let url = components.url {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func menuItem(_ title: String, systemImage: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = menuImage(systemName: systemImage)
        return item
    }
    
    private func menuImage(systemName: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image?.withSymbolConfiguration(configuration)
    }
}

// MARK: - 数据结构

/// 新建文件请求（只包含 templateId 和 path）
private struct FinderNewFileRequest: Codable {
    let templateId: String
    let path: String
}

// MARK: - 主应用检测

private extension FinderSync {
    var isHostAppRunning: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              bundleIdentifier.hasSuffix(".finderextension") else {
            return false
        }
        let hostBundleIdentifier = String(bundleIdentifier.dropLast(".finderextension".count))
        return !NSRunningApplication.runningApplications(withBundleIdentifier: hostBundleIdentifier).isEmpty
    }
}

// MARK: - 通知名称

private extension Notification.Name {
    static let airSentryFinderNewFileRequest = Notification.Name("AirSentry.Finder.NewFileRequest")
    static let airSentryFinderOpenTerminalRequest = Notification.Name("AirSentry.Finder.OpenTerminalRequest")
    static let airSentryFinderActionRequest = Notification.Name("AirSentry.Finder.ActionRequest")
}

// MARK: - 日志

private enum FinderExtensionLog {
    private static let logger = Logger(subsystem: "com.sjzm.airsentry.finderextension", category: "finder-sync")

    /// 日志目录：~/Library/Logs/AirSentry/
    private static var logDirectoryURL: URL? {
        guard let pw = getpwuid(getuid()) else { return nil }
        let home = URL(fileURLWithFileSystemRepresentation: pw.pointee.pw_dir, isDirectory: true, relativeTo: nil)
        let dir = home.appendingPathComponent("Library/Logs/AirSentry", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static let maxFileSizeBytes: UInt64 = 2 * 1024 * 1024
    private static let maxLogFiles = 20

    private static let fileTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let logLineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: "INFO", file: file, line: line)
    }

    static func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: "WARN", file: file, line: line)
    }

    static func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: "ERROR", file: file, line: line)
    }

    private static func log(_ message: String, level: String, file: String, line: Int) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = logLineFormatter.string(from: Date())
        let formattedLine = "\(timestamp) [FinderExt] [\(level)] [\(fileName):\(line)] \(message)\n"

        logger.log("AirSentry Finder extension [\(level, privacy: .public)] \(message, privacy: .public)")
        writeToFile(formattedLine)
    }

    private static func writeToFile(_ message: String) {
        guard let dir = logDirectoryURL else { return }
        let fileURL = currentLogFileURL(in: dir)
        guard let data = message.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: fileURL)
        }
        pruneOldLogs(in: dir)
    }

    /// 获取当前应写入的日志文件 URL（支持大小轮转）
    private static func currentLogFileURL(in dir: URL) -> URL {
        if let latest = listLogFiles(in: dir).first,
           let attrs = try? FileManager.default.attributesOfItem(atPath: latest.path),
           let size = attrs[.size] as? UInt64,
           size < maxFileSizeBytes {
            return latest
        }
        return createNewLogFile(in: dir)
    }

    private static func createNewLogFile(in dir: URL) -> URL {
        let timestamp = fileTimestampFormatter.string(from: Date())
        let fileName = "finder-extension-\(timestamp).log"
        let fileURL = dir.appendingPathComponent(fileName)
        let header = "# AirSentry Finder Extension log\n# Created: \(timestamp)\n\n"
        try? header.data(using: .utf8)?.write(to: fileURL)
        return fileURL
    }

    private static func listLogFiles(in dir: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("finder-extension") && $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    private static func pruneOldLogs(in dir: URL) {
        let files = listLogFiles(in: dir)
        guard files.count > maxLogFiles else { return }
        for file in files.suffix(from: maxLogFiles) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
