import Foundation

enum TranslationEngine: String, CaseIterable, Codable, Identifiable {
    case appleSystem
    case openAI
    case deepL
    case google
    case customAPI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleSystem: "Apple\n系统翻译"
        case .openAI: "OpenAI"
        case .deepL: "DeepL"
        case .google: "Google"
        case .customAPI: "自定义 API"
        }
    }

    var shortTitle: String {
        switch self {
        case .appleSystem: "Apple翻译"
        case .openAI: "OpenAI"
        case .deepL: "DeepL"
        case .google: "Google"
        case .customAPI: "自定义 API"
        }
    }

    var systemImage: String {
        switch self {
        case .appleSystem: "apple.logo"
        case .openAI: "sparkles"
        case .deepL: "shippingbox"
        case .google: "g.circle.fill"
        case .customAPI: "chevron.left.forwardslash.chevron.right"
        }
    }

    var statusTitle: String {
        switch self {
        case .appleSystem: "本地"
        case .openAI: "已启用"
        case .deepL, .google, .customAPI: "需配置"
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
    let id: TranslationEngine
    var engine: TranslationEngine { id }
    var state: TranslationResultState
    var text: String
    var duration: TimeInterval?
}
