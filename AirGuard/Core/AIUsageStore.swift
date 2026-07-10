import Foundation

@MainActor
final class AIUsageStore: ObservableObject {
    @Published private(set) var overview = AIUsageOverview.empty
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?

    private let reader = AIUsageReader()

    func refresh(providerIDs: Set<AIUsageProviderID>? = nil) {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil

        let scanTask = Task.detached(priority: .utility) { [reader, providerIDs] in
            reader.read(providerIDs: providerIDs)
        }

        Task { [weak self] in
            let overview = await scanTask.value
            self?.overview = overview
            self?.isScanning = false
        }
    }

    func clear() {
        overview = .empty
        errorMessage = nil
    }
}
