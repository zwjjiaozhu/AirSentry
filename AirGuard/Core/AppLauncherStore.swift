import AppKit
import Foundation

@MainActor
final class AppLauncherStore: ObservableObject {
    @Published private(set) var applications: [AppLauncherItem] = []
    @Published var groups: [AppLauncherGroup] {
        didSet { saveGroups() }
    }
    @Published var selectedGroupID: UUID?
    @Published var searchText = ""
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?
    @Published private(set) var authorizedDirectories: [URL] = []

    private let reader = AppLauncherReader()
    private let defaults: UserDefaults
    private let authorizedDirectoryBookmarkKey = "appLauncherAuthorizedDirectoryBookmarks"
    private var accessingSecurityScopedURLs: [URL] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        groups = Self.loadGroups(from: defaults)
        selectedGroupID = nil
        restoreAuthorizedDirectories()
    }

    deinit {
        accessingSecurityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    var selectedGroup: AppLauncherGroup? {
        guard let selectedGroupID else { return nil }
        return groups.first { $0.id == selectedGroupID }
    }

    var visibleApplications: [AppLauncherItem] {
        let sourceApplications = selectedGroup.map(apps(in:)) ?? applications
        return sourceApplications.filter { app in
            let matchesSearch = searchText.isEmpty || app.searchableText.localizedCaseInsensitiveContains(searchText)
            return matchesSearch
        }
    }

    var ungroupedApplications: [AppLauncherItem] {
        let groupedIDs = Set(groups.flatMap(\.appIDs))
        return applications.filter { !groupedIDs.contains($0.id) }
    }

    func refreshApplications() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil

        let extraDirectories = authorizedDirectories
        let scanTask = Task.detached(priority: .utility) { [reader] in
            reader.scanApplications(in: extraDirectories)
        }

        Task { [weak self] in
            guard let self else { return }
            self.applications = await scanTask.value
            self.pruneMissingApps()
            self.isScanning = false
        }
    }

    func addAuthorizedDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择应用目录"
        panel.message = "授权后，程序收纳台会扫描该目录下的应用。可选择“个人 - 应用程序”来纳入 ~/Applications。"
        panel.prompt = "授权"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        if didAccess { accessingSecurityScopedURLs.append(url) }
        authorizedDirectories.append(url)
        saveAuthorizedDirectoryBookmarks()
        refreshApplications()
    }

    func removeAuthorizedDirectory(at index: Int) {
        guard authorizedDirectories.indices.contains(index) else { return }
        let url = authorizedDirectories.remove(at: index)
        url.stopAccessingSecurityScopedResource()
        accessingSecurityScopedURLs.removeAll { $0 == url }
        saveAuthorizedDirectoryBookmarks()
        refreshApplications()
    }

    private func restoreAuthorizedDirectories() {
        let bookmarks = defaults.array(forKey: authorizedDirectoryBookmarkKey) as? [Data] ?? []
        var restored: [URL] = []
        for data in bookmarks {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                let didAccess = url.startAccessingSecurityScopedResource()
                if didAccess { accessingSecurityScopedURLs.append(url) }
                restored.append(url)
            } catch {
                // 忽略失效的授权
            }
        }
        authorizedDirectories = restored
        if !restored.isEmpty {
            saveAuthorizedDirectoryBookmarks()
        }
    }

    private func saveAuthorizedDirectoryBookmarks() {
        let bookmarks = authorizedDirectories.compactMap { url -> Data? in
            try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        defaults.set(bookmarks, forKey: authorizedDirectoryBookmarkKey)
    }

    func launch(_ app: AppLauncherItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.errorMessage = "无法打开 \(app.name)：\(error.localizedDescription)"
            }
        }
    }

    func addGroup(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let group = AppLauncherGroup(name: trimmed)
        groups.append(group)
        selectedGroupID = group.id
    }

    func renameGroup(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = trimmed
    }

    func updateGroupColor(id: UUID, colorHex: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].colorHex = colorHex
    }

    func removeGroup(id: UUID) {
        guard groups.count > 1 else { return }
        groups.removeAll { $0.id == id }
        if selectedGroupID == id {
            selectedGroupID = groups.first?.id
        }
    }

    func moveGroup(id: UUID, near targetID: UUID) {
        guard id != targetID,
              let sourceIndex = groups.firstIndex(where: { $0.id == id }),
              let targetIndex = groups.firstIndex(where: { $0.id == targetID }) else { return }

        let group = groups.remove(at: sourceIndex)
        groups.insert(group, at: targetIndex)
    }

    func add(_ app: AppLauncherItem, to groupID: UUID) {
        addApp(id: app.id, to: groupID)
    }

    func addApp(id appID: String, to groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if !groups[index].appIDs.contains(appID) {
            groups[index].appIDs.append(appID)
        }
    }

    func remove(_ app: AppLauncherItem, from groupID: UUID) {
        removeApp(id: app.id, from: groupID)
    }

    func removeApp(id appID: String, from groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].appIDs.removeAll { $0 == appID }
    }

    func move(_ app: AppLauncherItem, to groupID: UUID) {
        moveApp(id: app.id, to: groupID)
    }

    func moveApp(id appID: String, to groupID: UUID) {
        for index in groups.indices {
            groups[index].appIDs.removeAll { $0 == appID }
        }
        addApp(id: appID, to: groupID)
    }

    func moveApp(id appID: String, near targetAppID: String, in groupID: UUID) {
        guard appID != targetAppID,
              let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              let sourceIndex = groups[groupIndex].appIDs.firstIndex(of: appID),
              let targetIndex = groups[groupIndex].appIDs.firstIndex(of: targetAppID) else { return }

        let movedAppID = groups[groupIndex].appIDs.remove(at: sourceIndex)
        groups[groupIndex].appIDs.insert(movedAppID, at: targetIndex)
    }

    func app(withID appID: String) -> AppLauncherItem? {
        applications.first { $0.id == appID }
    }

    func apps(in group: AppLauncherGroup) -> [AppLauncherItem] {
        group.appIDs.compactMap { app(withID: $0) }
    }

    private func pruneMissingApps() {
        let availableIDs = Set(applications.map(\.id))
        for index in groups.indices {
            groups[index].appIDs.removeAll { !availableIDs.contains($0) }
        }
    }

    private func saveGroups() {
        do {
            let data = try JSONEncoder().encode(groups)
            defaults.set(data, forKey: Keys.groups)
        } catch {
            NSLog("AirSentry app launcher groups save failed: \(error.localizedDescription)")
        }
    }

    private static func loadGroups(from defaults: UserDefaults) -> [AppLauncherGroup] {
        guard let data = defaults.data(forKey: Keys.groups),
              let decoded = try? JSONDecoder().decode([AppLauncherGroup].self, from: data),
              !decoded.isEmpty else {
            return [
                AppLauncherGroup(name: "常用", colorHex: "#0A84FF"),
                AppLauncherGroup(name: "开发", colorHex: "#32D74B"),
                AppLauncherGroup(name: "AI", colorHex: "#BF5AF2"),
                AppLauncherGroup(name: "设计", colorHex: "#FF9F0A"),
                AppLauncherGroup(name: "系统工具", colorHex: "#64D2FF")
            ]
        }
        return decoded
    }
}

private enum Keys {
    static let groups = "appLauncherGroups"
}
