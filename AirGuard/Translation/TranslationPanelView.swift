import AppKit
import SwiftUI
import Translation

struct TranslationPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: TranslationStore
    @ObservedObject var settings: AppSettings
    let close: () -> Void

    @FocusState private var inputFocused: Bool
    @State private var favoritedEngines: Set<TranslationEngine> = []
    @State private var collapsedEngines: Set<TranslationEngine> = []
    @State private var resultContentHeights: [TranslationEngine: CGFloat] = [:]
    @State private var resizingStartHeights: [TranslationEngine: CGFloat] = [:]
    @State private var contentRevealProgress: [TranslationEngine: CGFloat] = [:]
    @State private var contentOpacity: [TranslationEngine: CGFloat] = [:]
    @StateObject private var speechSpeaker = TranslationSpeechSpeaker()

    private let defaultResultContentHeight: CGFloat = 122
    private let minResultContentHeight: CGFloat = 56
    private let maxResultContentHeight: CGFloat = 420
    private let expandAnimation: Animation = .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.32)
    private let contentFadeAnimation: Animation = .easeOut(duration: 0.16).delay(0.035)
    private let collapseAnimation: Animation = .timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.22)
    private let chevronAnimation: Animation = .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.24)

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
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 7) {
                topIconButton(store.isPinned ? "pin.fill" : "pin", store.isPinned ? "取消置顶" : "置顶") {
                    store.isPinned.toggle()
                }

                Spacer()

                HStack(spacing: 4) {
                    topIconButton("gearshape", "设置") {
                        NotificationCenter.default.post(name: .openTranslationSettings, object: nil)
                    }
                    topIconButton("xmark", "关闭", action: close)
                }
            }

            compactConfigBar
        }
        .background(WindowDragRegion())
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
            .background(controlFill, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: softShadow, radius: 10, y: 4)
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
        .background(controlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: softShadow, radius: 8, y: 3)
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
        .background(inputFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(inputFocused ? Color.blue.opacity(0.34) : Color.primary.opacity(0.075), lineWidth: 1)
        )
        .shadow(color: cardShadow, radius: 14, y: 6)
    }

    private var inputFloatingActions: some View {
        HStack(spacing: 4) {
            Text(store.characterCountText.replacingOccurrences(of: " / ", with: "/"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.65))
                .monospacedDigit()

            inputActionButton("doc.on.clipboard", "粘贴") {
                store.pasteFromClipboard()
            }

            inputActionButton("trash", "清空") {
                store.clear()
            }

            inputActionButton("sparkles", "翻译") {
                store.translate()
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private func inputActionButton(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(title == "翻译" ? Color.blue : Color.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
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
        .background(emptyFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func resultCard(_ result: TranslationResultItem) -> some View {
        let isCollapsed = collapsedEngines.contains(result.engine)
        let isFavorited = favoritedEngines.contains(result.engine)
        let visibleHeight = resultContentHeight(for: result)
        let revealProgress = contentRevealProgress[result.engine] ?? (isCollapsed ? 0 : 1)
        let bodyOpacity = contentOpacity[result.engine] ?? (isCollapsed ? 0 : 1)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                engineIcon(result.engine)

                Text(result.engine.shortTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(1)

                statusIcon(for: result)

                Spacer(minLength: 6)

                if let duration = result.duration {
                    Text(String(format: "%.1fs", duration))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.trailing, 2)
                }

                engineActionButton(isFavorited ? "star.fill" : "star", isFavorited ? "取消收藏" : "收藏") {
                    toggle(result.engine, in: &favoritedEngines)
                }
                .foregroundStyle(isFavorited ? .yellow : .secondary)

                engineSpeakerButton(
                    isPlaying: speechSpeaker.speakingEngine == result.engine,
                    isDisabled: result.text.isEmpty
                ) {
                    speak(result.text, engine: result.engine)
                }

                engineActionButton("doc.on.doc", "复制") {
                    store.copy(result.text)
                }
                .disabled(result.text.isEmpty)

                engineActionButton("chevron.right", isCollapsed ? "展开" : "折叠") {
                    toggleCollapse(result.engine)
                }
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .animation(chevronAnimation, value: isCollapsed)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                toggleCollapse(result.engine)
            }

            resultContentArea(
                result,
                visibleHeight: visibleHeight,
                isCollapsed: isCollapsed,
                revealProgress: revealProgress,
                bodyOpacity: bodyOpacity,
                showsResizeHandle: shouldShowResizeHandle(for: result)
            )
        }
        .background(cardBackground(for: result), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardStroke(for: result), lineWidth: 1)
        )
        .shadow(color: cardShadow, radius: 14, y: 6)
    }

    private func resultContentArea(
        _ result: TranslationResultItem,
        visibleHeight: CGFloat,
        isCollapsed: Bool,
        revealProgress: CGFloat,
        bodyOpacity: CGFloat,
        showsResizeHandle: Bool
    ) -> some View {
        let clampedProgress = min(max(revealProgress, 0), 1)
        let animatedHeight = max(0, visibleHeight * clampedProgress)
        let clampedOpacity = min(max(bodyOpacity, 0), 1)

        return VStack(spacing: 0) {
            resultContentView(result)
                .id(result.engine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(clampedOpacity)

            if showsResizeHandle {
                resizeHandle(for: result.engine)
                    .opacity(clampedProgress > 0.96 ? 1 : 0)
                    .allowsHitTesting(!isCollapsed && clampedProgress > 0.96)
            }
        }
        .frame(height: animatedHeight)
        .mask(alignment: .top) {
            Rectangle()
                .frame(height: max(0, visibleHeight * clampedProgress))
        }
        .opacity(clampedProgress <= 0.01 ? 0 : 1)
        .allowsHitTesting(!isCollapsed && clampedProgress > 0.98)
        .clipped()
        .animation(expandAnimation, value: revealProgress)
    }

    @ViewBuilder
    private func resultContentView(_ result: TranslationResultItem) -> some View {
        switch result.state {
        case .succeeded:
            SelectableResultTextView(text: result.text) {
                store.copy(result.text)
            }
        default:
            ScrollView {
                resultBody(result)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func resultContentHeight(for result: TranslationResultItem) -> CGFloat {
        if let customHeight = resultContentHeights[result.engine] {
            return customHeight
        }

        switch result.state {
        case .succeeded:
            let textLength = result.text.trimmingCharacters(in: .whitespacesAndNewlines).count
            if textLength <= 12 {
                return 54
            }
            if textLength <= 48 {
                return 70
            }
            if textLength <= 120 {
                return 96
            }
            return defaultResultContentHeight
        case .failed:
            return 54
        case .idle:
            return 44
        case .translating:
            return 48
        }
    }

    private func resultContentHeight(for engine: TranslationEngine) -> CGFloat {
        resultContentHeights[engine] ?? defaultResultContentHeight
    }

    private func shouldShowResizeHandle(for result: TranslationResultItem) -> Bool {
        guard case .succeeded = result.state else { return false }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines).count > 48 || resultContentHeights[result.engine] != nil
    }

    private func resizeHandle(for engine: TranslationEngine) -> some View {
        ResultResizeHandle(
            onDragBegan: {
                resizingStartHeights[engine] = resultContentHeight(for: engine)
            },
            onDragChanged: { deltaY in
                let startHeight = resizingStartHeights[engine] ?? resultContentHeight(for: engine)
                let nextHeight = min(
                    max(startHeight + deltaY, minResultContentHeight),
                    maxResultContentHeight
                )

                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    resultContentHeights[engine] = nextHeight
                }
            },
            onDragEnded: {
                resizingStartHeights[engine] = nil
            }
        )
        .frame(height: 14)
        .frame(maxWidth: .infinity)
        .help("拖拽调整内容高度")
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
                    .foregroundStyle(.primary)
                    .contextMenu {
                        Button("复制") {
                            store.copy(result.text)
                        }
                    }
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
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .pointingHandCursor()
        .help(title)
    }

    private func engineSpeakerButton(isPlaying: Bool, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AnimatedSpeakerIcon(isPlaying: isPlaying)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPlaying ? .blue : .secondary)
        .disabled(isDisabled)
        .pointingHandCursor()
        .help(isPlaying ? "停止朗读" : "朗读")
    }

    @ViewBuilder
    private func statusIcon(for result: TranslationResultItem) -> some View {
        switch result.state {
        case .idle:
            EmptyView()
        case .translating:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.58)
                .frame(width: 18, height: 18)
                .help("正在翻译")
        case .succeeded:
            EmptyView()
        case .failed:
            Button {
                retry(result.engine)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(Color.orange.opacity(0.10), in: Circle())
            .pointingHandCursor()
            .help("重新翻译")
        }
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

    private func speak(_ text: String, engine: TranslationEngine) {
        speechSpeaker.toggle(text, engine: engine)
    }

    private func toggleCollapse(_ engine: TranslationEngine) {
        if collapsedEngines.contains(engine) {
            expandEngine(engine)
        } else {
            collapseEngine(engine)
        }
    }

    private func expandEngine(_ engine: TranslationEngine) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            collapsedEngines.remove(engine)
            contentRevealProgress[engine] = 0
            contentOpacity[engine] = 0
        }

        DispatchQueue.main.async {
            withAnimation(expandAnimation) {
                contentRevealProgress[engine] = 1
            }
            withAnimation(contentFadeAnimation) {
                contentOpacity[engine] = 1
            }
        }
    }

    private func collapseEngine(_ engine: TranslationEngine) {
        withAnimation(.easeOut(duration: 0.08)) {
            contentOpacity[engine] = 0
        }
        withAnimation(collapseAnimation) {
            contentRevealProgress[engine] = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                collapsedEngines.insert(engine)
                contentOpacity[engine] = 0
            }
        }
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
            return Color.orange.opacity(0.10)
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

    private var controlFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.62)
    }

    private var inputFill: Color {
        colorScheme == .dark ? Color(nsColor: .controlBackgroundColor).opacity(0.68) : Color.white.opacity(0.78)
    }

    private var floatingButtonFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.70)
    }

    private var emptyFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.42)
    }

    private var softShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.035)
    }

    private var cardShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.26) : Color.black.opacity(0.045)
    }

    private var panelBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark ? [
                Color(nsColor: .windowBackgroundColor).opacity(0.96),
                Color.white.opacity(0.035)
            ] : [
                Color(nsColor: .windowBackgroundColor).opacity(0.92),
                Color.primary.opacity(0.035)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .background(colorScheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial))
    }
}

