# AirSentry 功能 Wiki

## 项目定位

AirSentry 是一个 macOS 菜单栏应用，用于 MacBook Air 的温度提醒与系统状态看板。应用常驻菜单栏，周期性读取温度、CPU、内存和网络状态，在达到用户设置的热状态阈值后发送系统通知，并给出基础降温建议。

主要入口：

- `AirGuard/AirGuardApp.swift`
- `AirGuard/Views/MenuBarPanelView.swift`
- `AirGuard/Views/SettingsView.swift`
- `AirGuard/Core/MonitorStore.swift`

## 功能总览

| 功能 | 当前状态 | 主要代码 | 说明 |
| --- | --- | --- | --- |
| 菜单栏常驻状态 | 已实现 | `AirGuardApp.swift` | 通过 `MenuBarExtra` 常驻菜单栏，显示温度或热状态。 |
| 系统状态看板 | 已实现 | `MenuBarPanelView.swift` | 展示温度、CPU、内存、网络和建议。 |
| 温度读取 | 已实现 | `ThermalReader.swift`、`HIDTemperatureReader.m` | 官方热状态 + SMC/HID 真实温度读取。 |
| 温度阈值换算 | 已实现 | `AppSettings.swift` | 真实温度可用时按用户阈值换算热状态。 |
| 高温通知 | 已实现 | `AlertManager.swift` | 达到触发等级后发送系统通知，支持冷却时间。 |
| 高 CPU 进程提示 | 已实现 | `CPUReader.swift`、`MonitorStore.swift` | 达到通知等级时读取 CPU 占用最高的进程。 |
| CPU 读取 | 已实现 | `CPUReader.swift` | 通过 Mach host statistics 计算使用率。 |
| 内存读取 | 已实现 | `MemoryReader.swift` | 读取 VM 统计和系统内存压力事件。 |
| 网络速率读取 | 已实现 | `NetworkReader.swift` | 通过网络接口字节差计算上传和下载速率。 |
| 设置页 | 已实现 | `SettingsView.swift`、`AppSettings.swift` | 支持通知、检测周期、冷却、阈值、开机启动等配置。 |
| 开机自动启动 | 已实现 | `LaunchAtLoginManager.swift` | 使用 `SMAppService.mainApp` 注册/取消登录启动。 |
| 活动监视器跳转 | 已实现 | `MenuBarPanelView.swift` | 点击指标卡片打开系统活动监视器。 |
| 退出应用 | 已实现 | `MenuBarPanelView.swift` | 菜单面板底部提供退出按钮。 |
| 工具箱 | 已实现 | `ToolboxView.swift` | 集中提供 AI 用量中心、软件卸载助手和输入法快捷切换。 |
| 软件卸载助手 | 已实现 | `AppUninstallerStore.swift`、`AppUninstallerReader.swift` | 扫描应用和常见残留文件，确认后将可处理项目移入废纸篓。 |
| 超级右键 | 部分实现 | `AirGuardFinderExtension/FinderSync.swift`、`ToolboxView.swift` | FinderSync 右键扩展已可注册和加载；Finder 内当前提供新建文件、拷贝路径、拷贝名称。配置页里的排序、开关、常用目录、AirDrop 等仍需接入扩展。 |

## 菜单栏常驻状态

### 用户能力

- 应用以菜单栏图标和文字形式常驻。
- 默认优先显示实时温度，例如 `52°`。
- 如果真实温度不可用，显示官方热状态短标题，例如 `正常`、`偏热`、`高温`、`危险`。
- 鼠标悬停时显示帮助文案，包含当前温度或真实温度不可用提示。

### 实现方式

`AirGuardApp` 创建三个共享对象：

- `AppSettings`
- `AlertManager`
- `MonitorStore`

菜单栏由 `MenuBarExtra` 创建，标签视图为 `MenuBarStatusLabel`。标签内容来自 `monitorStore.snapshot.thermal`，并受 `settings.menuBarShowsTemperature` 控制。

## 系统状态看板

### 用户能力

点击菜单栏项目后打开主面板，面板展示：

- 当前温度或温度不可用状态。
- 当前热状态。
- CPU 使用率和折线历史。
- 内存使用量、总量、使用率和压力等级。
- 网络下载/上传速度和折线历史。
- 当前建议。
- 设置入口。
- 退出入口。

### 实现方式

主面板由 `MenuBarPanelView` 负责。核心数据全部来自 `MonitorStore.snapshot` 和历史数组：

