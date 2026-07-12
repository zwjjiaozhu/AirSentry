import Foundation

enum FinderRenameFieldID: String, CaseIterable, Codable, Identifiable {
    case status
    case version
    case date
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "文件状态"
        case .version: return "版本号"
        case .date: return "日期"
        case .preview: return "新文件名预览"
        }
    }

    var systemImage: String {
        switch self {
        case .status: return "tag"
        case .version: return "number.square"
        case .date: return "calendar"
        case .preview: return "doc.text.magnifyingglass"
        }
    }
}

struct FinderRenameField: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    var isEnabled: Bool
}

enum FinderRenameDefaults {
    static let statuses = ["草稿", "待审核", "已盖章", "归档"]

    static let fields: [FinderRenameField] = FinderRenameFieldID.allCases.map {
        FinderRenameField(id: $0.rawValue, title: $0.title, systemImage: $0.systemImage, isEnabled: true)
    }
}

