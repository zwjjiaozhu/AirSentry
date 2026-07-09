import AppKit
import Combine
import Foundation

@MainActor
final class TranslationStore: ObservableObject {
    @Published var sourceText = ""
    @Published var sourceLanguage: TranslationLanguage
    @Published var targetLanguage: TranslationLanguage
    @Published var results: [TranslationResultItem] = []
    @Published var isPinned = false
    @Published var appleTranslationRequestID: UUID?

    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var activeStartDates: [TranslationEngineIdentifier: Date] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        sourceLanguage = settings.translationDefaultSourceLanguage
        targetLanguage = settings.translationDefaultTargetLanguage

        settings.$translationDefaultSourceLanguage
            .sink { [weak self] language in self?.sourceLanguage = language }
            .store(in: &cancellables)

        settings.$translationDefaultTargetLanguage
            .sink { [weak self] language in self?.targetLanguage = language }
            .store(in: &cancellables)
    }

    var activeEngines: [TranslationResultSource] {
        var sources = settings.translationEngines.map { TranslationResultSource.builtin($0) }
        sources.append(contentsOf: settings.customTranslationEngines.filter(\.enabled).map { .custom($0) })
        return sources.isEmpty ? [.builtin(.appleSystem)] : sources
    }

    var characterCountText: String {
        "\(sourceText.count) / 5000"
    }

    func prepareForPresentation() {
        sourceLanguage = settings.translationDefaultSourceLanguage
        targetLanguage = settings.translationDefaultTargetLanguage

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
        let engines = activeEngines

        guard !trimmedText.isEmpty else {
            results = engines.map {
                TranslationResultItem(source: $0, state: .failed("请输入要翻译的文本"), text: "", duration: nil)
            }
            return
        }

        activeStartDates = Dictionary(uniqueKeysWithValues: engines.map { ($0.id, Date()) })
        results = engines.map { TranslationResultItem(source: $0, state: .translating, text: "", duration: nil) }

        for source in engines {
            switch source {
            case .builtin(.appleSystem):
                if #available(macOS 15.0, *) {
                    appleTranslationRequestID = UUID()
                } else {
                    markResult(
                        for: source.id,
                        state: .failed("Apple 系统翻译需要 macOS 15 或更高版本"),
                        text: ""
                    )
                }
            case .builtin(let engine):
                markResult(
                    for: source.id,
                    state: .failed(enginePlaceholderMessage(for: engine)),
                    text: ""
                )
            case .custom(let engine):
                markResult(
                    for: source.id,
                    state: .failed(customEnginePlaceholderMessage(for: engine)),
                    text: ""
                )
            }
        }
    }

    func resetResults() {
        results = activeEngines.map { TranslationResultItem(source: $0, state: .idle, text: "", duration: nil) }
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

    func markAppleResult(text: String, requestID: UUID? = nil) {
        guard shouldAcceptAppleResult(for: requestID) else { return }
        markResult(for: .builtin(.appleSystem), state: .succeeded, text: text)

        if settings.translationAutoCopiesResult {
            copy(text)
        }
    }

    func markAppleError(_ message: String, requestID: UUID? = nil) {
        guard shouldAcceptAppleResult(for: requestID) else { return }
        markResult(for: .builtin(.appleSystem), state: .failed(message), text: "")
    }

    private func shouldAcceptAppleResult(for requestID: UUID?) -> Bool {
        guard let requestID else { return true }
        return appleTranslationRequestID == requestID
    }

    private func markResult(for id: TranslationEngineIdentifier, state: TranslationResultState, text: String) {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        let duration = activeStartDates[id].map { Date().timeIntervalSince($0) }
        results[index] = TranslationResultItem(source: results[index].source, state: state, text: text, duration: duration)
    }

    private func enginePlaceholderMessage(for engine: TranslationEngine) -> String {
        switch engine {
        case .appleSystem:
            return ""
        case .openAI:
            return settings.translationOpenAIAPIKey.isEmpty ? "请先配置 OpenAI API Key，或添加一个 OpenAI 兼容自定义引擎" : "OpenAI 引擎接口将在下一步接入"
        case .deepL:
            return "DeepL 引擎接口将在下一步接入"
        case .google:
            return "Google 引擎接口将在下一步接入"
        }
    }

    private func customEnginePlaceholderMessage(for engine: CustomTranslationEngine) -> String {
        let baseURL = engine.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseURL.isEmpty {
            return "请先配置 \(engine.name) 的 API 地址"
        }

        switch engine.format {
        case .openAICompatible:
            return engine.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "请先配置 OpenAI 兼容模型名称" : "OpenAI 兼容接口将在下一步接入"
        case .ollama:
            return engine.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "请先配置 Ollama 模型名称" : "Ollama 接口将在下一步接入"
        case .customHTTP:
            return engine.requestTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "请先配置自定义 HTTP 请求模板" : "自定义 HTTP 接口将在下一步接入"
        }
    }
}
