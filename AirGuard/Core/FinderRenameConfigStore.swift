import Foundation

@MainActor
final class FinderRenameConfigStore: ObservableObject {
    @Published var fields: [FinderRenameField] {
        didSet { saveFields(); syncSharedConfig?() }
    }

    var enabledFields: [FinderRenameField] {
        fields.filter(\.isEnabled)
    }

    var syncSharedConfig: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fields = Self.loadFields(from: defaults)
    }

    func setField(_ fieldID: String, isEnabled: Bool) {
        guard let index = fields.firstIndex(where: { $0.id == fieldID }) else { return }
        fields[index].isEnabled = isEnabled
    }

    func moveField(id: String, near targetID: String) {
        guard id != targetID,
              let sourceIndex = fields.firstIndex(where: { $0.id == id }),
              let targetIndex = fields.firstIndex(where: { $0.id == targetID }) else { return }

        let field = fields.remove(at: sourceIndex)
        fields.insert(field, at: targetIndex)
    }

    private func saveFields() {
        do {
            let data = try JSONEncoder().encode(fields)
            defaults.set(data, forKey: Self.fieldsKey)
        } catch {
            NSLog("AirSentry rename fields save failed: \(error.localizedDescription)")
        }
    }

    private static func loadFields(from defaults: UserDefaults) -> [FinderRenameField] {
        guard let data = defaults.data(forKey: fieldsKey),
              let decoded = try? JSONDecoder().decode([FinderRenameField].self, from: data),
              !decoded.isEmpty else {
            return FinderRenameDefaults.fields
        }

        let known = Dictionary(uniqueKeysWithValues: FinderRenameDefaults.fields.map { ($0.id, $0) })
        let decodedIDs = Set(decoded.map(\.id))
        let preserved = decoded.compactMap { savedField -> FinderRenameField? in
            guard var currentField = known[savedField.id] else { return nil }
            currentField.isEnabled = savedField.isEnabled
            return currentField
        }
        let missing = FinderRenameDefaults.fields.filter { !decodedIDs.contains($0.id) }
        return preserved + missing
    }

    static func enabledFields(from defaults: UserDefaults = .standard) -> [FinderRenameField] {
        loadFields(from: defaults).filter(\.isEnabled)
    }

    private static let fieldsKey = "finderRenameFields"
}
