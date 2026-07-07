import SwiftUI

struct ImageProcessingView: View {
    @ObservedObject var store: ImageProcessingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            summarySection

            HStack(alignment: .top, spacing: 16) {
                queueSection
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
                        store.appendImages()
                    } label: {
                        Label("追加图片", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

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


    private var controlsSection: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                controlGroup(title: "输出格式", icon: "doc.badge.gearshape") {
                    Picker("", selection: $store.outputFormat) {
                        ForEach(ImageProcessingOutputFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                controlDivider

                controlGroup(title: "压缩方式", icon: "doc.zipper") {
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

                controlDivider

                controlGroup(title: "尺寸调整", icon: "aspectratio") {
                    Picker("", selection: $store.resizeMode) {
                        ForEach(ImageProcessingResizeMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if store.resizeMode == .longestSide {
                        valueSlider(
                            title: "最长边",
                            value: $store.longestSidePixels,
                            range: 320...6000,
                            step: 20,
                            suffix: "px"
                        )
                    }

                    if store.resizeMode == .exactSize {
                        HStack(spacing: 8) {
                            exactDimensionField(
                                label: "宽",
                                value: $store.exactWidth,
                                locked: store.lockAspectRatio,
                                linkedValue: $store.exactHeight,
                                sourceImage: store.selectedItem?.sourceImage
                            )
                            Text("×")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                            exactDimensionField(
                                label: "高",
                                value: $store.exactHeight,
                                locked: store.lockAspectRatio,
                                linkedValue: $store.exactWidth,
                                sourceImage: store.selectedItem?.sourceImage,
                                isHeight: true
                            )
                            Text("px")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Toggle("锁定宽高比", isOn: $store.lockAspectRatio)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                    }
                }

                controlDivider

                controlGroup(title: "裁剪比例", icon: "crop") {
                    Picker("", selection: $store.cropMode) {
                        ForEach(ImageProcessingCropMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                }

                controlDivider

                HStack(spacing: 12) {
                    Button {
                        store.reset()
                    } label: {
                        Label("重置", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(!store.hasImages)

                    Button {
                        store.exportImages()
                    } label: {
                        Label("批量导出", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!store.hasImages || store.exportableCount == 0)
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
        .imageProcessingCard()
    }

    private var controlDivider: some View {
        Divider()
            .padding(.vertical, 14)
    }

    private func controlGroup<Content: View>(title: String, icon: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(suffix)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.blue.opacity(0.08))
                    )
            }
            Slider(value: value, in: range, step: step)
                .padding(.top, 2)
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


    private func exactDimensionField(
        label: String,
        value: Binding<Double>,
        locked: Bool,
        linkedValue: Binding<Double>,
        sourceImage: NSImage?,
        isHeight: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .frame(width: 68)
                .onChange(of: value.wrappedValue) { newValue in
                    guard locked, let sourceImage else { return }
                    let pixelSize = sourceImage.pixelSize
                    guard pixelSize.width > 0, pixelSize.height > 0 else { return }
                    let ratio = pixelSize.width / pixelSize.height
                    if isHeight {
                        linkedValue.wrappedValue = floor(newValue * ratio)
                    } else {
                        linkedValue.wrappedValue = floor(newValue / ratio)
                    }
                }
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
