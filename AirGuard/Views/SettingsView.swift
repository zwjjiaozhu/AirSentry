import SwiftUI
import AppKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var alertManager: AlertManager
    @EnvironmentObject private var agentMonitorStore: AgentMonitorStore
    @State private var selectedSection: SettingsSectionID = .reminder
    @State private var editingThreshold: TemperatureThresholdID?
    @FocusState private var focusedThreshold: TemperatureThresholdID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        reminderSection
                            .id(SettingsSectionID.reminder)
                        thresholdSection
                            .id(SettingsSectionID.threshold)
                        batteryThresholdSection
                            .id(SettingsSectionID.batteryThreshold)
                        labSection
                            .id(SettingsSectionID.labs)
                        systemSection
                            .id(SettingsSectionID.system)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .background(contentBackground)
                .onChange(of: selectedSection) { section in
                    dismissThresholdInput()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(section, anchor: .top)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            ThresholdInputFocusResetter(
                editingThreshold: $editingThreshold,
                focusedThreshold: $focusedThreshold
            )
        )
        .task {
            await alertManager.refreshAuthorizationStatus()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 34)

            VStack(spacing: 16) {
                AppLogo()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(spacing: 7) {
                    Text("AirSentry 设置")
                        .font(.system(size: 19, weight: .semibold))

                    Text("MacBook Air/Neo 温度提醒与\n菜单栏监控")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Text(Bundle.main.displayVersion)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.10), in: Capsule())
            }

            VStack(spacing: 8) {
                SidebarItem(
                    title: "提醒",
                    systemImage: "bell.fill",
                    isSelected: selectedSection == .reminder
                ) {
                    selectedSection = .reminder
                }

                SidebarItem(
                    title: "温度阈值",
                    systemImage: "thermometer.medium",
                    isSelected: selectedSection == .threshold
                ) {
                    selectedSection = .threshold
                }

                SidebarItem(
                    title: "电池阈值",
                    systemImage: "battery.50percent",
                    isSelected: selectedSection == .batteryThreshold
                ) {
                    selectedSection = .batteryThreshold
                }

                SidebarItem(
                    title: "AI 实验室",
                    systemImage: "flask.fill",
                    isSelected: selectedSection == .labs
                ) {
                    selectedSection = .labs
                }

                SidebarItem(
                    title: "系统",
                    systemImage: "gearshape.fill",
                    isSelected: selectedSection == .system
                ) {
                    selectedSection = .system
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 38)

            Spacer()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 22)

                Text("部分 Mac 未暴露真实温度，显示值可能不可用或不准确。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(14)
            .background(sidebarNoticeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(sidebarNoticeStroke, lineWidth: 1)
            )
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(width: 220)
        .background(sidebarBackground)
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("提醒设置")

            SettingsGroup {
                NotificationPreferenceRow(
                    title: "高温通知",
                    subtitle: notificationStatusText,
                    systemImage: "bell",
                    authorizationStatus: alertManager.authorizationStatus,
                    isOn: $settings.notificationsEnabled,
                    requestAuthorization: alertManager.requestAuthorization
                )
                .onChange(of: settings.notificationsEnabled) { enabled in
                    if enabled {
                        alertManager.requestAuthorization()
                    }
                }

                InsetDivider()

                IntervalPreferenceRow(
                    title: "检测周期",
                    subtitle: "读取温度、CPU、内存与网络状态的间隔",
                    systemImage: "timer",
                    valueText: settings.refreshInterval.formatted(.number.precision(.fractionLength(0))) + " 秒",
                    canDecrease: settings.refreshInterval > 1,
                    canIncrease: settings.refreshInterval < 60,
                    decrease: { settings.setRefreshInterval(settings.refreshInterval - 1) },
                    increase: { settings.setRefreshInterval(settings.refreshInterval + 1) }
                )

                InsetDivider()

                IntervalPreferenceRow(
                    title: "通知冷却",
                    subtitle: "同一热状态重复提醒前等待的时间",
                    systemImage: "bell.badge.clock",
                    valueText: notificationCooldownText,
                    canDecrease: settings.notificationCooldown > 0,
                    canIncrease: settings.notificationCooldown < 60 * 60,
                    decrease: { settings.setNotificationCooldown(settings.notificationCooldown - 5) },
                    increase: { settings.setNotificationCooldown(settings.notificationCooldown + 5) }
                )

                InsetDivider()

                PreferenceRow(
                    title: "番茄钟声音提醒",
                    subtitle: "时间到达时播放应用内提示音",
                    systemImage: "speaker.wave.2",
                    isOn: $settings.focusTimerSoundEnabled
                )

                InsetDivider()

                SoundPreferenceRow(
                    title: "番茄钟提示音",
                    subtitle: "到点时连续播放两声",
                    systemImage: "music.note",
                    selection: $settings.focusTimerSoundName,
                    preview: playFocusTimerSoundPreview
                )
                .disabled(!settings.focusTimerSoundEnabled)
                .opacity(settings.focusTimerSoundEnabled ? 1 : 0.55)

                InsetDivider()

                PreferenceRow(
                    title: "菜单栏显示温度",
                    subtitle: "显示实时温度；不可用时显示热状态",
                    systemImage: "menubar.rectangle",
                    isOn: $settings.menuBarShowsTemperature
                )
            }
        }
    }

    private var thresholdSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("温度阈值")
                Spacer()
                Text("°C")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            SettingsGroup {
                HStack(spacing: 12) {
                    ThresholdCard(
                        id: .fair,
                        title: "偏热",
                        color: .yellow,
                        value: settings.fairTemperatureThreshold,
                        range: 30...123,
                        editingThreshold: $editingThreshold,
                        focusedThreshold: $focusedThreshold,
                        onChange: settings.setFairTemperatureThreshold
                    )
                    .id("fair-threshold")

                    ThresholdCard(
                        id: .serious,
                        title: "高温",
                        color: .orange,
                        value: settings.seriousTemperatureThreshold,
                        range: 31...124,
                        editingThreshold: $editingThreshold,
                        focusedThreshold: $focusedThreshold,
                        onChange: settings.setSeriousTemperatureThreshold
                    )
                    .id("serious-threshold")

                    ThresholdCard(
                        id: .critical,
                        title: "严重",
                        color: .red,
                        value: settings.criticalTemperatureThreshold,
                        range: 32...125,
                        editingThreshold: $editingThreshold,
                        focusedThreshold: $focusedThreshold,
                        onChange: settings.setCriticalTemperatureThreshold
                    )
                    .id("critical-threshold")
                }
                .padding(14)

                Divider()
                    .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    HStack(spacing: 7) {
                        Text("通知触发等级")
                            .font(.system(size: 15, weight: .medium))
                        InfoButton(text: "达到所选热状态或更严重状态时发送通知。若能读取真实温度，会先按上方温度阈值换算为热状态。")
                    }

                    Spacer()

                    Picker("", selection: alertThermalLevelBinding) {
                        Text("偏热").tag(ThermalLevel.fair)
                        Text("高温").tag(ThermalLevel.serious)
                        Text("严重高温").tag(ThermalLevel.critical)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private var batteryThresholdSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("电池阈值")
                Spacer()
                Text("%")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            SettingsGroup {
                HStack(spacing: 12) {
                    ThresholdCard(
                        id: .batteryLow,
                        title: "低电量",
                        color: .orange,
                        value: settings.lowBatteryThreshold,
                        range: 5...80,
                        unit: "%",
                        inputHelpText: "点击直接输入电量",
                        editingThreshold: $editingThreshold,
                        focusedThreshold: $focusedThreshold,
                        onChange: settings.setLowBatteryThreshold
                    )

                    ThresholdCard(
                        id: .batteryCritical,
                        title: "严重",
                        color: .red,
                        value: settings.criticalBatteryThreshold,
                        range: 1...75,
                        unit: "%",
                        inputHelpText: "点击直接输入电量",
                        editingThreshold: $editingThreshold,
                        focusedThreshold: $focusedThreshold,
                        onChange: settings.setCriticalBatteryThreshold
                    )
                }
                .padding(14)

                Divider()
                    .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    HStack(spacing: 7) {
                        Text("电池提醒")
                            .font(.system(size: 15, weight: .medium))
                        InfoButton(text: "低于阈值且未接入电源时发送通知；充电中或接入电源时，菜单栏电池状态保持绿色。")
                    }

                    Spacer()

                    Toggle("", isOn: $settings.batteryAlertsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("启动")

                SettingsGroup {
                    PreferenceRow(
                        title: "开机自动启动",
                        subtitle: "在系统启动时自动运行 AirSentry",
                        systemImage: "power",
                        isOn: $settings.launchAtLoginEnabled
                    )
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("运行日志")

                SettingsGroup {
                    HStack(spacing: 18) {
                        Image(systemName: "text.badge.checkmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.blue)
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("显示日志级别")
                                .font(.system(size: 15, weight: .semibold))

                            Text("调试截图窗口识别等问题时可切换到 Debug，日志会写入下方文件夹。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("", selection: displayLogLevelBinding) {
                            ForEach(LogLevel.allCases) { level in
                                Text(level.title).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 320)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)

                    InsetDivider()

                    HStack(spacing: 18) {
                        Image(systemName: "folder")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.blue)
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("日志文件夹")
                                .font(.system(size: 15, weight: .semibold))

                            Text("温度异常等运行事件归档到 ~/Library/Logs/AirSentry/")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("打开") {
                            openLogFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)
                }
            }
        }
    }

    private var labSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle("AI 实验室")
                Text("探索刘海交互与智能工具状态等增强能力，不影响 AirSentry 的温度哨兵核心功能。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }

            agentSection
            musicSection
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("AI 编程状态")
                Spacer()
                Text(agentMonitorStore.isListening ? "监听中" : "未监听")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(agentMonitorStore.isListening ? .green : .secondary)
            }

            SettingsGroup {
                PreferenceRow(
                    title: "刘海状态提示",
                    subtitle: "在屏幕刘海区域显示 AI 编程任务状态",
                    systemImage: "macbook",
                    isOn: $settings.agentNotchEnabled
                )

                InsetDivider()

                PreferenceRow(
                    title: "监控 Codex",
                    subtitle: "接收会话、工具调用、批准请求和完成事件",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    isOn: $settings.codexMonitoringEnabled
                )

                InsetDivider()

                PreferenceRow(
                    title: "监控 Claude Code",
                    subtitle: "通过 Claude Code Hooks 接收本机会话状态",
                    systemImage: "brain.head.profile",
                    isOn: $settings.claudeMonitoringEnabled
                )

                InsetDivider()

                IntervalPreferenceRow(
                    title: "完成提示时长",
                    subtitle: "任务完成后，提示在刘海区域停留的时间",
                    systemImage: "clock",
                    valueText: settings.agentCompletionDisplayDuration.formatted(.number.precision(.fractionLength(0))) + " 秒",
                    canDecrease: settings.agentCompletionDisplayDuration > 2,
                    canIncrease: settings.agentCompletionDisplayDuration < 15,
                    decrease: { settings.setAgentCompletionDisplayDuration(settings.agentCompletionDisplayDuration - 1) },
                    increase: { settings.setAgentCompletionDisplayDuration(settings.agentCompletionDisplayDuration + 1) }
                )
            }

            SettingsGroup {
                HStack(spacing: 14) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Hooks 连接")
                            .font(.system(size: 15, weight: .semibold))
                        Text(agentMonitorStore.installationStatus.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(agentMonitorStore.installationStatus.lastError == nil ? Color.secondary : Color.red)
                    }

                    Spacer()

                    Button("测试提示") {
                        if !settings.agentNotchEnabled {
                            settings.agentNotchEnabled = true
                        }
                        agentMonitorStore.sendTestEvent()
                    }
                    .buttonStyle(.bordered)

                    if agentMonitorStore.installationStatus.codexInstalled || agentMonitorStore.installationStatus.claudeInstalled {
                        Button("卸载") { agentMonitorStore.uninstallHooks() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("安装 Hooks") { agentMonitorStore.installHooks() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!settings.codexMonitoringEnabled && !settings.claudeMonitoringEnabled)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
            }

            Text("安装时会合并现有配置，并在同目录保留 .airsentry-backup 备份。Codex 首次使用新增 Hook 时可能要求在 /hooks 中确认信任。")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("音乐状态")
                Spacer()
                Text("系统事件实时监听")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(settings.musicNotchEnabled ? .green : .secondary)
            }

            SettingsGroup {
                PreferenceRow(
                    title: "刘海显示当前音乐",
                    subtitle: "显示歌名、歌手、封面和播放进度",
                    systemImage: "music.note",
                    isOn: $settings.musicNotchEnabled
                )

                InsetDivider()

                HStack(spacing: 14) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Now Playing 监听")
                            .font(.system(size: 15, weight: .semibold))
                        Text("由播放器主动推送切歌、暂停和恢复事件，不需要设置刷新频率")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
            }

            Text("支持所有会向 macOS 控制中心上报播放状态的应用；播放器仅打开但没有当前歌曲时，刘海不会显示音乐卡片。")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
    }

    private var sidebarBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    sidebarSurfaceColor.opacity(0.88),
                    .blue.opacity(0.035),
                    sidebarSurfaceColor.opacity(0.76)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var contentBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                .blue.opacity(colorScheme == .dark ? 0.055 : 0.025),
                Color(nsColor: .windowBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var notificationStatusText: String {
        switch alertManager.authorizationStatus {
        case .authorized: "通知权限已允许"
        case .denied: "通知权限已拒绝"
        case .notDetermined: "开启后请求系统通知权限"
        case .provisional: "通知权限临时允许"
        case .ephemeral: "通知权限临时会话"
        @unknown default: "通知权限未知"
        }
    }

    private var notificationCooldownText: String {
        guard settings.notificationCooldown > 0 else { return "不冷却" }

        let totalSeconds = Int(settings.notificationCooldown)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0, seconds > 0 {
            return "\(minutes) 分 \(seconds) 秒"
        }
        if minutes > 0 {
            return "\(minutes) 分钟"
        }
        return "\(seconds) 秒"
    }

    private var alertThermalLevelBinding: Binding<ThermalLevel> {
        Binding {
            settings.alertThermalLevel
        } set: { level in
            DispatchQueue.main.async {
                settings.setAlertThermalLevel(level)
            }
        }
    }

    private var displayLogLevelBinding: Binding<LogLevel> {
        Binding {
            settings.displayLogLevel
        } set: { level in
            DispatchQueue.main.async {
                settings.setDisplayLogLevel(level)
            }
        }
    }

    private func playFocusTimerSoundPreview() {
        FocusTimerSoundPlayer.shared.playCompletionSound(named: settings.focusTimerSoundName)
    }

    private func dismissThresholdInput() {
        focusedThreshold = nil
    }

    private func openLogFolder() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/AirSentry", isDirectory: true)
        if !FileManager.default.fileExists(atPath: logsDir.path) {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logsDir.path)
    }

    private var sidebarSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white
    }

    private var sidebarNoticeBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.62)
    }

    private var sidebarNoticeStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.primary.opacity(0.06)
    }
}

