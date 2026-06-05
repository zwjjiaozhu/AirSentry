import Foundation

struct SystemSnapshot: Equatable {
    var thermal: ThermalStatus
    var cpuUsage: Double
    var memory: MemoryInfo
    var network: NetworkSpeed
    var capturedAt: Date

    static let empty = SystemSnapshot(
        thermal: ThermalStatus(level: .nominal, temperatureCelsius: nil),
        cpuUsage: 0,
        memory: .empty,
        network: .zero,
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
