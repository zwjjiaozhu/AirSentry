import AppKit
import SwiftUI

final class MenuBarSystemToolRunner: ObservableObject {
    @Published private(set) var sleepPreventerProcess: Process?
    @Published private(set) var desktopIconsHidden = MenuBarSystemToolRunner.currentDesktopIconsHidden()

    var isPreventingSleep: Bool {
        sleepPreventerProcess != nil
    }

    func perform(_ action: MenuBarSystemToolAction, openActivityMonitor: () -> Void, openToolbox: () -> Void) {
        switch action {
        case .toggleDesktopIcons:
            toggleDesktopIcons()
        case .preventSleep:
            togglePreventSleep()
        case .lockScreen:
            lockScreenOrSleepDisplay()
        case .sleep:
            runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
        case .activityMonitor:
            openActivityMonitor()
        case .toolbox:
            openToolbox()
        }
    }

    func isActive(_ action: MenuBarSystemToolAction) -> Bool {
        switch action {
        case .toggleDesktopIcons:
            desktopIconsHidden
        case .preventSleep:
            isPreventingSleep
        case .lockScreen, .sleep, .activityMonitor, .toolbox:
            false
        }
    }

    func togglePreventSleep() {
        if let process = sleepPreventerProcess {
            process.terminate()
            sleepPreventerProcess = nil
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-dimsu"]

        do {
            try process.run()
            sleepPreventerProcess = process
        } catch {
            LogArchiver.shared.error("Quick action prevent sleep failed: \(error.localizedDescription)")
        }
    }

    func toggleDesktopIcons() {
        let nextHidden = !desktopIconsHidden
        let value = nextHidden ? "false" : "true"
        runProcess("/usr/bin/defaults", arguments: ["write", "com.apple.finder", "CreateDesktop", "-bool", value])
        runProcess("/usr/bin/killall", arguments: ["Finder"])
        desktopIconsHidden = nextHidden
    }

    func lockScreenOrSleepDisplay() {
        let legacyLockPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        if FileManager.default.isExecutableFile(atPath: legacyLockPath) {
            runProcess(legacyLockPath, arguments: ["-suspend"])
            return
        }

        runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
    }

    func runProcess(_ path: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            LogArchiver.shared.error("Menu bar tool process failed: \(path) \(arguments.joined(separator: " ")) - \(error.localizedDescription)")
        }
    }

    static func openTerminal() {
        openApplication(bundleIdentifier: "com.apple.Terminal", fallbackPath: "/System/Applications/Utilities/Terminal.app")
    }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func openApplication(bundleIdentifier: String, fallbackPath: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return
        }

        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: fallbackPath), configuration: configuration)
    }

    private static func currentDesktopIconsHidden() -> Bool {
        let value = UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool
        return value == false
    }
}

enum MenuBarSystemToolAction: String, CaseIterable, Identifiable {
    case toggleDesktopIcons
    case preventSleep
    case lockScreen
    case sleep
    case activityMonitor
    case toolbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleDesktopIcons: "隐藏桌面图标"
        case .preventSleep: "防止休眠"
        case .lockScreen: "锁定/熄屏"
        case .sleep: "立即休眠"
        case .activityMonitor: "活动监视器"
        case .toolbox: "打开工具箱"
        }
    }

    var activeTitle: String {
        switch self {
        case .toggleDesktopIcons: "显示桌面图标"
        case .preventSleep: "停止防休眠"
        case .lockScreen, .sleep, .activityMonitor, .toolbox: title
        }
    }

    var helpText: String {
        switch self {
        case .toggleDesktopIcons: "切换 Finder 桌面图标显示"
        case .preventSleep: "切换临时防休眠"
        case .lockScreen: "立即关闭显示器并触发锁定"
        case .sleep: "让 Mac 立即进入休眠"
        case .activityMonitor: "打开系统活动监视器"
        case .toolbox: "打开完整工具箱"
        }
    }

    var systemImage: String {
        switch self {
        case .toggleDesktopIcons: "rectangle.dashed"
        case .preventSleep: "cup.and.saucer"
        case .lockScreen: "lock"
        case .sleep: "moon.zzz"
        case .activityMonitor: "waveform.path.ecg"
        case .toolbox: "wrench.and.screwdriver"
        }
    }

    var tint: Color {
        switch self {
        case .toggleDesktopIcons: .purple
        case .preventSleep: .blue
        case .lockScreen: .orange
        case .sleep: .indigo
        case .activityMonitor: .green
        case .toolbox: .secondary
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .lockScreen, .sleep:
            true
        case .toggleDesktopIcons, .preventSleep, .activityMonitor, .toolbox:
            false
        }
    }

    var isDestructive: Bool {
        switch self {
        case .sleep:
            true
        case .toggleDesktopIcons, .preventSleep, .lockScreen, .activityMonitor, .toolbox:
            false
        }
    }

    var confirmationTitle: String {
        switch self {
        case .lockScreen: "锁定/熄屏？"
        case .sleep: "立即休眠？"
        case .toggleDesktopIcons, .preventSleep, .activityMonitor, .toolbox: title
        }
    }

    var confirmationMessage: String? {
        switch self {
        case .lockScreen:
            "会立即关闭显示器；如果系统设置为唤醒后需要密码，就会进入锁定状态。"
        case .sleep:
            "Mac 会立即进入休眠，正在运行的任务可能会暂停。"
        case .toggleDesktopIcons, .preventSleep, .activityMonitor, .toolbox:
            nil
        }
    }
}

