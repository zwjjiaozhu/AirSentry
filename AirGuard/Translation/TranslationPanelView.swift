import AppKit
import SwiftUI
import Translation

struct TranslationPanelView: View {
    @ObservedObject var store: TranslationStore
    @ObservedObject var settings: AppSettings
    let close: () -> Void

    @FocusState private var inputFocused: Bool
    @State private var favoritedEngines: Set<TranslationEngine> = []
    @State private var collapsedEngines: Set<TranslationEngine> = []
    @StateObject private var speechSpeaker = TranslationSpeechSpeaker()

    var body: some View {
        ZStack {
            panelBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 9) {
                topBar
                inputEditor
                resultList
                shortcutHint
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .ignoresSafeArea(.container, edges: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if #available(macOS 15.0, *) {
                AppleSystemTranslationBridge(store: store)
            }
        }
        .frame(
            minWidth: 320,
            idealWidth: 380,
            maxWidth: .infinity,
            minHeight: 340,
            idealHeight: 620,
            maxHeight: .infinity
        )
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("翻译")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("多引擎实时对比翻译")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    topIconButton(store.isPinned ? "pin.fill" : "pin", store.isPinned ? "取消置顶" : "置顶") {
                        store.isPinned.toggle()
                    }
                    topIconButton("doc.on.doc", "复制最佳结果") {
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
            }

            compactConfigBar
        }
    }

    private var compactConfigBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                compactMenuPicker(
                    selection: $store.sourceLanguage,
                    options: TranslationLanguage.sourceOptions,
                    accent: .blue
                ) { $0.title }
                .frame(width: 82)

                Button {
                    store.swapLanguages()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.sourceLanguage == .automatic ? .tertiary : .secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.sourceLanguage == .automatic)
                .help("交换语言")

                compactMenuPicker(
                    selection: $store.targetLanguage,
                    options: TranslationLanguage.targetOptions,
                    accent: .red
                ) { $0.title }
                .frame(width: 82)

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 2)

                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("\(store.activeEngines.count) 引擎")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
            }
            .padding(2)
            .background(.white.opacity(0.62), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.035), radius: 10, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMenuPicker<T: Identifiable & Hashable>(
        selection: Binding<T>,
        options: [T],
        accent: Color,
        title: @escaping (T) -> String
    ) -> some View {
        Menu {
            ForEach(options) { option in
                Button(title(option)) {
                    selection.wrappedValue = option
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: accent.opacity(0.35), radius: 4, y: 1)

                Text(title(selection.wrappedValue))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func topIconButton(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
        .help(title)
    }

    private var inputEditor: some View {
        ZStack(alignment: .bottomTrailing) {
            TextEditor(text: $store.sourceText)
                .font(.system(size: 12.8, weight: .regular))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, minHeight: 58, idealHeight: 74, maxHeight: 96)

            inputFloatingActions
                .padding(.trailing, 7)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(inputFocused ? Color.blue.opacity(0.34) : Color.primary.opacity(0.075), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.045), radius: 14, y: 6)
    }

    private var inputFloatingActions: some View {
        HStack(spacing: 5) {
            Text(store.characterCountText.replacingOccurrences(of: " / ", with: "/"))
                .font(.system(size: 10.8, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.68))
                .monospacedDigit()

            inputActionButton("sparkles", "翻译") {
                store.translate()
            }
            .keyboardShortcut(.return, modifiers: [.command])

            inputActionButton("doc.on.clipboard", "粘贴") {
                store.pasteFromClipboard()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.035), radius: 7, y: 3)
    }

    private func inputActionButton(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(title == "翻译" ? Color.blue : Color.secondary)
                .frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.065), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.025), radius: 5, y: 2)
        .help(title)
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.results) { result in
                    resultCard(result)
                }

                if store.results.isEmpty {
                    emptyState
                }
            }
            .padding(.vertical, 1)
        }
        .frame(minHeight: 120, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("输入文本后按下翻译")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func resultCard(_ result: TranslationResultItem) -> some View {
        let isCollapsed = collapsedEngines.contains(result.engine)
        let isFavorited = favoritedEngines.contains(result.engine)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                engineIcon(result.engine)

                Text(result.engine.shortTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(1)

                statusBadge(for: result)

                Spacer()

                if let duration = result.duration {
                    Text(String(format: "%.1fs", duration))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.trailing, 2)
                }

                engineActionButton(isFavorited ? "star.fill" : "star", isFavorited ? "取消收藏" : "收藏") {
                    toggle(result.engine, in: &favoritedEngines)
                }
                .foregroundStyle(isFavorited ? .yellow : .secondary)

                engineActionButton("speaker.wave.2", "朗读") {
                    speak(result.text)
                }
                .disabled(result.text.isEmpty)

                engineActionButton("doc.on.doc", "复制") {
                    store.copy(result.text)
                }
                .disabled(result.text.isEmpty)

                engineActionButton(isCollapsed ? "chevron.down" : "chevron.up", isCollapsed ? "展开" : "折叠") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        toggle(result.engine, in: &collapsedEngines)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            if !isCollapsed {
                Divider()
                    .padding(.horizontal, 10)

                resultBody(result)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(cardBackground(for: result), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardStroke(for: result), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }

    @ViewBuilder
    private func resultBody(_ result: TranslationResultItem) -> some View {
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
                        .padding(.top, 2)
                    Text(message)
                }
                .foregroundStyle(.orange)
            }
        }
        .font(.system(size: 14.5))
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func engineIcon(_ engine: TranslationEngine) -> some View {
        Image(systemName: engine.systemImage)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(engineAccent(engine))
            .frame(width: 26, height: 26)
            .background(engineAccent(engine).opacity(0.10), in: Circle())
            .overlay(
                Circle()
                    .stroke(engineAccent(engine).opacity(0.15), lineWidth: 1)
            )
    }

    private func engineActionButton(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.075), lineWidth: 1)
        )
        .help(title)
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var shortcutHint: some View {
        HStack {
            Spacer()
            Text("⌘↩ 翻译")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.78))
        }
        .padding(.top, -2)
    }

    private func retry(_ engine: TranslationEngine) {
        store.translate()
    }

    private func speak(_ text: String) {
        speechSpeaker.speak(text)
    }

    private func toggle(_ engine: TranslationEngine, in set: inout Set<TranslationEngine>) {
        if set.contains(engine) {
            set.remove(engine)
        } else {
            set.insert(engine)
        }
    }

    private func cardBackground(for result: TranslationResultItem) -> Color {
        switch result.state {
        case .failed:
            return Color(nsColor: .textBackgroundColor).opacity(0.84)
        case .succeeded:
            return Color(nsColor: .textBackgroundColor).opacity(0.92)
        case .translating:
            return Color(nsColor: .textBackgroundColor).opacity(0.88)
        case .idle:
            return Color(nsColor: .textBackgroundColor).opacity(0.80)
        }
    }

    private func cardStroke(for result: TranslationResultItem) -> Color {
        switch result.state {
        case .failed:
            return Color.orange.opacity(0.16)
        case .translating:
            return Color.blue.opacity(0.20)
        default:
            return Color.primary.opacity(0.065)
        }
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

    private var panelBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor).opacity(0.92),
                Color.primary.opacity(0.035)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .background(.regularMaterial)
    }
}

@MainActor
private final class TranslationSpeechSpeaker: ObservableObject {
    private let synthesizer = NSSpeechSynthesizer()

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking()
        }
        synthesizer.startSpeaking(text)
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
