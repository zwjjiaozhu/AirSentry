import AppKit
import Combine
import Foundation

@MainActor
final class TranslationStore: ObservableObject {
    @Published var sourceText = ""
    @Published var sourceLanguage: TranslationLanguage
    @Published var targetLanguage: TranslationLanguage
    @Published var selectedEngine: TranslationEngine
    @Published var panelMode: TranslationPanelMode
    @Published var results: [TranslationResultItem] = []
    @Published var isPinned = false
    @Published var appleTranslationRequestID: UUID?

    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var activeStartDates: [TranslationEngine: Date] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        sourceLanguage = settings.translationDefaultSourceLanguage
        targetLanguage = settings.translationDefaultTargetLanguage
        selectedEngine = settings.translationDefaultEngine
        panelMode = settings.translationPanelMode

        settings.$translationDefaultSourceLanguage
            .sink { [weak self] language in self?.sourceLanguage = language }
            .store(in: &cancellables)

        settings.$translationDefaultTargetLanguage
            .sink { [weak self] language in self?.targetLanguage = language }
            .store(in: &cancellables)

        settings.$translationDefaultEngine
            .sink { [weak self] engine in self?.selectedEngine = engine }
            .store(in: &cancellables)

        settings.$translationPanelMode
            .sink { [weak self] mode in self?.panelMode = mode }
            .store(in: &cancellables)
    }

    var activeEngines: [TranslationEngine] {
        if panelMode == .single {
            return [selectedEngine]
        }

        let configured = settings.translationComparisonEngines
        return configured.isEmpty ? [.appleSystem] : configured
    }

    var characterCountText: String {
        "\(sourceText.count) / 5000"
    }

    func prepareForPresentation() {
        sourceLanguage = settings.translationDefaultSourceLanguage
        targetLanguage = settings.translationDefaultTargetLanguage
        selectedEngine = settings.translationDefaultEngine
        panelMode = settings.translationPanelMode

        if settings.translationReadsClipboardText,
           let pastedText = NSPasteboard.general.string(forType: .string),
           !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceText = String(pastedText.prefix(5000))
        }

        if settings.translationReadsClipboardText && !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translate()
        } else if results.isEmpty {
            resetResults()
        }
    }

    func translate() {
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            results = activeEngines.map {
                TranslationResultItem(id: $0, state: .failed("请输入要翻译的文本"), text: "", duration: nil)
            }
            return
        }

        let engines = activeEngines
        activeStartDates = Dictionary(uniqueKeysWithValues: engines.map { ($0, Date()) })
        results = engines.map { TranslationResultItem(id: $0, state: .translating, text: "", duration: nil) }

        for engine in engines where engine != .appleSystem {
            markResult(
                for: engine,
                state: .failed(enginePlaceholderMessage(for: engine)),
                text: ""
            )
        }

        if engines.contains(.appleSystem) {
            if #available(macOS 15.0, *) {
                appleTranslationRequestID = UUID()
            } else {
                markResult(
                    for: .appleSystem,
                    state: .failed("Apple 系统翻译需要 macOS 15 或更高版本"),
                    text: ""
                )
            }
        }
    }

    func resetResults() {
        results = activeEngines.map { TranslationResultItem(id: $0, state: .idle, text: "", duration: nil) }
    }

    func pasteFromClipboard() {
        guard let pastedText = NSPasteboard.general.string(forType: .string) else { return }
        sourceText = String(pastedText.prefix(5000))
    }

    func copyBestResult() {
        guard let result = results.first(where: {
            if case .succeeded = $0.state { return !$0.text.isEmpty }
            return false
        }) else { return }

        copy(result.text)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clear() {
        sourceText = ""
        appleTranslationRequestID = nil
        resetResults()
    }

    func swapLanguages() {
        guard sourceLanguage != .automatic else { return }
        let oldSource = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = oldSource
    }

    func markAppleResult(text: String) {
        markResult(for: .appleSystem, state: .succeeded, text: text)

        if settings.translationAutoCopiesResult {
            copy(text)
        }
    }

    func markAppleError(_ message: String) {
        markResult(for: .appleSystem, state: .failed(message), text: "")
    }

    private func markResult(for engine: TranslationEngine, state: TranslationResultState, text: String) {
        guard let index = results.firstIndex(where: { $0.engine == engine }) else { return }
        let duration = activeStartDates[engine].map { Date().timeIntervalSince($0) }
        results[index] = TranslationResultItem(id: engine, state: state, text: text, duration: duration)
    }

    private func enginePlaceholderMessage(for engine: TranslationEngine) -> String {
        switch engine {
        case .appleSystem:
            return ""
        case .openAI:
            return settings.translationOpenAIAPIKey.isEmpty ? "请先在工具箱配置 OpenAI API Key" : "OpenAI 引擎接口将在下一步接入"
        case .deepL:
            return "DeepL 引擎接口将在下一步接入"
        case .google:
            return "Google 引擎接口将在下一步接入"
        case .customAPI:
            return "请先配置自定义 API 端点"
        }
    }
}
