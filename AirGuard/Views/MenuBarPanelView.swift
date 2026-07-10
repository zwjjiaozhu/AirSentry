import AppKit
import IOKit
import IOKit.ps
import SwiftUI

struct MenuBarPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var monitorStore: MonitorStore
    @EnvironmentObject private var alertManager: AlertManager
    @EnvironmentObject private var screenshotCaptureController: ScreenshotCaptureController
    @State private var showsSystemStatusPopover = false
    @State private var moreStatusBattery: BatteryInfo = .empty
    @State private var moreStatusDisk: DiskStorageInfo = .empty
    @State private var moreStatusDiskIO: DiskIOInfo = .empty

    private var snapshot: SystemSnapshot { monitorStore.snapshot }
    private let batteryReader = BatteryReader()
    private let diskIOReader = DiskIOReader()
    private let storageReader = StorageReader()

    var body: some View {
        VStack(spacing: 12) {
            header
            thermalHero
            metricsGrid
            suggestionCard
            footer
        }
        .padding(18)
        .background(panelBackground)
        .task {
            alertManager.requestAuthorization()
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.12))

                Image(systemName: "shield.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("AirSentry")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(.primary)

                Text("六边形哨兵，守护你的Mac")
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
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(thermalColor.opacity(0.13))
                    .frame(width: 52, height: 52)

                Image(systemName: "thermometer.medium")
                    .font(.system(size: 32, weight: .medium))
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
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
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
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.18))
                Image(systemName: "lightbulb")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.orange)
            }
            .frame(width: 38, height: 38)

            suggestionContent

            Spacer(minLength: 0)

            Button {
                refreshMoreSystemStatus()
                showsSystemStatusPopover.toggle()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("查看更多系统状态")
            .popover(isPresented: $showsSystemStatusPopover, arrowEdge: .trailing) {
                moreSystemStatusPanel
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(surfaceStrokeColor, lineWidth: 1)
        )
    }

    private var moreSystemStatusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("更多系统状态")
                    .font(.system(size: 18, weight: .bold))

                Spacer()

                Button {
                    showsSystemStatusPopover = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("关闭")
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 0),
                GridItem(.flexible(), spacing: 0)
            ], spacing: 0) {
                statusMiniCell(
                    title: "电池电量",
                    value: batteryLevelText,
                    systemImage: "battery.100percent",
                    tint: batteryTint
                ) {
                    ProgressView(value: moreStatusBattery.levelRatio ?? 0)
                        .tint(batteryTint)
                }

                statusMiniCell(
                    title: "充电状态",
                    value: chargingStatusText,
                    systemImage: "powerplug",
                    tint: .green
                )

                statusMiniCell(
                    title: "电池健康",
                    value: batteryHealthText,
                    systemImage: "heart",
                    tint: batteryHealthTint
                )

                statusMiniCell(
                    title: "循环次数",
                    value: batteryCycleText,
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .secondary
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(popoverStrokeColor, lineWidth: 1)
            )

            statusWideCell(
                title: "存储状态",
                value: diskHealthText,
                detail: diskHealthDetail,
                systemImage: "shield",
                tint: diskTint
            ) {
                diskIOStatusLine
            }

            statusWideCell(
                title: "磁盘容量",
                value: diskCapacityText,
                detail: diskUsageText,
                systemImage: "internaldrive",
                tint: .blue
            ) {
                ProgressView(value: moreStatusDisk.usageRatio)
                    .tint(.blue)
            }

            statusWideCell(
                title: "内存使用",
                value: "\(ByteFormatter.string(from: snapshot.memory.usedBytes)) / \(ByteFormatter.string(from: snapshot.memory.totalBytes))",
                detail: percent(snapshot.memory.usageRatio),
                systemImage: "memorychip",
                tint: memoryPressureColor
            ) {
                ProgressView(value: snapshot.memory.usageRatio)
                    .tint(memoryPressureColor)
            }

            Button {
                openActivityMonitor()
                showsSystemStatusPopover = false
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("打开系统监控")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("查看更详细的系统数据与历史趋势")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(popoverSurfaceColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(popoverStrokeColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(16)
        .frame(width: 350)
        .background(panelBackground)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
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

            HStack(spacing: 0) {
                quickToolBar
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)
        }
    }

    private var quickToolBar: some View {
        HStack(spacing: 6) {
            ForEach(displayedQuickTools) { tool in
                QuickToolIconButton(tool: tool) {
                    runQuickTool(tool)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(surfaceColor.opacity(0.44), in: Capsule())
        .overlay(
            Capsule()
                .stroke(surfaceStrokeColor.opacity(0.72), lineWidth: 1)
        )
    }

    private var displayedQuickTools: [MenuBarQuickTool] {
        let tools = settings.menuBarQuickTools.isEmpty ? MenuBarQuickTool.defaultTools : settings.menuBarQuickTools
        return Array(tools.prefix(8))
    }

    private func runQuickTool(_ tool: MenuBarQuickTool) {
        switch tool {
        case .appLauncher:
            dismiss()
            NotificationCenter.default.post(name: .showAppLauncherPanel, object: nil)
        case .screenshot:
            dismiss()
            screenshotCaptureController.startCapture()
        case .ocr:
            dismiss()
            OCRPanelController.shared.show()
        case .translation:
            dismiss()
            NotificationCenter.default.post(name: .showTranslationPanel, object: nil)
        case .imageProcessing, .superRightClick, .storage, .uninstaller, .inputMethod:
            openToolboxWindow(selecting: tool)
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

    private func statusMiniCell<Content: View>(
        title: String,
        value: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                content()
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(height: 82)
        .background(popoverSurfaceColor)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(popoverStrokeColor)
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(popoverStrokeColor)
                .frame(height: 1)
        }
    }

    private func statusMiniCell(
        title: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        statusMiniCell(title: title, value: value, systemImage: systemImage, tint: tint) {
            EmptyView()
        }
    }

    private func statusWideCell<Content: View>(
        title: String,
        value: String,
        detail: String? = nil,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(value)
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    if let detail {
                        Text(detail)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    }
                }

                content()
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 72)
        .background(popoverSurfaceColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(popoverStrokeColor, lineWidth: 1)
        )
    }

    private func statusWideCell(
        title: String,
        value: String,
        detail: String? = nil,
        systemImage: String,
        tint: Color
    ) -> some View {
        statusWideCell(title: title, value: value, detail: detail, systemImage: systemImage, tint: tint) {
            EmptyView()
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

    private func openToolboxWindow(selecting quickTool: MenuBarQuickTool? = nil) {
        dismiss()
        openWindow(id: "toolbox")
        NSApp.activate(ignoringOtherApps: true)

        bringToolboxWindowToFront()
        [0.05, 0.15, 0.35].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                bringToolboxWindowToFront()
                if let quickTool {
                    NotificationCenter.default.post(name: .selectToolboxSection, object: quickTool.rawValue)
                }
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

    private func refreshMoreSystemStatus() {
        moreStatusBattery = batteryReader.read()
        moreStatusDisk = storageReader.readDiskStorage()
        moreStatusDiskIO = diskIOReader.read()
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

    private var batteryLevelText: String {
        guard moreStatusBattery.isPresent, let levelRatio = moreStatusBattery.levelRatio else { return "不可用" }
        return percent(levelRatio)
    }

    private var chargingStatusText: String {
        guard moreStatusBattery.isPresent else { return "不可用" }
        if moreStatusBattery.isCharged { return "已充满" }
        return moreStatusBattery.isCharging ? "充电中" : "未充电"
    }

    private var batteryHealthText: String {
        guard moreStatusBattery.isPresent else { return "不可用" }
        guard let health = moreStatusBattery.health, !health.isEmpty else { return "良好" }
        switch health.lowercased() {
        case "good": return "良好"
        case "fair": return "一般"
        case "poor": return "较差"
        default: return health
        }
    }

    private var batteryCycleText: String {
        guard moreStatusBattery.isPresent else { return "不可用" }
        guard let cycleCount = moreStatusBattery.cycleCount else { return "未知" }
        return "\(cycleCount) 次"
    }

    private var diskCapacityText: String {
        guard moreStatusDisk.totalBytes > 0 else { return "不可用" }
        return "\(ByteFormatter.string(from: moreStatusDisk.usedBytes)) / \(ByteFormatter.string(from: moreStatusDisk.totalBytes))"
    }

    private var diskUsageText: String {
        moreStatusDisk.totalBytes > 0 ? percent(moreStatusDisk.usageRatio) : ""
    }

    private var diskHealthText: String {
        guard moreStatusDisk.totalBytes > 0 else { return "未知" }
        return moreStatusDisk.usageRatio < 0.90 ? "正常" : "空间紧张"
    }

    private var diskHealthDetail: String {
        guard moreStatusDisk.totalBytes > 0 else { return "" }
        return "基于剩余空间"
    }

    private var diskIOStatusLine: some View {
        HStack(spacing: 12) {
            diskIOBadge(systemImage: "arrow.down", color: .green, text: "写 \(diskWriteText)")
            diskIOBadge(systemImage: "arrow.up", color: .blue, text: "读 \(diskReadText)")
            Spacer(minLength: 0)
        }
    }

    private func diskIOBadge(systemImage: String, color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)

            Text(text)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private var diskReadText: String {
        moreStatusDiskIO.readBytes.map(ByteFormatter.string(from:)) ?? "不可用"
    }

    private var diskWriteText: String {
        moreStatusDiskIO.writeBytes.map(ByteFormatter.string(from:)) ?? "不可用"
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

    private var batteryTint: Color {
        guard let levelRatio = moreStatusBattery.levelRatio else { return .secondary }
        if levelRatio <= 0.20 { return .red }
        if levelRatio <= 0.35 { return .orange }
        return .green
    }

    private var batteryHealthTint: Color {
        batteryHealthText == "较差" ? .orange : .green
    }

    private var diskTint: Color {
        moreStatusDisk.usageRatio >= 0.90 ? .orange : .green
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

    private var popoverSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.62)
    }

    private var popoverStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
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

private struct BatteryReader {
    func read() -> BatteryInfo {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            LogArchiver.shared.warning("More system status battery read failed: power source snapshot/list unavailable")
            return .empty
        }

        guard let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            LogArchiver.shared.warning("More system status battery read failed: no readable power source description, sourceCount=\(sources.count)")
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
            let message = "More system status battery cycle count unavailable: powerState=\(powerStateText) currentCapacity=\(currentCapacityText) maxCapacity=\(maxCapacityText) health=\(healthText) designCycleCount=\(designCycleCountText) keys=[\(keys)]"
            LogArchiver.shared.warning(message)
        }

        return BatteryInfo(
            levelRatio: levelRatio,
            isCharging: isCharging,
            isCharged: isCharged,
            isPresent: isPresent,
            cycleCount: cycleCount,
            health: health
        )
    }

    private func readCycleCountFromRegistry() -> Int? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            LogArchiver.shared.warning("More system status battery cycle count registry fallback failed: AppleSmartBattery service unavailable")
            return nil
        }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "CycleCount" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else {
            LogArchiver.shared.warning("More system status battery cycle count registry fallback failed: CycleCount property unavailable")
            return nil
        }

        return value.intValue
    }
}

private struct DiskIOInfo: Equatable {
    var readBytes: UInt64?
    var writeBytes: UInt64?

    static let empty = DiskIOInfo(readBytes: nil, writeBytes: nil)
}

private struct DiskIOReader {
    func read() -> DiskIOInfo {
        let matching = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            LogArchiver.shared.warning("More system status disk IO read failed: IOServiceGetMatchingServices result=\(result)")
            return .empty
        }
        defer { IOObjectRelease(iterator) }

        var totalReadBytes: UInt64 = 0
        var totalWriteBytes: UInt64 = 0
        var matchedDeviceCount = 0

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            guard let stats = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            let readBytes = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value
            let writeBytes = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value
            if readBytes != nil || writeBytes != nil {
                matchedDeviceCount += 1
                totalReadBytes += readBytes ?? 0
                totalWriteBytes += writeBytes ?? 0
            }
        }

        guard matchedDeviceCount > 0 else {
            LogArchiver.shared.warning("More system status disk IO read failed: no IOBlockStorageDriver statistics with byte counters")
            return .empty
        }

        return DiskIOInfo(readBytes: totalReadBytes, writeBytes: totalWriteBytes)
    }
}

private struct PanelButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.vertical, 11)
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

private struct QuickToolIconButton: View {
    let tool: MenuBarQuickTool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isHovering ? Color.blue : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovering ? Color.blue.opacity(0.11) : Color.clear)
        )
        .help(tool.helpText)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
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
