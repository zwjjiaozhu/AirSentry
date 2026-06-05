import Foundation
import AppKit
import UserNotifications

@MainActor
final class AlertManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var lastAlertLevel: ThermalLevel?
    private var lastAlertDate: Date?

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

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
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
