import SwiftUI
import AppKit

struct ToolboxView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var storageStore = StorageAnalyzerStore()
    @State private var selectedTool: ToolboxSection = .storage
    @State private var inputSources: [InputMethodSource] = []
    @State private var recordingRuleID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            toolboxSidebar
            Divider()
            content
        }
        .frame(minWidth: 820, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            storageStore.refresh()
        }
        .onChange(of: selectedTool) { tool in
            if tool == .inputMethod {
                refreshInputSources()
            }
        }
    }

    private var toolboxSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("工具箱")
                    .font(.system(size: 22, weight: .bold))
                Text("一些顺手的小工具")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 26)

            VStack(spacing: 7) {
                ToolboxSidebarItem(
                    title: "AI 存储分析",
                    systemImage: "internaldrive",
                    isSelected: selectedTool == .storage
                ) {
                    selectedTool = .storage
                }

                ToolboxSidebarItem(
                    title: "输入法快捷切换",
                    systemImage: "keyboard",
                    isSelected: selectedTool == .inputMethod
                ) {
                    selectedTool = .inputMethod
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            Label("更多工具正在路上", systemImage: "sparkles")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(20)
        }
        .frame(width: 210)
        .background(
            LinearGradient(
                colors: [
                    sidebarSurfaceColor.opacity(0.84),
                    .blue.opacity(colorScheme == .dark ? 0.06 : 0.035),
                    sidebarSurfaceColor.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var content: some View {
        ScrollView {
            Group {
                switch selectedTool {
                case .storage:
                    storageContent
                case .inputMethod:
                    inputMethodContent
                }
            }
            .padding(26)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    .blue.opacity(colorScheme == .dark ? 0.055 : 0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var storageContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            storageHeader
            diskOverview

            if storageStore.hasFolderAccess {
                resultSection
            } else {
                permissionCard
            }

            if let errorMessage = storageStore.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var inputMethodContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            inputMethodHeader
            inputMethodShortcutSection
        }
        .onAppear {
            refreshInputSources()
        }
    }

    private var storageHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("AI 存储分析")
                    .font(.system(size: 24, weight: .bold))
                Text("看看 AI 工具、模型与缓存悄悄占了多少空间。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                if let selectedFolderPath = storageStore.selectedFolderPath {
                    Label(selectedFolderPath, systemImage: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(selectedFolderPath)
                        .padding(.top, 1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if storageStore.hasFolderAccess {
                    Button {
                        storageStore.requestFolderAccess()
                    } label: {
                        Label("更换目录", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(storageStore.isScanning)
                }

                Button {
                    if storageStore.hasFolderAccess {
                        storageStore.refresh()
                    } else {
                        storageStore.requestFolderAccess()
                    }
                } label: {
                    Label(scanButtonTitle, systemImage: storageStore.hasFolderAccess ? "arrow.clockwise" : "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(storageStore.isScanning)
            }
        }
    }

    private var inputMethodHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("输入法快捷切换")
                    .font(.system(size: 24, weight: .bold))
                Text("给常用输入法绑定组合键，按下后直接切到指定输入法。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                refreshInputSources()
            } label: {
                Label("刷新输入法", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var inputMethodShortcutSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.green.opacity(0.12))
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.green)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("输入法快捷切换")
                        .font(.system(size: 17, weight: .semibold))
                    Text("给常用输入法绑定明确的全局快捷键。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $settings.inputMethodShortcutsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()

            if inputSources.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("暂未读取到可选择的输入法。请先在系统设置中添加输入法。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("刷新") { refreshInputSources() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(settings.inputMethodShortcutRules) { rule in
                        inputMethodRuleRow(rule)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        settings.addInputMethodShortcutRule()
                    } label: {
                        Label("添加快捷键", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        refreshInputSources()
                    } label: {
                        Label("刷新输入法", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text(inputMethodShortcutHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .toolboxCard()
    }

    private func inputMethodRuleRow(_ rule: InputMethodShortcutRule) -> some View {
        let conflict = isShortcutConflicting(rule)

        return HStack(spacing: 12) {
            ShortcutRecorderButton(
                shortcut: rule.shortcut,
                isRecording: recordingRuleID == rule.id,
                hasConflict: conflict,
                startRecording: { recordingRuleID = rule.id },
                record: { shortcut in
                    var updatedRule = rule
                    updatedRule.shortcut = shortcut
                    settings.updateInputMethodShortcutRule(updatedRule)
                    recordingRuleID = nil
                },
                cancel: { recordingRuleID = nil }
            )
            .frame(width: 118)

            Picker("", selection: inputSourceBinding(for: rule)) {
                Text("选择输入法").tag("")
                ForEach(inputSources) { source in
                    Text(source.name).tag(source.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button {
                settings.removeInputMethodShortcutRule(id: rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("删除")
        }
        .padding(.vertical, 4)
    }

    private var diskOverview: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: storageStore.disk.usageRatio)
                    .stroke(
                        diskTint,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(storageStore.disk.usageRatio.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                    Text("已用")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 94, height: 94)

            VStack(alignment: .leading, spacing: 12) {
                Text("系统磁盘")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 28) {
                    storageValue("总容量", bytes: storageStore.disk.totalBytes)
                    storageValue("已使用", bytes: storageStore.disk.usedBytes)
                    storageValue("可用", bytes: storageStore.disk.availableBytes)
                }
                ProgressView(value: storageStore.disk.usageRatio)
                    .tint(diskTint)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteFormatter.string(from: storageStore.totalAIBytes))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(.blue)
                Text("已识别 AI 数据")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .toolboxCard()
    }

    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("工具占用")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if let lastScannedAt = storageStore.lastScannedAt {
                    Text("更新于 \(lastScannedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if storageStore.isScanning && storageStore.items.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在统计目录大小，大型模型可能需要一点时间…")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .toolboxCard()
            } else if storageStore.items.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 27))
                        .foregroundStyle(.green)
                    Text("没有发现已支持的 AI 工具数据")
                        .font(.system(size: 14, weight: .semibold))
                    Text("目前会检查 Codex、Claude、Cursor、Windsurf、Copilot、Ollama、LM Studio 和 Hugging Face。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 118)
                .toolboxCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(storageStore.items.enumerated()), id: \.element.id) { index, item in
                        storageItemRow(item)
                        if index < storageStore.items.count - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .toolboxCard()
            }
        }
    }

    private var permissionCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(.blue.opacity(0.12))
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 6) {
                Text("允许读取个人文件夹")
                    .font(.system(size: 16, weight: .semibold))
                Text("仅用于统计常见 AI 工具目录的大小；不会读取文件内容，也不会删除或上传任何数据。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("选择文件夹") {
                storageStore.requestFolderAccess()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .toolboxCard()
    }

    private func storageItemRow(_ item: AIStorageItem) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(item.locations.filter(\.isDetected)) { location in
                    HStack(spacing: 10) {
                        Image(systemName: location.isAccessible ? "folder" : "lock.fill")
                            .foregroundStyle(location.isAccessible ? Color.secondary : Color.orange)
                            .frame(width: 18)
                        Text(location.displayPath)
                            .font(.system(size: 12.5).monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(location.isAccessible ? ByteFormatter.string(from: location.bytes) : "无法访问")
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(location.isAccessible ? Color.secondary : Color.orange)
                        Button {
                            storageStore.reveal(location)
                        } label: {
                            Image(systemName: "arrow.forward.circle")
                        }
                        .buttonStyle(.plain)
                        .help("在访达中显示")
                    }
                    .padding(.leading, 46)
                    .padding(.trailing, 4)
                    .padding(.vertical, 8)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.blue.opacity(0.11))
                    Image(systemName: item.systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 14.5, weight: .semibold))
                    Text("发现 \(item.detectedLocationCount) 个目录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteFormatter.string(from: item.bytes))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
            }
            .padding(.vertical, 12)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
    }

    private func storageValue(_ title: String, bytes: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(ByteFormatter.string(from: bytes))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
        }
    }

    private var diskTint: Color {
        storageStore.disk.usageRatio > 0.9 ? .red : (storageStore.disk.usageRatio > 0.75 ? .orange : .blue)
    }

    private var scanButtonTitle: String {
        if storageStore.isScanning { return "扫描中" }
        return storageStore.hasFolderAccess ? "重新扫描" : "开始扫描"
    }

    private var inputMethodShortcutHint: String {
        settings.inputMethodShortcutsEnabled ? "已启用" : "关闭时不会注册全局快捷键"
    }

    private func refreshInputSources() {
        inputSources = InputMethodSwitcher.selectableInputSources()
    }

    private func inputSourceBinding(for rule: InputMethodShortcutRule) -> Binding<String> {
        Binding(
            get: { rule.inputSourceID ?? "" },
            set: { inputSourceID in
                var updatedRule = rule
                updatedRule.inputSourceID = inputSourceID.isEmpty ? nil : inputSourceID
                settings.updateInputMethodShortcutRule(updatedRule)
            }
        )
    }

    private func isShortcutConflicting(_ rule: InputMethodShortcutRule) -> Bool {
        guard let shortcut = rule.shortcut else { return false }
        return settings.inputMethodShortcutRules.contains { otherRule in
            otherRule.id != rule.id && otherRule.shortcut == shortcut
        }
    }

    private var sidebarSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white
    }
}

private enum ToolboxSection {
    case storage
    case inputMethod
}

private struct ToolboxSidebarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? .blue : .secondary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.blue.opacity(0.10))
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }
}

private struct ShortcutRecorderButton: View {
    let shortcut: KeyboardShortcut?
    let isRecording: Bool
    let hasConflict: Bool
    let startRecording: () -> Void
    let record: (KeyboardShortcut) -> Void
    let cancel: () -> Void

    var body: some View {
        Button(action: startRecording) {
            Text(title)
                .font(.system(size: 13, weight: .semibold).monospaced())
                .foregroundStyle(hasConflict ? .red : .primary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .background(
            ShortcutCaptureView(
                isRecording: isRecording,
                record: record,
                cancel: cancel
            )
        )
        .help(isRecording ? "按下新的组合键，Esc 取消" : "点击录制快捷键")
    }

    private var title: String {
        if isRecording { return "录制中" }
        if let shortcut { return shortcut.displayText }
        return "录制"
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let record: (KeyboardShortcut) -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.record = record
        view.cancel = cancel
        return view
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        nsView.record = record
        nsView.cancel = cancel
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if nsView.window?.firstResponder === nsView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nil)
            }
        }
    }
}

private final class CaptureNSView: NSView {
    var record: ((KeyboardShortcut) -> Void)?
    var cancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancel?()
            return
        }

        let modifiers = KeyboardShortcutFormatter.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }

        record?(KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
    }
}

private extension View {
    func toolboxCard() -> some View {
        modifier(ToolboxCardModifier())
    }
}

private struct ToolboxCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(surfaceColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.035), radius: 12, y: 4)
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.74)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.primary.opacity(0.08)
    }
}