private enum SettingsSectionID: Hashable {
    case reminder
    case threshold
    case batteryThreshold
    case labs
    case system
}

private enum TemperatureThresholdID: Hashable {
    case fair
    case serious
    case critical
    case batteryLow
    case batteryCritical
}

private struct ThresholdInputFocusResetter: NSViewRepresentable {
    @Binding var editingThreshold: TemperatureThresholdID?
    let focusedThreshold: FocusState<TemperatureThresholdID?>.Binding

    func makeCoordinator() -> Coordinator {
        Coordinator(editingThreshold: $editingThreshold, focusedThreshold: focusedThreshold)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.editingThreshold = $editingThreshold
        context.coordinator.focusedThreshold = focusedThreshold
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        var editingThreshold: Binding<TemperatureThresholdID?>
        var focusedThreshold: FocusState<TemperatureThresholdID?>.Binding
        weak var hostView: NSView?
        private var monitor: Any?

        init(
            editingThreshold: Binding<TemperatureThresholdID?>,
            focusedThreshold: FocusState<TemperatureThresholdID?>.Binding
        ) {
            self.editingThreshold = editingThreshold
            self.focusedThreshold = focusedThreshold
        }

        func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.clearFocusIfNeeded(for: event)
                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func clearFocusIfNeeded(for event: NSEvent) {
            guard editingThreshold.wrappedValue != nil else { return }
            guard let window = hostView?.window, event.window === window else { return }
            guard let contentView = window.contentView else { return }

            let point = contentView.convert(event.locationInWindow, from: nil)
            let hitView = contentView.hitTest(point)
            guard !isTextInput(hitView) else { return }

            window.makeFirstResponder(nil)
            focusedThreshold.wrappedValue = nil
        }

        private func isTextInput(_ view: NSView?) -> Bool {
            var currentView = view
            while let view = currentView {
                if view is NSTextField || view is NSTextView {
                    return true
                }
                currentView = view.superview
            }
            return false
        }
    }
}