struct MenuBarQuickActionsPopover: View {
    @ObservedObject var runner: MenuBarSystemToolRunner

    let close: () -> Void
    let openActivityMonitor: () -> Void
    let openToolbox: () -> Void

    @State private var actionNeedingConfirmation: MenuBarSystemToolAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("快捷动作")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                if runner.isPreventingSleep {
                    Label("防休眠中", systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }

            quickActionGroup("系统动作", actions: [.toggleDesktopIcons, .preventSleep, .lockScreen, .sleep])
            quickActionGroup("效率动作", actions: [.activityMonitor, .toolbox])
        }
        .padding(14)
        .frame(width: 292)
        .background(panelBackground)
        .confirmationDialog(
            actionNeedingConfirmation?.confirmationTitle ?? "确认操作",
            isPresented: confirmationDialogBinding,
            titleVisibility: .visible,
            presenting: actionNeedingConfirmation
        ) { action in
            Button(action.title, role: action.isDestructive ? .destructive : nil) {
                perform(action)
            }
            Button("取消", role: .cancel) {
                actionNeedingConfirmation = nil
            }
        } message: { action in
            Text(action.confirmationMessage ?? "")
        }
    }

    private var panelBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(0.92),
                    Color.blue.opacity(0.08),
                    Color(nsColor: .controlBackgroundColor).opacity(0.80)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func quickActionGroup(_ title: String, actions: [MenuBarSystemToolAction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(actions) { action in
                    MenuBarQuickActionRow(
                        action: action,
                        isActive: runner.isActive(action)
                    ) {
                        runQuickAction(action)
                    }
                }
            }
        }
    }

    private var confirmationDialogBinding: Binding<Bool> {
        Binding(
            get: { actionNeedingConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    actionNeedingConfirmation = nil
                }
            }
        )
    }

    private func runQuickAction(_ action: MenuBarSystemToolAction) {
        if action.requiresConfirmation {
            actionNeedingConfirmation = action
            return
        }

        perform(action)
    }

    private func perform(_ action: MenuBarSystemToolAction) {
        actionNeedingConfirmation = nil
        if action.closesPopover {
            close()
        }
        runner.perform(action, openActivityMonitor: openActivityMonitor, openToolbox: openToolbox)
    }
}

private extension MenuBarSystemToolAction {
    var closesPopover: Bool {
        switch self {
        case .toggleDesktopIcons, .preventSleep:
            false
        case .lockScreen, .sleep, .activityMonitor, .toolbox:
            true
        }
    }
}

private struct MenuBarQuickActionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: MenuBarSystemToolAction
    let isActive: Bool
    let perform: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(action.tint.opacity(isActive ? 0.18 : 0.11))

                    Image(systemName: isActive ? activeSystemImage : action.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(action.tint)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isActive ? action.activeTitle : action.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(action.helpText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isActive {
                    Circle()
                        .fill(action.tint)
                        .frame(width: 6, height: 6)
                } else if action.requiresConfirmation {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(isHovering ? 0.10 : 0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(action.helpText)
        .menuBarToolPointingHandCursor()
        .onHover { isHovering = $0 }
    }

    private var activeSystemImage: String {
        switch action {
        case .toggleDesktopIcons:
            "rectangle"
        case .preventSleep:
            "cup.and.saucer.fill"
        case .lockScreen, .sleep, .activityMonitor, .toolbox:
            action.systemImage
        }
    }

    private var rowBackground: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isHovering ? 0.10 : 0.06)
        }
        return Color.white.opacity(isHovering ? 0.78 : 0.56)
    }
}

private struct MenuBarToolPointingHandCursorModifier: ViewModifier {
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

extension View {
    func menuBarToolPointingHandCursor() -> some View {
        modifier(MenuBarToolPointingHandCursorModifier())
    }
}
