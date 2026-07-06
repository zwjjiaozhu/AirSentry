import Cocoa
import FinderSync
import os

final class FinderSync: FIFinderSync {
    private var menuTargetDirectoryURL: URL?

    private let templates: [NewFileTemplate] = [
        NewFileTemplate(title: "Excel 表格", fileName: "新建表格.xlsx", systemImage: "tablecells", contents: Data()),
        NewFileTemplate(title: "PowerPoint 演示", fileName: "新建演示.pptx", systemImage: "play.rectangle", contents: Data()),
        NewFileTemplate(title: "Word 文档", fileName: "新建文档.docx", systemImage: "doc.richtext", contents: Data()),
        NewFileTemplate(title: "纯文本", fileName: "新建文本.txt", systemImage: "doc.plaintext", contents: Data()),
        NewFileTemplate(title: "Markdown", fileName: "新建文档.md", systemImage: "number.square", contents: Data("# 新建文档\n".utf8)),
        NewFileTemplate(title: "CSV 表格", fileName: "新建表格.csv", systemImage: "list.bullet.rectangle", contents: Data()),
        NewFileTemplate(title: "JSON 配置", fileName: "新建配置.json", systemImage: "curlybraces.square", contents: Data("{\n  \n}\n".utf8)),
        NewFileTemplate(title: "HTML 页面", fileName: "新建页面.html", systemImage: "chevron.left.forwardslash.chevron.right", contents: Data("<!doctype html>\n<html>\n<head>\n  <meta charset=\"utf-8\">\n  <title>新建页面</title>\n</head>\n<body>\n</body>\n</html>\n".utf8))
    ]

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        FinderExtensionLog.info("loaded")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        FinderExtensionLog.info("requested menu kind \(menuKind.rawValue)")

        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }

        let targetDirectoryURL = resolveTargetDirectoryURL()
        menuTargetDirectoryURL = targetDirectoryURL
        FinderExtensionLog.info("menu target directory \(targetDirectoryURL?.path ?? "nil")")

        let menu = NSMenu(title: "AirSentry")
        let rootItem = NSMenuItem(title: "AirSentry", action: nil, keyEquivalent: "")
        rootItem.image = menuImage(systemName: "filemenu.and.selection")
        let submenu = NSMenu(title: "AirSentry")

        let newFileItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        newFileItem.image = menuImage(systemName: "doc.badge.plus")
        let newFileSubmenu = NSMenu(title: "新建文件")
        for template in templates {
            let item = NSMenuItem(title: template.title, action: #selector(createNewFile(_:)), keyEquivalent: "")
            item.target = self
            item.image = menuImage(systemName: template.systemImage)
            item.representedObject = NewFileMenuRequest(template: template, directoryURL: targetDirectoryURL)
            FinderExtensionLog.info("attached new file request template=\(template.fileName), directory=\(targetDirectoryURL?.path ?? "nil")")
            newFileSubmenu.addItem(item)
        }
        newFileItem.submenu = newFileSubmenu
        submenu.addItem(newFileItem)
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(menuItem("拷贝路径", systemImage: "doc.on.clipboard", action: #selector(copySelectedPath)))
        submenu.addItem(menuItem("拷贝名称", systemImage: "textformat.abc", action: #selector(copySelectedName)))
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(menuItem("打开终端", systemImage: "terminal", action: #selector(openTerminal)))

        rootItem.submenu = submenu
        menu.addItem(rootItem)
        return menu
    }

    @objc private func createNewFile(_ sender: NSMenuItem) {
        let request = sender.representedObject as? NewFileMenuRequest
        guard let template = request?.template ?? templates.first(where: { $0.title == sender.title }) else {
            NSSound.beep()
            FinderExtensionLog.info("could not resolve new file template for item=\(sender.title), representedObject=\(String(describing: sender.representedObject))")
            return
        }

        guard let directoryURL = targetDirectoryURL(fallback: request?.directoryURL ?? menuTargetDirectoryURL) else {
            NSSound.beep()
            FinderExtensionLog.info("could not resolve target directory, fallback=\(request?.directoryURL?.path ?? menuTargetDirectoryURL?.path ?? "nil")")
            return
        }

        let fileURL = directoryURL.appendingPathComponent(template.fileName)
        FinderExtensionLog.info("create requested at \(fileURL.path)")

        guard forwardFileCreationRequest(fileURL: fileURL, contents: template.contents) else {
            NSSound.beep()
            FinderExtensionLog.info("failed to forward file creation request for \(fileURL.path)")
            return
        }
    }

    @objc private func copySelectedPath() {
        guard let text = selectedURLs().first?.path ?? targetDirectoryURL()?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func copySelectedName() {
        guard let text = selectedURLs().first?.lastPathComponent ?? targetDirectoryURL()?.lastPathComponent else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openTerminal() {
        guard let directoryURL = targetDirectoryURL() else {
            NSSound.beep()
            FinderExtensionLog.info("could not resolve target directory for terminal")
            return
        }
        FinderExtensionLog.info("open terminal at \(directoryURL.path)")
        forwardOpenTerminalRequest(directoryPath: directoryURL.path)
    }

    private func forwardOpenTerminalRequest(directoryPath: String) {
        if isHostAppRunning {
            DistributedNotificationCenter.default().postNotificationName(
                .airSentryFinderOpenTerminalRequest,
                object: directoryPath,
                userInfo: nil,
                deliverImmediately: true
            )
            FinderExtensionLog.info("forwarded open terminal request through distributed notification for \(directoryPath)")
        } else {
            var components = URLComponents()
            components.scheme = "airsentry"
            components.host = "finder"
            components.path = "/open-terminal"
            components.queryItems = [URLQueryItem(name: "path", value: directoryPath)]

            if let url = components.url {
                let opened = NSWorkspace.shared.open(url)
                FinderExtensionLog.info("forwarded open terminal request through URL scheme: opened=\(opened)")
            }
        }
    }

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

    private func targetDirectoryURL(fallback: URL? = nil) -> URL? {
        resolveTargetDirectoryURL() ?? menuTargetDirectoryURL ?? fallback
    }

    private func resolveTargetDirectoryURL() -> URL? {
        if let selectedURL = selectedURLs().first {
            return isFinderDirectory(selectedURL) ? selectedURL : selectedURL.deletingLastPathComponent()
        }

        if let targetedURL = FIFinderSyncController.default().targetedURL() {
            return isFinderDirectory(targetedURL) ? targetedURL : targetedURL.deletingLastPathComponent()
        }

        return nil
    }

    private func selectedURLs() -> [URL] {
        FIFinderSyncController.default().selectedItemURLs() ?? []
    }

    private func isFinderDirectory(_ url: URL) -> Bool {
        guard url.hasDirectoryPath else { return false }

        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        return !isPackage
    }

    private func forwardFileCreationRequest(fileURL: URL, contents: Data) -> Bool {
        if isHostAppRunning {
            let request = FinderNewFileDistributedRequest(path: fileURL.path, contents: contents.base64EncodedString())
            guard let data = try? JSONEncoder().encode(request),
                  let message = String(data: data, encoding: .utf8) else {
                return false
            }

            DistributedNotificationCenter.default().postNotificationName(
                .airSentryFinderNewFileRequest,
                object: message,
                userInfo: nil,
                deliverImmediately: true
            )
            FinderExtensionLog.info("forwarded file creation request through distributed notification for \(fileURL.path)")
            return true
        }

        return openHostAppToCreateFile(at: fileURL, contents: contents)
    }

    private func openHostAppToCreateFile(at fileURL: URL, contents: Data) -> Bool {
        var components = URLComponents()
        components.scheme = "airsentry"
        components.host = "finder"
        components.path = "/new-file"
        components.queryItems = [
            URLQueryItem(name: "path", value: fileURL.path),
            URLQueryItem(name: "contents", value: contents.base64EncodedString())
        ]

        guard let url = components.url else {
            return false
        }

        let opened = NSWorkspace.shared.open(url)
        FinderExtensionLog.info("forwarded file creation request through URL scheme: opened=\(opened)")
        return opened
    }
}

private struct NewFileTemplate {
    let title: String
    let fileName: String
    let systemImage: String
    let contents: Data
}

private final class NewFileMenuRequest: NSObject {
    let template: NewFileTemplate
    let directoryURL: URL?

    init(template: NewFileTemplate, directoryURL: URL?) {
        self.template = template
        self.directoryURL = directoryURL
    }
}

private struct FinderNewFileDistributedRequest: Codable {
    let path: String
    let contents: String
}

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

private extension Notification.Name {
    static let airSentryFinderNewFileRequest = Notification.Name("AirSentry.Finder.NewFileRequest")
    static let airSentryFinderOpenTerminalRequest = Notification.Name("AirSentry.Finder.OpenTerminalRequest")
}

private enum FinderExtensionLog {
    private static let logger = Logger(subsystem: "com.sjzm.airsentry.finderextension", category: "finder-sync")

    static func info(_ message: String) {
        logger.info("AirSentry Finder extension \(message, privacy: .public)")
    }
}
