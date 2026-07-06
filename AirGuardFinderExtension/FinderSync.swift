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
    
    // MARK: - 初始化
    
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        FinderExtensionLog.info("loaded")
    }
    
    // MARK: - 配置加载（仅读取 App Group UserDefaults）
    
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
        
        // 新建文件（只存 templateId）
        if enabledIDs.contains("newFile") && !templateMetas.isEmpty {
            let newFileItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
            newFileItem.image = menuImage(systemName: "doc.badge.plus")
            let newFileSubmenu = NSMenu(title: "新建文件")
            for meta in templateMetas {
                let item = NSMenuItem(title: meta.title, action: #selector(createNewFile(_:)), keyEquivalent: "")
                item.target = self
                item.image = menuImage(systemName: meta.systemImage)
                item.representedObject = meta.id  // 只存 templateId
                newFileSubmenu.addItem(item)
            }
            newFileItem.submenu = newFileSubmenu
            submenu.addItem(newFileItem)
        }
        
        // 打开终端
        if enabledIDs.contains("openTerminal") {
            if submenu.numberOfItems > 0 { submenu.addItem(NSMenuItem.separator()) }
            submenu.addItem(menuItem("打开终端", systemImage: "terminal", action: #selector(openTerminal)))
        }
        
        // 拷贝路径
        if enabledIDs.contains("copyPath") {
            if submenu.numberOfItems > 0 && submenu.items.last != nil && !submenu.items.last!.isSeparatorItem {
                submenu.addItem(NSMenuItem.separator())
            }
            submenu.addItem(menuItem("拷贝路径", systemImage: "doc.on.clipboard", action: #selector(copySelectedPath)))
        }
        
        // 拷贝名称
        if enabledIDs.contains("copyName") {
            submenu.addItem(menuItem("拷贝名称", systemImage: "textformat.abc", action: #selector(copySelectedName)))
        }
        
        rootItem.submenu = submenu
        menu.addItem(rootItem)
        return menu
    }
    
    // MARK: - 菜单动作（点击时才解析路径）
    
    @objc private func createNewFile(_ sender: NSMenuItem) {
        // 点击时才获取 templateId 和目标路径
        guard let templateId = sender.representedObject as? String else {
            NSSound.beep()
            return
        }
        
        // 点击时才解析目标目录（不调用 isFinderDirectory）
        guard let directoryURL = resolveTargetDirectoryForAction() else {
            NSSound.beep()
            FinderExtensionLog.info("could not resolve target directory for new file")
            return
        }
        
        // 查找模板元数据获取文件名
        let (_, templateMetas) = loadLightweightConfig()
        guard let meta = templateMetas.first(where: { $0.id == templateId }) else {
            NSSound.beep()
            FinderExtensionLog.info("could not find template for id=\(templateId)")
            return
        }
        
        let fileURL = directoryURL.appendingPathComponent(meta.fileName)
        FinderExtensionLog.info("create new file: templateId=\(templateId), path=\(fileURL.path)")
        
        // 只发送 templateId + path 给主应用，由主应用负责创建文件
        forwardFileCreationRequest(templateId: templateId, fileURL: fileURL)
    }
    
    @objc private func copySelectedPath() {
        guard let url = resolveTargetDirectoryForAction() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
    
    @objc private func copySelectedName() {
        guard let url = resolveTargetDirectoryForAction() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.lastPathComponent, forType: .string)
    }
    
    @objc private func openTerminal() {
        guard let directoryURL = resolveTargetDirectoryForAction() else {
            NSSound.beep()
            return
        }
        FinderExtensionLog.info("open terminal at \(directoryURL.path)")
        forwardOpenTerminalRequest(directoryPath: directoryURL.path)
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
}

// MARK: - 日志

private enum FinderExtensionLog {
    private static let logger = Logger(subsystem: "com.sjzm.airsentry.finderextension", category: "finder-sync")
    
    static func info(_ message: String) {
        logger.info("AirSentry Finder extension \(message, privacy: .public)")
    }
}
