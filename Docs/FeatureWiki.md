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
