import Foundation
import IOKit
import IOKit.ps

struct BatteryReader {
    func read() -> BatteryInfo {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            LogArchiver.shared.warning("Battery read failed: power source snapshot/list unavailable")
            return .empty
        }

        guard let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            LogArchiver.shared.warning("Battery read failed: no readable power source description, sourceCount=\(sources.count)")
            return .empty
        }

        let currentCapacity = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
        let maxCapacity = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
        let levelRatio = if let currentCapacity, let maxCapacity, maxCapacity > 0 {
            min(max(currentCapacity / maxCapacity, 0), 1)
        } else {
            Optional<Double>.none
        }

        let powerState = description[kIOPSPowerSourceStateKey] as? String
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let isCharged = (description[kIOPSIsChargedKey] as? Bool) ?? false
        let isPowerAdapterConnected = powerState == kIOPSACPowerValue
        let isPresent = (description[kIOPSIsPresentKey] as? Bool) ?? (powerState != nil)
        let powerSourceCycleCount = (description["Cycle Count"] as? NSNumber)?.intValue
        let registryCycleCount = readCycleCountFromRegistry()
        let cycleCount = powerSourceCycleCount ?? registryCycleCount
        let health = description["BatteryHealth"] as? String ?? description["Battery Health"] as? String

        if isPresent, cycleCount == nil {
            let keys = description.keys.sorted().joined(separator: ", ")
            let currentCapacityText = currentCapacity.map { String($0) } ?? "nil"
            let maxCapacityText = maxCapacity.map { String($0) } ?? "nil"
            let powerStateText = powerState ?? "nil"
            let healthText = health ?? "nil"
            let designCycleCountText = (description["DesignCycleCount"] as? NSNumber).map { String($0.intValue) } ?? "nil"
            let message = "Battery cycle count unavailable: powerState=\(powerStateText) currentCapacity=\(currentCapacityText) maxCapacity=\(maxCapacityText) health=\(healthText) designCycleCount=\(designCycleCountText) keys=[\(keys)]"
            LogArchiver.shared.warning(message)
        }

        return BatteryInfo(
            levelRatio: levelRatio,
            isCharging: isCharging,
            isCharged: isCharged,
            isPowerAdapterConnected: isPowerAdapterConnected,
            isPresent: isPresent,
            cycleCount: cycleCount,
            health: health
        )
    }

    private func readCycleCountFromRegistry() -> Int? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            LogArchiver.shared.warning("Battery cycle count registry fallback failed: AppleSmartBattery service unavailable")
            return nil
        }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "CycleCount" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else {
            LogArchiver.shared.warning("Battery cycle count registry fallback failed: CycleCount property unavailable")
            return nil
        }

        return value.intValue
    }
}