private struct SidebarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .blue : .secondary)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.blue.opacity(0.10))
                }
            }
        )
    }
}

private struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
    }
}

private struct SettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(surfaceColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.035), radius: 12, y: 4)
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.72)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.primary.opacity(0.09)
    }
}

private struct InfoButton: View {
    let text: String
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(14)
        }
    }
}

private struct NotificationPreferenceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let authorizationStatus: UNAuthorizationStatus
    @Binding var isOn: Bool
    let requestAuthorization: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if showsAuthorizationButton {
                Button(authorizationButtonTitle) {
                    requestAuthorization()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    private var showsAuthorizationButton: Bool {
        authorizationStatus == .denied || authorizationStatus == .notDetermined
    }

    private var authorizationButtonTitle: String {
        authorizationStatus == .denied ? "打开" : "授权"
    }
}

private struct PreferenceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

private struct SoundPreferenceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var selection: String
    let preview: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $selection) {
                ForEach(FocusTimerCompletionSound.allCases) { sound in
                    Text(sound.title).tag(sound.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 96)

            Button {
                preview()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("试听提示音")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

private struct IntervalPreferenceRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let systemImage: String
    let valueText: String
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 0) {
                IntervalStepButton(
                    systemImage: "minus",
                    helpText: "减少",
                    isEnabled: canDecrease,
                    action: decrease
                )

                Divider()
                    .frame(height: 20)

                Text(valueText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .frame(width: 84)

                Divider()
                    .frame(height: 20)

                IntervalStepButton(
                    systemImage: "plus",
                    helpText: "增加",
                    isEnabled: canIncrease,
                    action: increase
                )
            }
            .frame(height: 34)
            .background(controlSurfaceColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(controlStrokeColor, lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    private var controlSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.80)
    }

    private var controlStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.primary.opacity(0.09)
    }
}

private struct IntervalStepButton: View {
    let systemImage: String
    let helpText: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .background(
                    isHovering && isEnabled
                        ? Color.primary.opacity(0.07)
                        : Color.clear
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(helpText)
        .onHover { isHovering = $0 }
    }
}

private struct ThresholdCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let id: TemperatureThresholdID
    let title: String
    let color: Color
    let value: Double
    let range: ClosedRange<Double>
    var unit = "°C"
    var inputHelpText = "点击直接输入温度"
    @Binding var editingThreshold: TemperatureThresholdID?
    let focusedThreshold: FocusState<TemperatureThresholdID?>.Binding
    let onChange: (Double) -> Void
    @State private var inputText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isEditingInput {
                    TextField("", text: $inputText)
                        .font(.system(size: 32, weight: .semibold).monospacedDigit())
                        .textFieldStyle(.plain)
                        .focused(focusedThreshold, equals: id)
                        .frame(width: 54)
                        .onSubmit(commitInput)
                } else {
                    Button {
                        beginInputEditing()
                    } label: {
                        Text(value.formatted(.number.precision(.fractionLength(0))))
                            .font(.system(size: 32, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .help(inputHelpText)
                }

                Text(unit)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    adjustValue(by: -1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(value <= range.lowerBound)

                Divider()
                    .frame(height: 18)

                Text(value.formatted(.number.precision(.fractionLength(0))))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .frame(minWidth: 34)

                Divider()
                    .frame(height: 18)

                Button {
                    adjustValue(by: 1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(value >= range.upperBound)

                Spacer()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(controlSurfaceColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(controlStrokeColor, lineWidth: 1)
            )

            Text("\(Int(range.lowerBound))-\(Int(range.upperBound)) \(unit)")
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .onAppear(perform: syncInputText)
        .onChange(of: value) { _ in
            if !isEditingInput {
                syncInputText()
            }
        }
        .onChange(of: focusedThreshold.wrappedValue) { focusedID in
            if focusedID != id, isEditingInput {
                commitInput()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardSurfaceColor)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(color.opacity(0.90))
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: 10, y: 5)
    }

    private var cardSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.78)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.primary.opacity(0.08)
    }

    private var controlSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.80)
    }

    private var controlStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.primary.opacity(0.09)
    }

    private func syncInputText() {
        inputText = value.formatted(.number.precision(.fractionLength(0)))
    }

    private var isEditingInput: Bool {
        editingThreshold == id
    }

    private func beginInputEditing() {
        syncInputText()
        editingThreshold = id
        DispatchQueue.main.async {
            focusedThreshold.wrappedValue = id
        }
    }

    private func commitInput() {
        let sanitizedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newValue = Double(sanitizedText) else {
            syncInputText()
            focusedThreshold.wrappedValue = nil
            editingThreshold = nil
            return
        }

        let nextValue = clamped(newValue)
        onChange(nextValue)
        inputText = nextValue.formatted(.number.precision(.fractionLength(0)))
        focusedThreshold.wrappedValue = nil
        editingThreshold = nil
    }

    private func adjustValue(by delta: Double) {
        focusedThreshold.wrappedValue = nil
        editingThreshold = nil
        onChange(clamped(value + delta))
    }

    private func clamped(_ newValue: Double) -> Double {
        min(max(newValue, range.lowerBound), range.upperBound)
    }
}

private struct InsetDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 82)
    }
}

private extension Bundle {
    var displayVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String
        let build = infoDictionary?["CFBundleVersion"] as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            return "v\(version) (\(build))"
        case let (.some(version), .none):
            return "v\(version)"
        case let (.none, .some(build)):
            return "Build \(build)"
        case (.none, .none):
            return "版本未知"
        }
    }
}