- `cpuSparklineValues`
- `networkDownloadSparklineValues`
- `networkUploadSparklineValues`

CPU、内存和网络指标卡片被包在按钮中，点击后调用 `openActivityMonitor()` 打开系统活动监视器。

## 温度读取

温度读取详见：

- `Docs/TemperatureReadingWiki.md`

### 功能摘要

`ThermalReader` 每次读取都会获取官方热状态：

```text
ProcessInfo.processInfo.thermalState
```

真实温度读取采用分层策略：

```text
运行态已确认来源
else 持久化首选来源
else SMC CPU keys
else SMC fallback keys
else HID Apple Silicon sensors
else 温度不可用
```

读取成功后会缓存本次运行的来源，并写入 `UserDefaults.temperaturePreferredSource`。读取失败时会清空失效来源并重新探测。

## 温度阈值换算

### 用户能力

用户可设置三个温度阈值：

- 偏热：默认 `55°C`
- 高温：默认 `65°C`
- 严重：默认 `82°C`

真实温度可用时，应用会优先按阈值换算热状态：

```text
temperature >= criticalTemperatureThreshold -> 严重高温
temperature >= seriousTemperatureThreshold  -> 高温
temperature >= fairTemperatureThreshold     -> 偏热
else                                        -> 正常
```

### 保护规则

`AppSettings` 会限制阈值范围并保持递增关系：

- 偏热：`30...123`
- 高温：`31...124`
- 严重：`32...125`
- 高温必须大于偏热。
- 严重必须大于高温。

## 高温通知

### 用户能力

- 可开启或关闭高温通知。
- 可设置触发等级：偏热、高温、严重高温。
- 可设置同一热状态重复提醒前的冷却时间。
- 通知权限未授权时可从设置页触发系统授权。
- 通知权限被拒绝时可跳转系统通知设置。

### 实现方式

`AlertManager.handle(snapshot:settings:)` 在每次刷新后执行：

```text
通知开关关闭 -> 不通知
当前热状态低于触发等级 -> 重置上次等级
同一等级仍处于冷却时间内 -> 不重复通知
否则发送系统通知
```

通知内容使用 `UNUserNotificationCenter` 立即发送。前台展示由 `UNUserNotificationCenterDelegate` 返回 `.banner` 和 `.sound`。

## 高 CPU 进程提示

### 用户能力

当当前热状态达到通知触发等级时，菜单面板建议区会优先显示高 CPU 进程，帮助用户快速定位可能导致升温的任务。

### 实现方式

`MonitorStore.refreshTopCPUProcessesIfNeeded(for:)` 控制刷新节奏：

- 只有热状态达到 `settings.alertThermalLevel` 才读取。
- 每 10 秒最多刷新一次。
- 使用后台任务调用 `ProcessCPUReader.readTopProcesses()`。
- 默认取 CPU 占用最高的 3 个进程。

`ProcessCPUReader` 通过以下命令读取进程信息：

```text
/bin/ps -axo pid=,pcpu=,comm=
```

随后解析 PID、CPU 百分比和命令名，并按 CPU 占用倒序排序。

## CPU 读取

### 用户能力

应用显示当前 CPU 使用率，并保留最近 24 个采样点用于折线图。

### 实现方式

`CPUReader` 使用 `host_statistics` 和 `HOST_CPU_LOAD_INFO` 获取 CPU tick。每次读取与上一次采样做差：

```text
usage = (user + system + nice) / (user + system + idle + nice)
```

首次采样没有上一帧数据，因此返回 `0`。

## 内存读取

### 用户能力

应用显示：

- 内存使用百分比。
- 已用内存 / 总内存。
- 内存压力等级：正常、警告、严重。

### 实现方式

`MemoryReader` 使用 `host_statistics64` 和 `HOST_VM_INFO64` 读取 VM 统计：

- active
- inactive
- wired
- compressed
- free

已用内存按以下值求和：

```text
active + inactive + wired + compressed
```

总内存来自：

```text
ProcessInfo.processInfo.physicalMemory
```

内存压力由 `DispatchSource.makeMemoryPressureSource` 监听 `.normal`、`.warning`、`.critical` 事件。

## 网络速率读取

### 用户能力

应用显示当前下载速度和上传速度，并保留最近 24 个采样点用于折线图。

### 实现方式

