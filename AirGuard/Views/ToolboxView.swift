import SwiftUI
import AppKit
import ApplicationServices

struct ToolboxView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appLauncherStore: AppLauncherStore
    @EnvironmentObject private var screenshotCaptureController: ScreenshotCaptureController
    @StateObject private var storageStore = StorageAnalyzerStore()
    @StateObject private var uninstallerStore = AppUninstallerStore()
    @StateObject private var superRightClickStore = SuperRightClickStore()
    @StateObject private var finderAuthorizationStore = FinderNewFileAuthorizationStore()
    @StateObject private var imageProcessingStore = ImageProcessingStore()
    @State private var selectedTool: ToolboxSection = .storage
    @State private var inputSources: [InputMethodSource] = []
    @State private var recordingRuleID: UUID?
    @State private var isRecordingAppLauncherShortcut = false
    @State private var isRecordingScreenshotShortcut = false
    @State private var isRecordingTranslationShortcut = false
    @State private var selectedSuperRightClickMenuItemID: String = SuperRightClickStore.defaultSelectedMenuItemID
    @State private var draggedSuperRightClickMenuItemID: String?
    @State private var draggedSuperRightClickTemplateID: String?
    @State private var localSortOption: AppUninstallerStore.SortOption = .name

    var body: some View {
        HStack(spacing: 0) {
            toolboxSidebar
            Divider()
            content
        }
        .frame(minWidth: 820, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AirSentry.SelectSuperRightClickToolboxSection"))) { _ in
            selectedTool = .superRightClick
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectToolboxSection)) { notification in
            guard
                let rawValue = notification.object as? String,
                let quickTool = MenuBarQuickTool(rawValue: rawValue),
                let section = ToolboxSection(quickTool: quickTool)
            else {
                return
            }
            selectedTool = section
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTranslationSettings)) { _ in
            selectedTool = .translation
        }
    }

    private var toolboxSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("工具箱")
                    .font(.system(size: 22, weight: .bold))
                Text("一些顺手的小工具")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 26)

            VStack(spacing: 7) {
              ToolboxSidebarItem(
                title: "程序收纳台",
                systemImage: "square.grid.3x3",
                isSelected: selectedTool == .appLauncher
              ) {
                selectedTool = .appLauncher
              }

              ToolboxSidebarItem(
                title: "截图钉图",
                systemImage: "camera.viewfinder",
                isSelected: selectedTool == .screenshot
              ) {
                selectedTool = .screenshot
              }

              ToolboxSidebarItem(
                title: "文字识别",
                systemImage: "text.viewfinder",
                isSelected: selectedTool == .ocr
              ) {
                selectedTool = .ocr
              }

              ToolboxSidebarItem(
                title: "图片处理",
                systemImage: "photo.on.rectangle.angled",
                isSelected: selectedTool == .imageProcessing
              ) {
                selectedTool = .imageProcessing
              }

              ToolboxSidebarItem(
                title: "超级右键",
                systemImage: "computermouse",
                isSelected: selectedTool == .superRightClick
              ) {
                selectedTool = .superRightClick
              }

              ToolboxSidebarItem(
                title: "AI 存储分析",
                systemImage: "internaldrive",
                isSelected: selectedTool == .storage
              ) {
                selectedTool = .storage
              }

              ToolboxSidebarItem(
                title: "软件卸载助手",
                systemImage: "trash",
                isSelected: selectedTool == .uninstaller
              ) {
                selectedTool = .uninstaller
              }

              ToolboxSidebarItem(
                title: "输入法快捷切换",
                systemImage: "keyboard",
                isSelected: selectedTool == .inputMethod
              ) {
                selectedTool = .inputMethod
              }

              ToolboxSidebarItem(
                title: "翻译助手",
                systemImage: "character.book.closed",
                isSelected: selectedTool == .translation
              ) {
                selectedTool = .translation
              }
            }
            .padding(.horizontal, 12)

            Spacer()

            Label("更多工具正在路上", systemImage: "sparkles")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(20)
        }
        .frame(width: 210)
        .background(
            LinearGradient(
                colors: [
                    sidebarSurfaceColor.opacity(0.84),
                    .blue.opacity(colorScheme == .dark ? 0.06 : 0.035),
                    sidebarSurfaceColor.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            Group {
                switch selectedTool {
                case .storage:
                    storageContent
                case .uninstaller:
                    uninstallerContent
                case .inputMethod:
                    inputMethodContent
                case .appLauncher:
                    appLauncherContent
                case .screenshot:
                    screenshotContent
                case .ocr:
                    ocrContent
                case .imageProcessing:
                    imageProcessingContent
                case .superRightClick:
                    superRightClickContent
                case .translation:
                    translationContent
                }
            }
            .padding(26)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    .blue.opacity(colorScheme == .dark ? 0.055 : 0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var storageContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            storageHeader
            diskOverview

            if storageStore.hasFolderAccess {
                resultSection
            } else {
                permissionCard
            }

            if let errorMessage = storageStore.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.orange)
            }
        }
        .onAppear {
            storageStore.refresh()
        }
    }

    private var inputMethodContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            inputMethodHeader
            inputMethodShortcutSection
        }
        .onAppear {
            refreshInputSources()
        }
    }

    private var appLauncherContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            appLauncherHeader
            appLauncherShortcutSection
            appLauncherAuthorizationSection
            appLauncherPanelEntrySection
        }
        .onAppear {
            appLauncherStore.refreshApplications()
        }
    }

    private var screenshotContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            screenshotHeader
            screenshotPermissionGuideSection
            screenshotShortcutSection
            screenshotActionSection
        }
    }

    private var ocrContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            ocrHeader
            ocrActionSection
        }
    }

    private var imageProcessingContent: some View {
        ImageProcessingView(store: imageProcessingStore)
    }

    private var superRightClickContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            superRightClickHeader
            superRightClickSetupGuideSection
            superRightClickFolderAuthorizationSection
            superRightClickTemplatesSection
        }
    }

    private var translationContent: some View {
        TranslationSettingsView(
            settings: settings,
            isRecordingShortcut: $isRecordingTranslationShortcut,
            conflictReason: translationShortcutConflictReason
        )
    }

    private var uninstallerContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            uninstallerHeader

            if !uninstallerStore.hasHomeAccess {
                uninstallerPermissionCard
            }
            if !uninstallerStore.hasApplicationsAccess {
                uninstallerApplicationsPermissionCard
            }

            HStack(alignment: .top, spacing: 16) {
                appListSection
                    .frame(width: 280)
                uninstallPlanSection
                    .frame(maxWidth: .infinity)
            }

            if let summary = uninstallerStore.lastTrashSummary {
                Label(summary, systemImage: "checkmark.circle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.green)
            }

            if let errorMessage = uninstallerStore.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.orange)
            }

            if !uninstallerStore.trashLogs.isEmpty {
                uninstallerLogSection
            }
        }
        .onAppear {
            uninstallerStore.refreshApplications()
        }
    }

    private var storageHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("AI 存储分析")
                    .font(.system(size: 24, weight: .bold))
                Text("看看 AI 工具、模型与缓存悄悄占了多少空间。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                if let selectedFolderPath = storageStore.selectedFolderPath {
                    Label(selectedFolderPath, systemImage: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(selectedFolderPath)
                        .padding(.top, 1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if storageStore.hasFolderAccess {
                    Button {
                        storageStore.requestFolderAccess()
                    } label: {
                        Label("更换目录", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(storageStore.isScanning)
                }

                Button {
                    if storageStore.hasFolderAccess {
                        storageStore.refresh()
                    } else {
                        storageStore.requestFolderAccess()
                    }
                } label: {
                    Label(scanButtonTitle, systemImage: storageStore.hasFolderAccess ? "arrow.clockwise" : "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(storageStore.isScanning)
            }
        }
    }

    private var inputMethodHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("输入法快捷切换")
                    .font(.system(size: 24, weight: .bold))
                Text("给常用输入法绑定组合键，按下后直接切到指定输入法。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                refreshInputSources()
            } label: {
                Label("刷新输入法", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var uninstallerHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("软件卸载助手")
                    .font(.system(size: 24, weight: .bold))
                Text("预览应用本体和常见残留文件，确认后统一移入废纸篓。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                if let selectedHomePath = uninstallerStore.selectedHomePath {
                    HStack(spacing: 4) {
                        Label(selectedHomePath, systemImage: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(selectedHomePath)
                        Button {
                            uninstallerStore.clearHomeAccess()
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .help("移除授权")
                    }
                }
                if let selectedApplicationsPath = uninstallerStore.selectedApplicationsPath {
                    HStack(spacing: 4) {
                        Label(selectedApplicationsPath, systemImage: "app.badge")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(selectedApplicationsPath)
                        Button {
                            uninstallerStore.clearApplicationsAccess()
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .help("移除授权")
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    uninstallerStore.requestApplicationsAccess()
                } label: {
                    Label(uninstallerStore.hasApplicationsAccess ? "更换应用目录" : "授权应用目录", systemImage: "app.badge")
                }
                .buttonStyle(.bordered)
                .disabled(uninstallerStore.isTrashing)

                Button {
                    uninstallerStore.requestHomeAccess()
                } label: {
                    Label(uninstallerStore.hasHomeAccess ? "更换目录" : "授权目录", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(uninstallerStore.isTrashing)

                Button {
                    uninstallerStore.refreshApplications()
                } label: {
                    Label(uninstallerStore.isScanningApplications ? "扫描中" : "刷新应用", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(uninstallerStore.isScanningApplications || uninstallerStore.isTrashing)
            }
        }
    }

    private var appLauncherHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("程序收纳台")
                    .font(.system(size: 24, weight: .bold))
                Text("把应用按自己的习惯分组，快捷键弹出轻量面板后直接启动。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var superRightClickHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("超级右键")
                    .font(.system(size: 24, weight: .bold))
                Text("配置 Finder 右键菜单里的功能项和子菜单。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                superRightClickStore.resetTemplates()
            } label: {
                Label("恢复默认", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var superRightClickSetupGuideSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("先完成这两步")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Finder 扩展负责显示右键菜单，文件夹授权负责让“新建文件”真正写入目标目录。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                setupGuideStepRow(
                    step: "1",
                    title: "在系统设置里启用 Finder 扩展",
                    message: "进入「系统设置 - 通用 - 登录项与扩展 - Finder 扩展」，勾选「AirSentry Finder Extension」。",
                    buttonTitle: "去设置",
                    systemImage: "gearshape",
                    action: openSuperRightClickExtensionSettings
                )

                setupGuideStepRow(
                    step: "2",
                    title: "授权常用文件夹",
                    message: "给桌面、下载、文稿或需要新建文件的目录授权，否则右键里的“新建文件”不会写入。",
                    buttonTitle: "添加文件夹",
                    systemImage: "folder.badge.plus",
                    action: { finderAuthorizationStore.addFolder() }
                )
            }
        }
        .padding(18)
        .toolboxCard()
    }

    private func setupGuideStepRow(
        step: String,
        title: String,
        message: String,
        buttonTitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(step)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var uninstallerPermissionCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(.orange.opacity(0.13))
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.orange)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 6) {
                Text("允许读取个人文件夹")
                    .font(.system(size: 16, weight: .semibold))
                Text("用于识别 ~/Library 中的缓存、偏好设置和容器残留；未授权时只能显示应用本体。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("选择文件夹") {
                uninstallerStore.requestHomeAccess()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .toolboxCard()
    }

    private var uninstallerApplicationsPermissionCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(.red.opacity(0.10))
                Image(systemName: "app.badge")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.red)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 6) {
                Text("允许管理应用目录")
                    .font(.system(size: 16, weight: .semibold))
                Text("用于把 /Applications 或用户应用目录中的应用本体移入废纸篓；未授权时仍可预览残留文件。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("选择应用目录") {
                uninstallerStore.requestApplicationsAccess()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(20)
        .toolboxCard()
    }

    private var appListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("应用")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if uninstallerStore.isScanningApplications {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextField("搜索应用或 Bundle ID", text: $uninstallerStore.searchText)
                .textFieldStyle(.roundedBorder)

            Picker("", selection: $localSortOption) {
                ForEach(AppUninstallerStore.SortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: localSortOption) { newValue in
                uninstallerStore.sortOption = newValue
            }

            if uninstallerStore.filteredApplications.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text(uninstallerStore.isScanningApplications ? "正在扫描应用…" : "没有找到应用")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(uninstallerStore.filteredApplications) { app in
                            appRow(app)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .padding(16)
        .toolboxCard()
    }

    private func appRow(_ app: InstalledAppInfo) -> some View {
        Button {
            uninstallerStore.select(app)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    Text(ByteFormatter.string(from: app.bytes))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(
                Group {
                    if uninstallerStore.plan?.app.id == app.id {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.blue.opacity(0.10))
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var uninstallPlanSection: some View {
        if let plan = uninstallerStore.plan {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: plan.app.url.path))
                        .resizable()
                        .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.app.name)
                            .font(.system(size: 18, weight: .bold))
                        Text("\(plan.app.displayVersion) · \(plan.app.bundleIdentifier ?? "无 Bundle ID")")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(ByteFormatter.string(from: uninstallerStore.selectedBytes))
                            .font(.system(size: 19, weight: .bold).monospacedDigit())
                            .foregroundStyle(.blue)
                        Text("已选择 \(uninstallerStore.selectedCount) 项")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                if uninstallerStore.isBuildingPlan {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在识别残留文件…")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    VStack(spacing: 0) {
                        ForEach(plan.artifacts) { artifact in
                            uninstallArtifactRow(artifact)
                            if artifact.id != plan.artifacts.last?.id {
                                Divider().padding(.leading, 34)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("建议选择") {
                        uninstallerStore.selectRecommended()
                    }
                    .buttonStyle(.bordered)

                    Button("清空") {
                        uninstallerStore.clearSelection()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        uninstallerStore.trashSelectedItems()
                    } label: {
                        Label(uninstallerStore.isTrashing ? "处理中" : "移入废纸篓", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(uninstallerStore.selectedArtifactIDs.isEmpty || uninstallerStore.isTrashing)
                }
            }
            .padding(18)
            .toolboxCard()
        } else {
            VStack(spacing: 10) {
                Image(systemName: "app.badge")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("选择一个应用查看卸载预览")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .toolboxCard()
        }
    }

    private func uninstallArtifactRow(_ artifact: AppUninstallArtifact) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { uninstallerStore.selectedArtifactIDs.contains(artifact.id) },
                set: { _ in uninstallerStore.toggleArtifact(artifact) }
            ))
            .labelsHidden()
            .disabled(!artifact.isAccessible)

            Image(systemName: iconName(for: artifact.kind))
                .foregroundStyle(riskColor(for: artifact.risk))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(artifact.kind.rawValue)
                        .font(.system(size: 13.5, weight: .semibold))
                    Label(artifact.risk.rawValue, systemImage: artifact.risk.systemImage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(riskColor(for: artifact.risk))
                }
                Text(artifact.displayPath)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(artifact.displayPath)
            }

            Spacer()

            Text(artifact.isAccessible ? ByteFormatter.string(from: artifact.bytes) : "需手动处理")
                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                .foregroundStyle(artifact.isAccessible ? Color.secondary : Color.orange)

            Button {
                uninstallerStore.reveal(artifact)
            } label: {
                Image(systemName: "arrow.forward.circle")
            }
            .buttonStyle(.plain)
            .help("在访达中显示")
        }
        .padding(.vertical, 9)
    }

    private var uninstallerLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近卸载日志")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(uninstallerStore.trashLogs.count) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(uninstallerStore.trashLogs.suffix(40).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11.5).monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(16)
        .toolboxCard()
    }

    private var inputMethodShortcutSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.green.opacity(0.12))
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.green)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("输入法快捷切换")
                        .font(.system(size: 17, weight: .semibold))
                    Text("给常用输入法绑定明确的全局快捷键。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $settings.inputMethodShortcutsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()

            if inputSources.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("暂未读取到可选择的输入法。请先在系统设置中添加输入法。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("刷新") { refreshInputSources() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(settings.inputMethodShortcutRules) { rule in
                        inputMethodRuleRow(rule)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        settings.addInputMethodShortcutRule()
                    } label: {
                        Label("添加快捷键", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        refreshInputSources()
                    } label: {
                        Label("刷新输入法", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text(inputMethodShortcutHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .toolboxCard()
    }

    private func inputMethodRuleRow(_ rule: InputMethodShortcutRule) -> some View {
        let conflictReason = inputMethodShortcutConflictReason(for: rule)

        return HStack(spacing: 12) {
            ShortcutRecorderButton(
                shortcut: rule.shortcut,
                isRecording: recordingRuleID == rule.id,
                conflictReason: conflictReason,
                startRecording: { recordingRuleID = rule.id },
                record: { shortcut in
                    var updatedRule = rule
                    updatedRule.shortcut = shortcut
                    settings.updateInputMethodShortcutRule(updatedRule)
                    recordingRuleID = nil
                },
                cancel: { recordingRuleID = nil },
                clear: {
                    var updatedRule = rule
                    updatedRule.shortcut = nil
                    settings.updateInputMethodShortcutRule(updatedRule)
                    if recordingRuleID == rule.id {
                        recordingRuleID = nil
                    }
                }
            )
            .frame(width: 142)

            Picker("", selection: inputSourceBinding(for: rule)) {
                Text("选择输入法").tag("")
                ForEach(inputSources) { source in
                    Text(source.name).tag(source.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button {
                settings.removeInputMethodShortcutRule(id: rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("删除")
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottomLeading) {
            if let conflictReason {
                Label(conflictReason, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .padding(.leading, 130)
                    .offset(y: 13)
            }
        }
        .padding(.bottom, conflictReason == nil ? 0 : 14)
    }

    private var appLauncherShortcutSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.purple.opacity(0.12))
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.purple)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷键弹出面板")
                        .font(.system(size: 17, weight: .semibold))
                    Text("弹出的是独立轻量面板，不会打开完整工具箱。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ShortcutRecorderButton(
                    shortcut: settings.appLauncherShortcut,
                    isRecording: isRecordingAppLauncherShortcut,
                    conflictReason: appLauncherShortcutConflictReason,
                    startRecording: { isRecordingAppLauncherShortcut = true },
                    record: { shortcut in
                        settings.setAppLauncherShortcut(shortcut)
                        isRecordingAppLauncherShortcut = false
                    },
                    cancel: { isRecordingAppLauncherShortcut = false },
                    clear: {
                        settings.appLauncherShortcut = nil
                        isRecordingAppLauncherShortcut = false
                    }
                )
                .frame(width: 142)

                Toggle("", isOn: $settings.appLauncherShortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if let appLauncherShortcutConflictReason {
                Label(appLauncherShortcutConflictReason, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .toolboxCard()
    }

    private var appLauncherAuthorizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("授权应用目录")
                        .font(.system(size: 16, weight: .semibold))
                    Text("沙盒下 ~/Applications 等用户目录需要授权才能扫描，授权后会持续纳入程序收纳台。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    appLauncherStore.addAuthorizedDirectory()
                } label: {
                    Label("添加目录", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(appLauncherStore.isScanning)
            }

            if !appLauncherStore.authorizedDirectories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(appLauncherStore.authorizedDirectories.enumerated()), id: \.offset) { index, url in
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(url.path)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                appLauncherStore.removeAuthorizedDirectory(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .help("移除")
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .toolboxCard()
    }

    private var appLauncherPanelEntrySection: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.blue.opacity(0.12))
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 6) {
                Text("程序面板")
                    .font(.system(size: 16, weight: .semibold))
                Text("应用分组、拖拽整理和启动都在同一个面板里完成。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NotificationCenter.default.post(name: .showAppLauncherPanel, object: nil)
            } label: {
                Label("打开面板", systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .toolboxCard()
    }

    private var screenshotHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("截图钉图")
                    .font(.system(size: 24, weight: .bold))
                Text("框选屏幕区域后复制、保存，或像 Snipaste 一样钉在屏幕上。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                screenshotCaptureController.startCapture()
            } label: {
                Label("立即截图", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var screenshotPermissionGuideSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("先完成这两步")
                        .font(.system(size: 16, weight: .semibold))
                    Text("截图权限负责读取屏幕内容，辅助功能权限负责识别窗口内控件，让自动高亮和框选更精准。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                setupGuideStepRow(
                    step: "1",
                    title: "给截图的权限",
                    message: "用于读取屏幕画面，才能框选、复制、保存和钉图。请在「系统设置 - 隐私与安全性 - 屏幕与系统音频录制」或「屏幕录制」中允许 AirSentry。",
                    buttonTitle: "去授权",
                    systemImage: "camera.viewfinder",
                    action: openScreenshotScreenCaptureSettings
                )

                setupGuideStepRow(
                    step: "2",
                    title: "给辅助功能的权限",
                    message: "用于识别鼠标下方的按钮、图标、文本框等控件，让截图高亮更贴合目标；未开启时仍可使用窗口级识别。请在「系统设置 - 隐私与安全性 - 辅助功能」中允许 AirSentry。",
                    buttonTitle: "去授权",
                    systemImage: "accessibility",
                    action: openScreenshotAccessibilitySettings
                )
            }
        }
        .padding(18)
        .toolboxCard()
    }

    private var screenshotShortcutSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.teal.opacity(0.12))
                    Image(systemName: "keyboard.badge.eye")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.teal)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("全局截图快捷键")
                        .font(.system(size: 17, weight: .semibold))
                    Text("按下快捷键后进入框选截图；Esc 可取消。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ShortcutRecorderButton(
                    shortcut: settings.screenshotShortcut,
                    isRecording: isRecordingScreenshotShortcut,
                    conflictReason: screenshotShortcutConflictReason,
                    startRecording: { isRecordingScreenshotShortcut = true },
                    record: { shortcut in
                        settings.setScreenshotShortcut(shortcut)
                        isRecordingScreenshotShortcut = false
                    },
                    cancel: { isRecordingScreenshotShortcut = false },
                    clear: {
                        settings.screenshotShortcut = nil
                        isRecordingScreenshotShortcut = false
                    }
                )
                .frame(width: 142)

                Toggle("", isOn: $settings.screenshotShortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if let screenshotShortcutConflictReason {
                Label(screenshotShortcutConflictReason, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .toolboxCard()
    }

    private var screenshotActionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.blue.opacity(0.12))
                    Image(systemName: "pin")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 6) {
                    Text("钉图工作流")
                        .font(.system(size: 16, weight: .semibold))
                    Text("框选完成后会自动复制到剪贴板，并出现复制、保存、钉图操作条。钉图窗口支持拖动、缩放、透明度和关闭。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    screenshotCaptureController.startCapture()
                } label: {
                    Label("框选截图", systemImage: "viewfinder")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    screenshotCaptureController.pinClipboardImageIfAvailable()
                } label: {
                    Label("钉住剪贴板图片", systemImage: "pin")
                }
                .buttonStyle(.bordered)

                Spacer()

                Label("首次使用可能需要屏幕录制权限", systemImage: "lock.shield")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .toolboxCard()
    }

    private var ocrHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("文字识别")
                    .font(.system(size: 24, weight: .bold))
                Text("调用 macOS 系统 OCR，支持拖入图片、粘贴剪贴板图片和框选截图识别。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                OCRPanelController.shared.show()
            } label: {
                Label("打开 OCR", systemImage: "text.viewfinder")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var ocrActionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.indigo.opacity(0.12))
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.indigo)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 6) {
                    Text("OCR 工作台")
                        .font(.system(size: 16, weight: .semibold))
                    Text("弹窗内可以拖入图片文件、粘贴剪贴板图片，或发起一次框选截图；识别结果可编辑和复制。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    OCRPanelController.shared.show()
                } label: {
                    Label("打开 OCR 窗口", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    OCRPanelController.shared.show()
                    screenshotCaptureController.startOCRCapture()
                } label: {
                    Label("截图识别", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.bordered)

                Button {
                    OCRPanelController.shared.pasteFromClipboard()
                } label: {
                    Label("粘贴识别", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Spacer()

                Label("使用系统 Vision 文字识别", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .toolboxCard()
    }

    private var superRightClickTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自定义菜单项")
                        .font(.system(size: 17, weight: .semibold))
                    Text("配置 Finder 右键菜单的一级功能，以及带子菜单的格式选项。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("菜单项")
                            .font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                    Text("拖拽排序")
                            .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                VStack(spacing: 0) {
                    ForEach(Array(superRightClickStore.menuItems.enumerated()), id: \.element.id) { index, menuItem in
                        superRightClickMenuItemRow(menuItem)
                            .onDrag {
                                draggedSuperRightClickMenuItemID = menuItem.id
                                return NSItemProvider(object: superRightClickMenuItemDragPayload(menuItem.id) as NSString)
                            }
                            .onDrop(
                                of: [.plainText],
                                delegate: SuperRightClickMenuItemDropDelegate(
                                    store: superRightClickStore,
                                    targetMenuItemID: menuItem.id,
                                    draggedMenuItemID: $draggedSuperRightClickMenuItemID
                                )
                            )

                        if index < superRightClickStore.menuItems.count - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
                .frame(width: 360)

                Divider()
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    superRightClickPreviewSection

                    Divider()

                    superRightClickDetailSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
        .toolboxCard()
    }

    private var superRightClickFolderAuthorizationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.orange.opacity(0.12))
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text("文件夹授权")
                        .font(.system(size: 16, weight: .semibold))
                    Text("新建文件需要先授权目标目录。建议添加桌面、下载、文稿，或按需添加根目录。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        finderAuthorizationStore.addFolder(startingAt: URL(fileURLWithPath: "/"))
                    } label: {
                        Label("授权根目录", systemImage: "externaldrive.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        finderAuthorizationStore.addFolder()
                    } label: {
                        Label("添加文件夹", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)

            if finderAuthorizationStore.folders.isEmpty {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("未授权任何文件夹时，Finder 右键里的“新建文件”不会写入文件。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                Divider()
                VStack(spacing: 0) {
                    ForEach(finderAuthorizationStore.folders) { folder in
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.orange)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.displayName)
                                    .font(.system(size: 13.5, weight: .medium))
                                Text(folder.path)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                finderAuthorizationStore.removeFolder(folder)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("移除授权")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if folder.id != finderAuthorizationStore.folders.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
        }
        .toolboxCard()
    }

    @ViewBuilder
    private var superRightClickDetailSection: some View {
        if selectedSuperRightClickMenuItemID == SuperRightClickStore.newFileMenuItemID {
            superRightClickNewFileDetailSection
        } else if let menuItem = superRightClickStore.menuItem(withID: selectedSuperRightClickMenuItemID) {
            VStack(alignment: .leading, spacing: 0) {
                Text("功能详情")
                    .font(.system(size: 13.5, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(superRightClickColor(for: menuItem.accent).opacity(0.12))
                        Image(systemName: menuItem.systemImage)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(superRightClickColor(for: menuItem.accent))
                    }
                    .frame(width: 46, height: 46)

                    Text(menuItem.title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(menuItem.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("启用此菜单项", isOn: superRightClickMenuItemEnabledBinding(for: menuItem))
                        .font(.system(size: 13.5, weight: .medium))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("请选择一个菜单项")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    private var superRightClickNewFileDetailSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("新建文件")
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Text("格式排序")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            VStack(spacing: 0) {
                ForEach(Array(superRightClickStore.templates.enumerated()), id: \.element.id) { index, template in
                    superRightClickTemplateRow(template)
                        .onDrag {
                            draggedSuperRightClickTemplateID = template.id
                            return NSItemProvider(object: superRightClickTemplateDragPayload(template.id) as NSString)
                        }
                        .onDrop(
                            of: [.plainText],
                            delegate: SuperRightClickTemplateDropDelegate(
                                store: superRightClickStore,
                                targetTemplateID: template.id,
                                draggedTemplateID: $draggedSuperRightClickTemplateID
                            )
                        )

                    if index < superRightClickStore.templates.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    private var superRightClickPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最终右键预览")
                .font(.system(size: 13.5, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(superRightClickStore.enabledMenuItems) { menuItem in
                    HStack(spacing: 9) {
                        Image(systemName: menuItem.systemImage)
                            .foregroundStyle(superRightClickColor(for: menuItem.accent))
                            .frame(width: 18)
                        Text(menuItem.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if menuItem.hasChildren {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                if superRightClickStore.enabledMenuItems.isEmpty {
                    Text("未启用任何菜单项")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 74)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func superRightClickMenuItemRow(_ menuItem: SuperRightClickMenuItem) -> some View {
        Button {
            selectedSuperRightClickMenuItemID = menuItem.id
        } label: {
            HStack(spacing: 12) {
                Toggle("", isOn: superRightClickMenuItemEnabledBinding(for: menuItem))
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                Image(systemName: menuItem.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(superRightClickColor(for: menuItem.accent))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(menuItem.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(menuItem.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: menuItem.hasChildren ? "chevron.right" : "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(
                Group {
                    if selectedSuperRightClickMenuItemID == menuItem.id {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.blue.opacity(0.09))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                    } else if draggedSuperRightClickMenuItemID == menuItem.id {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.blue.opacity(0.06))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func superRightClickTemplateRow(_ template: SuperRightClickTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(superRightClickColor(for: template.accent).opacity(0.12))
                Image(systemName: template.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(superRightClickColor(for: template.accent))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(template.fileExtension.uppercased())
                    .font(.system(size: 11.5).monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: superRightClickTemplateEnabledBinding(for: template))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(
            Group {
                if draggedSuperRightClickTemplateID == template.id {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.blue.opacity(0.07))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                }
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var diskOverview: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: storageStore.disk.usageRatio)
                    .stroke(
                        diskTint,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(storageStore.disk.usageRatio.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                    Text("已用")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 94, height: 94)

            VStack(alignment: .leading, spacing: 12) {
                Text("系统磁盘")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 28) {
                    storageValue("总容量", bytes: storageStore.disk.totalBytes)
                    storageValue("已使用", bytes: storageStore.disk.usedBytes)
                    storageValue("可用", bytes: storageStore.disk.availableBytes)
                }
                ProgressView(value: storageStore.disk.usageRatio)
                    .tint(diskTint)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteFormatter.string(from: storageStore.totalAIBytes))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(.blue)
                Text("已识别 AI 数据")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .toolboxCard()
    }

    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("工具占用")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if let lastScannedAt = storageStore.lastScannedAt {
                    Text("更新于 \(lastScannedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if storageStore.isScanning && storageStore.items.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在统计目录大小，大型模型可能需要一点时间…")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .toolboxCard()
            } else if storageStore.items.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 27))
                        .foregroundStyle(.green)
                    Text("没有发现已支持的 AI 工具数据")
                        .font(.system(size: 14, weight: .semibold))
                    Text("目前会检查 Codex、Claude、Cursor、Windsurf、Copilot、Ollama、LM Studio 和 Hugging Face。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 118)
                .toolboxCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(storageStore.items.enumerated()), id: \.element.id) { index, item in
                        storageItemRow(item)
                        if index < storageStore.items.count - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .toolboxCard()
            }
        }
    }

    private var permissionCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(.blue.opacity(0.12))
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 6) {
                Text("允许读取个人文件夹")
                    .font(.system(size: 16, weight: .semibold))
                Text("仅用于统计常见 AI 工具目录的大小；不会读取文件内容，也不会删除或上传任何数据。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("选择文件夹") {
                storageStore.requestFolderAccess()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .toolboxCard()
    }

    private func storageItemRow(_ item: AIStorageItem) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(item.locations.filter(\.isDetected)) { location in
                    HStack(spacing: 10) {
                        Image(systemName: location.isAccessible ? "folder" : "lock.fill")
                            .foregroundStyle(location.isAccessible ? Color.secondary : Color.orange)
                            .frame(width: 18)
                        Text(location.displayPath)
                            .font(.system(size: 12.5).monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(location.isAccessible ? ByteFormatter.string(from: location.bytes) : "无法访问")
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(location.isAccessible ? Color.secondary : Color.orange)
                        Button {
                            storageStore.reveal(location)
                        } label: {
                            Image(systemName: "arrow.forward.circle")
                        }
                        .buttonStyle(.plain)
                        .help("在访达中显示")
                    }
                    .padding(.leading, 46)
                    .padding(.trailing, 4)
                    .padding(.vertical, 8)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.blue.opacity(0.11))
                    Image(systemName: item.systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 14.5, weight: .semibold))
                    Text("发现 \(item.detectedLocationCount) 个目录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteFormatter.string(from: item.bytes))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
            }
            .padding(.vertical, 12)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
    }

    private func storageValue(_ title: String, bytes: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(ByteFormatter.string(from: bytes))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
        }
    }

    private var diskTint: Color {
        storageStore.disk.usageRatio > 0.9 ? .red : (storageStore.disk.usageRatio > 0.75 ? .orange : .blue)
    }

    private var scanButtonTitle: String {
        if storageStore.isScanning { return "扫描中" }
        return storageStore.hasFolderAccess ? "重新扫描" : "开始扫描"
    }

    private var inputMethodShortcutHint: String {
        settings.inputMethodShortcutsEnabled ? "已启用" : "关闭时不会注册全局快捷键"
    }

    private func refreshInputSources() {
        inputSources = InputMethodSwitcher.selectableInputSources()
    }

    private func inputSourceBinding(for rule: InputMethodShortcutRule) -> Binding<String> {
        Binding(
            get: { rule.inputSourceID ?? "" },
            set: { inputSourceID in
                var updatedRule = rule
                updatedRule.inputSourceID = inputSourceID.isEmpty ? nil : inputSourceID
                settings.updateInputMethodShortcutRule(updatedRule)
            }
        )
    }

    private func inputMethodShortcutConflictReason(for rule: InputMethodShortcutRule) -> String? {
        guard let shortcut = rule.shortcut else { return nil }
        if let otherRule = settings.inputMethodShortcutRules.first(where: { $0.id != rule.id && $0.shortcut == shortcut }) {
            let sourceName = inputSources.first { $0.id == otherRule.inputSourceID }?.name ?? "另一个输入法规则"
            return "已被 \(sourceName) 使用"
        }
        if settings.appLauncherShortcut == shortcut {
            return "已被程序面板快捷键使用"
        }
        if settings.screenshotShortcut == shortcut {
            return "已被截图钉图快捷键使用"
        }
        if settings.translationShortcut == shortcut {
            return "已被翻译助手快捷键使用"
        }
        return nil
    }

    private var appLauncherShortcutConflictReason: String? {
        guard let shortcut = settings.appLauncherShortcut else { return nil }
        if let rule = settings.inputMethodShortcutRules.first(where: { $0.shortcut == shortcut }) {
            let sourceName = inputSources.first { $0.id == rule.inputSourceID }?.name ?? "输入法快捷切换"
            return "已被 \(sourceName) 使用"
        }
        if settings.screenshotShortcut == shortcut {
            return "已被截图钉图快捷键使用"
        }
        if settings.translationShortcut == shortcut {
            return "已被翻译助手快捷键使用"
        }
        return nil
    }

    private var screenshotShortcutConflictReason: String? {
        guard let shortcut = settings.screenshotShortcut else { return nil }
        if let rule = settings.inputMethodShortcutRules.first(where: { $0.shortcut == shortcut }) {
            let sourceName = inputSources.first { $0.id == rule.inputSourceID }?.name ?? "输入法快捷切换"
            return "已被 \(sourceName) 使用"
        }
        if settings.appLauncherShortcut == shortcut {
            return "已被程序面板快捷键使用"
        }
        if settings.translationShortcut == shortcut {
            return "已被翻译助手快捷键使用"
        }
        return nil
    }

    private var translationShortcutConflictReason: String? {
        guard let shortcut = settings.translationShortcut else { return nil }
        if let rule = settings.inputMethodShortcutRules.first(where: { $0.shortcut == shortcut }) {
            let sourceName = inputSources.first { $0.id == rule.inputSourceID }?.name ?? "输入法快捷切换"
            return "已被 \(sourceName) 使用"
        }
        if settings.appLauncherShortcut == shortcut {
            return "已被程序面板快捷键使用"
        }
        if settings.screenshotShortcut == shortcut {
            return "已被截图钉图快捷键使用"
        }
        return nil
    }

    private func superRightClickMenuItemEnabledBinding(for menuItem: SuperRightClickMenuItem) -> Binding<Bool> {
        Binding(
            get: { menuItem.isEnabled },
            set: { isEnabled in
                superRightClickStore.setMenuItem(menuItem.id, isEnabled: isEnabled)
            }
        )
    }

    private func superRightClickTemplateEnabledBinding(for template: SuperRightClickTemplate) -> Binding<Bool> {
        Binding(
            get: { template.isEnabled },
            set: { isEnabled in
                superRightClickStore.setTemplate(template.id, isEnabled: isEnabled)
            }
        )
    }

    private func superRightClickColor(for accent: SuperRightClickTemplate.Accent) -> Color {
        switch accent {
        case .blue:
            return .blue
        case .green:
            return .green
        case .orange:
            return .orange
        case .purple:
            return .purple
        case .red:
            return .red
        case .teal:
            return .teal
        case .gray:
            return .secondary
        }
    }

    private func openScreenshotScreenCaptureSettings() {
        if #available(macOS 10.15, *) {
            _ = CGRequestScreenCaptureAccess()
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openScreenshotAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openSuperRightClickExtensionSettings() {
        let preferenceURLs = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]

        for preferenceURL in preferenceURLs {
            guard let url = URL(string: preferenceURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.open(settingsURL)
    }

    private func iconName(for kind: AppUninstallArtifactKind) -> String {
        switch kind {
        case .application:
            return "app"
        case .support:
            return "folder"
        case .cache:
            return "externaldrive"
        case .preferences:
            return "slider.horizontal.3"
        case .logs:
            return "doc.text"
        case .savedState:
            return "macwindow"
        case .container:
            return "shippingbox"
        case .groupContainer:
            return "square.stack.3d.up"
        }
    }

    private func riskColor(for risk: AppUninstallRisk) -> Color {
        switch risk {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private var sidebarSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white
    }
}

private enum ToolboxSection {
    case storage
    case uninstaller
    case inputMethod
    case appLauncher
    case screenshot
    case ocr
    case imageProcessing
    case superRightClick
    case translation

    init?(quickTool: MenuBarQuickTool) {
        switch quickTool {
        case .appLauncher:
            self = .appLauncher
        case .screenshot:
            self = .screenshot
        case .ocr:
            self = .ocr
        case .imageProcessing:
            self = .imageProcessing
        case .superRightClick:
            self = .superRightClick
        case .storage:
            self = .storage
        case .uninstaller:
            self = .uninstaller
        case .inputMethod:
            self = .inputMethod
        case .translation:
            self = .translation
        }
    }
}

extension Notification.Name {
    static let selectToolboxSection = Notification.Name("AirSentry.SelectToolboxSection")
}

private struct SuperRightClickMenuItem: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let systemImage: String
    let accent: SuperRightClickTemplate.Accent
    let hasChildren: Bool
    var isEnabled: Bool
}

private struct SuperRightClickTemplate: Identifiable, Codable, Equatable, Hashable {
    enum Accent: String, Codable {
        case blue
        case green
        case orange
        case purple
        case red
        case teal
        case gray
    }

    let id: String
    let name: String
    let fileExtension: String
    let systemImage: String
    let accent: Accent
    var isEnabled: Bool

    var menuTitle: String {
        "\(name) 文件"
    }
}

@MainActor
private final class SuperRightClickStore: ObservableObject {
    static let newFileMenuItemID = "newFile"
    static let defaultSelectedMenuItemID = newFileMenuItemID

    @Published var menuItems: [SuperRightClickMenuItem] {
        didSet { saveMenuItems(); syncToSharedConfig() }
    }

    @Published var templates: [SuperRightClickTemplate] {
        didSet { saveTemplates(); syncToSharedConfig() }
    }

    var enabledMenuItems: [SuperRightClickMenuItem] {
        menuItems.filter(\.isEnabled)
    }

    var enabledTemplates: [SuperRightClickTemplate] {
        templates.filter(\.isEnabled)
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuItems = Self.loadMenuItems(from: defaults)
        templates = Self.loadTemplates(from: defaults)
        // 初始化时同步配置到共享文件，确保 Finder 扩展能读取
        syncToSharedConfig()
    }

    func menuItem(withID menuItemID: String) -> SuperRightClickMenuItem? {
        menuItems.first { $0.id == menuItemID }
    }

    func setMenuItem(_ menuItemID: String, isEnabled: Bool) {
        guard let index = menuItems.firstIndex(where: { $0.id == menuItemID }) else { return }
        menuItems[index].isEnabled = isEnabled
    }

    func setTemplate(_ templateID: String, isEnabled: Bool) {
        guard let index = templates.firstIndex(where: { $0.id == templateID }) else { return }
        templates[index].isEnabled = isEnabled
    }

    func moveMenuItem(id: String, near targetID: String) {
        guard id != targetID,
              let sourceIndex = menuItems.firstIndex(where: { $0.id == id }),
              let targetIndex = menuItems.firstIndex(where: { $0.id == targetID }) else { return }

        let menuItem = menuItems.remove(at: sourceIndex)
        menuItems.insert(menuItem, at: targetIndex)
    }

    func moveTemplate(id: String, near targetID: String) {
        guard id != targetID,
              let sourceIndex = templates.firstIndex(where: { $0.id == id }),
              let targetIndex = templates.firstIndex(where: { $0.id == targetID }) else { return }

        let template = templates.remove(at: sourceIndex)
        templates.insert(template, at: targetIndex)
    }

    func resetTemplates() {
        menuItems = Self.defaultMenuItems
        templates = Self.defaultTemplates
    }

    private func saveMenuItems() {
        do {
            let data = try JSONEncoder().encode(menuItems)
            defaults.set(data, forKey: Keys.menuItems)
        } catch {
            NSLog("AirSentry super right click menu items save failed: \(error.localizedDescription)")
        }
    }

    private func saveTemplates() {
        do {
            let data = try JSONEncoder().encode(templates)
            defaults.set(data, forKey: Keys.templates)
        } catch {
            NSLog("AirSentry super right click templates save failed: \(error.localizedDescription)")
        }
    }

    private static func loadMenuItems(from defaults: UserDefaults) -> [SuperRightClickMenuItem] {
        guard let data = defaults.data(forKey: Keys.menuItems),
              let decoded = try? JSONDecoder().decode([SuperRightClickMenuItem].self, from: data),
              !decoded.isEmpty else {
            return defaultMenuItems
        }

        return mergedMenuItems(decoded)
    }

    private static func loadTemplates(from defaults: UserDefaults) -> [SuperRightClickTemplate] {
        guard let data = defaults.data(forKey: Keys.templates),
              let decoded = try? JSONDecoder().decode([SuperRightClickTemplate].self, from: data),
              !decoded.isEmpty else {
            return defaultTemplates
        }

        return mergedTemplates(decoded)
    }

    private static func mergedMenuItems(_ decoded: [SuperRightClickMenuItem]) -> [SuperRightClickMenuItem] {
        let knownItems = Dictionary(uniqueKeysWithValues: defaultMenuItems.map { ($0.id, $0) })
        let decodedIDs = Set(decoded.map(\.id))
        let preserved = decoded.compactMap { savedItem -> SuperRightClickMenuItem? in
            guard var currentItem = knownItems[savedItem.id] else { return nil }
            currentItem.isEnabled = savedItem.isEnabled
            return currentItem
        }
        let missing = defaultMenuItems.filter { !decodedIDs.contains($0.id) }
        return preserved + missing
    }

    private static func mergedTemplates(_ decoded: [SuperRightClickTemplate]) -> [SuperRightClickTemplate] {
        let knownTemplates = Dictionary(uniqueKeysWithValues: defaultTemplates.map { ($0.id, $0) })
        let decodedIDs = Set(decoded.map(\.id))
        let preserved = decoded.map { savedTemplate in
            guard let currentTemplate = knownTemplates[savedTemplate.id] else { return savedTemplate }
            var mergedTemplate = currentTemplate
            mergedTemplate.isEnabled = savedTemplate.isEnabled
            return mergedTemplate
        }
        let missing = defaultTemplates.filter { !decodedIDs.contains($0.id) }
        return preserved + missing
    }

    private static let defaultMenuItems: [SuperRightClickMenuItem] = [
        SuperRightClickMenuItem(id: newFileMenuItemID, title: "新建文件", subtitle: "Excel、PPT、Word 等格式", detail: "在 Finder 右键菜单中展开常用文件模板，格式顺序可单独拖拽调整。", systemImage: "doc.badge.plus", accent: .blue, hasChildren: true, isEnabled: true),
        SuperRightClickMenuItem(id: "openWith", title: "其他应用打开", subtitle: "快速选择指定应用", detail: "为文件或目录提供快捷打开方式，后续可在这里维护应用列表。", systemImage: "app.badge", accent: .purple, hasChildren: true, isEnabled: true),
        SuperRightClickMenuItem(id: "favoriteFolders", title: "常用目录", subtitle: "复制或跳转常用路径", detail: "把高频目录放进右键菜单，便于快速复制路径或在 Finder 中打开。", systemImage: "folder.badge.gearshape", accent: .orange, hasChildren: true, isEnabled: true),
        SuperRightClickMenuItem(id: "airdrop", title: "隔空投送", subtitle: "调用系统 AirDrop", detail: "把系统隔空投送动作放到统一菜单中，减少在 Finder 分享菜单里的查找成本。", systemImage: "airplayaudio", accent: .teal, hasChildren: false, isEnabled: true),
        SuperRightClickMenuItem(id: "openTerminal", title: "打开终端", subtitle: "在当前目录启动 Terminal", detail: "快速打开终端并自动切换到当前所选目录，便于执行命令行操作。", systemImage: "terminal", accent: .gray, hasChildren: false, isEnabled: true),
        SuperRightClickMenuItem(id: "copyPath", title: "拷贝路径", subtitle: "复制完整文件路径", detail: "复制所选文件或目录的完整路径，方便在终端、编辑器和脚本中使用。", systemImage: "doc.on.clipboard", accent: .gray, hasChildren: false, isEnabled: true),
        SuperRightClickMenuItem(id: "copyName", title: "拷贝名称", subtitle: "复制文件名", detail: "仅复制所选项目名称，不包含父级目录路径。", systemImage: "tag", accent: .gray, hasChildren: false, isEnabled: true),
        SuperRightClickMenuItem(id: "showHidden", title: "显示隐藏", subtitle: "切换隐藏文件可见性", detail: "一键切换 Finder 中隐藏文件的显示状态。", systemImage: "eye", accent: .orange, hasChildren: false, isEnabled: false),
        SuperRightClickMenuItem(id: "hideDesktop", title: "隐藏桌面", subtitle: "切换桌面图标显示", detail: "在演示、录屏或专注时快速隐藏桌面图标。", systemImage: "desktopcomputer", accent: .blue, hasChildren: false, isEnabled: true)
    ]

    private static let defaultTemplates: [SuperRightClickTemplate] = [
        SuperRightClickTemplate(id: "xlsx", name: "Excel 表格", fileExtension: "xlsx", systemImage: "tablecells", accent: .green, isEnabled: true),
        SuperRightClickTemplate(id: "pptx", name: "PowerPoint 演示", fileExtension: "pptx", systemImage: "play.rectangle", accent: .orange, isEnabled: true),
        SuperRightClickTemplate(id: "docx", name: "Word 文档", fileExtension: "docx", systemImage: "doc.richtext", accent: .blue, isEnabled: true),
        SuperRightClickTemplate(id: "txt", name: "纯文本", fileExtension: "txt", systemImage: "doc.plaintext", accent: .gray, isEnabled: true),
        SuperRightClickTemplate(id: "md", name: "Markdown", fileExtension: "md", systemImage: "number.square", accent: .purple, isEnabled: true),
        SuperRightClickTemplate(id: "csv", name: "CSV 表格", fileExtension: "csv", systemImage: "list.bullet.rectangle", accent: .teal, isEnabled: true),
        SuperRightClickTemplate(id: "json", name: "JSON 配置", fileExtension: "json", systemImage: "curlybraces.square", accent: .red, isEnabled: false),
        SuperRightClickTemplate(id: "rtf", name: "富文本", fileExtension: "rtf", systemImage: "textformat", accent: .blue, isEnabled: false),
        SuperRightClickTemplate(id: "html", name: "HTML 页面", fileExtension: "html", systemImage: "chevron.left.forwardslash.chevron.right", accent: .orange, isEnabled: false)
    ]

    private enum Keys {
        static let menuItems = "superRightClickMenuItems"
        static let templates = "superRightClickTemplates"
    }

    private func syncToSharedConfig() {
        NSLog("AirSentry syncToSharedConfig called")
        let enabledMenuItemIDs = menuItems.filter(\.isEnabled).map(\.id)
        let enabledTemplateIDs = templates.filter(\.isEnabled).map(\.id)
        NSLog("AirSentry enabled menu items: %{public}@", enabledMenuItemIDs.joined(separator: ", "))
        // 只同步轻量元数据（不含 contents）
        let templateMetas = templates.filter(\.isEnabled).map { template in
            SuperRightClickSharedConfig.TemplateMeta(
                id: template.id,
                title: template.name,
                fileName: Self.fileName(for: template),
                systemImage: template.systemImage
            )
        }

        let config = SuperRightClickSharedConfig(
            enabledMenuItemIDs: enabledMenuItemIDs,
            enabledTemplateIDs: enabledTemplateIDs,
            templates: templateMetas
        )
        config.save()
    }

    private static func fileName(for template: SuperRightClickTemplate) -> String {
        switch template.id {
        case "xlsx": return "新建表格.xlsx"
        case "pptx": return "新建演示.pptx"
        case "docx": return "新建文档.docx"
        case "txt": return "新建文本.txt"
        case "md": return "新建文档.md"
        case "csv": return "新建表格.csv"
        case "json": return "新建配置.json"
        case "rtf": return "新建文档.rtf"
        case "html": return "新建页面.html"
        default: return "新建文件.\(template.fileExtension)"
        }
    }

    private static func contents(for template: SuperRightClickTemplate) -> Data {
        switch template.id {
        case "md": return Data("# 新建文档\n".utf8)
        case "json": return Data("{\n  \n}\n".utf8)
        case "html": return Data("<!doctype html>\n<html>\n<head>\n  <meta charset=\"utf-8\">\n  <title>新建页面</title>\n</head>\n<body>\n</body>\n</html>\n".utf8)
        default: return Data()
        }
    }
}

private func superRightClickMenuItemDragPayload(_ menuItemID: String) -> String {
    "airsentry-super-right-click:menu-item:\(menuItemID)"
}

private func parseSuperRightClickMenuItemDragPayload(_ payload: String) -> String? {
    let parts = payload.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count == 3,
          parts[0] == "airsentry-super-right-click",
          parts[1] == "menu-item" else {
        return nil
    }

    return parts[2]
}

private func superRightClickTemplateDragPayload(_ templateID: String) -> String {
    "airsentry-super-right-click:template:\(templateID)"
}

private func parseSuperRightClickTemplateDragPayload(_ payload: String) -> String? {
    let parts = payload.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count == 3,
          parts[0] == "airsentry-super-right-click",
          parts[1] == "template" else {
        return nil
    }

    return parts[2]
}

private func loadSuperRightClickMenuItemDragPayload(from providers: [NSItemProvider], completion: @escaping (String) -> Void) {
    loadSuperRightClickDragPayload(from: providers, completion: completion)
}

private func loadSuperRightClickTemplateDragPayload(from providers: [NSItemProvider], completion: @escaping (String) -> Void) {
    loadSuperRightClickDragPayload(from: providers, completion: completion)
}

private func loadSuperRightClickDragPayload(from providers: [NSItemProvider], completion: @escaping (String) -> Void) {
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

private struct SuperRightClickMenuItemDropDelegate: DropDelegate {
    let store: SuperRightClickStore
    let targetMenuItemID: String
    @Binding var draggedMenuItemID: String?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard let draggedMenuItemID,
              draggedMenuItemID != targetMenuItemID else { return }

        store.moveMenuItem(id: draggedMenuItemID, near: targetMenuItemID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if draggedMenuItemID != nil {
            draggedMenuItemID = nil
            return true
        }

        loadSuperRightClickMenuItemDragPayload(from: info.itemProviders(for: [.plainText])) { payload in
            guard let menuItemID = parseSuperRightClickMenuItemDragPayload(payload) else { return }
            Task { @MainActor in
                store.moveMenuItem(id: menuItemID, near: targetMenuItemID)
            }
        }

        return true
    }

    func dropExited(info: DropInfo) {
        if draggedMenuItemID == targetMenuItemID {
            draggedMenuItemID = nil
        }
    }
}

private struct SuperRightClickTemplateDropDelegate: DropDelegate {
    let store: SuperRightClickStore
    let targetTemplateID: String
    @Binding var draggedTemplateID: String?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard let draggedTemplateID,
              draggedTemplateID != targetTemplateID else { return }

        store.moveTemplate(id: draggedTemplateID, near: targetTemplateID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if draggedTemplateID != nil {
            draggedTemplateID = nil
            return true
        }

        loadSuperRightClickTemplateDragPayload(from: info.itemProviders(for: [.plainText])) { payload in
            guard let templateID = parseSuperRightClickTemplateDragPayload(payload) else { return }
            Task { @MainActor in
                store.moveTemplate(id: templateID, near: targetTemplateID)
            }
        }

        return true
    }

    func dropExited(info: DropInfo) {
        if draggedTemplateID == targetTemplateID {
            draggedTemplateID = nil
        }
    }
}

private struct ToolboxSidebarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? .blue : .secondary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.blue.opacity(0.10))
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }
}

private struct ShortcutRecorderButton: View {
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
                if isRecording {
                    cancel()
                } else {
                    startRecording()
                }
            } label: {
                Text(title)
                    .font(.system(size: 13, weight: .semibold).monospaced())
                    .foregroundStyle(conflictReason == nil ? Color.primary : Color.orange)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .background(
                ShortcutCaptureView(
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

private struct ShortcutCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let record: (KeyboardShortcut) -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.record = record
        view.cancel = cancel
        return view
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
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

private final class CaptureNSView: NSView {
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

private extension View {
    func toolboxCard() -> some View {
        modifier(ToolboxCardModifier())
    }
}

private struct ToolboxCardModifier: ViewModifier {
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
