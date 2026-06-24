import Foundation

struct StorageReader {
    private struct ToolDefinition {
        let id: String
        let name: String
        let systemImage: String
        let relativePaths: [String]
    }

    private let fileManager = FileManager.default

    func readDiskStorage() -> DiskStorageInfo {
        let rootURL = URL(fileURLWithPath: "/", isDirectory: true)
        guard let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else {
            return .empty
        }

        return DiskStorageInfo(
            totalBytes: UInt64(max(values.volumeTotalCapacity ?? 0, 0)),
            availableBytes: UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
        )
    }

    func scan(homeURL: URL) -> AIStorageSnapshot {
        let items = Self.toolDefinitions.map { definition in
            let locations = definition.relativePaths.map { relativePath in
                readLocation(relativePath, below: homeURL)
            }
            return AIStorageItem(
                id: definition.id,
                name: definition.name,
                systemImage: definition.systemImage,
                bytes: locations.reduce(0) { $0 + $1.bytes },
                locations: locations
            )
        }
        .filter { $0.detectedLocationCount > 0 }
        .sorted { lhs, rhs in
            if lhs.bytes == rhs.bytes { return lhs.name < rhs.name }
            return lhs.bytes > rhs.bytes
        }

        return AIStorageSnapshot(disk: readDiskStorage(), items: items, scannedAt: Date())
    }

    private func readLocation(_ relativePath: String, below homeURL: URL) -> AIStorageLocation {
        let url = homeURL.appendingPathComponent(relativePath, isDirectory: true)
        let displayPath = "~/" + relativePath
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return AIStorageLocation(
                id: relativePath,
                displayPath: displayPath,
                url: url,
                bytes: 0,
                isDetected: false,
                isAccessible: true
            )
        }

        guard fileManager.isReadableFile(atPath: url.path) else {
            return AIStorageLocation(
                id: relativePath,
                displayPath: displayPath,
                url: url,
                bytes: 0,
                isDetected: true,
                isAccessible: false
            )
        }

        let bytes = isDirectory.boolValue ? allocatedSize(of: url) : allocatedFileSize(at: url)
        return AIStorageLocation(
            id: relativePath,
            displayPath: displayPath,
            url: url,
            bytes: bytes,
            isDetected: true,
            isAccessible: true
        )
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

        var total: UInt64 = 0
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

    private static let toolDefinitions: [ToolDefinition] = [
        ToolDefinition(id: "codex", name: "Codex", systemImage: "chevron.left.forwardslash.chevron.right", relativePaths: [".codex"]),
        ToolDefinition(id: "claude", name: "Claude", systemImage: "brain.head.profile", relativePaths: [".claude", "Library/Application Support/Claude", "Library/Caches/Claude"]),
        ToolDefinition(id: "cursor", name: "Cursor", systemImage: "cursorarrow.rays", relativePaths: [".cursor", "Library/Application Support/Cursor", "Library/Caches/Cursor"]),
        ToolDefinition(id: "windsurf", name: "Windsurf", systemImage: "wind", relativePaths: [".codeium/windsurf", "Library/Application Support/Windsurf", "Library/Caches/Windsurf"]),
        ToolDefinition(id: "copilot", name: "GitHub Copilot", systemImage: "person.crop.circle.badge.checkmark", relativePaths: [".config/github-copilot", "Library/Application Support/GitHub Copilot"]),
        ToolDefinition(id: "ollama", name: "Ollama", systemImage: "externaldrive", relativePaths: [".ollama"]),
        ToolDefinition(id: "lm-studio", name: "LM Studio", systemImage: "cube", relativePaths: [".cache/lm-studio", "Library/Application Support/LM Studio"]),
        ToolDefinition(id: "hugging-face", name: "Hugging Face", systemImage: "shippingbox", relativePaths: [".cache/huggingface"])
    ]
}