`NetworkReader` 通过 `getifaddrs` 遍历网络接口，跳过 `lo` 回环接口，累计所有 `AF_LINK` 接口的：

- `ifi_ibytes`
- `ifi_obytes`

每次读取与上次采样做差，并除以采样间隔得到每秒速率。首次采样没有上一帧数据，因此上传和下载速度均为 `0`。

## 设置页

### 用户能力

设置页包含三个区域：

- 提醒
- 温度阈值
- 启动

提醒区域：

- 高温通知开关。
- 通知权限状态。
- 检测周期，范围 `1...60` 秒。
- 通知冷却，范围 `0...3600` 秒。
- 菜单栏显示温度开关。

温度阈值区域：

- 偏热、高温、严重三个阈值卡片。
- 可用上下按钮微调。
- 可点击数值直接输入。
- 可选择通知触发等级。

启动区域：

- 开机自动启动开关。

### 持久化

`AppSettings` 使用 `UserDefaults` 保存：

| Key | 默认值 | 说明 |
| --- | --- | --- |
| `notificationsEnabled` | `true` | 是否启用高温通知。 |
| `menuBarShowsTemperature` | `true` | 菜单栏是否优先显示温度。 |
| `alertThermalLevel` | `serious` | 通知触发等级。 |
| `fairTemperatureThreshold` | `55` | 偏热阈值。 |
| `seriousTemperatureThreshold` | `65` | 高温阈值。 |
| `criticalTemperatureThreshold` | `82` | 严重阈值。 |
| `refreshInterval` | `2` | 检测周期，单位秒。 |
| `notificationCooldown` | `60` | 通知冷却，单位秒。 |
| `launchAtLoginEnabled` | 系统当前状态 | 是否开机自动启动。 |

## 开机自动启动

### 用户能力

用户可以在设置页开启或关闭开机自动启动。

### 实现方式

`LaunchAtLoginManager` 使用 `ServiceManagement`：

```text
SMAppService.mainApp.register()
SMAppService.mainApp.unregister()
SMAppService.mainApp.status
```

设置项变更时会立即调用 `LaunchAtLoginManager.setEnabled(_:)`。失败时通过 `NSLog` 输出错误。

## 工具箱

工具箱由 `ToolboxView` 负责，当前包含：

- AI 用量中心。
- 软件卸载助手。
- 输入法快捷切换。
- 超级右键。

软件卸载助手详见：

- `Docs/AppUninstallerWiki.md`

### 软件卸载助手摘要

软件卸载助手用于扫描已安装应用、应用本体和 `~/Library` 中的常见残留文件。用户确认后，可处理项目会通过 `FileManager.trashItem` 移入废纸篓。

重要权限边界：

```text
NSOpenPanel 授权目录只代表 sandbox 访问授权，不代表管理员写权限。
```

如果应用本体位于 `/Applications` 且父目录不可写，`trashItem` 会失败：

```text
NSCocoaErrorDomain code=513
```

当前策略是将这类项目标为“需手动处理”，默认不勾选，删除时跳过并在访达中定位。用户目录下可写的缓存、日志、偏好设置等项目仍可正常移入废纸篓。

## 超级右键

### 当前状态

超级右键由两部分组成：

- App 内配置页：`ToolboxView.swift`
- Finder 右键扩展：`AirGuardFinderExtension/FinderSync.swift`

当前 Finder 扩展已经可以被系统注册、启用和加载。实际右键菜单里已实现的动作包括：

- `新建文件`
- `拷贝路径`
- `拷贝名称`

配置页当前提供了更完整的预览和配置模型，包括菜单项开关、排序、文件模板、常用目录、AirDrop、显示隐藏等，但这些配置尚未全部同步到 Finder 扩展运行时。也就是说，UI 侧的“超级右键”配置能力比实际 Finder 扩展实现更完整，后续还需要接入共享配置和对应动作。

### FinderSync 扩展结构

Finder 扩展 target 为 `AirSentryFinderExtension`，产物嵌入宿主 App：

```text
AirSentry.app
└── Contents
    └── PlugIns
        └── AirSentryFinderExtension.appex
```

关键声明：

```text
NSExtensionPointIdentifier = com.apple.FinderSync
NSExtensionPrincipalClass  = AirSentryFinderExtension.FinderSync
```

扩展 bundle id 使用宿主 bundle id 加小写后缀：

```text
宿主 App:       com.sjzm.airsentry
Finder 扩展:    com.sjzm.airsentry.finderextension
```

