import AppKit
import Foundation

struct FinderAuthorizedFolder: Identifiable, Codable, Equatable {
    let id: UUID
    let bookmarkData: Data
    let displayName: String
    let path: String

    init(url: URL) throws {
        id = UUID()
        bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        displayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        path = url.path
    }
}

final class FinderNewFileAuthorizationStore: ObservableObject {
    @Published private(set) var folders: [FinderAuthorizedFolder]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folders = Self.loadFolders(from: defaults)
    }

    func addFolder(startingAt directoryURL: URL? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        panel.prompt = "授权"
        panel.message = "选择允许 AirSentry 通过 Finder 右键菜单新建文件的文件夹。"
        panel.directoryURL = directoryURL

        guard panel.runModal() == .OK else { return }

        var updated = folders
        for url in panel.urls {
            do {
                let folder = try FinderAuthorizedFolder(url: url)
                updated.removeAll { $0.path == folder.path }
                updated.append(folder)
            } catch {
                NSLog("AirSentry failed to create folder authorization bookmark: \(error.localizedDescription)")
            }
        }

        folders = updated.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        save()
    }

    func removeFolder(_ folder: FinderAuthorizedFolder) {
        folders.removeAll { $0.id == folder.id }
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(folders)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            NSLog("AirSentry failed to save folder authorizations: \(error.localizedDescription)")
        }
    }

    private static func loadFolders(from defaults: UserDefaults) -> [FinderAuthorizedFolder] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([FinderAuthorizedFolder].self, from: data) else {
            return []
        }

        return decoded
    }

    private static let defaultsKey = "finderNewFileAuthorizedFolders"
}

enum FinderNewFileService {
    /// 根据 templateId 返回模板文件内容
    static func contents(forTemplateId templateId: String) -> Data {
        switch templateId {
        case "xlsx", "pptx", "docx": return bundledTemplateData(forTemplateId: templateId)
        case "md": return Data("# 新建文档\n".utf8)
        case "json": return Data("{\n  \n}\n".utf8)
        case "rtf": return Data("{\\rtf1\\ansi\\deff0\n\\pard\\fs24\\par\n}\n".utf8)
        case "html": return Data("<!doctype html>\n<html>\n<head>\n  <meta charset=\"utf-8\">\n  <title>新建页面</title>\n</head>\n<body>\n</body>\n</html>\n".utf8)
        default: return Data()
        }
    }

    private static func bundledTemplateData(forTemplateId templateId: String) -> Data {
        guard let url = Bundle.main.url(
            forResource: "Blank",
            withExtension: templateId,
            subdirectory: "NewFileTemplates"
        ) else {
            assertionFailure("Missing bundled Office template for \(templateId)")
            return Data()
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }

    static func createFile(at requestedURL: URL, contents: Data, defaults: UserDefaults = .standard) -> FinderNewFileCreationResult {
        guard let scope = authorizedScope(for: requestedURL, defaults: defaults) else {
            NSLog("AirSentry Finder new file target is not authorized: \(requestedURL.path)")
            return .unauthorized(requestedURL)
        }

        let didAccess = scope.url.startAccessingSecurityScopedResource()
        NSLog("AirSentry Finder new file authorization matched \(scope.url.path), securityScope=\(didAccess)")
        defer {
            if didAccess {
                scope.url.stopAccessingSecurityScopedResource()
            }
        }

        let fileURL = uniqueFileURL(for: requestedURL)
        guard FileManager.default.createFile(atPath: fileURL.path, contents: contents) else {
            NSLog("AirSentry failed to create authorized file at \(fileURL.path)")
            return .writeFailed(fileURL)
        }

        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        return .created(fileURL)
    }

    private static func authorizedScope(for requestedURL: URL, defaults: UserDefaults) -> AuthorizedScope? {
        let folders = FinderNewFileAuthorizationStoreMirror.loadFolders(from: defaults)
        NSLog("AirSentry Finder new file checking \(folders.count) authorized folders for \(requestedURL.path)")

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
                    if isStale {
                        NSLog("AirSentry Finder new file bookmark is stale for \(url.path)")
                    }
                    return AuthorizedScope(url: url)
                }
            } catch {
                NSLog("AirSentry failed to resolve folder authorization bookmark: \(error.localizedDescription)")
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

    private static func uniqueFileURL(for requestedURL: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: requestedURL.path) else { return requestedURL }

        let extensionName = requestedURL.pathExtension
        let directoryURL = requestedURL.deletingLastPathComponent()
        let baseName = requestedURL.deletingPathExtension().lastPathComponent

        for index in 2...999 {
            let fileName = extensionName.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(extensionName)"
            let candidateURL = directoryURL.appendingPathComponent(fileName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directoryURL.appendingPathComponent(UUID().uuidString).appendingPathExtension(extensionName)
    }

    private struct AuthorizedScope {
        let url: URL
    }
}

enum FinderNewFileCreationResult {
    case created(URL)
    case unauthorized(URL)
    case writeFailed(URL)
}

private enum FinderNewFileAuthorizationStoreMirror {
    static func loadFolders(from defaults: UserDefaults) -> [FinderAuthorizedFolder] {
        guard let data = defaults.data(forKey: "finderNewFileAuthorizedFolders"),
              let decoded = try? JSONDecoder().decode([FinderAuthorizedFolder].self, from: data) else {
            return []
        }

        return decoded
    }
}
