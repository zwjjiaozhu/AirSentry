import AppKit
import Foundation

enum FinderVersionRenameResult {
    case renamed(URL)
    case unauthorized(URL)
    case invalidTarget(URL)
    case failed(URL, Error)
}

enum FinderVersionRenameService {
    static func suggestedDraft(for fileURL: URL, date: Date = Date()) -> FinderRenameDraft {
        let statuses = FinderRenameConfigStore.statuses()
        let parsed = parse(fileURL: fileURL, statuses: statuses)
        return FinderRenameDraft(
            originalURL: fileURL,
            baseName: parsed.baseName,
            version: parsed.version.map { $0 + 1 } ?? 1,
            date: date,
            status: parsed.status ?? statuses[0]
        )
    }

    static func fileName(for draft: FinderRenameDraft) -> String {
        let dateString = dateFormatter.string(from: draft.date)
        let versionString = "v\(String(format: "%03d", max(1, draft.version)))"
        let name = "\(draft.baseName)_\(versionString)_\(dateString)_\(draft.status)"
        guard !draft.originalURL.pathExtension.isEmpty else { return name }
        return "\(name).\(draft.originalURL.pathExtension)"
    }

    static func rename(draft: FinderRenameDraft, defaults: UserDefaults = .standard) -> FinderVersionRenameResult {
        let originalURL = draft.originalURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: originalURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return .invalidTarget(originalURL)
        }

        guard let scope = authorizedScope(for: originalURL, defaults: defaults) else {
            return .unauthorized(originalURL)
        }

        let didAccess = scope.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                scope.stopAccessingSecurityScopedResource()
            }
        }

        let targetURL = uniqueURL(for: originalURL.deletingLastPathComponent().appendingPathComponent(fileName(for: draft)))
        do {
            try FileManager.default.moveItem(at: originalURL, to: targetURL)
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            return .renamed(targetURL)
        } catch {
            return .failed(targetURL, error)
        }
    }

    private static func parse(fileURL: URL, statuses: [String]) -> (baseName: String, version: Int?, status: String?) {
        let name = fileURL.deletingPathExtension().lastPathComponent
        let statusPattern = statuses.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = #"^(.*)_v(\d{1,4})_\d{8}_("# + statusPattern + #")$"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              match.numberOfRanges == 4,
              let baseRange = Range(match.range(at: 1), in: name),
              let versionRange = Range(match.range(at: 2), in: name),
              let statusRange = Range(match.range(at: 3), in: name) else {
            return (name, nil, nil)
        }

        return (String(name[baseRange]), Int(name[versionRange]), String(name[statusRange]))
    }

    private static func authorizedScope(for requestedURL: URL, defaults: UserDefaults) -> URL? {
        let folders = FinderNewFileAuthorizationStoreMirrorForRename.loadFolders(from: defaults)
        for folder in folders {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: folder.bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isDescendant(requestedURL, of: url) {
                    return url
                }
            } catch {
                NSLog("AirSentry failed to resolve rename authorization bookmark: \(error.localizedDescription)")
            }
        }
        return nil
    }

    private static func isDescendant(_ childURL: URL, of parentURL: URL) -> Bool {
        let childPath = childURL.standardizedFileURL.path
        let parentPath = parentURL.standardizedFileURL.path
        if parentPath == "/" { return childPath.hasPrefix("/") }
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    private static func uniqueURL(for requestedURL: URL) -> URL {
        guard FileManager.default.fileExists(atPath: requestedURL.path) else { return requestedURL }

        let extensionName = requestedURL.pathExtension
        let directoryURL = requestedURL.deletingLastPathComponent()
        let baseName = requestedURL.deletingPathExtension().lastPathComponent

        for index in 2...999 {
            let fileName = extensionName.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(extensionName)"
            let candidateURL = directoryURL.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directoryURL.appendingPathComponent("\(baseName) \(UUID().uuidString)").appendingPathExtension(extensionName)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

struct FinderRenameDraft {
    let originalURL: URL
    var baseName: String
    var version: Int
    var date: Date
    var status: String
}

private enum FinderNewFileAuthorizationStoreMirrorForRename {
    static func loadFolders(from defaults: UserDefaults) -> [FinderAuthorizedFolder] {
        guard let data = defaults.data(forKey: "finderNewFileAuthorizedFolders"),
              let decoded = try? JSONDecoder().decode([FinderAuthorizedFolder].self, from: data) else {
            return []
        }

        return decoded
    }
}
