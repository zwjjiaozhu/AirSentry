import Foundation

/// 超级右键功能的共享配置（轻量版，不含文件内容）
struct SuperRightClickSharedConfig: Codable {
    /// 启用的菜单项 ID 列表（按顺序）
    let enabledMenuItemIDs: [String]
    /// 启用的文件模板 ID 列表（按顺序）
    let enabledTemplateIDs: [String]
    /// 文件模板元数据（不含 contents，仅用于菜单显示）
    let templates: [TemplateMeta]
    /// “其他应用打开”子菜单中的应用列表（按顺序）
    let openWithApps: [OpenWithAppMeta]
    /// "常用目录"子菜单中的目录列表（按顺序）
    let favoriteFolders: [FavoriteFolderMeta]
    /// “重命名”面板字段列表（按顺序）
    let renameFields: [RenameFieldMeta]?
    /// 是否在右键菜单中显示菜单栏（AirSentry 子菜单）
    let showMenuBar: Bool

    /// 模板元数据（轻量）
    struct TemplateMeta: Codable {
        let id: String
        let title: String
        let fileName: String
        let systemImage: String
    }

    /// “其他应用打开”中的应用元数据
    struct OpenWithAppMeta: Codable {
        let id: String
        let name: String
        let bundleID: String
        let systemImage: String
    }

    /// “常用目录”中的目录元数据
    struct FavoriteFolderMeta: Codable {
        let id: String
        let name: String
        let path: String
        let systemImage: String
    }

    /// “重命名”面板字段元数据
    struct RenameFieldMeta: Codable {
        let id: String
        let title: String
        let systemImage: String
    }

    // MARK: - 文件共享配置（替代 App Group UserDefaults）

    private static let appSupportSubdir = "AirSentry"
    private static let configFileName = "super_right_click_config.json"

    /// 获取真实主目录（绕过沙盒容器路径）
    private static var realHomeDirectory: URL? {
        guard let pw = getpwuid(getuid()) else { return nil }
        return URL(fileURLWithFileSystemRepresentation: pw.pointee.pw_dir, isDirectory: true, relativeTo: nil)
    }

    /// 共享配置目录：~/Library/Application Support/AirSentry/
    static var sharedDirectoryURL: URL? {
        guard let home = realHomeDirectory else { return nil }
        let dir = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(appSupportSubdir, isDirectory: true)
        return dir
    }

    /// 配置文件路径
    private static var configFileURL: URL? {
        sharedDirectoryURL?.appendingPathComponent(configFileName)
    }

    /// 从 JSON 文件加载配置
    static func load() -> SuperRightClickSharedConfig? {
        guard let url = configFileURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SuperRightClickSharedConfig.self, from: data)
    }

    /// 保存配置到 JSON 文件
    func save() {
        guard let url = Self.configFileURL else {
            NSLog("AirSentry: could not resolve shared config path")
            return
        }
        do {
            // 确保目录存在
            let dir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
            NSLog("AirSentry saved config to %{public}@", url.path)
        } catch {
            NSLog("AirSentry failed to save config: %{public}@", error.localizedDescription)
        }
    }
}
