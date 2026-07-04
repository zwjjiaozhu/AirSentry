import Foundation
import Combine
import Carbon.HIToolbox

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

    @Published var agentNotchEnabled: Bool {
        didSet { defaults.set(agentNotchEnabled, forKey: Keys.agentNotchEnabled) }
    }

    @Published var codexMonitoringEnabled: Bool {
        didSet { defaults.set(codexMonitoringEnabled, forKey: Keys.codexMonitoringEnabled) }
    }

    @Published var claudeMonitoringEnabled: Bool {
        didSet { defaults.set(claudeMonitoringEnabled, forKey: Keys.claudeMonitoringEnabled) }
    }

    @Published var agentCompletionDisplayDuration: TimeInterval {
        didSet { defaults.set(agentCompletionDisplayDuration, forKey: Keys.agentCompletionDisplayDuration) }
    }

    @Published var musicNotchEnabled: Bool {
        didSet { defaults.set(musicNotchEnabled, forKey: Keys.musicNotchEnabled) }
    }

    @Published var inputMethodShortcutsEnabled: Bool {
        didSet { defaults.set(inputMethodShortcutsEnabled, forKey: Keys.inputMethodShortcutsEnabled) }
    }

    @Published var inputMethodShortcutRules: [InputMethodShortcutRule] {
        didSet { saveInputMethodShortcutRules() }
    }

    @Published var appLauncherShortcutEnabled: Bool {
        didSet { defaults.set(appLauncherShortcutEnabled, forKey: Keys.appLauncherShortcutEnabled) }
    }

    @Published var appLauncherShortcut: KeyboardShortcut? {
        didSet { saveAppLauncherShortcut() }
    }

    @Published var screenshotShortcutEnabled: Bool {
        didSet { defaults.set(screenshotShortcutEnabled, forKey: Keys.screenshotShortcutEnabled) }
    }

    @Published var screenshotShortcut: KeyboardShortcut? {
        didSet { saveScreenshotShortcut() }
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
        agentNotchEnabled = defaults.object(forKey: Keys.agentNotchEnabled) as? Bool ?? false
        codexMonitoringEnabled = defaults.object(forKey: Keys.codexMonitoringEnabled) as? Bool ?? true
        claudeMonitoringEnabled = defaults.object(forKey: Keys.claudeMonitoringEnabled) as? Bool ?? true
        let savedAgentCompletionDuration = defaults.double(forKey: Keys.agentCompletionDisplayDuration)
        agentCompletionDisplayDuration = savedAgentCompletionDuration > 0 ? savedAgentCompletionDuration : 4
        musicNotchEnabled = defaults.object(forKey: Keys.musicNotchEnabled) as? Bool ?? true
        inputMethodShortcutsEnabled = defaults.object(forKey: Keys.inputMethodShortcutsEnabled) as? Bool ?? false
        inputMethodShortcutRules = Self.loadInputMethodShortcutRules(from: defaults)
        appLauncherShortcutEnabled = defaults.object(forKey: Keys.appLauncherShortcutEnabled) as? Bool ?? false
        appLauncherShortcut = Self.loadAppLauncherShortcut(from: defaults)
        screenshotShortcutEnabled = defaults.object(forKey: Keys.screenshotShortcutEnabled) as? Bool ?? true
        screenshotShortcut = Self.loadScreenshotShortcut(from: defaults)
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
        let clampedValue = min(max(value, 0), 60 * 60)
        notificationCooldown = (clampedValue / 5).rounded() * 5
    }

    func setAgentCompletionDisplayDuration(_ value: TimeInterval) {
        agentCompletionDisplayDuration = min(max(value, 2), 15)
    }

    func setInputMethodShortcutRules(_ rules: [InputMethodShortcutRule]) {
        inputMethodShortcutRules = rules
    }

    func addInputMethodShortcutRule() {
        inputMethodShortcutRules.append(InputMethodShortcutRule())
    }

    func updateInputMethodShortcutRule(_ rule: InputMethodShortcutRule) {
        guard let index = inputMethodShortcutRules.firstIndex(where: { $0.id == rule.id }) else { return }
        inputMethodShortcutRules[index] = rule
    }

    func removeInputMethodShortcutRule(id: UUID) {
        inputMethodShortcutRules.removeAll { $0.id == id }
    }

    func setAppLauncherShortcut(_ shortcut: KeyboardShortcut) {
        appLauncherShortcut = shortcut
    }

    func setScreenshotShortcut(_ shortcut: KeyboardShortcut) {
        screenshotShortcut = shortcut
    }

    private func normalizeLoadedTemperatureThresholds() {
        fairTemperatureThreshold = min(max(fairTemperatureThreshold, 30), 123)
        seriousTemperatureThreshold = min(max(seriousTemperatureThreshold, fairTemperatureThreshold + 1), 124)
        criticalTemperatureThreshold = min(max(criticalTemperatureThreshold, seriousTemperatureThreshold + 1), 125)
    }

    private func normalizeLoadedIntervals() {
        refreshInterval = min(max(refreshInterval, 1), 60)
        let clampedCooldown = min(max(notificationCooldown, 0), 60 * 60)
        notificationCooldown = (clampedCooldown / 5).rounded() * 5
    }

    private func saveInputMethodShortcutRules() {
        do {
            let data = try JSONEncoder().encode(inputMethodShortcutRules)
            defaults.set(data, forKey: Keys.inputMethodShortcutRules)
        } catch {
            NSLog("AirSentry input method shortcut rules save failed: \(error.localizedDescription)")
        }
    }

    private func saveAppLauncherShortcut() {
        guard let appLauncherShortcut else {
            defaults.removeObject(forKey: Keys.appLauncherShortcut)
            return
        }

        do {
            let data = try JSONEncoder().encode(appLauncherShortcut)
            defaults.set(data, forKey: Keys.appLauncherShortcut)
        } catch {
            NSLog("AirSentry app launcher shortcut save failed: \(error.localizedDescription)")
        }
    }

    private func saveScreenshotShortcut() {
        guard let screenshotShortcut else {
            defaults.removeObject(forKey: Keys.screenshotShortcut)
            return
        }

        do {
            let data = try JSONEncoder().encode(screenshotShortcut)
            defaults.set(data, forKey: Keys.screenshotShortcut)
        } catch {
            NSLog("AirSentry screenshot shortcut save failed: \(error.localizedDescription)")
        }
    }

    private static func loadInputMethodShortcutRules(from defaults: UserDefaults) -> [InputMethodShortcutRule] {
        guard let data = defaults.data(forKey: Keys.inputMethodShortcutRules) else {
            return [
                InputMethodShortcutRule(
                    shortcut: KeyboardShortcut(keyCode: 18, modifiers: UInt32(controlKey)),
                    inputSourceID: nil
                ),
                InputMethodShortcutRule(
                    shortcut: KeyboardShortcut(keyCode: 19, modifiers: UInt32(controlKey)),
                    inputSourceID: nil
                )
            ]
        }

        do {
            let rules = try JSONDecoder().decode([InputMethodShortcutRule].self, from: data)
            return rules.isEmpty ? [InputMethodShortcutRule()] : rules
        } catch {
            NSLog("AirSentry input method shortcut rules load failed: \(error.localizedDescription)")
            return [InputMethodShortcutRule()]
        }
    }

    private static func loadAppLauncherShortcut(from defaults: UserDefaults) -> KeyboardShortcut? {
        guard let data = defaults.data(forKey: Keys.appLauncherShortcut) else {
            return KeyboardShortcut(keyCode: 49, modifiers: UInt32(optionKey))
        }

        do {
            return try JSONDecoder().decode(KeyboardShortcut.self, from: data)
        } catch {
            NSLog("AirSentry app launcher shortcut load failed: \(error.localizedDescription)")
            return KeyboardShortcut(keyCode: 49, modifiers: UInt32(optionKey))
        }
    }

    private static func loadScreenshotShortcut(from defaults: UserDefaults) -> KeyboardShortcut? {
        guard let data = defaults.data(forKey: Keys.screenshotShortcut) else {
            return KeyboardShortcut(keyCode: 0, modifiers: UInt32(controlKey | shiftKey))
        }

        do {
            return try JSONDecoder().decode(KeyboardShortcut.self, from: data)
        } catch {
            NSLog("AirSentry screenshot shortcut load failed: \(error.localizedDescription)")
            return KeyboardShortcut(keyCode: 0, modifiers: UInt32(controlKey | shiftKey))
        }
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
    static let agentNotchEnabled = "agentNotchEnabled"
    static let codexMonitoringEnabled = "codexMonitoringEnabled"
    static let claudeMonitoringEnabled = "claudeMonitoringEnabled"
    static let agentCompletionDisplayDuration = "agentCompletionDisplayDuration"
    static let musicNotchEnabled = "musicNotchEnabled"
    static let inputMethodShortcutsEnabled = "inputMethodShortcutsEnabled"
    static let inputMethodShortcutRules = "inputMethodShortcutRules"
    static let appLauncherShortcutEnabled = "appLauncherShortcutEnabled"
    static let appLauncherShortcut = "appLauncherShortcut"
    static let screenshotShortcutEnabled = "screenshotShortcutEnabled"
    static let screenshotShortcut = "screenshotShortcut"
}
