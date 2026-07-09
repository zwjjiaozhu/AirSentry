import Foundation

enum TranslationEngine: String, CaseIterable, Codable, Identifiable {
    case appleSystem
    case openAI
    case deepL
    case google

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleSystem: "Apple\n系统翻译"
        case .openAI: "OpenAI"
        case .deepL: "DeepL"
        case .google: "Google"
        }
    }

    var shortTitle: String {
        switch self {
        case .appleSystem: "Apple翻译"
        case .openAI: "OpenAI"
        case .deepL: "DeepL"
        case .google: "Google"
        }
    }

    var systemImage: String {
        switch self {
        case .appleSystem: "apple.logo"
        case .openAI: "sparkles"
        case .deepL: "shippingbox"
        case .google: "g.circle.fill"
        }
    }

    var statusTitle: String {
        switch self {
        case .appleSystem: "本地"
        case .openAI: "需配置"
        case .deepL, .google: "需配置"
        }
    }
}

enum TranslationAPIFormat: String, CaseIterable, Codable, Identifiable, Hashable {
    case openAICompatible
    case ollama
    case customHTTP

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容"
        case .ollama: "Ollama"
        case .customHTTP: "自定义 HTTP"
        }
    }

    var shortTitle: String {
        switch self {
        case .openAICompatible: "OpenAI"
        case .ollama: "Ollama"
        case .customHTTP: "HTTP"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAICompatible: "http://127.0.0.1:1234/v1"
        case .ollama: "http://127.0.0.1:11434"
        case .customHTTP: "http://127.0.0.1:8000/translate"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAICompatible: ""
        case .ollama: "hf.co/tencent/Hy-MT1.5-1.8B-2bit-GGUF"
        case .customHTTP: ""
        }
    }

    var helpText: String {
        switch self {
        case .openAICompatible:
            "兼容 OpenAI Chat Completions，例如 LM Studio、llama.cpp server、OneAPI、LiteLLM。"
        case .ollama:
            "调用 Ollama 原生接口，默认地址通常是 http://127.0.0.1:11434。"
        case .customHTTP:
            "高级模式，可填写请求模板和响应字段路径，适合自建服务。"
        }
    }
}

struct CustomTranslationEngine: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var format: TranslationAPIFormat
    var baseURL: String
    var apiKey: String
    var model: String
    var enabled: Bool
    var requestTemplate: String
    var responsePath: String

    init(
        id: UUID = UUID(),
        name: String = "新翻译引擎",
        icon: String = "sparkles",
        format: TranslationAPIFormat = .openAICompatible,
        baseURL: String? = nil,
        apiKey: String = "",
        model: String? = nil,
        enabled: Bool = true,
        requestTemplate: String = "",
        responsePath: String = ""
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.format = format
        self.baseURL = baseURL ?? format.defaultBaseURL
        self.apiKey = apiKey
        self.model = model ?? format.defaultModel
        self.enabled = enabled
        self.requestTemplate = requestTemplate
        self.responsePath = responsePath
    }

    static var hunyuanOllamaPreset: CustomTranslationEngine {
        CustomTranslationEngine(
            name: "本地混元 HY-MT",
            icon: "sparkles",
            format: .ollama,
            baseURL: TranslationAPIFormat.ollama.defaultBaseURL,
            model: TranslationAPIFormat.ollama.defaultModel,
            enabled: true
        )
    }
}

enum TranslationEngineIdentifier: Hashable, Equatable, Identifiable {
    case builtin(TranslationEngine)
    case custom(UUID)

    var id: String {
        switch self {
        case .builtin(let engine): "builtin.\(engine.rawValue)"
        case .custom(let id): "custom.\(id.uuidString)"
        }
    }
}

enum TranslationResultSource: Identifiable, Equatable, Hashable {
    case builtin(TranslationEngine)
    case custom(CustomTranslationEngine)

    var id: TranslationEngineIdentifier {
        switch self {
        case .builtin(let engine): .builtin(engine)
        case .custom(let engine): .custom(engine.id)
        }
    }

    var title: String {
        switch self {
        case .builtin(let engine): engine.title
        case .custom(let engine): engine.name
        }
    }

    var shortTitle: String {
        switch self {
        case .builtin(let engine): engine.shortTitle
        case .custom(let engine): engine.name
        }
    }

    var systemImage: String {
        switch self {
        case .builtin(let engine): engine.systemImage
        case .custom(let engine): engine.icon
        }
    }

    var statusTitle: String {
        switch self {
        case .builtin(let engine): engine.statusTitle
        case .custom(let engine): engine.format.shortTitle
        }
    }

    var builtinEngine: TranslationEngine? {
        switch self {
        case .builtin(let engine): engine
        case .custom: nil
        }
    }

    var customEngine: CustomTranslationEngine? {
        switch self {
        case .builtin: nil
        case .custom(let engine): engine
        }
    }
}

enum TranslationLanguage: String, CaseIterable, Codable, Identifiable {
    case automatic
    case simplifiedChinese
    case english
    case japanese
    case korean
    case french
    case german
    case spanish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "自动检测"
        case .simplifiedChinese: "简体中文"
        case .english: "英语"
        case .japanese: "日语"
        case .korean: "韩语"
        case .french: "法语"
        case .german: "德语"
        case .spanish: "西班牙语"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .automatic: nil
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        case .japanese: "ja"
        case .korean: "ko"
        case .french: "fr"
        case .german: "de"
        case .spanish: "es"
        }
    }

    static var sourceOptions: [TranslationLanguage] {
        [.automatic, .simplifiedChinese, .english, .japanese, .korean, .french, .german, .spanish]
    }

    static var targetOptions: [TranslationLanguage] {
        [.simplifiedChinese, .english, .japanese, .korean, .french, .german, .spanish]
    }
}

enum TranslationResultState: Equatable {
    case idle
    case translating
    case succeeded
    case failed(String)
}

struct TranslationResultItem: Identifiable, Equatable {
    let source: TranslationResultSource
    var id: TranslationEngineIdentifier { source.id }
    var customEngine: CustomTranslationEngine? { source.customEngine }
    var state: TranslationResultState
    var text: String
    var duration: TimeInterval?
}
