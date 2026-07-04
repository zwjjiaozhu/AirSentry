import Foundation

struct AppLauncherItem: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let path: String
    let version: String?
    let isSystemApp: Bool

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var searchableText: String {
        [name, bundleIdentifier, path]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

struct AppLauncherGroup: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var appIDs: [String]
    var colorHex: String

    init(id: UUID = UUID(), name: String, appIDs: [String] = [], colorHex: String = "#0A84FF") {
        self.id = id
        self.name = name
        self.appIDs = appIDs
        self.colorHex = colorHex
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case appIDs
        case colorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        appIDs = try container.decode([String].self, forKey: .appIDs)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#0A84FF"
    }
}
