import Foundation

struct SystemSnapshot: Equatable {
    var thermal: ThermalStatus
    var cpuUsage: Double
    var memory: MemoryInfo
    var network: NetworkSpeed
    var battery: BatteryInfo
    var disk: DiskStorageInfo
    var capturedAt: Date

    static let empty = SystemSnapshot(
        thermal: ThermalStatus(level: .nominal, temperatureCelsius: nil),
        cpuUsage: 0,
        memory: .empty,
        network: .zero,
        battery: .empty,
        disk: .empty,
        capturedAt: Date()
    )
}

struct ThermalStatus: Equatable {
    var level: ThermalLevel
    var temperatureCelsius: Double?
}

struct TopCPUProcess: Equatable, Identifiable {
    var pid: Int32
    var cpuPercent: Double
    var name: String

    var id: Int32 { pid }
}

struct BatteryInfo: Equatable {
    var levelRatio: Double?
    var isCharging: Bool
    var isCharged: Bool
    var isPowerAdapterConnected: Bool
    var isPresent: Bool
    var cycleCount: Int?
    var health: String?

    static let empty = BatteryInfo(
        levelRatio: nil,
        isCharging: false,
        isCharged: false,
        isPowerAdapterConnected: false,
        isPresent: false,
        cycleCount: nil,
        health: nil
    )
}
