import Foundation

struct DiskStorageInfo: Equatable {
    let totalBytes: UInt64
    let availableBytes: UInt64

    var usedBytes: UInt64 {
        totalBytes > availableBytes ? totalBytes - availableBytes : 0
    }

    var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    static let empty = DiskStorageInfo(totalBytes: 0, availableBytes: 0)
}

struct AIStorageItem: Identifiable, Equatable {
    let id: String
    let name: String
    let systemImage: String
    let bytes: UInt64
    let locations: [AIStorageLocation]

    var detectedLocationCount: Int {
        locations.filter(\.isDetected).count
    }
}

struct AIStorageLocation: Identifiable, Equatable {
    let id: String
    let displayPath: String
    let url: URL
    let bytes: UInt64
    let isDetected: Bool
    let isAccessible: Bool
}

struct AIStorageSnapshot: Equatable {
    let disk: DiskStorageInfo
    let items: [AIStorageItem]
    let scannedAt: Date

    var totalAIBytes: UInt64 {
        items.reduce(0) { $0 + $1.bytes }
    }
}
