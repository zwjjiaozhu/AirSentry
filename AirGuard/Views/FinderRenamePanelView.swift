import SwiftUI

@MainActor
final class FinderRenamePanelViewModel: ObservableObject {
    @Published var draft: FinderRenameDraft
    @Published var errorMessage: String?
    let configStore: FinderRenameConfigStore

    init(fileURL: URL, configStore: FinderRenameConfigStore) {
        self.draft = FinderVersionRenameService.suggestedDraft(for: fileURL)
        self.configStore = configStore
    }

    var originalFileName: String {
        draft.originalURL.lastPathComponent
    }

    var previewFileName: String {
        FinderVersionRenameService.fileName(for: draft)
    }

    var fields: [FinderRenameField] {
        configStore.enabledFields
    }

    func rename(onSuccess: () -> Void) {
        errorMessage = nil
        switch FinderVersionRenameService.rename(draft: draft) {
        case .renamed:
            onSuccess()
        case .unauthorized(let url):
            errorMessage = "没有此文件夹的重命名权限：\(url.deletingLastPathComponent().path)"
            NSSound.beep()
        case .invalidTarget:
            errorMessage = "只能重命名单个文件。"
            NSSound.beep()
        case .failed(_, let error):
            errorMessage = "重命名失败：\(error.localizedDescription)"
            NSSound.beep()
        }
    }
}

struct FinderRenamePanelView: View {
    @ObservedObject var viewModel: FinderRenamePanelViewModel
    let onClose: () -> Void
    @State private var showsFieldSettings = false
    @State private var draggedFieldID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if showsFieldSettings {
                fieldSettingsSection
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.fields) { field in
                            fieldView(field)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(errorMessage)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.orange.opacity(0.18), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }

