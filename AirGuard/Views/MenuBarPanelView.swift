import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var monitorStore: MonitorStore
    @EnvironmentObject private var alertManager: AlertManager

    private var snapshot: SystemSnapshot { monitorStore.snapshot }

    var body: some View {
        VStack(spacing: 14) {
            header
            thermalHero
            metricsGrid
            suggestionCard
            footer
        }
        .padding(20)
        .background(panelBackground)
        .task {
            alertManager.requestAuthorization()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.12))

                Image(systemName: "shield.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("AirSentry")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)

                Text("守护你的 MacBook Air")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Image(systemName: snapshot.thermal.level.symbolName)
                .font(.system(size: 15, weight: .semibold))

            Text(snapshot.thermal.level.shortTitle)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(thermalColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(thermalColor.opacity(0.12), in: Capsule())
    }

    private var thermalHero: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(thermalColor.opacity(0.10))
                    .frame(width: 92, height: 92)

                Circle()
                    .fill(thermalColor.opacity(0.13))
                    .frame(width: 60, height: 60)

                Image(systemName: "thermometer.medium")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(thermalColor)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(temperatureText)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 8) {
                    Text("系统热状态：")
                        .foregroundStyle(.secondary)

                    Text(snapshot.thermal.level.title)
                        .foregroundStyle(thermalColor)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 15))
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    thermalColor.opacity(0.13),
                    heroSurfaceColor,
                    heroSurfaceColor.opacity(0.72)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(surfaceStrokeColor, lineWidth: 1)
        )
        .shadow(color: thermalColor.opacity(0.08), radius: 16, y: 8)
    }

    private var metricsGrid: some View {
        HStack(alignment: .top, spacing: 12) {
            activityMonitorButton {
                MetricTile(
                    title: "CPU",
                    systemImage: "cpu",
                    tint: .blue,
                    value: percent(snapshot.cpuUsage)
                ) {
                    Sparkline(color: .blue, values: monitorStore.cpuSparklineValues)
                        .frame(height: 32)
                }
            }

            activityMonitorButton {
                MetricTile(
                    title: "内存",
                    systemImage: "memorychip",
                    tint: memoryPressureColor,
                    value: percent(snapshot.memory.usageRatio)
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(ByteFormatter.string(from: snapshot.memory.usedBytes)) / \(ByteFormatter.string(from: snapshot.memory.totalBytes))")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        ProgressView(value: snapshot.memory.usageRatio)
                            .tint(memoryPressureColor)

                        memoryPressureLine
                    }
                }
            }

            activityMonitorButton {
                MetricTile(
                    title: "网络",
                    systemImage: "network",
                    tint: .green,
                    value: nil
                ) {
                    VStack(alignment: .leading, spacing: 9) {
                        networkLine(systemImage: "arrow.down", color: .blue, value: ByteFormatter.speedString(from: snapshot.network.downloadBytesPerSecond))
                        networkLine(systemImage: "arrow.up", color: .green, value: ByteFormatter.speedString(from: snapshot.network.uploadBytesPerSecond))
                        ZStack {
                            Sparkline(color: .blue, values: monitorStore.networkDownloadSparklineValues, fillOpacity: 0.12)
                            Sparkline(color: .green, values: monitorStore.networkUploadSparklineValues, fillOpacity: 0.08)
                        }
                            .frame(height: 24)
                    }
                }
            }
        }
    }

    private var suggestionCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.18))
                Image(systemName: "lightbulb")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.orange)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text("建议")
                    .font(.system(size: 16, weight: .semibold))

                suggestionContent
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(surfaceStrokeColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var suggestionContent: some View {
        if shouldShowTopCPUProcesses {
            topCPUProcessesSuggestion
        } else {
            Text(suggestionText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var topCPUProcessesSuggestion: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("当前达到通知温度级别，优先检查高 CPU 进程。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if monitorStore.topCPUProcesses.isEmpty {
                Text(monitorStore.isRefreshingTopCPUProcesses ? "正在读取高 CPU 进程..." : "暂未读取到高 CPU 进程。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ForEach(Array(monitorStore.topCPUProcesses.enumerated()), id: \.element.id) { index, process in
                    topCPUProcessLine(index: index, process: process)
                }
            }
        }
    }

    private func topCPUProcessLine(index: Int, process: TopCPUProcess) -> some View {
        HStack(spacing: 6) {
            Text("\(index + 1).")
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)

            Text(process.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(process.cpuPercent.formatted(.number.precision(.fractionLength(1))) + "%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
        }
        .font(.system(size: 12, weight: .medium))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                openToolboxWindow()
            } label: {
                Label("工具箱", systemImage: "wrench.and.screwdriver")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelButtonStyle())

            settingsButton

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelButtonStyle())
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                settingsLabel
            }
            .simultaneousGesture(TapGesture().onEnded {
                dismiss()
                NSApp.activate(ignoringOtherApps: true)
            })
            .buttonStyle(PanelButtonStyle())
        } else {
            Button {
                openSettingsWindow()
                dismiss()
            } label: {
                settingsLabel
            }
            .buttonStyle(PanelButtonStyle())
        }
    }

    private var settingsLabel: some View {
        Label("设置", systemImage: "gearshape")
            .frame(maxWidth: .infinity)
    }

    private var panelBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    backgroundSurfaceColor.opacity(0.92),
                    Color.blue.opacity(0.08),
                    backgroundSurfaceColor.opacity(0.80)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func networkLine(systemImage: String, color: Color, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14)

            Text(value)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
    }

    private var memoryPressureLine: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.memory.pressureLevel.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(memoryPressureColor)
                .frame(width: 14)

            Text("压力 \(snapshot.memory.pressureLevel.title)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(memoryPressureColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openToolboxWindow() {
        dismiss()
        openWindow(id: "toolbox")
        NSApp.activate(ignoringOtherApps: true)

        bringToolboxWindowToFront()
        [0.05, 0.15, 0.35].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                bringToolboxWindowToFront()
            }
        }
    }

    private func bringToolboxWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)

        guard let toolboxWindow = NSApp.windows.first(where: { $0.title == "工具箱" }) else {
            return
        }

        toolboxWindow.deminiaturize(nil)
        toolboxWindow.orderFrontRegardless()
        toolboxWindow.makeKeyAndOrderFront(nil)
    }

    private func openActivityMonitor() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return
        }

        let fallbackURL = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: fallbackURL, configuration: configuration)
    }

    private func activityMonitorButton<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Button {
            openActivityMonitor()
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .pointingHandCursor()
        .help("打开活动监视器")
    }

    private var temperatureText: String {
        guard let temperature = snapshot.thermal.temperatureCelsius else { return "温度不可用" }
        return "\(temperature.formatted(.number.precision(.fractionLength(1)))) °C"
    }

    private var suggestionText: String {
        switch snapshot.thermal.level {
        case .nominal:
            "当前状态良好，可以继续正常使用。"
        case .fair:
            "当前略微偏热，建议保持通风，避免长时间重负载。"
        case .serious:
            "当前处于高温状态，建议降低负载并改善散热。"
        case .critical:
            "当前热状态严重，建议尽快停止重负载任务。"
        case .unknown:
            "热状态暂时未知，请稍后刷新查看。"
        }
    }

    private var shouldShowTopCPUProcesses: Bool {
        snapshot.thermal.level.severity >= settings.alertThermalLevel.severity
    }

    private var thermalColor: Color {
        switch snapshot.thermal.level {
        case .nominal: .green
        case .fair: .orange
        case .serious: .red
        case .critical: .red
        case .unknown: .secondary
        }
    }

    private var memoryPressureColor: Color {
        switch snapshot.memory.pressureLevel {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private var backgroundSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white
    }

    private var heroSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.70)
    }

    private var surfaceStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.62)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct MetricTile<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String
    let tint: Color
    let value: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 30, height: 30)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Spacer(minLength: 0)
            }

            if let value {
                Text(value)
                    .font(.system(size: 27, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            content

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 166, maxHeight: 166, alignment: .topLeading)
        .background(surfaceColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(surfaceStrokeColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 12, y: 5)
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
    }

    private var surfaceStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.72)
    }
}

