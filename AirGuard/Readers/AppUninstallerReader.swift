import AppKit
import Foundation

struct AppUninstallerReader {
    private struct ArtifactCandidate {
        let url: URL
        let kind: AppUninstallArtifactKind
        let risk: AppUninstallRisk
    }

    private let fileManager = FileManager.default

    func scanApplications() -> [InstalledAppInfo] {
        applicationDirectories()
            .flatMap { scanApplications(in: $0) }
            .reduce(into: [String: InstalledAppInfo]()) { result, app in
                result[app.id] = app
            }
            .values
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func buildPlan(for app: InstalledAppInfo, homeURL: URL) -> AppUninstallPlan {
        let artifacts = ([applicationArtifact(for: app)] + residualArtifacts(for: app, homeURL: homeURL))
            .filter { fileManager.fileExists(atPath: $0.url.path) }
            .reduce(into: [String: AppUninstallArtifact]()) { result, artifact in
                result[artifact.id] = artifact
            }
            .values
            .sorted { lhs, rhs in
                if lhs.kind.rawValue == rhs.kind.rawValue {
                    return lhs.displayPath.localizedCaseInsensitiveCompare(rhs.displayPath) == .orderedAscending
                }
                return lhs.kind.rawValue < rhs.kind.rawValue
            }

        return AppUninstallPlan(app: app, artifacts: artifacts)
    }

    private func applicationDirectories() -> [URL] {
        var urls = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
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

    private func scanApplications(in directoryURL: URL) -> [InstalledAppInfo] {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .isPackageKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var apps: [InstalledAppInfo] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                if let app = readApplication(at: url) {
                    apps.append(app)
                }
                enumerator.skipDescendants()
            }
        }
        return apps
    }

    private func readApplication(at url: URL) -> InstalledAppInfo? {
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
        let version = info?["CFBundleShortVersionString"] as? String
        let bundleIdentifier = bundle?.bundleIdentifier
        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])

        return InstalledAppInfo(
            id: url.path,
            name: name,
            bundleIdentifier: bundleIdentifier,
            version: version,
            url: url,
            bytes: allocatedSize(of: url),
            lastUsedAt: values?.contentAccessDate ?? values?.contentModificationDate,
            isSystemApp: url.path.hasPrefix("/System/")
        )
    }

    private func applicationArtifact(for app: InstalledAppInfo) -> AppUninstallArtifact {
        AppUninstallArtifact(
            id: app.url.path,
            url: app.url,
            displayPath: app.url.path,
            kind: .application,
            risk: .medium,
            bytes: app.bytes,
            isAccessible: fileManager.isWritableFile(atPath: app.url.deletingLastPathComponent().path)
        )
    }

    private func residualArtifacts(for app: InstalledAppInfo, homeURL: URL) -> [AppUninstallArtifact] {
        let libraryURL = homeURL.appendingPathComponent("Library", isDirectory: true)
        let names = candidateNames(for: app)
        let bundleIdentifiers = [app.bundleIdentifier].compactMap { $0 }

        var candidates: [ArtifactCandidate] = []
        candidates += names.map { ArtifactCandidate(url: libraryURL.appendingPathComponent("Application Support/\($0)", isDirectory: true), kind: .support, risk: .medium) }
        candidates += names.map { ArtifactCandidate(url: libraryURL.appendingPathComponent("Caches/\($0)", isDirectory: true), kind: .cache, risk: .low) }
        candidates += names.map { ArtifactCandidate(url: libraryURL.appendingPathComponent("Logs/\($0)", isDirectory: true), kind: .logs, risk: .low) }
        candidates += bundleIdentifiers.map { ArtifactCandidate(url: libraryURL.appendingPathComponent("Caches/\($0)", isDirectory: true), kind: .cache, risk: .low) }
        candidates += bundleIdentifiers.map { ArtifactCandidate(url: libraryURL.appendingPathComponent("Preferences/\($0).plist"), kind: .preferences, risk: .medium) }
        candidates += bundleIdentifiers.map { ArtifactCandidate(url: libraryURL.appendingPathComponent("Saved Application State/\($0).savedState", isDirectory: true), kind: .savedState, risk: .low) }
        candidates += bundleIdentifiers.map { ArtifactCandidate(url: libraryURL.appendingPathComponent("Containers/\($0)", isDirectory: true), kind: .container, risk: .high) }
        candidates += matchingGroupContainers(in: libraryURL, app: app)

        return candidates.compactMap { candidate in
            // 先检查可读性，避免未授权的 TCC 保护路径触发系统弹窗
            guard fileManager.isReadableFile(atPath: candidate.url.path) else { return nil }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.url.path, isDirectory: &isDirectory) else { return nil }
            let bytes = isDirectory.boolValue ? allocatedSize(of: candidate.url) : allocatedFileSize(at: candidate.url)
            return AppUninstallArtifact(
                id: candidate.url.path,
                url: candidate.url,
                displayPath: displayPath(for: candidate.url, homeURL: homeURL),
                kind: candidate.kind,
                risk: candidate.risk,
                bytes: bytes,
                isAccessible: fileManager.isWritableFile(atPath: candidate.url.path)
            )
        }
    }

    private func matchingGroupContainers(in libraryURL: URL, app: InstalledAppInfo) -> [ArtifactCandidate] {
        let groupContainerURL = libraryURL.appendingPathComponent("Group Containers", isDirectory: true)
        guard let children = try? fileManager.contentsOfDirectory(
            at: groupContainerURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let tokens = ([app.bundleIdentifier].compactMap { $0 } + candidateNames(for: app))
            .map(normalize)
            .filter { !$0.isEmpty }

        return children.compactMap { url in
            let normalizedName = normalize(url.lastPathComponent)
            guard tokens.contains(where: { normalizedName.contains($0) }) else { return nil }
            return ArtifactCandidate(url: url, kind: .groupContainer, risk: .high)
        }
    }

    private func candidateNames(for app: InstalledAppInfo) -> [String] {
        var names = [
            app.name,
            app.url.deletingPathExtension().lastPathComponent
        ]
        if let bundleIdentifier = app.bundleIdentifier {
            names.append(bundleIdentifier)
            names.append(bundleIdentifier.components(separatedBy: ".").last ?? bundleIdentifier)
        }
        return Array(Set(names)).filter { !$0.isEmpty }
    }

    private func displayPath(for url: URL, homeURL: URL) -> String {
        let homePath = homeURL.path
        if url.path.hasPrefix(homePath + "/") {
            return "~" + String(url.path.dropFirst(homePath.count))
        }
        return url.path
    }

    private func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func allocatedSize(of directoryURL: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total = allocatedFileSize(at: directoryURL)
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total += UInt64(max(size, 0))
        }
        return total
    }

    private func allocatedFileSize(at url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        return UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0, 0))
    }
}