不要让打包脚本把宿主 App 和扩展 target 的 `PRODUCT_BUNDLE_IDENTIFIER` 覆盖成同一个值。工程里通过 `AIR_SENTRY_BUNDLE_ID` 作为基础变量：

```text
AirGuard target:                 $(AIR_SENTRY_BUNDLE_ID)
AirSentryFinderExtension target:  $(AIR_SENTRY_BUNDLE_ID).finderextension
```

### 已修复的问题

曾出现过“系统设置里能看到 Finder 扩展，但 Finder 右键没有反应”的问题。实际排查到的关键点如下：

1. `NSExtensionPrincipalClass` 和 Swift 运行时类名需要一致。

   `Info.plist` 中使用 `AirSentryFinderExtension.FinderSync`。如果 Swift 类被写成 `@objc(FinderSync)`，可能导致系统按模块限定名找不到主类。当前做法是移除自定义 `@objc` 名称，让 Swift 默认导出模块限定类名。

2. FinderSync 插件必须 sandbox。

   系统日志中的明确拒绝信息：

   ```text
   rejecting; Ignoring mis-configured plugin at [...AirSentryFinderExtension.appex]: plug-ins must be sandboxed
   ```

   因此 Finder 扩展必须带 `com.apple.security.app-sandbox = true`。当前扩展 entitlement 文件为：

   ```text
   AirGuardFinderExtension/FinderExtension.entitlements
   ```

3. 手工签名时必须给 `.appex` 带上 entitlements。

   `scripts/build-release.sh` 先以 `CODE_SIGNING_ALLOWED=NO` 构建，再手工签名。手工签名如果只签二进制、不带扩展 entitlements，PlugInKit 会拒绝收录扩展。当前脚本会对 `.appex` 使用：

   ```text
   codesign ... --entitlements AirGuardFinderExtension/FinderExtension.entitlements
   ```

4. 旧签名需要先移除再重新签。

   构建产物可能带有 linker/ad-hoc 签名。直接覆盖签名时曾出现 `invalid signature` 或资源封印不完整。当前脚本会先执行：

   ```text
   codesign --remove-signature
   ```

   然后按顺序签名 framework、`.appex`、宿主 App。

5. Finder 扩展回退唤起宿主 App 时不能指定 App 路径。

   曾在右键“新建文件”时看到扩展已启动，但系统日志出现：

   ```text
   kTCCServiceAppleEvents requires entitlement com.apple.security.automation.apple-events
   ```

   根因是 Finder 扩展使用 `NSWorkspace.open(..., withApplicationAt: ...)` 指定宿主 App 打开 `airsentry://finder/new-file` URL。hardened runtime 会把这种调用视为 AppleEvents 自动化访问，而 Finder 扩展没有、也不应该为了这个路径申请 `com.apple.security.automation.apple-events`。

   当前兜底做法是只调用：

   ```text
   NSWorkspace.shared.open(url)
   ```

   让 LaunchServices 根据 URL scheme 把请求交给宿主 App 的 URL handler。这样右键扩展不再触发 AppleEvents TCC 拦截。

6. 右键“新建文件”真正写入由宿主 App 完成。

   Finder 扩展处于 sandbox 内，直接写入目标目录可能失败。当前扩展会把新建文件请求转发给宿主 App，宿主 App 再通过 `FinderNewFileAuthorizationStore` 检查用户授权过的 security-scoped bookmark。

   如果目标目录未授权或授权后仍写入失败，宿主 App 会弹出提示，并提供“打开授权设置”按钮，引导用户进入“工具箱 > 超级右键 > 文件夹授权”添加目标目录或上级目录。

7. Finder 菜单生成阶段和点击阶段不能只依赖扩展实例状态。

   曾出现菜单生成日志已经识别到目标目录，例如 `/Users/zwj/Downloads`，但点击“新建文件”后只蜂鸣，日志显示：

   ```text
   AirSentry Finder extension could not resolve target directory
   ```

   后续细化日志又看到菜单生成时每个子项都成功绑定了 `representedObject`，但点击时 Finder/AppKit 传回来的 `sender.representedObject` 可能变成 `nil`：

   ```text
   AirSentry Finder extension could not read new file menu request object: nil
   ```

   因此 FinderSync 右键菜单不能只依赖 `representedObject` 保存上下文。当前修复是：模板优先从 `representedObject` 读取，取不到时用菜单标题反查；目录优先用点击时的 Finder 状态，取不到时回退到菜单生成阶段保存的目标目录。同时 `.app` 等 package 虽然底层是目录，但右键时按文件处理，目标目录应为其父目录，避免尝试写入 App 包内部。

