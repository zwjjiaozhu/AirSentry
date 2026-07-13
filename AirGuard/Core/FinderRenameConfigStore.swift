import Foundation

@MainActor
final class FinderRenameConfigStore: ObservableObject {
    @Published var fields: [FinderRenameField] {
        didSet { saveFields(); syncSharedConfig?() }
    }

    @Published var customStatuses: [String] {
        didSet { saveCustomStatuses() }
    }

    var enabledFields: [FinderRenameField] {
        fields.filter(\.isEnabled)
    }

    var statuses: [String] {
        Self.mergedStatuses(customStatuses)
    }

    var syncSharedConfig: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fields = Self.loadFields(from: defaults)
        customStatuses = Self.loadCustomStatuses(from: defaults)
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

    func addStatus(_ rawStatus: String) {
        let status = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !status.isEmpty,
              !statuses.contains(where: { $0.localizedCaseInsensitiveCompare(status) == .orderedSame }) else {
            return
        }
        customStatuses.append(status)
    }

    func removeCustomStatus(_ status: String) {
        customStatuses.removeAll { $0 == status }
    }

    func isCustomStatus(_ status: String) -> Bool {
        customStatuses.contains(status)
    }

    private func saveFields() {
        do {
            let data = try JSONEncoder().encode(fields)
            defaults.set(data, forKey: Self.fieldsKey)
        } catch {
            NSLog("AirSentry rename fields save failed: \(error.localizedDescription)")
        }
    }

    private func saveCustomStatuses() {
        do {
            let data = try JSONEncoder().encode(customStatuses)
            defaults.set(data, forKey: Self.customStatusesKey)
        } catch {
            NSLog("AirSentry rename statuses save failed: \(error.localizedDescription)")
        }
    }

    nonisolated private static func loadFields(from defaults: UserDefaults) -> [FinderRenameField] {
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

    nonisolated private static func loadCustomStatuses(from defaults: UserDefaults) -> [String] {
        guard let data = defaults.data(forKey: customStatusesKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !FinderRenameDefaults.statuses.contains($0) }
    }

    nonisolated static func statuses(from defaults: UserDefaults = .standard) -> [String] {
        mergedStatuses(loadCustomStatuses(from: defaults))
    }

    nonisolated private static func mergedStatuses(_ customStatuses: [String]) -> [String] {
        var seen = Set(FinderRenameDefaults.statuses)
        var result = FinderRenameDefaults.statuses
        for status in customStatuses where !seen.contains(status) {
            seen.insert(status)
            result.append(status)
        }
        return result
    }

    nonisolated static func enabledFields(from defaults: UserDefaults = .standard) -> [FinderRenameField] {
        loadFields(from: defaults).filter(\.isEnabled)
    }

    private static let fieldsKey = "finderRenameFields"
    private static let customStatusesKey = "finderRenameCustomStatuses"
}
