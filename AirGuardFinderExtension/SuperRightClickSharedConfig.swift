import Foundation

/// 超级右键功能的共享配置（轻量版，不含文件内容）
struct SuperRightClickSharedConfig: Codable {
    /// 启用的菜单项 ID 列表（按顺序）
    let enabledMenuItemIDs: [String]
    /// 启用的文件模板 ID 列表（按顺序）
    let enabledTemplateIDs: [String]
    /// 文件模板元数据（不含 contents，仅用于菜单显示）
    let templates: [TemplateMeta]

    /// 模板元数据（轻量）
    struct TemplateMeta: Codable {
        let id: String
        let title: String
        let fileName: String
        let systemImage: String
    }

    static let appGroupID = "group.com.sjzm.airsentry"
    private static let configKey = "superRightClickSharedConfig"

    /// App Group 共享 UserDefaults
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func load() -> SuperRightClickSharedConfig? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(SuperRightClickSharedConfig.self, from: data) else {
            return nil
        }
        return config
    }

    func save() {
        guard let defaults = Self.sharedDefaults else {
            NSLog("AirSentry: App Group UserDefaults is nil")
            return
        }
        do {
            let data = try JSONEncoder().encode(self)
            defaults.set(data, forKey: Self.configKey)
            NSLog("AirSentry saved config to App Group UserDefaults")
        } catch {
            NSLog("AirSentry failed to save config: %{public}@", error.localizedDescription)
        }
    }
}
