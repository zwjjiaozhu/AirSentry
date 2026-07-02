import SwiftUI
import UserNotifications

@main
struct AirGuardApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var alertManager = AlertManager()
    @StateObject private var monitorStore: MonitorStore
    @StateObject private var agentMonitorStore: AgentMonitorStore
    @StateObject private var inputMethodShortcutController: InputMethodShortcutController

    init() {
        let settings = AppSettings()
        let alertManager = AlertManager()
        _settings = StateObject(wrappedValue: settings)
        _alertManager = StateObject(wrappedValue: alertManager)
        _monitorStore = StateObject(wrappedValue: MonitorStore(settings: settings, alertManager: alertManager))
        _agentMonitorStore = StateObject(wrappedValue: AgentMonitorStore(settings: settings))
        _inputMethodShortcutController = StateObject(wrappedValue: InputMethodShortcutController(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView()
                .environmentObject(settings)
                .environmentObject(alertManager)
                .environmentObject(monitorStore)
                .environmentObject(agentMonitorStore)
                .frame(width: 400)
        } label: {
            MenuBarStatusLabel(settings: settings, monitorStore: monitorStore)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(alertManager)
                .environmentObject(agentMonitorStore)
                .frame(width: 860, height: 600)
        }

        Window("工具箱", id: "toolbox") {
            ToolboxView()
                .environmentObject(settings)
        }
        .defaultSize(width: 900, height: 650)
    }

}

private struct MenuBarStatusLabel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitorStore: MonitorStore

    private var snapshot: SystemSnapshot {
        monitorStore.snapshot
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.thermal.level.symbolName)

            Text(title)
                .monospacedDigit()
        }
        .help(helpText)
    }

    private var title: String {
        if settings.menuBarShowsTemperature,
           let temperature = snapshot.thermal.temperatureCelsius {
            return temperature.formatted(.number.precision(.fractionLength(0))) + "°"
        }

        return snapshot.thermal.level.shortTitle
    }

    private var helpText: String {
        if let temperature = snapshot.thermal.temperatureCelsius {
            return "当前温度 \(temperature.formatted(.number.precision(.fractionLength(0))))°C，状态：\(snapshot.thermal.level.title)"
        }

        return "当前状态：\(snapshot.thermal.level.title)。真实温度暂不可用。"
    }
}
