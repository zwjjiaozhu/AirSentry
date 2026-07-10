import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class OCRStore: ObservableObject {
    @Published var image: NSImage?
    @Published var recognizedText = ""
    @Published var statusMessage = "拖入图片文件、粘贴剪贴板图片，或从截图进入识别。"
    @Published var isRecognizing = false
    @Published var sourceName: String?
    @Published var qrCodeItems: [OCRQRCodeItem] = []

    func setImage(_ image: NSImage, sourceName: String? = nil, recognizeImmediately: Bool = true) {
        self.image = image
        self.sourceName = sourceName
        recognizedText = ""
        qrCodeItems = []
        statusMessage = "图片已载入"

        if recognizeImmediately {
            recognize()
        }
    }

    func loadFile(at url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            NSSound.beep()
            statusMessage = "无法读取该文件"
            return
        }

        setImage(image, sourceName: url.lastPathComponent)
    }

    func pasteFromClipboard() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            NSSound.beep()
            statusMessage = "剪贴板里没有可识别的图片"
            return
        }

        setImage(image, sourceName: "剪贴板")
    }

    func copyResult() {
        guard !recognizedText.isEmpty else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(recognizedText, forType: .string)
        statusMessage = "识别结果已复制"
    }

    func recognize() {
        guard let image else {
            NSSound.beep()
            statusMessage = "请先提供一张图片"
            return
        }

        isRecognizing = true
        statusMessage = "正在识别..."

        Task {
            do {
                let result = try await OCRService.recognizeContent(in: image)
                recognizedText = result.displayText
                qrCodeItems = result.qrCodeItems
                let qrSummary = result.qrCodeItems.isEmpty ? "" : "，\(result.qrCodeItems.count) 个二维码"
                statusMessage = "识别完成，\(result.textItems.count) 段文字\(qrSummary)"
            } catch {
                recognizedText = ""
                qrCodeItems = []
                statusMessage = error.localizedDescription
                NSSound.beep()
            }
            isRecognizing = false
        }
    }
}

struct OCRPanelView: View {
    @ObservedObject var store: OCRStore
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            HStack(spacing: 0) {
                imagePane
                    .frame(minWidth: 300)

                Divider()

                resultPane
                    .frame(minWidth: 300)
            }
        }
        .frame(minWidth: 640, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL, .image, .png, .tiff], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var toolbar: some View {
        HStack(spacing: 9) {
            Button {
                openImagePanel()
            } label: {
                Label("打开", systemImage: "folder")
            }

            Button {
                store.pasteFromClipboard()
            } label: {
                Label("粘贴", systemImage: "doc.on.clipboard")
            }

            Button {
                NotificationCenter.default.post(name: .ocrCaptureRequested, object: nil)
            } label: {
                Label("截图", systemImage: "camera.viewfinder")
            }

            Spacer()

            if store.isRecognizing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                store.recognize()
            } label: {
                Label("识别", systemImage: "text.viewfinder")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.image == nil || store.isRecognizing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var imagePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(store.sourceName ?? "图片", systemImage: "photo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isDropTargeted ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1)
                    )

                if let image = store.image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(14)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(.blue)
                        Text("拖入图片或粘贴截图")
                            .font(.system(size: 17, weight: .semibold))
                        Text(store.statusMessage)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                }
            }
        }
        .padding(16)
    }

    private var resultPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("识别结果", systemImage: "doc.text")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.copyResult()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("复制识别结果")
                .disabled(store.recognizedText.isEmpty)
            }

            TextEditor(text: $store.recognizedText)
                .font(.system(size: 13.5))
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )

            if !store.qrCodeItems.isEmpty {
                HStack(spacing: 8) {
                    ForEach(store.qrCodeItems.prefix(2)) { item in
                        if let url = item.url {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label("打开链接", systemImage: "safari")
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            Text(store.statusMessage)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
    }

    private func openImagePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK,
           let url = panel.url {
            store.loadFile(at: url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = item as? URL
                    }

                    if let url {
                        Task { @MainActor in
                            store.loadFile(at: url)
                        }
                    }
                }
                return true
            }

            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let image = image as? NSImage else { return }
                    Task { @MainActor in
                        store.setImage(image, sourceName: "拖入图片")
                    }
                }
                return true
            }
        }

        return false
    }
}
