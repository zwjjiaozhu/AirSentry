import AppKit
import SwiftUI

struct TranslationSettingsView: View {
    @ObservedObject var settings: AppSettings
    @Binding var isRecordingShortcut: Bool
    let conflictReason: String?

    @State private var configurationEngine: TranslationEngine = .appleSystem
    @State private var configurationCustomEngineID: UUID?
    @State private var showingCustomEngineEditor = false
    @State private var editingCustomEngineID: UUID?
    @State private var customEngineDraft = CustomTranslationEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            shortcutCard
            languageCard
            engineCard
            behaviorCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingCustomEngineEditor) {
            CustomTranslationEngineEditorSheet(
                engine: $customEngineDraft,
                isEditing: editingCustomEngineID != nil,
                onCancel: { showingCustomEngineEditor = false },
                onSave: saveCustomEngineDraft
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("翻译助手")
                    .font(.system(size: 24, weight: .bold))
                Text("配置独立翻译面板、全局快捷键和多个翻译引擎。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer()

            Button {
                NotificationCenter.default.post(name: .showTranslationPanel, object: nil)
            } label: {
                Label("打开面板", systemImage: "character.bubble")
            }
            .buttonStyle(.borderedProminent)
            .fixedSize()
        }
    }

    private var shortcutCard: some View {
        settingsCard {
            HStack(alignment: .top, spacing: 14) {
                settingsIcon("keyboard.badge.ellipsis")

                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷键弹出翻译面板")
                        .font(.system(size: 17, weight: .semibold))
                    Text("面板独立显示，可自动读取剪贴板并进入多引擎对照翻译。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                TranslationShortcutRecorderButton(
                    shortcut: settings.translationShortcut,
                    isRecording: isRecordingShortcut,
                    conflictReason: conflictReason,
                    startRecording: { isRecordingShortcut = true },
                    record: { shortcut in
                        settings.setTranslationShortcut(shortcut)
                        isRecordingShortcut = false
                    },
                    cancel: { isRecordingShortcut = false },
                    clear: {
                        settings.translationShortcut = nil
                        isRecordingShortcut = false
                    }
                )
                .frame(width: 150)

                Toggle("", isOn: $settings.translationShortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .padding(.top, 3)
            }

            if let conflictReason {
                Label(conflictReason, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var languageCard: some View {
        settingsCard {
            Text("默认语言")
                .font(.system(size: 17, weight: .semibold))

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("源语言")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $settings.translationDefaultSourceLanguage) {
                        ForEach(TranslationLanguage.sourceOptions) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    guard settings.translationDefaultSourceLanguage != .automatic else { return }
                    let oldSource = settings.translationDefaultSourceLanguage
                    settings.translationDefaultSourceLanguage = settings.translationDefaultTargetLanguage
                    settings.translationDefaultTargetLanguage = oldSource
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(settings.translationDefaultSourceLanguage == .automatic ? .tertiary : .secondary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(settings.translationDefaultSourceLanguage == .automatic ? Color.primary.opacity(0.04) : Color.accentColor.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .disabled(settings.translationDefaultSourceLanguage == .automatic)
                .help("交换默认语言")
                .padding(.top, 18)
                .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 6) {
                    Text("目标语言")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $settings.translationDefaultTargetLanguage) {
                        ForEach(TranslationLanguage.targetOptions) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var engineCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("翻译引擎")
                    .font(.system(size: 17, weight: .semibold))
                Text("勾选的引擎会出现在翻译面板中。自定义引擎可添加多个，并可选择 OpenAI、Ollama 或 HTTP 格式。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("系统引擎")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 170), spacing: 10)], spacing: 10) {
                    ForEach(TranslationEngine.allCases) { engine in
                        engineTile(engine)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("我的引擎")
                    Spacer()
                    Button {
                        addHunyuanPreset()
                    } label: {
                        Label("混元预设", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        startAddingCustomEngine()
                    } label: {
                        Label("添加引擎", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if settings.customTranslationEngines.isEmpty {
                    emptyCustomEngineView
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 170), spacing: 10)], spacing: 10) {
                        ForEach(settings.customTranslationEngines) { engine in
                            customEngineTile(engine)
                        }
                    }
                }
            }

            Divider()

            engineConfiguration
        }
    }

    @ViewBuilder
    private var engineConfiguration: some View {
        if let customID = configurationCustomEngineID,
           let engineBinding = customEngineBinding(id: customID) {
            customEngineConfiguration(engine: engineBinding)
        } else {
            switch configurationEngine {
            case .appleSystem:
                localEngineConfiguration
            case .openAI:
                openAIConfiguration
            case .deepL:
                placeholderConfiguration(
                    title: "DeepL 配置",
                    icon: "shippingbox",
                    message: "DeepL 接口将在后续接入，配置项会放在这里。",
                    fields: ["API Key", "区域"]
                )
            case .google:
                placeholderConfiguration(
                    title: "Google 配置",
                    icon: "g.circle.fill",
                    message: "Google 翻译接口将在后续接入，配置项会放在这里。",
                    fields: ["API Key", "项目 ID"]
                )
            }
        }
    }

    private var localEngineConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            configHeader(title: "Apple 系统翻译", icon: "apple.logo", message: "使用系统 Translation 引擎，macOS 15 或更高版本可用。")

            HStack(spacing: 10) {
                Label("无需 API Key", systemImage: "checkmark.shield")
                Label("优先本地能力", systemImage: "lock")
                Label("支持语言由系统决定", systemImage: "globe")
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var openAIConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            configHeader(title: "内置 OpenAI 配置", icon: "sparkles", message: "保留原有配置；建议新接口使用“我的引擎”添加 OpenAI 兼容配置。")

            VStack(spacing: 8) {
                formRow("API Key") {
                    SecureField("sk-...", text: $settings.translationOpenAIAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Base URL") {
                    TextField("https://api.openai.com/v1", text: $settings.translationOpenAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("模型") {
                    TextField("gpt-4o-mini", text: $settings.translationOpenAIModel)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("质量 / 速度") {
                    HStack(spacing: 8) {
                        Text("更快")
                        Slider(value: $settings.translationQualityPreference, in: 0...1)
                        Text("更准")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                } label: {
                    Label("测试连接", systemImage: "checkmark.circle")
                }
                .disabled(true)

                Text("如果要接 DeepSeek、LM Studio、Ollama 或本地混元，建议添加为自定义引擎。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func customEngineConfiguration(engine: Binding<CustomTranslationEngine>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: engine.wrappedValue.icon)
                    .foregroundStyle(.blue)
                    .frame(width: 18)
                Text(engine.wrappedValue.name)
                    .font(.system(size: 15, weight: .semibold))
                Text(engine.wrappedValue.format.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12), in: Capsule())
                Spacer()
                Button("编辑") {
                    startEditingCustomEngine(engine.wrappedValue)
                }
                .controlSize(.small)
                Button("删除", role: .destructive) {
                    settings.removeCustomTranslationEngine(id: engine.wrappedValue.id)
                    configurationCustomEngineID = nil
                    configurationEngine = .appleSystem
                }
                .controlSize(.small)
            }

            Toggle("启用这个引擎", isOn: engine.enabled)
                .toggleStyle(.switch)

            Picker("接口格式", selection: engine.format) {
                ForEach(TranslationAPIFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: engine.wrappedValue.format) { newFormat in
                if engine.wrappedValue.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.wrappedValue.baseURL.hasPrefix("http://127.0.0.1") {
                    engine.wrappedValue.baseURL = newFormat.defaultBaseURL
                }
                if engine.wrappedValue.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    engine.wrappedValue.model = newFormat.defaultModel
                }
            }

            Text(engine.wrappedValue.format.helpText)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                formRow(engine.wrappedValue.format == .customHTTP ? "Endpoint" : "Base URL") {
                    TextField(engine.wrappedValue.format.defaultBaseURL, text: engine.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                if engine.wrappedValue.format != .ollama {
                    formRow("API Key") {
                        SecureField("可选", text: engine.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if engine.wrappedValue.format != .customHTTP {
                    formRow("模型") {
                        TextField(engine.wrappedValue.format.defaultModel, text: engine.model)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if engine.wrappedValue.format == .customHTTP {
                    formRow("响应字段") {
                        TextField("data.translation", text: engine.responsePath)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("请求模板")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        TextEditor(text: engine.requestTemplate)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 88)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                    }
                }
            }

            localEngineTips(format: engine.wrappedValue.format)

            HStack {
                Button {
                } label: {
                    Label("测试连接", systemImage: "checkmark.circle")
                }
                .disabled(true)

                Text("测试连接和真实请求逻辑可以在 Provider 层接入。当前先完成多配置存储和 UI。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func placeholderConfiguration(title: String, icon: String, message: String, fields: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configHeader(title: title, icon: icon, message: message)

            VStack(spacing: 8) {
                ForEach(fields, id: \.self) { field in
                    formRow(field) {
                        TextField("待配置", text: .constant(""))
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func configHeader(title: String, icon: String, message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Label(message, systemImage: "info.circle")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var behaviorCard: some View {
        settingsCard {
            Text("面板行为")
                .font(.system(size: 17, weight: .semibold))

            behaviorToggle(
                title: "读取剪贴板文本",
                subtitle: "打开面板后自动把剪贴板内容填入输入框",
                isOn: $settings.translationReadsClipboardText
            )
            behaviorToggle(
                title: "打开后自动聚焦",
                subtitle: "打开翻译面板后直接进入输入状态",
                isOn: $settings.translationAutoFocusesInput
            )
            behaviorToggle(
                title: "翻译完成自动复制",
                subtitle: "第一个成功结果会自动复制到剪贴板",
                isOn: $settings.translationAutoCopiesResult
            )
        }
    }

    private func engineTile(_ engine: TranslationEngine) -> some View {
        let isConfiguring = configurationCustomEngineID == nil && configurationEngine == engine
        let isEnabled = settings.translationEngines.contains(engine)
        let accent = engine == .appleSystem ? Color.blue : (engine == .openAI ? Color.green : Color.orange)

        return Button {
            configurationCustomEngineID = nil
            configurationEngine = engine
        } label: {
            VStack(spacing: 8) {
                Image(systemName: engine.systemImage)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(isConfiguring ? .blue : .secondary)
                    .frame(height: 26)

                Text(engine.title.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(height: 32)

                Text(engine.statusTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.12), in: Capsule())

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { settings.setTranslationEngine(engine, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 124)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.60), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isConfiguring ? Color.blue.opacity(0.70) : Color.primary.opacity(0.08), lineWidth: isConfiguring ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func customEngineTile(_ engine: CustomTranslationEngine) -> some View {
        let isConfiguring = configurationCustomEngineID == engine.id
        let accent = engine.enabled ? Color.blue : Color.secondary

        return Button {
            configurationCustomEngineID = engine.id
        } label: {
            VStack(spacing: 8) {
                Image(systemName: engine.icon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(isConfiguring ? .blue : .secondary)
                    .frame(height: 26)

                Text(engine.name)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(height: 32)

                Text(engine.format.shortTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.12), in: Capsule())

                Toggle("", isOn: Binding(
                    get: { engine.enabled },
                    set: { settings.setCustomTranslationEngine(id: engine.id, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 124)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.60), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isConfiguring ? Color.blue.opacity(0.70) : Color.primary.opacity(0.08), lineWidth: isConfiguring ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contextMenu {
                Button("编辑") { startEditingCustomEngine(engine) }
                Button("复制") { duplicateCustomEngine(engine) }
                Divider()
                Button("删除", role: .destructive) {
                    settings.removeCustomTranslationEngine(id: engine.id)
                    if configurationCustomEngineID == engine.id {
                        configurationCustomEngineID = nil
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyCustomEngineView: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("还没有自定义引擎")
                    .font(.system(size: 13, weight: .semibold))
                Text("可以添加本地混元、Ollama、LM Studio、公司内部接口等。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func localEngineTips(format: TranslationAPIFormat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("使用提示")
                .font(.system(size: 12.5, weight: .semibold))
            switch format {
            case .openAICompatible:
                Text("适合 LM Studio、llama.cpp server、OneAPI、LiteLLM 等。Ollama 也可填写 http://127.0.0.1:11434/v1 走兼容模式。")
            case .ollama:
                Text("需要用户先启动 Ollama，并确保模型名称和本地模型一致。腾讯混元 HY-MT 可使用 Hugging Face GGUF 模型。")
            case .customHTTP:
                Text("请求模板可使用 {{text}}、{{source_lang}}、{{target_lang}} 占位符。响应字段例如 data.translation。")
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(.secondary)
        .padding(10)
        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func behaviorToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
    }

    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
                .fixedSize()
            content()
        }
    }

    private func settingsIcon(_ systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.blue.opacity(0.12))
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.blue)
        }
        .frame(width: 42, height: 42)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(18)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.74), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func customEngineBinding(id: UUID) -> Binding<CustomTranslationEngine>? {
        guard let index = settings.customTranslationEngines.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { settings.customTranslationEngines[index] },
            set: { settings.updateCustomTranslationEngine($0) }
        )
    }

    private func startAddingCustomEngine() {
        editingCustomEngineID = nil
        customEngineDraft = CustomTranslationEngine()
        showingCustomEngineEditor = true
    }

    private func startEditingCustomEngine(_ engine: CustomTranslationEngine) {
        editingCustomEngineID = engine.id
        customEngineDraft = engine
        showingCustomEngineEditor = true
    }

    private func duplicateCustomEngine(_ engine: CustomTranslationEngine) {
        var duplicated = engine
        duplicated.id = UUID()
        duplicated.name = "\(engine.name) 副本"
        settings.addCustomTranslationEngine(duplicated)
        configurationCustomEngineID = duplicated.id
    }

    private func addHunyuanPreset() {
        let engine = CustomTranslationEngine.hunyuanOllamaPreset
        settings.addCustomTranslationEngine(engine)
        configurationCustomEngineID = engine.id
    }

    private func saveCustomEngineDraft() {
        if editingCustomEngineID != nil {
            settings.updateCustomTranslationEngine(customEngineDraft)
            configurationCustomEngineID = customEngineDraft.id
        } else {
            settings.addCustomTranslationEngine(customEngineDraft)
            configurationCustomEngineID = customEngineDraft.id
        }
        showingCustomEngineEditor = false
    }
}

private struct CustomTranslationEngineEditorSheet: View {
    @Binding var engine: CustomTranslationEngine
    let isEditing: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    private let iconOptions = [
        "sparkles", "cpu", "cloud", "server.rack", "globe", "character.bubble", "bolt.horizontal", "terminal", "network", "wand.and.stars"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEditing ? "编辑翻译引擎" : "添加翻译引擎")
                        .font(.system(size: 20, weight: .bold))
                    Text("配置用户自己启动的本地或远程 API。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                formRow("名称") {
                    TextField("本地混元", text: $engine.name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("图标")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 44), spacing: 8)], spacing: 8) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                engine.icon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 17, weight: .medium))
                                    .frame(width: 36, height: 32)
                                    .background(engine.icon == icon ? Color.blue.opacity(0.16) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(engine.icon == icon ? Color.blue.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                formRow("接口格式") {
                    Picker("", selection: $engine.format) {
                        ForEach(TranslationAPIFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: engine.format) { newFormat in
                        if engine.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.baseURL.hasPrefix("http://127.0.0.1") {
                            engine.baseURL = newFormat.defaultBaseURL
                        }
                        if engine.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            engine.model = newFormat.defaultModel
                        }
                    }
                }

                Text(engine.format.helpText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)

                formRow(engine.format == .customHTTP ? "Endpoint" : "Base URL") {
                    TextField(engine.format.defaultBaseURL, text: $engine.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                if engine.format != .ollama {
                    formRow("API Key") {
                        SecureField("可选", text: $engine.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if engine.format != .customHTTP {
                    formRow("模型") {
                        TextField(engine.format.defaultModel, text: $engine.model)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    formRow("响应字段") {
                        TextField("data.translation", text: $engine.responsePath)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("请求模板")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $engine.requestTemplate)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 92)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                    }
                }
            }

            HStack {
                Link("腾讯混元 HY-MT 官方", destination: URL(string: "https://github.com/Tencent-Hunyuan/HY-MT")!)
                Link("Ollama", destination: URL(string: "https://ollama.com")!)
                Spacer()
                Button("取消", action: onCancel)
                Button(isEditing ? "保存" : "添加", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            content()
        }
    }
}

private struct TranslationShortcutRecorderButton: View {
    let shortcut: KeyboardShortcut?
    let isRecording: Bool
    let conflictReason: String?
    let startRecording: () -> Void
    let record: (KeyboardShortcut) -> Void
    let cancel: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording ? cancel() : startRecording()
            } label: {
                Text(title)
                    .font(.system(size: 13, weight: .semibold).monospaced())
                    .foregroundStyle(conflictReason == nil ? Color.primary : Color.orange)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .background(
                TranslationShortcutCaptureView(
                    isRecording: isRecording,
                    record: record,
                    cancel: cancel
                )
            )
            .help(helpText)

            if shortcut != nil {
                Button {
                    clear()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清除快捷键")
                .disabled(isRecording)
            }
        }
    }

    private var title: String {
        if isRecording { return "取消" }
        if let shortcut { return shortcut.displayText }
        return "录制"
    }

    private var helpText: String {
        if isRecording { return "再次点击或按 Esc 取消录制" }
        if let conflictReason { return conflictReason }
        return "点击录制快捷键"
    }
}

private struct TranslationShortcutCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let record: (KeyboardShortcut) -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> TranslationCaptureNSView {
        let view = TranslationCaptureNSView()
        view.record = record
        view.cancel = cancel
        return view
    }

    func updateNSView(_ nsView: TranslationCaptureNSView, context: Context) {
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

private final class TranslationCaptureNSView: NSView {
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