### Menuist / RightMenu Master 参考结论

`jaywcjlove/rightmenu-master` 仓库不是源码仓库，README 明确说明它只是官网和反馈页，因此不能直接参考内部实现代码。公开文档里能确认的产品策略如下：

- 它也是 Finder 右键菜单增强工具，核心能力包括创建新文件。
- 创建文件依赖“文件夹授权”，并建议在设置里的 `Folder Authorization` 添加目录。
- 文档明确说明 `Full Disk Access` 不能解决 Finder 扩展写文件权限问题，仍需要用户手动选择目录并授予权限。
- 为减少频繁授权，文档建议按需添加根目录。

### RClick 参考结论

`wflixu/RClick` 是 GPL-3.0 开源项目，README 描述的架构是双进程：

- 主 App 管理设置、状态和文件操作。
- FinderSync Extension 只负责渲染菜单项。
- 两个进程通过 `DistributedNotificationCenter` 通信。
- 菜单配置通过共享容器持久化。

RClick 的“新建文件”路径是瘦扩展模式：扩展拿到菜单项点击和 Finder 当前选中项后，发一个 `.newFile` 点击事件给主 App；主 App 收到事件后再根据文件类型、目标目录和模板创建文件。这样可以避免 Finder 扩展自己承担复杂文件写入、模板处理和权限判断。

AirSentry 已按这个思路调整：Finder 扩展不再直接写文件，而是优先通过 `DistributedNotificationCenter` 发送 `AirSentry.Finder.NewFileRequest` 给宿主 App。宿主 App 收到后仍走 `FinderNewFileService`，也就是只在用户授权过的目录下创建文件。如果宿主 App 未运行，扩展再通过 `airsentry://finder/new-file` URL scheme 唤起宿主 App 作为兜底。

### 验证步骤

日常本地验证优先使用脚本构建、安装并刷新 Finder 扩展：

```text
./build.sh --install
```

如果只想刷新当前已安装的 Finder 扩展，不重新构建：

```text
./build.sh --reload-finder-extension
```

如果需要清理 FinderSync 扩展注册残留，使用独立注销脚本：

```text
scripts/unregister-finder-extension.sh
```

只查看会执行哪些注销动作，不实际修改系统注册：

```text
scripts/unregister-finder-extension.sh --dry-run --no-restart-finder
```

这个脚本会注销 `/Applications/AirSentry.app` 内嵌的 `.appex`，并扫描 `pluginkit -m -v -p com.apple.FinderSync` 里同 bundle id 的残留路径，例如 Xcode `DerivedData` 里的 Debug 扩展注册。

脚本会执行以下动作：

- 重新构建 Release 产物。
- 将 App 复制到 `/Applications/AirSentry.app`。
- 注销旧的 Finder 扩展注册。
- 重新注册并启用新的 Finder 扩展。
- 重启 Finder 让右键菜单重新加载。

构建并安装后，可以用以下命令检查系统是否收录 Finder 扩展：

```text
/usr/bin/pluginkit -m -v -p com.apple.FinderSync
```

正常状态应能看到 AirSentry 扩展，并且前缀为 `+`：

```text
+    com.sjzm.airsentry.finderextension(1.1.0)    ...    /Applications/AirSentry.app/Contents/PlugIns/AirSentryFinderExtension.appex
```

如需手工排查，也可以单独启用扩展：

```text
/usr/bin/pluginkit -e use -i com.sjzm.airsentry.finderextension
```

手工重启 Finder 让右键菜单重新加载：

```text
killall Finder
```

确认扩展是否被 Finder 启动：

```text
/usr/bin/log show --style compact --last 2m --predicate "eventMessage CONTAINS 'AirSentry Finder extension' OR process CONTAINS 'AirSentryFinderExtension'"
```

如果日志里出现 `AirSentryFinderExtension` launched，说明系统注册、启用、加载链路已经打通。

右键“新建文件”蜂鸣时，优先看更窄的链路日志：

