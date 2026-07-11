import AppKit
import SwiftUI

@MainActor
final class FocusTimerLauncherPanelController {
    private let timerStore: FocusTimerStore
    private var panel: NSPanel?

    init(timerStore: FocusTimerStore) {
        self.timerStore = timerStore
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showFromNotification),
            name: .showFocusTimerLauncher,
            object: nil
        )
    }

    func toggle() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            makePanel()
        }
        panel?.center()
        panel?.orderFrontRegardless()
    }

    @objc private func showFromNotification() {
        show()
    }

    private func makePanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "时间节律"
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: FocusTimerLauncherView(timerStore: timerStore) { [weak panel] in
                panel?.orderOut(nil)
            }
        )
        self.panel = panel
    }
}

private struct FocusTimerLauncherView: View {
    @ObservedObject var timerStore: FocusTimerStore
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            presetSection(title: "节律模板", presets: FocusTimerPreset.rhythmPresets)
            presetSection(title: "快速开始", presets: FocusTimerPreset.quickPresets)
            if timerStore.isActive || timerStore.showsFloatingReminder {
                controlBar
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("时间节律")
                    .font(.system(size: 24, weight: .bold))
                Text(timerStore.isActive ? "\(timerStore.mode?.title ?? "计时中") · \(timerStore.displayTime)" : "选一个节奏，悬浮球会接管展示和提醒")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
    }

    private func presetSection(title: String, presets: [FocusTimerPreset]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(presets) { preset in
                    Button {
                        timerStore.start(preset)
                        close()
                    } label: {
                        HStack(spacing: 12) {
                            Text(preset.subtitle)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .frame(width: 86, alignment: .leading)
                            Text(preset.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button(timerStore.isPaused ? "继续" : "暂停") {
                timerStore.togglePause()
            }
            Button("+5 分钟") {
                timerStore.extend()
            }
            Button("结束") {
                timerStore.stop()
            }
        }
        .buttonStyle(.bordered)
    }
}
