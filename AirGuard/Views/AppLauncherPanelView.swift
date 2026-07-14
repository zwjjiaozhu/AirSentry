import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppLauncherPanelView: View {
    @ObservedObject var store: AppLauncherStore
    let close: () -> Void
    @FocusState private var searchFocused: Bool
    @State private var isEditing = false
    @State private var newGroupName = ""
    @State private var highlightedGroupID: UUID?
    @State private var draggedGroupID: UUID?
    @State private var draggedAppID: String?
    @State private var draftGroupNames: [UUID: String] = [:]
    @State private var scrollTargetSectionID: String?
    @State private var scrollRequestID = UUID()

    private let columns = [
        GridItem(.adaptive(minimum: 82, maximum: 98), spacing: 12)
    ]
    private let groupColorPalette = [
        "#0A84FF", "#32D74B", "#BF5AF2", "#FF9F0A",
        "#FF453A", "#64D2FF", "#FFD60A", "#8E8E93"
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }

            closeButton
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(.regularMaterial)
        .onAppear {
            searchFocused = true
            if store.applications.isEmpty {
                store.refreshApplications()
            }
            for group in store.groups {
                draftGroupNames[group.id] = group.name
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("程序")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button {
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(isEditing ? .blue : .secondary)
                .help(isEditing ? "完成" : "整理")
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 8)

            groupButton(title: "全部", count: store.applications.count, groupID: nil) {
                store.selectedGroupID = nil
                requestScroll(to: nil)
            }

            ForEach(store.groups) { group in
                groupRow(for: group)
            }

            Spacer()

            if isEditing {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        TextField("新分组", text: $newGroupName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addGroup)

                        Button {
                            addGroup()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let group = store.selectedGroup {
                        Button {
                            store.removeGroup(id: group.id)
                        } label: {
                            Label("删除当前分组", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                        .disabled(store.groups.count <= 1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "keyboard")
                    Text("Return 打开")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .frame(width: 172)
        .clipped()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索应用", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($searchFocused)
                    .onSubmit(launchFirstResult)
                    .frame(maxWidth: .infinity)

                if store.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }

                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清除搜索")
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 20)
            .padding(.horizontal, 20)

            if store.isScanning && store.applications.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在扫描应用")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedApplications.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("没有找到应用")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !store.searchText.isEmpty {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(searchResults) { app in
                            appTile(app, groupID: nil)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            Color.clear
                                .frame(height: 0)
                                .id(sectionID(for: nil))

                            ForEach(store.groups) { group in
                                let apps = filteredApplications(store.apps(in: group))
                                if !apps.isEmpty || store.searchText.isEmpty {
                                    appSection(
                                        title: group.name,
                                        count: apps.count,
                                        apps: apps,
                                        sectionID: sectionID(for: group.id),
                                        groupID: group.id,
                                        color: color(from: group.colorHex)
                                    )
                                }
                            }

                            let ungroupedApps = filteredApplications(store.ungroupedApplications)
                            if !ungroupedApps.isEmpty {
                                appSection(
                                    title: "未分组",
                                    count: ungroupedApps.count,
                                    apps: ungroupedApps,
                                    sectionID: "ungrouped-apps",
                                    groupID: nil,
                                    color: .secondary
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 22)
                    }
                    .onAppear {
                        scrollToSelectedSection(with: proxy, animated: false)
                    }
                    .onChange(of: scrollRequestID) { _ in
                        scrollToSelectedSection(with: proxy, animated: true)
                    }
                    .onChange(of: store.isScanning) { _ in
                        scrollToSelectedSection(with: proxy, animated: false)
                    }
                }
            }
        }
    }

    private var sectionedApplications: [AppLauncherItem] {
        store.groups.flatMap { filteredApplications(store.apps(in: $0)) } + filteredApplications(store.ungroupedApplications)
    }

    private var searchResults: [AppLauncherItem] {
        filteredApplications(store.applications)
    }

    private var displayedApplications: [AppLauncherItem] {
        store.searchText.isEmpty ? sectionedApplications : searchResults
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .padding(.top, 8)
        .padding(.trailing, 10)
        .offset(y: -32)
        .help("关闭")
    }

    @ViewBuilder
    private func groupRow(for group: AppLauncherGroup) -> some View {
        if isEditing {
            editableGroupRow(for: group)
        } else {
            groupButton(title: group.name, count: store.apps(in: group).count, groupID: group.id) {
                store.selectedGroupID = group.id
                requestScroll(to: group.id)
            }
        }
    }

    private func editableGroupRow(for group: AppLauncherGroup) -> some View {
        let isSelected = store.selectedGroupID == group.id
        let isHighlighted = highlightedGroupID == group.id
        let groupColor = color(from: group.colorHex)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                Image(systemName: "folder")
                    .foregroundStyle(groupColor)
                    .frame(width: 16)

                TextField("分组名称", text: groupNameBinding(for: group))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(store.apps(in: group).count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)

            if isSelected {
                colorSwatches(for: group)
                    .padding(.top, -1)
                    .padding(.bottom, 5)
            }
        }
        .foregroundStyle(isSelected ? groupColor : .primary)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(groupBackground(isSelected: isSelected, isHighlighted: isHighlighted, color: groupColor))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
        .onTapGesture {
            store.selectedGroupID = group.id
            requestScroll(to: group.id)
        }
        .onDrag {
            draggedGroupID = group.id
            return NSItemProvider(object: dragPayload(kind: .group, value: group.id.uuidString) as NSString)
        }
        .onDrop(
            of: [.plainText],
            delegate: AppLauncherGroupDropDelegate(
                store: store,
                targetGroupID: group.id,
                isEditing: isEditing,
                draggedGroupID: $draggedGroupID,
                highlightedGroupID: $highlightedGroupID
            )
        )
    }

    private func groupButton(title: String, count: Int, groupID: UUID?, action: @escaping () -> Void) -> some View {
        let isSelected = store.selectedGroupID == groupID
        let isHighlighted = highlightedGroupID == groupID
        let groupColor = groupColor(for: groupID)

        return Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: groupID == nil ? "square.grid.2x2" : "folder")
                    .foregroundStyle(groupColor)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(isSelected ? groupColor : .primary)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(groupBackground(isSelected: isSelected, isHighlighted: isHighlighted, color: groupColor))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .onDrop(of: [.plainText], isTargeted: dropTargetBinding(for: groupID)) { providers in
            guard let groupID else { return false }
            handleAppDrop(providers, to: groupID)
            return true
        }
    }

    private func appSection(title: String, count: Int, apps: [AppLauncherItem], sectionID: String, groupID: UUID?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: groupID == nil ? "square.grid.2x2" : "folder")
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Text("\(count)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if apps.isEmpty {
                Text("没有应用")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(apps) { app in
                        appTile(app, groupID: groupID)
                    }
                }
            }
        }
        .id(sectionID)
        .onDrop(of: [.plainText], isTargeted: dropTargetBinding(for: groupID)) { providers in
            guard let groupID else { return false }
            handleAppDrop(providers, to: groupID)
            return true
        }
    }

    private func appTile(_ app: AppLauncherItem, groupID: UUID?) -> some View {
        VStack(spacing: 5) {
            Button {
                if !isEditing {
                    store.launch(app)
                    close()
                }
            } label: {
                VStack(spacing: 7) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 48, height: 48)
                    Text(app.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(height: 34, alignment: .top)
                }
                .frame(width: 88, height: 96)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(app.path)
            .onDrag {
                draggedAppID = app.id
                return NSItemProvider(object: dragPayload(kind: .app, value: app.id) as NSString)
            }
            .onDrop(
                of: [.plainText],
                delegate: AppLauncherAppDropDelegate(
                    store: store,
                    targetAppID: app.id,
                    targetGroupID: groupID,
                    isEditing: isEditing,
                    draggedAppID: $draggedAppID
                )
            )

            if isEditing,
               let groupID,
               let group = store.groups.first(where: { $0.id == groupID }),
               group.appIDs.contains(app.id) {
                Button {
                    store.remove(app, from: group.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("从当前分组移出")
            }
        }
        .padding(.vertical, isEditing ? 4 : 0)
        .background(
            Group {
                if isEditing {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
            }
        )
    }

    private func colorSwatches(for group: AppLauncherGroup) -> some View {
        HStack(spacing: 5) {
            ForEach(groupColorPalette, id: \.self) { colorHex in
                let swatchColor = color(from: colorHex)
                Button {
                    store.updateGroupColor(id: group.id, colorHex: colorHex)
                } label: {
                    ZStack {
                        Circle()
                            .fill(swatchColor)
                            .frame(width: 10, height: 10)

                        if group.colorHex == colorHex {
                            Circle()
                                .stroke(.primary.opacity(0.65), lineWidth: 2)
                                .frame(width: 14, height: 14)
                        }
                    }
                    .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help(colorHex)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filteredApplications(_ apps: [AppLauncherItem]) -> [AppLauncherItem] {
        apps.filter { app in
            store.searchText.isEmpty || app.searchableText.localizedCaseInsensitiveContains(store.searchText)
        }
    }

    private func sectionID(for groupID: UUID?) -> String {
        groupID?.uuidString ?? "all-apps"
    }

    private func requestScroll(to groupID: UUID?) {
        scrollTargetSectionID = sectionID(for: groupID)
        scrollRequestID = UUID()
    }

    private func scrollToSelectedSection(with proxy: ScrollViewProxy, animated: Bool) {
        let target = scrollTargetSectionID ?? sectionID(for: store.selectedGroupID)
        let action = {
            proxy.scrollTo(target, anchor: .top)
        }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.18), action)
            } else {
                action()
            }
        }
    }

    private func groupBackground(isSelected: Bool, isHighlighted: Bool, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHighlighted ? color.opacity(0.22) : (isSelected ? color.opacity(0.13) : Color.clear))
    }

    private func groupColor(for groupID: UUID?) -> Color {
        guard let groupID,
              let group = store.groups.first(where: { $0.id == groupID }) else {
            return .blue
        }
        return color(from: group.colorHex)
    }

    private func color(from hex: String) -> Color {
        let fallback = Color.blue
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard normalized.count == 6,
              let value = UInt64(normalized, radix: 16) else {
            return fallback
        }

        return Color(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }

    private func dropTargetBinding(for groupID: UUID?) -> Binding<Bool> {
        Binding(
            get: { highlightedGroupID == groupID },
            set: { isTargeted in
                guard let groupID else { return }
                highlightedGroupID = isTargeted ? groupID : nil
            }
        )
    }

    private func handleAppDrop(_ providers: [NSItemProvider], to groupID: UUID) {
        loadDragPayload(from: providers) { payload in
            guard case let .app(appID) = parseDragPayload(payload) else { return }
            Task { @MainActor in
                store.moveApp(id: appID, to: groupID)
                highlightedGroupID = nil
            }
        }
    }

    private func groupNameBinding(for group: AppLauncherGroup) -> Binding<String> {
        Binding(
            get: { draftGroupNames[group.id] ?? store.groups.first { $0.id == group.id }?.name ?? group.name },
            set: { name in
                draftGroupNames[group.id] = name
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    store.renameGroup(id: group.id, name: name)
                }
            }
        )
    }

    private func addGroup() {
        store.addGroup(named: newGroupName)
        if let group = store.selectedGroup {
            draftGroupNames[group.id] = group.name
        }
        newGroupName = ""
    }

    private func launchFirstResult() {
        guard !isEditing, let first = displayedApplications.first else { return }
        store.launch(first)
        close()
    }
}

private enum AppLauncherDragKind: String {
    case app
    case group
}

private enum AppLauncherDragPayload {
    case app(String)
    case group(UUID)
}

private func dragPayload(kind: AppLauncherDragKind, value: String) -> String {
    "airsentry-app-launcher:\(kind.rawValue):\(value)"
}

private func parseDragPayload(_ payload: String) -> AppLauncherDragPayload? {
    let parts = payload.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count == 3,
          parts[0] == "airsentry-app-launcher",
          let kind = AppLauncherDragKind(rawValue: parts[1]) else {
        return nil
    }

    switch kind {
    case .app:
        return .app(parts[2])
    case .group:
        guard let groupID = UUID(uuidString: parts[2]) else { return nil }
        return .group(groupID)
    }
}

private func loadDragPayload(from providers: [NSItemProvider], completion: @escaping (String) -> Void) {
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

private struct AppLauncherGroupDropDelegate: DropDelegate {
    let store: AppLauncherStore
    let targetGroupID: UUID
    let isEditing: Bool
    @Binding var draggedGroupID: UUID?
    @Binding var highlightedGroupID: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        highlightedGroupID = targetGroupID

        guard isEditing,
              let draggedGroupID,
              draggedGroupID != targetGroupID else { return }

        store.moveGroup(id: draggedGroupID, near: targetGroupID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        highlightedGroupID = nil

        if draggedGroupID != nil {
            draggedGroupID = nil
            return true
        }

        loadDragPayload(from: info.itemProviders(for: [.plainText])) { payload in
            guard case let .app(appID) = parseDragPayload(payload) else { return }
            Task { @MainActor in
                store.moveApp(id: appID, to: targetGroupID)
            }
        }

        return true
    }

    func dropExited(info: DropInfo) {
        if highlightedGroupID == targetGroupID {
            highlightedGroupID = nil
        }
    }
}

private struct AppLauncherAppDropDelegate: DropDelegate {
    let store: AppLauncherStore
    let targetAppID: String
    let targetGroupID: UUID?
    let isEditing: Bool
    @Binding var draggedAppID: String?

    func validateDrop(info: DropInfo) -> Bool {
        isEditing && targetGroupID != nil && info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard isEditing,
              let targetGroupID,
              let draggedAppID,
              draggedAppID != targetAppID else { return }

        store.moveApp(id: draggedAppID, near: targetAppID, in: targetGroupID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedAppID = nil
        return true
    }
}