```text
/usr/bin/log show --info --style compact --last 5m --predicate "subsystem == 'com.sjzm.airsentry.finderextension' OR eventMessage CONTAINS 'AirSentry Finder extension' OR eventMessage CONTAINS 'AirSentry handling Finder new file request' OR eventMessage CONTAINS 'AirSentry Finder new file' OR eventMessage CONTAINS 'AirSentry failed to create Finder file' OR eventMessage CONTAINS 'AirSentry received malformed Finder new file notification'"
```

典型判断：

- 只有 `requested menu` / `menu target directory`，没有 `create requested`：点击 action 没拿到目标目录或菜单项状态。
- 有 `create requested`，没有 `AirSentry handling Finder new file request`：扩展到宿主 App 的通信失败。
- 有 `target is not authorized`：目标目录没有在工具箱里授权，主 App 应弹窗引导打开“超级右键 > 文件夹授权”。
- 有 `authorization matched` 但仍失败：检查目标路径是否可写、文件名是否非法或目标卷是否只读，主 App 应提示重新授权或检查目录写权限。

### 后续待办

后续需要把 App 内配置页和 Finder 扩展运行时接起来：

- 将 `SuperRightClickStore` 的菜单项、排序、文件模板写入 App Group 或其他扩展可读的共享配置。
- Finder 扩展按共享配置动态生成菜单，而不是硬编码菜单。
- 实现常用目录、AirDrop、显示隐藏等动作。
- 根据 `showsFinderIcon` 决定菜单呈现方式。
- 给 Finder 扩展动作补充失败提示和日志，便于排查沙盒权限、文件写入权限和系统服务调用问题。

## 刷新与数据流

核心刷新由 `MonitorStore` 负责：

```text
AppSettings
AlertManager
    |
    v
MonitorStore.refresh()
    |
    +-- ThermalReader.read()
    +-- CPUReader.readUsage()
    +-- MemoryReader.read()
    +-- NetworkReader.readSpeed()
    |
    +-- 生成 SystemSnapshot
    +-- 写入 CPU/网络历史
    +-- 必要时刷新高 CPU 进程
    +-- AlertManager.handle()
```

刷新定时器由 `settings.refreshInterval` 控制，最小间隔为 1 秒。阈值变化后会触发一次即时刷新，让 UI 和通知判断尽快同步。

## 数据模型

### SystemSnapshot

`SystemSnapshot` 是单次采样结果：

- `thermal: ThermalStatus`
- `cpuUsage: Double`
- `memory: MemoryInfo`
- `network: NetworkSpeed`
- `capturedAt: Date`

### ThermalStatus

- `level: ThermalLevel`
- `temperatureCelsius: Double?`

### ThermalLevel

支持状态：

- `nominal`：正常
- `fair`：偏热
- `serious`：高温
- `critical`：严重高温
- `unknown`：未知

每个状态包含展示标题、短标题、SF Symbol 名称和严重等级。

### MemoryInfo

- `totalBytes`
- `usedBytes`
- `freeBytes`
- `pressureLevel`
- `usageRatio`

### NetworkSpeed

- `uploadBytesPerSecond`
- `downloadBytesPerSecond`

### TopCPUProcess

- `pid`
- `cpuPercent`
- `name`

## 格式化工具

### ByteFormatter

用于格式化内存容量和网络速度：

- `string(from:)`
- `speedString(from:)`

使用二进制单位，允许 KB、MB、GB。

### DateFormatterUtil

用于格式化时间字符串：

```text
HH:mm:ss
```

当前代码中已定义，但暂未在主要 UI 中使用。

## 已知限制

1. 首次 CPU 和网络采样需要上一帧数据，因此首次显示可能为 `0`。
2. 真实温度依赖 SMC 或 HID 传感器，不同 Mac 型号可能不可用。
3. 网络速率累计所有非回环接口，未区分 Wi-Fi、有线、虚拟网卡等接口。
4. 高 CPU 进程读取依赖 `/bin/ps`，进程名来自命令路径末尾。
5. 通知冷却按热状态等级去重，不区分温度具体数值。
6. 内存压力等级依赖系统内存压力事件，刚启动时默认为正常。

## 后续建议

1. 在 UI 中显示真实温度来源，例如 `HID`、`SMC CPU`、`SMC fallback`。
2. 为网络读取增加接口过滤或按接口展示。
3. 给高 CPU 进程提示增加“打开活动监视器并搜索进程”的后续动作。
4. 为设置项和 reader 增加单元测试，尤其是阈值递增规则、通知冷却和格式化输出。
5. 将采样历史抽成通用结构，减少 CPU/网络历史维护的重复逻辑。
