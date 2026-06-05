import Foundation
import IOKit

struct ThermalReader {
    func read() -> ThermalStatus {
        let level = ProcessInfo.processInfo.thermalState.thermalLevel
        let result: TemperatureResult?
        if TemperatureSourcePreference.isRuntimeResolved {
            result = TemperatureSourcePreference.runtimeSource == nil
                ? nil
                : readRuntimeTemperature() ?? resolveTemperatureSource()
        } else {
            result = resolveTemperatureSource()
        }

        if result == nil {
            NSLog("AirSentry temperature unavailable, thermalState=%@", level.title)
        }

        return ThermalStatus(
            level: level,
            temperatureCelsius: result?.value
        )
    }

    private func readRuntimeTemperature() -> TemperatureResult? {
        guard let source = TemperatureSourcePreference.runtimeSource else { return nil }
        guard let result = readTemperature(from: source) else {
            NSLog("AirSentry temperature runtime source failed: %@", source.rawValue)
            TemperatureSourcePreference.clearRuntimeSource()
            TemperatureSourcePreference.clearPersistedSource()
            return nil
        }
        return result
    }

    private func resolveTemperatureSource() -> TemperatureResult? {
        if let source = TemperatureSourcePreference.persistedSource {
            if let result = readTemperature(from: source) {
                TemperatureSourcePreference.save(result.source)
                return result
            }

            NSLog("AirSentry temperature persisted source failed: %@", source.rawValue)
            TemperatureSourcePreference.clearPersistedSource()
        }

        if let result = discoverTemperature() {
            TemperatureSourcePreference.save(result.source)
            return result
        }

        TemperatureSourcePreference.markUnavailable()
        return nil
    }

    private func readTemperature(from source: TemperatureSource) -> TemperatureResult? {
        switch source {
        case .hid:
            HIDTemperatureReader().readTemperature()
        case .smcCPU:
            SMCTemperatureReader().readCPUTemperature()
        case .smcFallback:
            SMCTemperatureReader().readFallbackTemperature()
        }
    }

    private func discoverTemperature() -> TemperatureResult? {
        SMCTemperatureReader().readTemperature() ?? HIDTemperatureReader().readTemperature()
    }
}

private enum TemperatureSource: String {
    case smcCPU
    case smcFallback
    case hid
}

private struct TemperatureResult {
    let source: TemperatureSource
    let value: Double
}

private enum TemperatureSourcePreference {
    private static let key = "temperaturePreferredSource"
    private static let noPreference = "none"
    private static var didResolveRuntimeSource = false
    private static var resolvedRuntimeSource: TemperatureSource?

    static var runtimeSource: TemperatureSource? {
        didResolveRuntimeSource ? resolvedRuntimeSource : nil
    }

    static var isRuntimeResolved: Bool {
        didResolveRuntimeSource
    }

    static var persistedSource: TemperatureSource? {
        guard !didResolveRuntimeSource else { return nil }
        guard let rawValue = UserDefaults.standard.string(forKey: key) else {
            return .hid
        }
        guard rawValue != noPreference else { return nil }
        return TemperatureSource(rawValue: rawValue)
    }

    static func save(_ source: TemperatureSource) {
        didResolveRuntimeSource = true
        resolvedRuntimeSource = source
        UserDefaults.standard.set(source.rawValue, forKey: key)
    }

    static func clearRuntimeSource() {
        didResolveRuntimeSource = false
        resolvedRuntimeSource = nil
    }

    static func markUnavailable() {
        didResolveRuntimeSource = true
        resolvedRuntimeSource = nil
    }

    static func clearPersistedSource() {
        UserDefaults.standard.set(noPreference, forKey: key)
    }
}

private struct HIDTemperatureReader {
    private let temperatureType: Int32 = 15
    private let sensorUsagePage: Int32 = 0xff00
    private let sensorUsage: Int32 = 5
    private let cpuNameMarkers = [
        "pACC", "eACC", "CPU", "SOC", "PMGR SOC Die", "PMU tdie"
    ]

    func readTemperature() -> TemperatureResult? {
        let sensors = AirSentryAppleSiliconSensors(sensorUsagePage, sensorUsage, temperatureType)
        guard !sensors.isEmpty else {
            NSLog("AirSentry temperature HID: no sensors")
            return nil
        }

        let validReadings = sensors
            .map { TemperatureReading(key: $0.key, value: $0.value.doubleValue) }
            .filter { $0.value.isFinite && $0.value >= 15 && $0.value <= 125 }

        guard !validReadings.isEmpty else {
            let rawSummary = sensors
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(String(format: "%.2f", $0.value.doubleValue))" }
                .joined(separator: ", ")
            NSLog("AirSentry temperature HID: sensors found but no valid temperatures: %@", rawSummary)
            return nil
        }

        let cpuReadings = validReadings.filter { reading in
            cpuNameMarkers.contains { marker in
                reading.key.localizedCaseInsensitiveContains(marker)
            }
        }
        let selectedReadings = cpuReadings.isEmpty ? validReadings : cpuReadings
        let average = selectedReadings.reduce(0) { $0 + $1.value } / Double(selectedReadings.count)
        return TemperatureResult(source: .hid, value: average)
    }
}

