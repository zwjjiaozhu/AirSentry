import Foundation
import AppKit
import UserNotifications

@MainActor
final class AlertManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var lastAlertLevel: ThermalLevel?
    private var lastAlertDate: Date?
    private var lastBatteryAlertLevel: BatteryAlertLevel?
    private var lastBatteryAlertDate: Date?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    func requestAuthorization() {
        Task {
            if authorizationStatus == .denied {
                openNotificationSettings()
                return
            }

            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func handle(snapshot: SystemSnapshot, settings: AppSettings) {
        guard settings.notificationsEnabled else { return }
        handleThermalAlert(snapshot: snapshot, settings: settings)
        handleBatteryAlert(snapshot: snapshot, settings: settings)
    }

    private func handleThermalAlert(snapshot: SystemSnapshot, settings: AppSettings) {
        guard snapshot.thermal.level.severity >= settings.alertThermalLevel.severity else {
            lastAlertLevel = nil
            return
        }

        let now = Date()
        if lastAlertLevel == snapshot.thermal.level,
           let lastAlertDate,
           now.timeIntervalSince(lastAlertDate) < settings.notificationCooldown {
            return
        }

        lastAlertLevel = snapshot.thermal.level
        lastAlertDate = now
        sendThermalAlert(for: snapshot)
    }

    private func handleBatteryAlert(snapshot: SystemSnapshot, settings: AppSettings) {
        guard settings.batteryAlertsEnabled else {
            lastBatteryAlertLevel = nil
            return
        }

        let battery = snapshot.battery
        guard battery.isPresent, let levelRatio = battery.levelRatio else {
            lastBatteryAlertLevel = nil
            return
        }

        if battery.isCharging || battery.isPowerAdapterConnected {
            lastBatteryAlertLevel = nil
            return
        }

        let percent = levelRatio * 100
        let alertLevel: BatteryAlertLevel?
        if percent <= settings.criticalBatteryThreshold {
            alertLevel = .critical
        } else if percent <= settings.lowBatteryThreshold {
            alertLevel = .low
        } else {
            alertLevel = nil
        }

        guard let alertLevel else {
            lastBatteryAlertLevel = nil
            return
        }

        let now = Date()
        if lastBatteryAlertLevel == alertLevel,
           let lastBatteryAlertDate,
           now.timeIntervalSince(lastBatteryAlertDate) < settings.notificationCooldown {
            return
        }

        guard lastBatteryAlertLevel != .critical || alertLevel == .critical else { return }
        lastBatteryAlertLevel = alertLevel
        lastBatteryAlertDate = now
        sendBatteryAlert(for: battery, level: alertLevel)
    }

    private func sendThermalAlert(for snapshot: SystemSnapshot) {
        let content = UNMutableNotificationContent()
        content.title = "AirSentry \(snapshot.thermal.level.title)提醒"
        content.body = "当前热状态：\(snapshot.thermal.level.title)。建议降低负载或改善散热。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "airsentry.thermal.\(snapshot.capturedAt.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func sendBatteryAlert(for battery: BatteryInfo, level: BatteryAlertLevel) {
        let percentText = battery.levelRatio.map { Int(($0 * 100).rounded()) } ?? 0
        let content = UNMutableNotificationContent()
        content.title = level.title
        content.body = "当前电量 \(percentText)%，建议尽快连接电源。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "airsentry.battery.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum BatteryAlertLevel {
    case low
    case critical

    var title: String {
        switch self {
        case .low: "AirSentry 电量偏低"
        case .critical: "AirSentry 电量严重偏低"
        }
    }
}

extension AlertManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