            Spacer(minLength: 0)
            footer
        }
        .frame(width: 560, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
                .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("重命名文件")
                    .font(.system(size: 17, weight: .semibold))
                Text(viewModel.originalFileName)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                withAnimation(.snappy(duration: 0.16)) {
                    showsFieldSettings.toggle()
                }
            } label: {
                Image(systemName: showsFieldSettings ? "slider.horizontal.2.gobackward" : "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(showsFieldSettings ? .blue : .secondary)
            .background((showsFieldSettings ? Color.blue.opacity(0.10) : Color.primary.opacity(0.055)), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help(showsFieldSettings ? "返回重命名" : "配置字段顺序")
        }
        .padding(18)
    }

    private var fieldSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("字段显示")
                        .font(.system(size: 14.5, weight: .semibold))
                    Text("拖拽调整面板字段顺序，关闭后不会显示在重命名面板中。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.configStore.fields.enumerated()), id: \.element.id) { index, field in
                    fieldSettingRow(field)
                        .onDrag {
                            draggedFieldID = field.id
                            return NSItemProvider(object: finderRenameFieldDragPayload(field.id) as NSString)
                        }
                        .onDrop(
                            of: [.plainText],
                            delegate: FinderRenamePanelFieldDropDelegate(
                                store: viewModel.configStore,
                                targetFieldID: field.id,
                                draggedFieldID: $draggedFieldID
                            )
                        )

                    if index < viewModel.configStore.fields.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .background(.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(0.075), lineWidth: 1)
            )
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func fieldSettingRow(_ field: FinderRenameField) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Image(systemName: field.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(field.title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(field.id)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { field.isEnabled },
                set: { viewModel.configStore.setField(field.id, isEnabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(
            Group {
                if draggedFieldID == field.id {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.blue.opacity(0.07))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                }
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func fieldView(_ field: FinderRenameField) -> some View {
        switch FinderRenameFieldID(rawValue: field.id) {
        case .status:
            controlCard {
                fieldLabel(field)
                HStack(spacing: 8) {
                    ForEach(FinderRenameDefaults.statuses, id: \.self) { status in
                        statusButton(status)
                    }
                    Spacer(minLength: 0)
                }
            }
        case .version:
            controlCard {
                fieldLabel(field)
                HStack(spacing: 10) {
                    Text("v\(String(format: "%03d", viewModel.draft.version))")
                        .font(.system(size: 19, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(width: 72, alignment: .leading)

                    HStack(spacing: 6) {
                        iconButton("minus") {
                            viewModel.draft.version = max(1, viewModel.draft.version - 1)
                        }
                        .disabled(viewModel.draft.version <= 1)

                        iconButton("plus") {
                            viewModel.draft.version = min(999, viewModel.draft.version + 1)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        case .date:
            controlCard {
                fieldLabel(field)
                HStack(spacing: 10) {
                    Text(compactDateString(viewModel.draft.date))
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(.blue)

                    DatePicker("", selection: $viewModel.draft.date, displayedComponents: [.date])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .frame(width: 122)

                    HStack(spacing: 6) {
                        iconButton("chevron.left") {
                            shiftDate(days: -1)
                        }
                        iconButton("chevron.right") {
                            shiftDate(days: 1)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        case .preview:
            controlCard {
                fieldLabel(field)
                Text(viewModel.previewFileName)
                    .font(.system(size: 14.5, weight: .semibold).monospaced())
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        case .none:
            EmptyView()
        }
    }

    private func controlCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.primary.opacity(0.075), lineWidth: 1)
        )
    }

    private func fieldLabel(_ field: FinderRenameField) -> some View {
        HStack(spacing: 6) {
            Image(systemName: field.systemImage)
                .frame(width: 16)
            Text(field.title)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private func statusButton(_ status: String) -> some View {
        let isSelected = viewModel.draft.status == status
        return Button {
            viewModel.draft.status = status
        } label: {
            Text(status)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(minWidth: 74)
                .frame(height: 32)
                .background(isSelected ? Color.blue : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? Color.blue.opacity(0.0) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func shiftDate(days: Int) {
        viewModel.draft.date = Calendar.current.date(byAdding: .day, value: days, to: viewModel.draft.date) ?? viewModel.draft.date
    }

    private func compactDateString(_ date: Date) -> String {
        Self.compactDateFormatter.string(from: date)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("取消") {
                onClose()
            }
            Button {
                viewModel.rename(onSuccess: onClose)
            } label: {
                Label("重命名", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.primary.opacity(0.025))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

private func finderRenameFieldDragPayload(_ fieldID: String) -> String {
    "airsentry-finder-rename:field:\(fieldID)"
}

private func parseFinderRenameFieldDragPayload(_ payload: String) -> String? {
    let parts = payload.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count == 3,
          parts[0] == "airsentry-finder-rename",
          parts[1] == "field" else {
        return nil
    }

    return parts[2]
}

private func loadFinderRenameFieldDragPayload(from providers: [NSItemProvider], completion: @escaping (String) -> Void) {
    for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
        _ = provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let value = (item as? String) ?? (item as? NSString).map(String.init) else { return }
            Task { @MainActor in
                completion(value)
            }
        }
        return
    }
}

private struct FinderRenamePanelFieldDropDelegate: DropDelegate {
    let store: FinderRenameConfigStore
    let targetFieldID: String
    @Binding var draggedFieldID: String?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard let draggedFieldID,
              draggedFieldID != targetFieldID else { return }

        store.moveField(id: draggedFieldID, near: targetFieldID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if draggedFieldID != nil {
            draggedFieldID = nil
            return true
        }

        loadFinderRenameFieldDragPayload(from: info.itemProviders(for: [.plainText])) { payload in
            guard let fieldID = parseFinderRenameFieldDragPayload(payload) else { return }
            Task { @MainActor in
                store.moveField(id: fieldID, near: targetFieldID)
            }
        }

        return true
    }

    func dropExited(info: DropInfo) {
        if draggedFieldID == targetFieldID {
            draggedFieldID = nil
        }
    }
}