private struct Sparkline: View {
    let color: Color
    let values: [Double]
    var fillOpacity: Double = 0.24

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }

            let points = values.enumerated().map { index, value in
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let clamped = min(max(value, 0), 1)
                let y = size.height * CGFloat(1 - clamped)
                return CGPoint(x: x, y: y)
            }

            var line = Path()
            line.move(to: points[0])
            for point in points.dropFirst() {
                line.addLine(to: point)
            }

            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()

            context.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(fillOpacity), color.opacity(0.02)]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            ))
            context.stroke(line, with: .color(color), lineWidth: 2)
        }
    }
}

private struct PanelButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.vertical, 13)
            .background(
                surfaceColor(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(surfaceStrokeColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(shadowOpacity(isPressed: configuration.isPressed)), radius: 10, y: 4)
    }

    private var surfaceStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.72)
    }

    private func surfaceColor(isPressed: Bool) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(isPressed ? 0.06 : 0.09)
        }
        return Color.white.opacity(isPressed ? 0.58 : 0.72)
    }

    private func shadowOpacity(isPressed: Bool) -> Double {
        colorScheme == .dark ? (isPressed ? 0.16 : 0.24) : (isPressed ? 0.03 : 0.06)
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @State private var isPointing = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, !isPointing {
                    NSCursor.pointingHand.push()
                    isPointing = true
                } else if !hovering, isPointing {
                    NSCursor.pop()
                    isPointing = false
                }
            }
            .onDisappear {
                if isPointing {
                    NSCursor.pop()
                    isPointing = false
                }
            }
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}
