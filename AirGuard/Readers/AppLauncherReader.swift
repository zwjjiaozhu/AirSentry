import AppKit
import Foundation

struct AppLauncherReader {
    private let fileManager = FileManager.default

    func scanApplications() -> [AppLauncherItem] {
        applicationDirectories()
            .flatMap { scanApplications(in: $0) }
            .reduce(into: [String: AppLauncherItem]()) { result, item in
                result[item.id] = item
            }
            .values
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func applicationDirectories() -> [URL] {
        var urls = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        if let localApplications = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first {
            urls.append(localApplications)
        }
        if let userApplications = fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first {
            urls.append(userApplications)
        }

        return Array(Set(urls)).filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func scanApplications(in directoryURL: URL) -> [AppLauncherItem] {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var items: [AppLauncherItem] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                if let item = readApplication(at: url) {
                    items.append(item)
                }
                enumerator.skipDescendants()
            }
        }
        return items
    }

    private func readApplication(at url: URL) -> AppLauncherItem? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary
        let displayName = info?["CFBundleDisplayName"] as? String
        let bundleName = info?["CFBundleName"] as? String
        let name = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = bundle?.bundleIdentifier
        let id = bundleIdentifier?.isEmpty == false ? bundleIdentifier! : url.path

        return AppLauncherItem(
            id: id,
            name: name,
            bundleIdentifier: bundleIdentifier,
            path: url.path,
            version: info?["CFBundleShortVersionString"] as? String,
            isSystemApp: url.path.hasPrefix("/System/")
        )
    }
}
