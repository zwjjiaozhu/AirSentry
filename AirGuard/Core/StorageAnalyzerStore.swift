import AppKit
import Foundation

@MainActor
final class StorageAnalyzerStore: ObservableObject {
    @Published private(set) var disk = DiskStorageInfo.empty
    @Published private(set) var items: [AIStorageItem] = []
    @Published private(set) var lastScannedAt: Date?
    @Published private(set) var isScanning = false
    @Published private(set) var hasFolderAccess = false
    @Published private(set) var errorMessage: String?

    private let bookmarkKey = "storageAnalyzerHomeBookmark"
    private let reader = StorageReader()
    private var homeURL: URL?
    private var isAccessingSecurityScopedResource = false

    init() {
        disk = reader.readDiskStorage()
        restoreBookmark()
    }

    deinit {
        if isAccessingSecurityScopedResource {
            homeURL?.stopAccessingSecurityScopedResource()
        }
    }

    var totalAIBytes: UInt64 {
        items.reduce(0) { $0 + $1.bytes }
    }

    func requestFolderAccess() {
        let panel = NSOpenPanel()
        panel.title = "选择个人文件夹"
        panel.message = "AirSentry 将只读扫描其中常见 AI 工具的缓存、模型和应用数据。"
        panel.prompt = "允许扫描"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        setHomeURL(selectedURL, saveBookmark: true)
        refresh()
    }

    func refresh() {
        disk = reader.readDiskStorage()
        guard let homeURL else { return }
        guard !isScanning else { return }

        isScanning = true
        errorMessage = nil
        let scanTask = Task.detached(priority: .utility) { [reader] in
            reader.scan(homeURL: homeURL)
        }
        Task { [weak self] in
            let snapshot = await scanTask.value
            self?.disk = snapshot.disk
            self?.items = snapshot.items
            self?.lastScannedAt = snapshot.scannedAt
            self?.isScanning = false
        }
    }

    func reveal(_ location: AIStorageLocation) {
        guard location.isDetected else { return }
        NSWorkspace.shared.activateFileViewerSelecting([location.url])
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
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
            errorMessage = "之前的目录授权已失效，请重新选择个人文件夹。"
        }
    }

    private func setHomeURL(_ url: URL, saveBookmark: Bool) {
        if isAccessingSecurityScopedResource {
            homeURL?.stopAccessingSecurityScopedResource()
        }
        homeURL = url
        isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
        hasFolderAccess = true

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
}
