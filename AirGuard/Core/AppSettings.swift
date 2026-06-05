import Foundation
import Combine

final class AppSettings: ObservableObject {
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    @Published var menuBarShowsTemperature: Bool {
        didSet { defaults.set(menuBarShowsTemperature, forKey: Keys.menuBarShowsTemperature) }
    }

    @Published var alertThermalLevel: ThermalLevel {
        didSet { defaults.set(alertThermalLevel.rawValue, forKey: Keys.alertThermalLevel) }
    }

    @Published var fairTemperatureThreshold: Double {
        didSet { defaults.set(fairTemperatureThreshold, forKey: Keys.fairTemperatureThreshold) }
    }

    @Published var seriousTemperatureThreshold: Double {
        didSet { defaults.set(seriousTemperatureThreshold, forKey: Keys.seriousTemperatureThreshold) }
    }

    @Published var criticalTemperatureThreshold: Double {
        didSet { defaults.set(criticalTemperatureThreshold, forKey: Keys.criticalTemperatureThreshold) }
    }

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published var notificationCooldown: TimeInterval {
        didSet { defaults.set(notificationCooldown, forKey: Keys.notificationCooldown) }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled)
            LaunchAtLoginManager.setEnabled(launchAtLoginEnabled)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        menuBarShowsTemperature = defaults.object(forKey: Keys.menuBarShowsTemperature) as? Bool ?? true
        let savedLevel = defaults.string(forKey: Keys.alertThermalLevel)
        alertThermalLevel = ThermalLevel(rawValue: savedLevel ?? "") ?? .serious
        let savedFairThreshold = defaults.double(forKey: Keys.fairTemperatureThreshold)
        fairTemperatureThreshold = savedFairThreshold > 0 ? savedFairThreshold : 55
        let savedSeriousThreshold = defaults.double(forKey: Keys.seriousTemperatureThreshold)
        seriousTemperatureThreshold = savedSeriousThreshold > 0 ? savedSeriousThreshold : 65
        let savedCriticalThreshold = defaults.double(forKey: Keys.criticalTemperatureThreshold)
        criticalTemperatureThreshold = savedCriticalThreshold > 0 ? savedCriticalThreshold : 82
        let savedInterval = defaults.double(forKey: Keys.refreshInterval)
        refreshInterval = savedInterval > 0 ? savedInterval : 2
        let savedCooldown = defaults.double(forKey: Keys.notificationCooldown)
        notificationCooldown = savedCooldown >= 0 ? savedCooldown : 60
        launchAtLoginEnabled = defaults.object(forKey: Keys.launchAtLoginEnabled) as? Bool ?? LaunchAtLoginManager.isEnabled
        normalizeLoadedTemperatureThresholds()
        normalizeLoadedIntervals()
    }

    func effectiveThermalStatus(from status: ThermalStatus) -> ThermalStatus {
        guard let temperature = status.temperatureCelsius else { return status }

        let level: ThermalLevel
        if temperature >= criticalTemperatureThreshold {
            level = .critical
        } else if temperature >= seriousTemperatureThreshold {
            level = .serious
        } else if temperature >= fairTemperatureThreshold {
            level = .fair
        } else {
            level = .nominal
        }

        return ThermalStatus(level: level, temperatureCelsius: temperature)
    }

    func setAlertThermalLevel(_ level: ThermalLevel) {
        alertThermalLevel = level
    }

    func setFairTemperatureThreshold(_ value: Double) {
        fairTemperatureThreshold = min(max(value, 30), 123)
        if seriousTemperatureThreshold <= fairTemperatureThreshold {
            seriousTemperatureThreshold = min(fairTemperatureThreshold + 1, 124)
        }
        if criticalTemperatureThreshold <= seriousTemperatureThreshold {
            criticalTemperatureThreshold = min(seriousTemperatureThreshold + 1, 125)
        }
    }

    func setSeriousTemperatureThreshold(_ value: Double) {
        seriousTemperatureThreshold = min(max(value, 31), 124)
        if fairTemperatureThreshold >= seriousTemperatureThreshold {
            fairTemperatureThreshold = max(seriousTemperatureThreshold - 1, 30)
        }
        if criticalTemperatureThreshold <= seriousTemperatureThreshold {
            criticalTemperatureThreshold = min(seriousTemperatureThreshold + 1, 125)
        }
    }

    func setCriticalTemperatureThreshold(_ value: Double) {
        criticalTemperatureThreshold = min(max(value, 32), 125)
        if seriousTemperatureThreshold >= criticalTemperatureThreshold {
            seriousTemperatureThreshold = min(max(criticalTemperatureThreshold - 1, 31), 124)
        }
        if fairTemperatureThreshold >= seriousTemperatureThreshold {
            fairTemperatureThreshold = max(seriousTemperatureThreshold - 1, 30)
        }
    }

    func setRefreshInterval(_ value: TimeInterval) {
        refreshInterval = min(max(value, 1), 60)
    }

    func setNotificationCooldown(_ value: TimeInterval) {
        notificationCooldown = min(max(value, 0), 60 * 60)
    }

    private func normalizeLoadedTemperatureThresholds() {
        fairTemperatureThreshold = min(max(fairTemperatureThreshold, 30), 123)
        seriousTemperatureThreshold = min(max(seriousTemperatureThreshold, fairTemperatureThreshold + 1), 124)
        criticalTemperatureThreshold = min(max(criticalTemperatureThreshold, seriousTemperatureThreshold + 1), 125)
    }

    private func normalizeLoadedIntervals() {
        refreshInterval = min(max(refreshInterval, 1), 60)
        notificationCooldown = min(max(notificationCooldown, 0), 60 * 60)
    }
}

private enum Keys {
    static let notificationsEnabled = "notificationsEnabled"
    static let menuBarShowsTemperature = "menuBarShowsTemperature"
    static let alertThermalLevel = "alertThermalLevel"
    static let fairTemperatureThreshold = "fairTemperatureThreshold"
    static let seriousTemperatureThreshold = "seriousTemperatureThreshold"
    static let criticalTemperatureThreshold = "criticalTemperatureThreshold"
    static let refreshInterval = "refreshInterval"
    static let notificationCooldown = "notificationCooldown"
    static let launchAtLoginEnabled = "launchAtLoginEnabled"
}
