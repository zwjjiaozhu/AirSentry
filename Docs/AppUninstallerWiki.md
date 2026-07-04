# AirSentry 软件卸载助手 Wiki

## 项目定位

软件卸载助手是工具箱中的安全清理工具，用于帮助用户识别已安装应用、应用本体和常见残留数据，并在用户确认后把可处理项目移入废纸篓。

当前功能定位是：

- 先预览，再处理。
- 默认不永久删除文件。
- 优先处理用户目录下可写的缓存、日志、偏好设置和应用数据。
- 对 `/Applications` 中需要管理员权限的应用本体，只提示并在访达中定位，不在 App 内强行提权删除。

主要入口：

- `AirGuard/Views/ToolboxView.swift`
- `AirGuard/Core/AppUninstallerStore.swift`
- `AirGuard/Readers/AppUninstallerReader.swift`
- `AirGuard/Models/AppUninstallerInfo.swift`
- `AirGuard/AppStore.entitlements`

## 用户能力

用户可以在工具箱中进入“软件卸载助手”，完成以下操作：

- 扫描 `/Applications` 和用户应用目录中的 `.app`。
- 查看应用图标、名称、版本、Bundle ID、大小。
- 按名称、大小、最近使用排序。
- 搜索应用名称或 Bundle ID。
- 授权个人文件夹后，扫描 `~/Library` 中的常见残留文件。
- 勾选需要处理的项目。
- 二次确认后把可处理项目移入废纸篓。
- 查看最近一次处理日志。
- 对无权限项目一键在访达中定位，交给 Finder 或用户手动处理。

## 功能入口

工具箱侧边栏新增：

```text
软件卸载助手
```

界面布局：

- 顶部：标题、目录授权状态、刷新按钮。
- 左侧：应用列表、搜索框、排序分段控件。
- 右侧：当前应用详情、卸载预览、风险标签、勾选项、移入废纸篓按钮。
- 底部：最近卸载日志。

## 扫描范围

### 应用扫描

`AppUninstallerReader.scanApplications()` 扫描以下目录：

```text
/Applications
~/Applications
FileManager .applicationDirectory localDomain
FileManager .applicationDirectory userDomain
```

扫描到 `.app` 后读取：

- `CFBundleDisplayName`
- `CFBundleName`
- `CFBundleShortVersionString`
- Bundle Identifier
- 应用图标
- 应用大小
- 最近访问或修改时间

### 残留文件扫描

授权个人文件夹后，根据应用名、`.app` 文件名、Bundle ID 派生候选名称，在 `~/Library` 下匹配：

```text
~/Library/Application Support/{name}
~/Library/Caches/{name}
~/Library/Caches/{bundleIdentifier}
~/Library/Preferences/{bundleIdentifier}.plist
~/Library/Logs/{name}
~/Library/Saved Application State/{bundleIdentifier}.savedState
~/Library/Containers/{bundleIdentifier}
~/Library/Group Containers/*
```

`Group Containers` 采用名称 token 包含匹配，风险等级默认较高。

## 卸载项模型

核心模型为 `AppUninstallArtifact`：

```text
id
url
displayPath
kind
risk
bytes
isAccessible
isRecommended
```

`kind` 用于区分项目类型：

- 应用本体
- 应用数据
- 缓存
- 偏好设置
- 日志
- 窗口状态
- 容器数据
- 群组容器

`risk` 用于 UI 风险提示：

- 低风险：缓存、日志、窗口状态。
- 需确认：应用本体、应用数据、偏好设置。
- 高风险：容器数据、群组容器。

默认推荐选择规则：

```text
risk != high && isAccessible == true
```

也就是说，高风险项目和当前没有写入权限的项目不会默认勾选。

## 删除流程

删除动作由 `AppUninstallerStore.trashSelectedItems()` 负责：

```text
用户勾选项目
点击“移入废纸篓”
过滤不可访问项目
如果没有可处理项目，提示并在访达中定位
弹出二次确认
后台任务重新进入安全作用域
FileManager.trashItem
记录成功、失败和最终状态
刷新应用列表和卸载预览
```

