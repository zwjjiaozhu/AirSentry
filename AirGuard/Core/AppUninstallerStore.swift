import AppKit
import Combine
import Foundation

@MainActor
final class AppUninstallerStore: ObservableObject {
    enum SortOption: String, CaseIterable, Identifiable {
        case name = "名称"
        case size = "大小"
        case lastUsed = "最近使用"

        var id: String { rawValue }
    }

    @Published private(set) var filteredApplications: [InstalledAppInfo] = []
    @Published private(set) var isBackfillingSizes = false
    @Published private(set) var applications: [InstalledAppInfo] = []
    @Published private(set) var plan: AppUninstallPlan?
    @Published private(set) var selectedArtifactIDs: Set<String> = []
    @Published private(set) var isScanningApplications = false
    @Published private(set) var isBuildingPlan = false
    @Published private(set) var isTrashing = false
    @Published private(set) var hasHomeAccess = false
    @Published private(set) var hasApplicationsAccess = false
    @Published private(set) var selectedHomePath: String?
    @Published private(set) var selectedApplicationsPath: String?
    @Published var searchText = ""
    @Published var sortOption: SortOption = .name
    @Published var errorMessage: String?
    @Published var lastTrashSummary: String?
    @Published private(set) var trashLogs: [String] = []

    private let bookmarkKey = "appUninstallerHomeBookmark"
    private let applicationsBookmarkKey = "appUninstallerApplicationsBookmark"
    private let reader = AppUninstallerReader()
    private var homeURL: URL?
    private var applicationsURL: URL?
    private var isAccessingSecurityScopedResource = false
    private var isAccessingApplicationsSecurityScopedResource = false
    private var sizeBackfillTask: Task<Void, Never>?

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let airSentryDir = dir.appendingPathComponent("AirSentry", isDirectory: true)
        if !FileManager.default.fileExists(atPath: airSentryDir.path) {
            try? FileManager.default.createDirectory(at: airSentryDir, withIntermediateDirectories: true)
        }
        return airSentryDir.appendingPathComponent("UninstalledAppsCache.json")
    }()

    init() {
        restoreBookmark()
        restoreApplicationsBookmark()
        loadCachedApplications()

        // 当 applications / searchText / sortOption 变化时自动更新 filteredApplications
        Publishers.CombineLatest3($applications, $searchText, $sortOption)
            .map { apps, search, sort in
                let filtered = apps.filter { app in
                    search.isEmpty ||
                    app.name.localizedCaseInsensitiveContains(search) ||
                    (app.bundleIdentifier?.localizedCaseInsensitiveContains(search) ?? false)
                }
                switch sort {
                case .name:
                    return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                case .size:
                    return filtered.sorted { $0.bytes > $1.bytes }
                case .lastUsed:
                    return filtered.sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
                }
            }
            .assign(to: &$filteredApplications)
    }

    deinit {
        sizeBackfillTask?.cancel()
        if isAccessingSecurityScopedResource {
            homeURL?.stopAccessingSecurityScopedResource()
        }
        if isAccessingApplicationsSecurityScopedResource {
            applicationsURL?.stopAccessingSecurityScopedResource()
        }
    }

    var selectedBytes: UInt64 {
        guard let plan else { return 0 }
        return plan.artifacts
            .filter { selectedArtifactIDs.contains($0.id) }
            .reduce(0) { $0 + $1.bytes }
    }

    var selectedCount: Int {
        selectedArtifactIDs.count
    }

    func refreshApplications(force: Bool = false) {
        guard !isScanningApplications else { return }
        // 有缓存且非强制刷新时跳过扫描
        if !force && !applications.isEmpty { return }
        isScanningApplications = true
        errorMessage = nil

        let scanTask = Task.detached(priority: .utility) { [reader] in
            reader.scanApplications()
        }
        Task { [weak self] in
            guard let self else { return }
            let applications = await scanTask.value
            self.applications = applications
            self.isScanningApplications = false
            self.saveCachedApplications()
            self.backfillSizes()

            if let selectedApp = self.plan?.app,
               let refreshed = applications.first(where: { $0.id == selectedApp.id }) {
                self.select(refreshed)
            }
        }
    }

    /// 后台分批计算应用体积并逐个更新
    private func backfillSizes() {
        sizeBackfillTask?.cancel()
        isBackfillingSizes = true
        sizeBackfillTask = Task { [weak self, reader] in
            guard let self else { return }
            let apps = self.applications
            for (index, app) in apps.enumerated() {
                guard !Task.isCancelled else { break }
                let size = await reader.computeSize(for: app)
                await MainActor.run {
                    guard index < self.applications.count else { return }
                    if self.applications[index].id == app.id {
                        self.applications[index].bytes = size
                    }
                }
            }
            await MainActor.run {
                self.isBackfillingSizes = false
                self.saveCachedApplications()
            }
        }
    }

    func requestApplicationsAccess() {
        let panel = NSOpenPanel()
        panel.title = "选择应用目录"
        panel.message = "AirSentry 需要应用目录的读写授权，才能把应用本体移入废纸篓。"
        panel.prompt = "允许管理"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            bringToolboxWindowToFront()
            return
        }
        bringToolboxWindowToFront()
        setApplicationsURL(selectedURL, saveBookmark: true)
        refreshApplications()
        if let app = plan?.app {
            select(app)
        }
    }

    func requestHomeAccess() {
        let panel = NSOpenPanel()
        panel.title = "选择个人文件夹"
        panel.message = "AirSentry 将扫描其中的 Library 目录，用来识别应用缓存、偏好设置和容器残留。"
        panel.prompt = "允许扫描"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            bringToolboxWindowToFront()
            return
        }
        bringToolboxWindowToFront()
        setHomeURL(selectedURL, saveBookmark: true)
        if let app = plan?.app {
            select(app)
        }
    }

    func clearHomeAccess() {
        if isAccessingSecurityScopedResource {
            homeURL?.stopAccessingSecurityScopedResource()
            isAccessingSecurityScopedResource = false
        }
        homeURL = nil
        selectedHomePath = nil
        hasHomeAccess = false
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        if let app = plan?.app {
            select(app)
        }
    }

    func clearApplicationsAccess() {
        if isAccessingApplicationsSecurityScopedResource {
            applicationsURL?.stopAccessingSecurityScopedResource()
            isAccessingApplicationsSecurityScopedResource = false
        }
        applicationsURL = nil
        selectedApplicationsPath = nil
        hasApplicationsAccess = false
        UserDefaults.standard.removeObject(forKey: applicationsBookmarkKey)
        refreshApplications()
        if let app = plan?.app {
            select(app)
        }
    }

    func select(_ app: InstalledAppInfo) {
        guard let homeURL else {
            plan = AppUninstallPlan(app: app, artifacts: [
                AppUninstallArtifact(
                    id: app.url.path,
                    url: app.url,
                    displayPath: app.url.path,
                    kind: .application,
                    risk: .medium,
                    bytes: app.bytes,
                    isAccessible: canManageApplication(at: app.url)
                )
            ])
            selectedArtifactIDs = []
            return
        }

        isBuildingPlan = true
        errorMessage = nil
        Task { [weak self, reader] in
            guard let self else { return }
            await Task.yield()
            let plan = reader.buildPlan(for: app, homeURL: homeURL)
            self.plan = self.planWithCurrentPermissions(plan)
            self.selectedArtifactIDs = Set(plan.artifacts.filter(\.isRecommended).map(\.id))
            self.isBuildingPlan = false
        }
    }

    func toggleArtifact(_ artifact: AppUninstallArtifact) {
        if selectedArtifactIDs.contains(artifact.id) {
            selectedArtifactIDs.remove(artifact.id)
        } else {
            selectedArtifactIDs.insert(artifact.id)
        }
    }

    func selectRecommended() {
        guard let plan else { return }
        selectedArtifactIDs = Set(plan.artifacts.filter(\.isRecommended).map(\.id))
    }

    func clearSelection() {
        selectedArtifactIDs = []
    }

    func reveal(_ artifact: AppUninstallArtifact) {
        NSWorkspace.shared.activateFileViewerSelecting([artifact.url])
    }

    func trashSelectedItems() {
        guard let plan, !selectedArtifactIDs.isEmpty, !isTrashing else { return }
        let selectedArtifacts = plan.artifacts.filter { selectedArtifactIDs.contains($0.id) }
        let blockedArtifacts = selectedArtifacts.filter { !$0.isAccessible }
        let trashableArtifacts = selectedArtifacts.filter(\.isAccessible)

        if !blockedArtifacts.isEmpty {
            errorMessage = "有 \(blockedArtifacts.count) 个项目没有写入权限，已跳过。/Applications 中的应用通常需要在访达里输入管理员密码删除。"
            blockedArtifacts.forEach { artifact in
                appendTrashLog("跳过无权限项目：\(artifact.displayPath)")
            }
            if trashableArtifacts.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(blockedArtifacts.map(\.url))
                return
            }
        }

        guard confirmTrash(app: plan.app, artifacts: trashableArtifacts) else { return }

        isTrashing = true
        if blockedArtifacts.isEmpty {
            errorMessage = nil
        }
        lastTrashSummary = nil
        trashLogs = []
        appendTrashLog("开始移入废纸篓：\(plan.app.name)，选择 \(selectedArtifacts.count) 项，可处理 \(trashableArtifacts.count) 项，跳过 \(blockedArtifacts.count) 项")
        appendTrashLog("个人目录授权：\(selectedHomePath ?? "未授权")")
        appendTrashLog("应用目录授权：\(selectedApplicationsPath ?? "未授权")")
        blockedArtifacts.forEach { artifact in
            appendTrashLog("跳过无权限项目：\(artifact.displayPath)")
        }

        let scopedURLs = [homeURL, applicationsURL].compactMap { $0 }
        let trashTask = Task.detached(priority: .userInitiated) {
            var trashedCount = 0
            var trashedBytes: UInt64 = 0
            var failures: [String] = []
            var logs: [String] = []
            let fileManager = FileManager.default

            logs.append("后台任务启动，准备重新进入 \(scopedURLs.count) 个安全作用域")
            let accessedURLs = scopedURLs.filter { url in
                let didAccess = url.startAccessingSecurityScopedResource()
                logs.append("安全作用域 \(didAccess ? "成功" : "失败/无需")：\(url.path)")
                return didAccess
            }
            defer {
                accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            }

            for artifact in trashableArtifacts {
                let existsBefore = fileManager.fileExists(atPath: artifact.url.path)
                let parentPath = artifact.url.deletingLastPathComponent().path
                let parentWritable = fileManager.isWritableFile(atPath: parentPath)
                logs.append("准备处理：\(artifact.displayPath)")
                logs.append("  kind=\(artifact.kind.rawValue), risk=\(artifact.risk.rawValue), existsBefore=\(existsBefore), parentWritable=\(parentWritable), bytes=\(artifact.bytes)")

                do {
                    var resultingURL: NSURL?
                    try fileManager.trashItem(at: artifact.url, resultingItemURL: &resultingURL)
                    let existsAfter = fileManager.fileExists(atPath: artifact.url.path)
                    logs.append("  trashItem 成功，result=\(resultingURL?.path ?? "nil"), existsAfter=\(existsAfter)")
                    trashedCount += 1
                    trashedBytes += artifact.bytes
                } catch {
                    let nsError = error as NSError
                    let message = "\(artifact.displayPath)：\(error.localizedDescription)"
                    logs.append("  trashItem 失败，domain=\(nsError.domain), code=\(nsError.code), message=\(nsError.localizedDescription)")
                    failures.append(message)
                }
            }

            logs.append("后台任务结束，成功 \(trashedCount) 项，失败 \(failures.count) 项")
            return (trashedCount: trashedCount, trashedBytes: trashedBytes, failures: failures, logs: logs)
        }

        Task { [weak self] in
            guard let self else { return }
            let result = await trashTask.value
            result.logs.forEach { self.appendTrashLog($0) }
            self.isTrashing = false
            self.lastTrashSummary = "已移入废纸篓 \(result.trashedCount) 项，约 \(ByteFormatter.string(from: result.trashedBytes))。"
            if !result.failures.isEmpty {
                self.errorMessage = "部分项目未能移入废纸篓：\(result.failures.prefix(2).joined(separator: "；"))"
            }
            self.refreshApplications()
            if let currentApp = self.plan?.app {
                self.select(currentApp)
            }
        }
    }

    private func bringToolboxWindowToFront() {
        guard let toolboxWindow = NSApp.windows.first(where: { $0.title.contains("工具箱") }) else { return }
        toolboxWindow.makeKeyAndOrderFront(nil)
        toolboxWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func confirmTrash(app: InstalledAppInfo, artifacts: [AppUninstallArtifact]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确认移入废纸篓？"
        alert.informativeText = "将处理 \(app.name) 的 \(artifacts.count) 个项目，约 \(ByteFormatter.string(from: artifacts.reduce(0) { $0 + $1.bytes }))。项目会进入废纸篓，不会永久删除。"
        alert.addButton(withTitle: "移入废纸篓")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func appendTrashLog(_ message: String) {
        let timestamp = Self.logTimeFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        trashLogs.append(line)
        NSLog("[AirSentry][Uninstaller] %@", line)
    }

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private func loadCachedApplications() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode([InstalledAppInfo].self, from: data) else { return }
        self.applications = cached
    }

    private func saveCachedApplications() {
        let apps = applications
        let url = cacheURL
        Task.detached(priority: .background) {
            guard let data = try? JSONEncoder().encode(apps) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            selectedHomePath = nil
            return
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            setHomeURL(url, saveBookmark: isStale)
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            errorMessage = "之前的个人文件夹授权已失效，请重新选择。"
        }
    }

    private func restoreApplicationsBookmark() {
        guard let data = UserDefaults.standard.data(forKey: applicationsBookmarkKey) else {
            selectedApplicationsPath = nil
            return
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            setApplicationsURL(url, saveBookmark: isStale)
        } catch {
            UserDefaults.standard.removeObject(forKey: applicationsBookmarkKey)
            errorMessage = "之前的应用目录授权已失效，请重新选择。"
        }
    }

    private func setHomeURL(_ url: URL, saveBookmark: Bool) {
        if isAccessingSecurityScopedResource {
            homeURL?.stopAccessingSecurityScopedResource()
        }

        homeURL = url
        selectedHomePath = url.path
        isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
        hasHomeAccess = true

        // 预热 TCC 权限：主动触发一次 "访问其他 App 数据" 的系统弹窗，
        // 用户点击允许后，后续 buildPlan() 访问 ~/Library 子目录时不再弹窗。
        let libraryURL = url.appendingPathComponent("Library", isDirectory: true)
        for subdirectory in ["Application Support", "Containers", "Group Containers"] {
            let dirURL = libraryURL.appendingPathComponent(subdirectory, isDirectory: true)
            _ = try? FileManager.default.contentsOfDirectory(atPath: dirURL.path)
        }

        guard saveBookmark else { return }
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            errorMessage = "无法保存目录授权，下次启动时需要重新选择。"
        }
    }

    private func setApplicationsURL(_ url: URL, saveBookmark: Bool) {
        if isAccessingApplicationsSecurityScopedResource {
            applicationsURL?.stopAccessingSecurityScopedResource()
        }

        applicationsURL = url
        selectedApplicationsPath = url.path
        isAccessingApplicationsSecurityScopedResource = url.startAccessingSecurityScopedResource()
        hasApplicationsAccess = true

        guard saveBookmark else { return }
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: applicationsBookmarkKey)
        } catch {
            errorMessage = "无法保存应用目录授权，下次启动时需要重新选择。"
        }
    }

    private func planWithCurrentPermissions(_ plan: AppUninstallPlan) -> AppUninstallPlan {
        AppUninstallPlan(
            app: plan.app,
            artifacts: plan.artifacts.map { artifact in
                guard artifact.kind == .application else { return artifact }
                return AppUninstallArtifact(
                    id: artifact.id,
                    url: artifact.url,
                    displayPath: artifact.displayPath,
                    kind: artifact.kind,
                    risk: artifact.risk,
                    bytes: artifact.bytes,
                    isAccessible: canManageApplication(at: artifact.url)
                )
            }
        )
    }

    private func canManageApplication(at url: URL) -> Bool {
        let parentPath = url.deletingLastPathComponent().path
        guard let applicationsURL else {
            return FileManager.default.isWritableFile(atPath: parentPath)
        }
        let isInsideAuthorizedDirectory = url.path.hasPrefix(applicationsURL.path + "/") || url.path == applicationsURL.path
        return isInsideAuthorizedDirectory && FileManager.default.isWritableFile(atPath: parentPath)
    }
}
