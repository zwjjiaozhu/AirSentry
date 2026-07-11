import AppKit
import SwiftUI

struct DiskHealthGuideView: View {
    let onBack: () -> Void
    let onClose: () -> Void

    @StateObject private var smartReader = DiskSmartReader()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
            footerActions
        }
        .padding(16)
        .frame(width: 390)
        .task {
            await smartReader.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .menuBarToolPointingHandCursor()
            .help("返回")

            VStack(alignment: .leading, spacing: 2) {
                Text("磁盘健康与写入量")
                    .font(.system(size: 18, weight: .bold))
                Text("通过 smartmontools 读取 SSD SMART 数据")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .menuBarToolPointingHandCursor()
            .help("关闭")
        }
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("需要 Homebrew、smartmontools 和一次管理员密码。", systemImage: "lock.shield")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)

            Text("安装后可以读取 Data Units Written，也就是 SSD 累计写入量。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch smartReader.state {
        case .checking, .authorizing:
            checkingView
        case .notInstalled:
            notice
            steps
        case .available, .failed:
            smartResultView
        }
    }

    private var checkingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text(smartReader.state == .authorizing ? "正在通过管理员权限读取 SMART 数据..." : "正在检测 smartmontools...")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(12)
        .background(popoverSurfaceColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(popoverStrokeColor, lineWidth: 1)
        )
    }

    private var smartResultView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(smartReader.state == .available ? smartReader.statusText : "smartctl 已安装，但读取失败。", systemImage: smartReader.state == .available ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(smartReader.state == .available ? .green : .orange)

                Spacer()

                Button {
                    Task { await smartReader.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .menuBarToolPointingHandCursor()
                .help("重新读取")
            }

            Text(smartReader.output.isEmpty ? "没有读取到 Data Units Written。部分磁盘可能需要管理员权限。" : smartReader.output)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            if smartReader.state == .failed {
                Text("如果取消了管理员授权，或当前磁盘不支持 Data Units Written，可以复制下方命令到终端排查。")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(popoverSurfaceColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(popoverStrokeColor, lineWidth: 1)
        )
    }

    private var steps: some View {
        VStack(spacing: 10) {
            DiskHealthGuideStepView(
                number: 1,
                title: "安装 Homebrew",
                detail: "如果已经安装，可以跳过这一步。",
                command: DiskHealthCommand.installHomebrew
            )

            DiskHealthGuideStepView(
                number: 2,
                title: "安装 smartmontools",
                detail: "提供 smartctl 命令，用来读取磁盘 SMART 信息。",
                command: DiskHealthCommand.installSmartmontools
            )

            DiskHealthGuideStepView(
                number: 3,
                title: "读取磁盘健康和累计写入量",
                detail: "首次执行会要求输入 Mac 登录密码。",
                command: DiskHealthCommand.readSmartSummary
            )
        }
    }

    private var footerActions: some View {
        HStack(spacing: 8) {
            Button {
                MenuBarSystemToolRunner.copyToPasteboard(smartReader.state == .notInstalled ? DiskHealthCommand.full : DiskHealthCommand.readSmartSummary)
            } label: {
                Label(smartReader.state == .notInstalled ? "复制完整命令" : "复制读取命令", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MenuBarGuideActionButtonStyle(tint: .blue))

            Button {
                MenuBarSystemToolRunner.openTerminal()
            } label: {
                Label("打开终端", systemImage: "terminal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MenuBarGuideActionButtonStyle(tint: .secondary))
        }
    }

    private var popoverSurfaceColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.62)
    }

    private var popoverStrokeColor: Color {
        Color.black.opacity(0.08)
    }
}

enum DiskHealthCommand {
    static let installHomebrew = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
    static let installSmartmontools = "brew install smartmontools"
    static let readSmartSummary = #"sudo smartctl -a /dev/disk0 | grep "Data Units Written""#
    static let full = #"brew install smartmontools && sudo smartctl -a /dev/disk0 | grep "Data Units Written""#
}

@MainActor
private final class DiskSmartReader: ObservableObject {
    enum State {
        case checking
        case authorizing
        case notInstalled
        case available
        case failed
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var output = ""
    @Published private(set) var statusText = "已检测到 smartctl，已自动读取累计写入量。"

    private var hasLoaded = false

    func refresh(force: Bool = false) async {
        guard force || !hasLoaded else { return }
        hasLoaded = true
        state = .checking
        output = ""
        statusText = "已检测到 smartctl，已自动读取累计写入量。"

        let smartctlPath = await runShell(#"command -v smartctl || true"#).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !smartctlPath.isEmpty else {
            LogArchiver.shared.warning("Disk SMART read skipped: smartctl not found in PATH")
            state = .notInstalled
            return
        }
        LogArchiver.shared.info("Disk SMART reader found smartctl at: \(smartctlPath)")

        let smartCommand = #"\#(shellQuoted(smartctlPath)) -a /dev/disk0 2>&1"#
        let result = await runShell(smartCommand)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        LogArchiver.shared.info("Disk SMART normal read output:\n\(result.isEmpty ? "<empty>" : result)")

        let summary = smartSummary(from: result)
        if hasUsableSmartSummary(summary) {
            output = summary
            statusText = smartStatusText(for: summary)
            LogArchiver.shared.info("Disk SMART normal read summary:\n\(summary)")
            state = .available
            return
        }

        state = .authorizing
        LogArchiver.shared.warning("Disk SMART normal read did not include Data Units Written; requesting administrator privileges")
        let privilegedResult = await runPrivilegedShell(smartCommand)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        LogArchiver.shared.info("Disk SMART privileged read output:\n\(privilegedResult.isEmpty ? "<empty>" : privilegedResult)")

        let privilegedSummary = smartSummary(from: privilegedResult)
        output = privilegedSummary.isEmpty ? (privilegedResult.isEmpty ? result : privilegedResult) : privilegedSummary
        statusText = smartStatusText(for: privilegedSummary)
        state = hasUsableSmartSummary(privilegedSummary) ? .available : .failed
        if state == .failed {
            LogArchiver.shared.warning("Disk SMART read failed. normalSummary=\(summary.isEmpty ? "<empty>" : summary), privilegedSummary=\(privilegedSummary.isEmpty ? "<empty>" : privilegedSummary)")
        } else {
            LogArchiver.shared.info("Disk SMART privileged read summary:\n\(privilegedSummary)")
        }
    }

    private nonisolated func runShell(_ command: String) async -> String {
        await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return error.localizedDescription
            }
        }.value
    }

    private nonisolated func runPrivilegedShell(_ command: String) async -> String {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e",
                #"do shell script "/bin/zsh -lc " & quoted form of "\#(command)" with administrator privileges"#
            ]
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return error.localizedDescription
            }
        }.value
    }

    private nonisolated func smartSummary(from text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                line.localizedCaseInsensitiveContains("Data Units Written")
            }
            .joined(separator: "\n")
    }

    private nonisolated func hasUsableSmartSummary(_ text: String) -> Bool {
        text
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let colon = trimmed.firstIndex(of: ":") else { return false }
                return !trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    private nonisolated func smartStatusText(for summary: String) -> String {
        summary.localizedCaseInsensitiveContains("Data Units Written")
            ? "已检测到 smartctl，已自动读取累计写入量。"
            : "已检测到 smartctl，但未读到累计写入量。"
    }

    private nonisolated func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private struct DiskHealthGuideStepView: View {
    let number: Int
    let title: String
    let detail: String
    let command: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.blue, in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))

                Text(detail)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 0)

                    Button {
                        MenuBarSystemToolRunner.copyToPasteboard(command)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .menuBarToolPointingHandCursor()
                    .help("复制命令")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(10)
        .background(popoverSurfaceColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(popoverStrokeColor, lineWidth: 1)
        )
    }

    private var popoverSurfaceColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.62)
    }

    private var popoverStrokeColor: Color {
        Color.black.opacity(0.08)
    }
}

struct MenuBarGuideActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(tint == .secondary ? Color.primary : tint)
            .padding(.vertical, 9)
            .background(
                backgroundColor(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if tint == .secondary {
            return colorScheme == .dark ? Color.white.opacity(isPressed ? 0.06 : 0.09) : Color.white.opacity(isPressed ? 0.52 : 0.68)
        }
        return tint.opacity(isPressed ? 0.10 : 0.14)
    }

    private var strokeColor: Color {
        if tint == .secondary {
            return colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
        }
        return tint.opacity(0.18)
    }
}