删除使用：

```swift
FileManager.default.trashItem(at: artifact.url, resultingItemURL: &resultingURL)
```

不会使用 `rm`，也不会永久删除。

## 权限设计

### Sandbox 授权

当前 entitlements 使用用户选择文件读写权限：

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

用户需要分别授权：

- 个人文件夹：用于扫描 `~/Library` 残留数据。
- 应用目录：用于访问 `/Applications` 或 `~/Applications` 中的应用本体。

授权使用 security-scoped bookmark 保存，下次启动会尝试恢复。

### Sandbox 授权不等于管理员权限

这是当前功能最重要的边界。

用户通过 `NSOpenPanel` 授权 `/Applications` 后，App 只是获得了 sandbox 访问能力，并不自动获得 POSIX 写权限。如果 `/Applications` 对当前用户不可写：

```text
parentWritable=false
```

则 `FileManager.trashItem` 会失败，典型错误为：

```text
domain=NSCocoaErrorDomain
code=513
message=“xxx.app” couldn’t be moved to the trash because you don’t have permission to access it.
```

Finder 可以删除这类应用，是因为 Finder 能走系统授权流程并弹出管理员密码。`FileManager.trashItem` 不会自动弹出管理员授权。

### 当前处理策略

对没有写入权限的应用本体：

- UI 显示“需手动处理”。
- Toggle 禁用。
- 不默认勾选。
- 删除时跳过并写入日志。
- 如果所有选中项都不可处理，自动在访达中定位。

对用户目录下可写项目：

- 可以正常移入废纸篓。
- 成功后刷新列表和卸载计划。

## 日志排查

软件卸载助手会同时在界面和 Console 打日志。

Console 搜索关键字：

```text
[AirSentry][Uninstaller]
```

日志内容包括：

- 当前应用名称。
- 选择项目数量。
- 个人目录授权路径。
- 应用目录授权路径。
- 安全作用域重新进入结果。
- 每个项目处理前是否存在。
- 父目录是否可写。
- `trashItem` 成功后的废纸篓路径。
- `trashItem` 失败时的 NSError domain/code/message。

典型无权限日志：

```text
kind=应用本体, risk=需确认, existsBefore=true, parentWritable=false
trashItem 失败，domain=NSCocoaErrorDomain, code=513
```

结论：

```text
sandbox 授权成功，但父目录没有 POSIX 写权限，需要 Finder 或管理员授权流程处理。
```

## 当前已知限制

- 不能在 App 内直接删除 `/Applications` 中需要管理员权限的应用本体。
- 不会自动终止正在运行的应用。
- 不会清理 LaunchAgent、Login Item、Privileged Helper、系统扩展、浏览器扩展等高级残留。
- `Group Containers` 目前只是启发式匹配，默认高风险，不建议默认清理。
- 不做永久删除，只移动到废纸篓。

## 后续方向

### 管理员权限删除

如果要在 App 内完成 `/Applications` 中受保护应用的删除，需要单独设计授权方案：

- privileged helper tool
- SMJobBless 或现代替代方案
- XPC 通信
- 明确的权限提示和审计日志
- 更严格的路径校验

不建议用普通 shell 提权或隐藏式删除。

### 更完整的卸载能力

可继续扩展：

- 检测正在运行的目标应用并提示退出。
- 检测登录项。
- 检测 LaunchAgent / LaunchDaemon。
- 检测 Homebrew Cask 安装来源。
- 检测 App Store receipt。
- 支持卸载历史记录。
- 支持只清缓存模式。

## 设计原则

- 删除前必须可预览。
- 默认选择要保守。
- 高风险项目必须用户主动选择。
- 权限不足时要解释原因，而不是静默失败。
- App 内删除能力不能伪装成 Finder 的管理员授权能力。
- 所有删除动作优先进入废纸篓，避免不可恢复损失。
