import AppKit
import SwiftUI
import Translation

struct TranslationPanelView: View {
    @ObservedObject var store: TranslationStore
    @ObservedObject var settings: AppSettings
    let close: () -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                inputEditor
                resultList
                bottomBar
            }
            .padding(18)

            if #available(macOS 15.0, *) {
                AppleSystemTranslationBridge(store: store)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .background(.regularMaterial)
        .onAppear {
            if settings.translationAutoFocusesInput {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    inputFocused = true
                }
            }
            store.resetResults()
        }
        .onChange(of: store.isPinned) { pinned in
            NSApp.keyWindow?.level = pinned ? .floating : .normal
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("翻译")
                    .font(.system(size: 22, weight: .bold))

                Spacer()

                topIconButton(store.isPinned ? "pin.fill" : "pin", store.isPinned ? "取消置顶" : "置顶") {
                    store.isPinned.toggle()
                }
                topIconButton("doc.on.doc", "复制结果") {
                    store.copyBestResult()
                }
                topIconButton("trash", "清空") {
                    store.clear()
                }
                topIconButton("gearshape", "设置") {
                    NotificationCenter.default.post(name: .openTranslationSettings, object: nil)
                }
                topIconButton("xmark", "关闭", action: close)
            }

            HStack(spacing: 10) {
                compactPicker(selection: $store.sourceLanguage, options: TranslationLanguage.sourceOptions) { $0.title }
                    .frame(width: 145)

                Button {
                    store.swapLanguages()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.sourceLanguage == .automatic ? .tertiary : .secondary)
                .background(controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .disabled(store.sourceLanguage == .automatic)
                .help("交换语言")

                compactPicker(selection: $store.targetLanguage, options: TranslationLanguage.targetOptions) { $0.title }
                    .frame(width: 145)

                HStack(spacing: 6) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(store.activeEngines.count) 个引擎")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(controlBackground, in: Capsule())

                Spacer()
            }
        }
    }

    private func compactPicker<T: Identifiable & Hashable>(
        selection: Binding<T>,
        options: [T],
        title: @escaping (T) -> String
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(options) { option in
                Text(title(option)).tag(option)
            }
        }
        .labelsHidden()
        .controlSize(.regular)
        .background(controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func topIconButton(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(title)
    }

    private var inputEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("输入文本")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(store.characterCountText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.72))
            }

            TextEditor(text: $store.sourceText)
                .font(.system(size: 18))
                .scrollContentBackground(.hidden)
                .focused($inputFocused)
                .padding(14)
                .frame(minHeight: 150, maxHeight: 190)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.86), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.results) { result in
                    resultCard(result)
                }

                if store.results.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("输入文本后按下翻译")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                }
            }
            .padding(1)
        }
        .frame(minHeight: 220)
    }

    private func resultCard(_ result: TranslationResultItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: result.engine.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(engineAccent(result.engine))
                Text(result.engine.shortTitle)
                    .font(.system(size: 15, weight: .semibold))

                statusBadge(for: result)

                Spacer()

                if let duration = result.duration {
                    Text(String(format: "%.1fs", duration))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Button {
                    retry(result.engine)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("重试")

                Button {
                    store.copy(result.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(result.text.isEmpty)
                .help("复制")
            }

            Group {
                switch result.state {
                case .idle:
                    Text("等待翻译")
                        .foregroundStyle(.secondary)
                case .translating:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在翻译")
                            .foregroundStyle(.secondary)
                    }
                case .succeeded:
                    Text(result.text)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                case .failed(let message):
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.top, 1)
                        Text(message)
                    }
                    .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 16))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(cardBackground(for: result), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardStroke(for: result), lineWidth: 1)
        )
    }

    private func statusBadge(for result: TranslationResultItem) -> some View {
        let title: String
        let color: Color
        switch result.state {
        case .idle:
            title = "待命"
            color = .secondary
        case .translating:
            title = "进行中"
            color = .blue
        case .succeeded:
            title = "完成"
            color = .green
        case .failed:
            title = "提示"
            color = .orange
        }

        return Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                store.pasteFromClipboard()
            } label: {
                Label("粘贴", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)

            Button {
                store.translate()
            } label: {
                Label("翻译", systemImage: "sparkles")
                    .frame(minWidth: 112)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])

            Spacer()

            Text("⌘↩ 翻译")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func retry(_ engine: TranslationEngine) {
        store.translate()
    }

    private func cardBackground(for result: TranslationResultItem) -> Color {
        if case .succeeded = result.state {
            return Color(nsColor: .textBackgroundColor).opacity(0.90)
        }
        return Color(nsColor: .textBackgroundColor).opacity(0.84)
    }

    private func cardStroke(for result: TranslationResultItem) -> Color {
        if case .failed = result.state {
            return Color.orange.opacity(0.36)
        }
        if case .translating = result.state {
            return Color.blue.opacity(0.20)
        }
        return Color.primary.opacity(0.07)
    }

    private func engineAccent(_ engine: TranslationEngine) -> Color {
        switch engine {
        case .appleSystem: .blue
        case .openAI: .blue
        case .deepL: .indigo
        case .google: .red
        case .customAPI: .secondary
        }
    }

    private var controlBackground: Color {
        Color.primary.opacity(0.065)
    }
}

@available(macOS 15.0, *)
private struct AppleSystemTranslationBridge: View {
    @ObservedObject var store: TranslationStore
    @State private var configuration: TranslationSession.Configuration?
    @State private var handledRequestID: UUID?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(configuration) { session in
                await translate(with: session)
            }
            .onChange(of: store.appleTranslationRequestID) { requestID in
                guard let requestID, requestID != handledRequestID else { return }
                handledRequestID = requestID
                var nextConfiguration = makeConfiguration()
                nextConfiguration.invalidate()
                configuration = nextConfiguration
            }
    }

    private func makeConfiguration() -> TranslationSession.Configuration {
        TranslationSession.Configuration(
            source: store.sourceLanguage.localeIdentifier.map { Locale.Language(identifier: $0) },
            target: store.targetLanguage.localeIdentifier.map { Locale.Language(identifier: $0) }
        )
    }

    private func translate(with session: TranslationSession) async {
        let text = store.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            store.markAppleError("请输入要翻译的文本")
            return
        }

        do {
            let response = try await session.translate(text)
            store.markAppleResult(text: response.targetText)
        } catch {
            store.markAppleError(appleErrorMessage(for: error))
        }
    }

    private func appleErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.isEmpty {
            return "Apple 系统翻译暂时不可用"
        }
        return message
    }
}

extension Notification.Name {
    static let openTranslationSettings = Notification.Name("AirSentryOpenTranslationSettings")
}
