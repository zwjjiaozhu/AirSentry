import Foundation

struct AIUsageReader {
    private struct ProviderDefinition {
        let id: AIUsageProviderID
        let relativePaths: [String]
        let allowedExtensions: Set<String>
        let maxDepth: Int
        let maxFiles: Int
    }

    private struct ParseAccumulator {
        var isDetected = false
        var latestEventAt: Date?
        var currentUsage: AITokenUsage?
        var totalUsage: AITokenUsage?
        var rateLimits: [AIUsageRateLimit.WindowKind: AIUsageRateLimit] = [:]
        var sourceFiles = Set<String>()
    }

    private let fileManager = FileManager.default
    private let maxReadableFileBytes: UInt64 = 80 * 1024 * 1024
    private let maxJSONLTailBytes: UInt64 = 768 * 1024

    func read(
        providerIDs: Set<AIUsageProviderID>? = nil,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AIUsageOverview {
        let definitions = Self.definitions.filter { definition in
            providerIDs?.contains(definition.id) ?? true
        }
        let snapshots = definitions.map { definition in
            read(definition: definition, homeURL: homeURL)
        }
        return AIUsageOverview(snapshots: snapshots, scannedAt: Date(), errorMessage: nil)
    }

    private func read(definition: ProviderDefinition, homeURL: URL) -> AIUsageSnapshot {
        var accumulator = ParseAccumulator()

        for relativePath in definition.relativePaths {
            let rootURL = homeURL.appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: rootURL.path) else { continue }
            accumulator.isDetected = true

            if isReadableDataFile(rootURL, allowedExtensions: definition.allowedExtensions) {
                parseFile(rootURL, into: &accumulator)
            } else {
                for fileURL in candidateFiles(
                    below: rootURL,
                    allowedExtensions: definition.allowedExtensions,
                    maxDepth: definition.maxDepth,
                    maxFiles: definition.maxFiles
                ) {
                    parseFile(fileURL, into: &accumulator)
                }
            }
        }

        var snapshot = AIUsageSnapshot.empty(definition.id)
        snapshot.isDetected = accumulator.isDetected
        snapshot.latestEventAt = accumulator.latestEventAt
        snapshot.currentUsage = accumulator.currentUsage
        snapshot.totalUsage = accumulator.totalUsage
        snapshot.rateLimits = accumulator.rateLimits.values.sorted { lhs, rhs in
            lhs.kind.rawValue < rhs.kind.rawValue
        }
        snapshot.sourceFileCount = accumulator.sourceFiles.count
        snapshot.sourceDescription = accumulator.sourceFiles.isEmpty ? nil : "\(accumulator.sourceFiles.count) 个文件"
        if !accumulator.isDetected {
            snapshot.statusMessage = "未发现本地记录"
        } else if accumulator.currentUsage == nil && accumulator.totalUsage == nil && accumulator.rateLimits.isEmpty {
            snapshot.statusMessage = "已发现工具目录，未找到额度字段"
        } else {
            snapshot.statusMessage = "本地记录已读取"
        }
        return snapshot
    }

    private func candidateFiles(below rootURL: URL, allowedExtensions: Set<String>, maxDepth: Int, maxFiles: Int) -> [URL] {
        guard !shouldSkip(rootURL) else { return [] }
        let rootDepth = rootURL.pathComponents.count
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if shouldSkip(url) {
                enumerator.skipDescendants()
                continue
            }
            if url.pathComponents.count - rootDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard isReadableDataFile(url, allowedExtensions: allowedExtensions) else { continue }
            urls.append(url)
        }

