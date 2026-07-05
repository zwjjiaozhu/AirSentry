import SwiftUI

struct ImageProcessingView: View {
    @ObservedObject var store: ImageProcessingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            summarySection

            HStack(alignment: .top, spacing: 16) {
                queueSection
                    .frame(width: 260)
                imagePreviewSection
                    .frame(maxWidth: .infinity)
                controlsSection
                    .frame(width: 300)
            }

            if let statusMessage = store.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.green)
            }

            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("图片处理")
                    .font(.system(size: 24, weight: .bold))
                Text("批量压缩图片、按目标大小导出，也可以统一裁剪和缩放。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if store.hasImages {
                    Button {
                        store.clearImages()
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    store.chooseImages()
                } label: {
                    Label(store.hasImages ? "重新选择" : "选择图片", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var summarySection: some View {
        HStack(spacing: 18) {
            batchMetric("队列", value: "\(store.items.count) 张", systemImage: "photo.stack")
            batchMetric("原始大小", value: byteText(store.totalOriginalBytes), systemImage: "externaldrive")
            batchMetric("预计导出", value: store.totalOutputBytes > 0 ? byteText(store.totalOutputBytes) : "-", systemImage: "square.and.arrow.down")
            batchMetric("可导出", value: "\(store.exportableCount) 张", systemImage: "checkmark.circle")

            Spacer()

            if let totalCompressionRatioText = store.totalCompressionRatioText {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(totalCompressionRatioText)
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(.green)
                    Text("预计减少")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .imageProcessingCard()
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("图片队列")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if store.failedCount > 0 {
                    Text("\(store.failedCount) 失败")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            if store.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("还没有图片")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.items) { item in
                            queueRow(item)
                        }
                    }
                }
                .frame(minHeight: 300, maxHeight: 470)
            }
        }
        .padding(14)
        .imageProcessingCard()
    }

    private func queueRow(_ item: ImageProcessingItem) -> some View {
        Button {
            store.selectedItemID = item.id
        } label: {
            HStack(spacing: 9) {
                thumbnail(for: item)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(queueRowSubtitle(for: item))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(item.errorMessage == nil ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    store.remove(item)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("移出队列")
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(store.selectedItem?.id == item.id ? Color.blue.opacity(0.10) : Color.primary.opacity(0.035))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var imagePreviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(store.selectedItem?.displayName ?? "预览")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let outputBytes = store.selectedItem?.outputBytes {
                    Text(ByteFormatter.string(from: UInt64(outputBytes)))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.blue)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.045))

                if let previewImage = store.selectedItem?.previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(store.hasImages ? "当前图片无法预览" : "选择多张图片开始处理")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 330)

            if let item = store.selectedItem {
                HStack(spacing: 18) {
                    imageMetric("原图", size: item.originalPixelSize, bytes: item.originalBytes)
                    imageMetric("导出", size: item.previewPixelSize, bytes: item.outputBytes)

                    Spacer()

                    if let compressionRatioText = item.compressionRatioText {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(compressionRatioText)
                                .font(.system(size: 18, weight: .bold).monospacedDigit())
                                .foregroundStyle(.green)
                            Text("单张预计减少")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .imageProcessingCard()
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            controlGroup(title: "格式") {
                Picker("", selection: $store.outputFormat) {
                    ForEach(ImageProcessingOutputFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            controlGroup(title: "压缩") {
                Picker("", selection: $store.compressionMode) {
                    ForEach(ImageProcessingCompressionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!store.outputFormat.supportsQuality)

                if store.compressionMode == .targetSize, store.outputFormat.supportsQuality {
                    valueSlider(
                        title: "目标大小",
                        value: $store.targetSizeKB,
                        range: 50...5000,
                        step: 50,
                        suffix: "KB"
                    )
                } else {
                    valueSlider(
                        title: "质量",
                        value: $store.qualityPercent,
                        range: 5...100,
                        step: 1,
                        suffix: "%"
                    )
                    .disabled(!store.outputFormat.supportsQuality)
                }
            }

            controlGroup(title: "尺寸") {
                Toggle("限制最长边", isOn: $store.shouldResize)
                    .toggleStyle(.checkbox)

                valueSlider(
                    title: "最长边",
                    value: $store.longestSidePixels,
                    range: 320...6000,
                    step: 20,
                    suffix: "px"
                )
                .disabled(!store.shouldResize)
            }

            controlGroup(title: "裁剪") {
                Picker("", selection: $store.cropMode) {
                    ForEach(ImageProcessingCropMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    store.reset()
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(!store.hasImages)

                Spacer()

                Button {
                    store.exportImages()
                } label: {
                    Label("批量导出", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.hasImages || store.exportableCount == 0)
            }
        }
        .padding(18)
        .imageProcessingCard()
    }

    private func controlGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
            content()
        }
    }

    private func valueSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(suffix)")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func batchMetric(_ title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
            }
        }
    }

    private func imageMetric(_ title: String, size: CGSize?, bytes: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(pixelText(size))
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            Text(byteText(bytes))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func thumbnail(for item: ImageProcessingItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            Image(nsImage: item.previewImage ?? item.sourceImage)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(width: 34, height: 34)
    }

    private func queueRowSubtitle(for item: ImageProcessingItem) -> String {
        if let errorMessage = item.errorMessage {
            return errorMessage
        }

        let original = byteText(item.originalBytes)
        let output = byteText(item.outputBytes)
        return "\(original) -> \(output)"
    }

    private func pixelText(_ size: CGSize?) -> String {
        guard let size else { return "-" }
        return "\(Int(size.width)) x \(Int(size.height))"
    }

    private func byteText(_ bytes: Int?) -> String {
        guard let bytes else { return "-" }
        return byteText(bytes)
    }

    private func byteText(_ bytes: Int) -> String {
        guard bytes > 0 else { return "-" }
        return ByteFormatter.string(from: UInt64(bytes))
    }
}

private extension View {
    func imageProcessingCard() -> some View {
        modifier(ImageProcessingCardModifier())
    }
}

private struct ImageProcessingCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(surfaceColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.035), radius: 12, y: 4)
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.74)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.primary.opacity(0.08)
    }
}