private struct SMCTemperatureReader {
    private let cpuTemperatureKeys = [
        "TC0D", "TC0E", "TC0F", "TC0H", "TC0P", "TCAD",
        "TC0C", "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C",
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",
        "Te05", "Te0L", "Te0P", "Te0S", "Te09", "Te0H",
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
        "Tp0V", "Tp0Y", "Tp0e",
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0a", "Tp0d", "Tp0g", "Tp0m", "Tp0p", "Tp0u", "Tp0y"
    ]

    private let fallbackTemperatureKeys = [
        "Tm0P", "Tm0p", "Tm1p", "Tm2p",
        "TN0D", "TN0H", "TN0P",
        "TaLP", "TaRF", "TH0x", "TB1T", "TB2T", "TW0P",
        "TA0P", "Th0H", "TZ0C", "TTLD", "TTRD"
    ]

    func readTemperature() -> TemperatureResult? {
        if let cpuTemperature = readCPUTemperature() {
            return cpuTemperature
        }
        return readFallbackTemperature()
    }

    func readCPUTemperature() -> TemperatureResult? {
        readTemperature(forKeys: cpuTemperatureKeys, label: "CPU", source: .smcCPU)
    }

    func readFallbackTemperature() -> TemperatureResult? {
        readTemperature(forKeys: fallbackTemperatureKeys, label: "fallback", source: .smcFallback)
    }

    private func readTemperature(forKeys keys: [String], label: String, source: TemperatureSource) -> TemperatureResult? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            NSLog("AirSentry temperature SMC: AppleSMC service unavailable")
            return nil
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == KERN_SUCCESS else {
            NSLog("AirSentry temperature SMC: IOServiceOpen failed, result=%d", openResult)
            return nil
        }
        defer { IOServiceClose(connection) }

        return averageTemperature(forKeys: keys, label: label, source: source, connection: connection)
    }

    private func averageTemperature(
        forKeys keys: [String],
        label: String,
        source: TemperatureSource,
        connection: io_connect_t
    ) -> TemperatureResult? {
        let readings: [TemperatureReading] = Array(Set(keys))
            .compactMap { key -> TemperatureReading? in
                guard let value = readTemperature(forKey: key, connection: connection) else { return nil }
                return TemperatureReading(key: key, value: value)
            }
            .filter { $0.value.isFinite && $0.value >= 15 && $0.value <= 125 }

        guard !readings.isEmpty else {
            NSLog("AirSentry temperature SMC %@: no readable keys", label)
            return nil
        }

        let average = readings.reduce(0) { $0 + $1.value } / Double(readings.count)
        return TemperatureResult(source: source, value: average)
    }

    private func readTemperature(forKey key: String, connection: io_connect_t) -> Double? {
        guard let keyInfo = readKeyInfo(key, connection: connection) else { return nil }

        var input = SMCKeyData()
        input.key = fourCharCode(key)
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = SMCCommand.readBytes.rawValue

        guard let output = callSMC(input: input, connection: connection) else { return nil }
        let bytes = bytes(from: output.bytes)
        return decodeTemperature(bytes: bytes, dataType: keyInfo.dataType, dataSize: keyInfo.dataSize)
    }

    private func readKeyInfo(_ key: String, connection: io_connect_t) -> SMCKeyInfo? {
        var input = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = SMCCommand.readKeyInfo.rawValue

        guard let output = callSMC(input: input, connection: connection),
              output.result == 0 else {
            return nil
        }

        return output.keyInfo
    }

    private func callSMC(input: SMCKeyData, connection: io_connect_t) -> SMCKeyData? {
        var input = input
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride

        let result = withUnsafePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    UInt32(SMCSelector.keyInfo.rawValue),
                    inputPointer,
                    MemoryLayout<SMCKeyData>.stride,
                    outputPointer,
                    &outputSize
                )
            }
        }

        return result == KERN_SUCCESS ? output : nil
    }

    private func decodeTemperature(bytes: [UInt8], dataType: UInt32, dataSize: UInt32) -> Double? {
        let type = string(fromFourCharCode: dataType)

        if (type == "sp78" || type == "fp78"), bytes.count >= 2 {
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return validTemperature(Double(raw) / 256.0)
        }

        if type == "flt ", bytes.count >= 4 {
            let raw = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            return validTemperature(Double(Float(bitPattern: raw)))
        }

        guard dataSize >= 2, bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return validTemperature(Double(raw) / 256.0)
    }

    private func validTemperature(_ value: Double) -> Double? {
        value.isFinite && value >= 0 && value <= 130 ? value : nil
    }

    private func bytes(from tuple: SMCBytes) -> [UInt8] {
        withUnsafeBytes(of: tuple) { Array($0) }
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        string.utf8.reduce(UInt32(0)) { result, character in
            (result << 8) + UInt32(character)
        }
    }

    private func string(fromFourCharCode code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? ""
    }
}

private struct TemperatureReading {
    let key: String
    let value: Double
}

private enum SMCSelector: UInt8 {
    case keyInfo = 2
}

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

private extension ProcessInfo.ThermalState {
    var thermalLevel: ThermalLevel {
        switch self {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }
}