        return urls
            .sorted { lhs, rhs in
                modificationDate(lhs) > modificationDate(rhs)
            }
            .prefix(maxFiles)
            .map { $0 }
    }

    private func isReadableDataFile(_ url: URL, allowedExtensions: Set<String>) -> Bool {
        guard !shouldSkip(url) else { return false }
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else { return false }
        return UInt64(max(values.fileSize ?? 0, 0)) <= maxReadableFileBytes
    }

    private func parseFile(_ url: URL, into accumulator: inout ParseAccumulator) {
        guard let data = dataForParsing(url), !data.isEmpty else { return }
        var didReadUsage = false

        if url.pathExtension.lowercased() == "jsonl" {
            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline) {
                guard let lineData = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
                didReadUsage = parseObject(object, fallbackTimestamp: nil, into: &accumulator) || didReadUsage
            }
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            didReadUsage = parseObject(object, fallbackTimestamp: nil, into: &accumulator)
        } else if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for object in array {
                didReadUsage = parseObject(object, fallbackTimestamp: nil, into: &accumulator) || didReadUsage
            }
        }

        if didReadUsage {
            accumulator.sourceFiles.insert(url.path)
        }
    }

    private func dataForParsing(_ url: URL) -> Data? {
        guard url.pathExtension.lowercased() == "jsonl" else {
            return try? Data(contentsOf: url)
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > maxJSONLTailBytes else {
            try? handle.seek(toOffset: 0)
            return try? handle.readToEnd()
        }

        let offset = fileSize - maxJSONLTailBytes
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd() else { return nil }
        if let firstNewline = data.firstIndex(of: 10), firstNewline < data.endIndex {
            data.removeSubrange(data.startIndex...firstNewline)
        }
        return data
    }

    @discardableResult
    private func parseObject(_ object: [String: Any], fallbackTimestamp: Date?, into accumulator: inout ParseAccumulator) -> Bool {
        let timestamp = parseDate(object["timestamp"]) ?? parseDate(object["created_at"]) ?? parseDate(object["updated_at"]) ?? fallbackTimestamp
        let payload = object["payload"] as? [String: Any]

        var didRead = false
        if let payload, (payload["type"] as? String) == "token_count" {
            let info = payload["info"] as? [String: Any]
            didRead = readUsagePayload(info, timestamp: timestamp, into: &accumulator) || didRead
            if let rateLimits = payload["rate_limits"] as? [String: Any] {
                didRead = readRateLimits(rateLimits, timestamp: timestamp, into: &accumulator) || didRead
            }
            return didRead
        }

        didRead = readUsagePayload(payload, timestamp: timestamp, into: &accumulator) || didRead
        didRead = readUsagePayload(object, timestamp: timestamp, into: &accumulator) || didRead

        if let rateLimits = object["rate_limits"] as? [String: Any] {
            didRead = readRateLimits(rateLimits, timestamp: timestamp, into: &accumulator) || didRead
        }
        if let rateLimits = payload?["rate_limits"] as? [String: Any] {
            didRead = readRateLimits(rateLimits, timestamp: timestamp, into: &accumulator) || didRead
        }

        return didRead
    }

    private func readUsagePayload(_ object: [String: Any]?, timestamp: Date?, into accumulator: inout ParseAccumulator) -> Bool {
        guard let object else { return false }
        var didRead = false

        if let total = usage(from: object["total_token_usage"] as? [String: Any]) {
            accumulator.totalUsage = chooseNewer(existing: accumulator.totalUsage, candidate: total, existingDate: accumulator.latestEventAt, candidateDate: timestamp)
            didRead = true
        }
        if let last = usage(from: object["last_token_usage"] as? [String: Any]) {
            accumulator.currentUsage = chooseNewer(existing: accumulator.currentUsage, candidate: last, existingDate: accumulator.latestEventAt, candidateDate: timestamp)
            didRead = true
        }
        if let usage = usage(from: object["usage"] as? [String: Any]) {
            accumulator.currentUsage = chooseNewer(existing: accumulator.currentUsage, candidate: usage, existingDate: accumulator.latestEventAt, candidateDate: timestamp)
            didRead = true
        }
        if let usage = usage(from: object) {
            accumulator.currentUsage = chooseNewer(existing: accumulator.currentUsage, candidate: usage, existingDate: accumulator.latestEventAt, candidateDate: timestamp)
            didRead = true
        }

        if didRead, let timestamp, timestamp > (accumulator.latestEventAt ?? .distantPast) {
            accumulator.latestEventAt = timestamp
        }
        return didRead
    }

    private func readRateLimits(_ object: [String: Any], timestamp: Date?, into accumulator: inout ParseAccumulator) -> Bool {
        var didRead = false
        for kind in [AIUsageRateLimit.WindowKind.primary, .secondary] {
            guard let value = object[kind.rawValue] as? [String: Any] else { continue }
            let limit = AIUsageRateLimit(
                kind: kind,
                usedPercent: doubleValue(value["used_percent"]),
                windowMinutes: intValue(value["window_minutes"]),
                resetsAt: dateFromEpoch(value["resets_at"]),
                observedAt: timestamp
            )
            if limit.usedPercent != nil || limit.resetsAt != nil {
                accumulator.rateLimits[kind] = newerRateLimit(
                    existing: accumulator.rateLimits[kind],
                    candidate: limit
                )
                didRead = true
            }
        }
        if didRead, let timestamp, timestamp > (accumulator.latestEventAt ?? .distantPast) {
            accumulator.latestEventAt = timestamp
        }
        return didRead
    }

    private func usage(from object: [String: Any]?) -> AITokenUsage? {
        guard let object else { return nil }
        let input = intValue(object["input_tokens"] ?? object["inputTokens"] ?? object["prompt_tokens"])
        let cached = intValue(object["cached_input_tokens"] ?? object["cachedInputTokens"] ?? object["cache_read_input_tokens"])
        let output = intValue(object["output_tokens"] ?? object["outputTokens"] ?? object["completion_tokens"])
        let reasoning = intValue(object["reasoning_output_tokens"] ?? object["reasoningOutputTokens"])
        let total = intValue(object["total_tokens"] ?? object["totalTokens"]) ?? [input, cached, output, reasoning].compactMap { $0 }.reduce(0, +)

        guard input != nil || cached != nil || output != nil || reasoning != nil || total > 0 else { return nil }
        return AITokenUsage(
            inputTokens: input ?? 0,
            cachedInputTokens: cached ?? 0,
            outputTokens: output ?? 0,
            reasoningOutputTokens: reasoning ?? 0,
            totalTokens: total
        )
    }

    private func chooseNewer(existing: AITokenUsage?, candidate: AITokenUsage, existingDate: Date?, candidateDate: Date?) -> AITokenUsage {
        guard existing != nil else { return candidate }
        guard let candidateDate else { return existing ?? candidate }
        return candidateDate >= (existingDate ?? .distantPast) ? candidate : (existing ?? candidate)
    }

    private func newerRateLimit(existing: AIUsageRateLimit?, candidate: AIUsageRateLimit) -> AIUsageRateLimit {
        guard let existing else { return candidate }
        switch (existing.observedAt, candidate.observedAt) {
        case let (existingDate?, candidateDate?):
            return candidateDate >= existingDate ? candidate : existing
        case (nil, _?):
            return candidate
        case (_?, nil):
            return existing
        case (nil, nil):
            let existingReset = existing.resetsAt ?? .distantPast
            let candidateReset = candidate.resetsAt ?? .distantPast
            return candidateReset >= existingReset ? candidate : existing
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func dateFromEpoch(_ value: Any?) -> Date? {
        guard let seconds = doubleValue(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return Self.isoFormatter.date(from: string) ?? Self.fractionalISOFormatter.date(from: string)
    }

    private func shouldSkip(_ url: URL) -> Bool {
        let lowercasedPath = url.path.lowercased()
        let blockedFragments = [
            "/auth",
            "/.auth",
            "auth.json",
            "cookie",
            "httpstorages",
            "indexeddb",
            "local storage",
            "session storage",
            "extensions",
            "node_modules"
        ]
        return blockedFragments.contains { lowercasedPath.contains($0) }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let definitions: [ProviderDefinition] = [
        ProviderDefinition(
            id: .codex,
            relativePaths: [
                ".codex/session_index.jsonl",
                ".codex/sessions",
                ".codex/archived_sessions"
            ],
            allowedExtensions: ["jsonl"],
            maxDepth: 6,
            maxFiles: 36
        ),
        ProviderDefinition(
            id: .claude,
            relativePaths: [
                ".claude/history.jsonl",
                ".claude/sessions",
                "Library/Application Support/Claude/claude-code"
            ],
            allowedExtensions: ["json", "jsonl", "log"],
            maxDepth: 5,
            maxFiles: 28
        ),
        ProviderDefinition(
            id: .qoder,
            relativePaths: [
                ".qoder/projects",
                ".qoder/events",
                ".qoder/cache/experts"
            ],
            allowedExtensions: ["json", "jsonl"],
            maxDepth: 4,
            maxFiles: 28
        ),
        ProviderDefinition(
            id: .cursor,
            relativePaths: [
                ".cursor",
                "Library/Application Support/Cursor/User/globalStorage"
            ],
            allowedExtensions: ["json", "jsonl", "log"],
            maxDepth: 4,
            maxFiles: 24
        ),
        ProviderDefinition(
            id: .windsurf,
            relativePaths: [
                ".codeium/windsurf",
                "Library/Application Support/Windsurf/User/globalStorage"
            ],
            allowedExtensions: ["json", "jsonl", "log"],
            maxDepth: 4,
            maxFiles: 24
        ),
        ProviderDefinition(
            id: .copilot,
            relativePaths: [
                ".config/github-copilot",
                "Library/Application Support/GitHub Copilot"
            ],
            allowedExtensions: ["json", "jsonl", "log"],
            maxDepth: 4,
            maxFiles: 24
        )
    ]
}
