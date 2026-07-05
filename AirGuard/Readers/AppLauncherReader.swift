import AppKit
import Foundation

struct AppLauncherReader {
    private let fileManager = FileManager.default

    func scanApplications(in additionalDirectories: [URL] = []) -> [AppLauncherItem] {
        let allDirectories = Array(Set(applicationDirectories() + additionalDirectories))
            .filter { fileManager.fileExists(atPath: $0.path) }
        return allDirectories
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
        // 优先读取本地化名称：系统应用的中文名存储在 *.lproj/InfoPlist.strings 中，
        // 不在 Info.plist 里，仅读取 infoDictionary 会拿到英文默认名。
        let localizedInfo = bundle?.localizedInfoDictionary
        let displayName = localizedInfo?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleDisplayName"] as? String
        let bundleName = localizedInfo?["CFBundleName"] as? String
            ?? info?["CFBundleName"] as? String
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