@MainActor
private final class TranslationSpeechSpeaker: NSObject, ObservableObject, NSSpeechSynthesizerDelegate {
    @Published var speakingEngine: TranslationEngine?

    private let synthesizer = NSSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String, engine: TranslationEngine) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if synthesizer.isSpeaking, speakingEngine == engine {
            synthesizer.stopSpeaking()
            speakingEngine = nil
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking()
        }

        speakingEngine = engine
        synthesizer.startSpeaking(trimmedText)
    }

    nonisolated func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        Task { @MainActor in
            self.speakingEngine = nil
        }
    }
}

private struct AnimatedSpeakerIcon: View {
    let isPlaying: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isPlaying {
                Circle()
                    .stroke(Color.blue.opacity(pulse ? 0.18 : 0.46), lineWidth: 1.5)
                    .scaleEffect(pulse ? 1.22 : 0.78)
                    .opacity(pulse ? 0.15 : 0.65)

                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .scaleEffect(pulse ? 1.04 : 0.96)
            } else {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .onAppear {
            guard isPlaying else { return }
            pulse = false
            withAnimation(.easeInOut(duration: 0.78).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: isPlaying) { playing in
            if playing {
                pulse = false
                withAnimation(.easeInOut(duration: 0.78).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside {
                guard !isHovering else { return }
                NSCursor.pointingHand.push()
                isHovering = true
            } else if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}


private struct ResultResizeHandle: NSViewRepresentable {
    var onDragBegan: () -> Void
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: () -> Void

    func makeNSView(context: Context) -> ResizeHandleView {
        let view = ResizeHandleView()
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: ResizeHandleView, context: Context) {
        nsView.onDragBegan = onDragBegan
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }

    final class ResizeHandleView: NSView {
        var onDragBegan: (() -> Void)?
        var onDragChanged: ((CGFloat) -> Void)?
        var onDragEnded: (() -> Void)?

        private var startLocationInWindow: NSPoint?
        private var isDragging = false
        private var didPushCursor = false
        private let handleLayer = CALayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = false

            handleLayer.backgroundColor = NSColor.clear.cgColor
            handleLayer.cornerRadius = 1.5
            layer?.addSublayer(handleLayer)

            addHoverTrackingArea()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            let handleSize = NSSize(width: 30, height: 3)
            handleLayer.frame = CGRect(
                x: (bounds.width - handleSize.width) / 2,
                y: (bounds.height - handleSize.height) / 2,
                width: handleSize.width,
                height: handleSize.height
            )
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            addHoverTrackingArea()
        }

        private func addHoverTrackingArea() {
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                )
            )
        }

        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseEntered(with event: NSEvent) {
            showHoverState()
        }

        override func mouseMoved(with event: NSEvent) {
            showHoverState()
        }

        override func mouseExited(with event: NSEvent) {
            guard !isDragging else { return }
            hideHoverState()
        }

        private func showHoverState() {
            if !didPushCursor {
                NSCursor.resizeUpDown.push()
                didPushCursor = true
            }
            NSCursor.resizeUpDown.set()
            handleLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.30).cgColor
        }

        private func hideHoverState() {
            if didPushCursor {
                NSCursor.pop()
                didPushCursor = false
            }
            handleLayer.backgroundColor = NSColor.clear.cgColor
        }

        override func mouseDown(with event: NSEvent) {
            isDragging = true
            startLocationInWindow = event.locationInWindow
            NSCursor.resizeUpDown.set()
            handleLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
            onDragBegan?()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startLocationInWindow else { return }
            // NSEvent window coordinates grow upward; dragging down should increase the SwiftUI height,
            // so invert the delta to match DragGesture's positive-down convention.
            let deltaY = startLocationInWindow.y - event.locationInWindow.y
            onDragChanged?(deltaY)
        }

        override func mouseUp(with event: NSEvent) {
            finishDragging()
        }

        override func mouseCancelled(with event: NSEvent) {
            finishDragging()
        }

        private func finishDragging() {
            isDragging = false
            startLocationInWindow = nil
            onDragEnded?()

            if let window, bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
                showHoverState()
            } else {
                hideHoverState()
            }
        }
    }
}


private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragRegionView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragRegionView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDragged(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}


private struct SelectableResultTextView: NSViewRepresentable {
    let text: String
    var onCopy: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: 14.5)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.allowsUndo = false
        textView.menu = makeContextMenu()

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: 14.5)

        if textView.string != text {
            textView.string = text
        }

        textView.textContainer?.containerSize = NSSize(
            width: max(scrollView.contentSize.width, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        return menu
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
            .id(handledRequestID)
            .translationTask(configuration) { session in
                await translate(with: session)
            }
            .onChange(of: store.appleTranslationRequestID) { requestID in
                guard let requestID, requestID != handledRequestID else { return }
                handledRequestID = requestID

                // Apple Translation 的 Configuration 在源/目标语言不变时，
                // 只重新赋一个“相同配置”不一定会触发新的 translationTask。
                // 先置空，再下一轮 RunLoop 重新挂载并 invalidate，确保连续点击翻译也会重新执行。
                configuration = nil
                Task { @MainActor in
                    await Task.yield()
                    configuration = makeConfiguration()
                    await Task.yield()
                    configuration?.invalidate()
                }
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
