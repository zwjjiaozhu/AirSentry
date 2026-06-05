# AirSentry 温度读取 Wiki

## 背景

AirSentry 的核心目标是给 MacBook Air 提供高温提醒。macOS 没有公开稳定的 API 直接返回 CPU 温度，所以第一版采用分层读取：

1. 优先读取真实温度。
2. 真实温度不可用时，继续使用 `ProcessInfo.processInfo.thermalState` 作为官方热状态。
3. UI 必须能区分“温度不可用”和“系统热状态正常/偏热/严重”。

## 当前读取链路

代码入口：

- `AirGuard/Readers/ThermalReader.swift`
- `AirGuard/Readers/HIDTemperatureReader.m`
- `AirGuard/Readers/HIDTemperatureReader.h`
- `AirGuard/AirGuard-Bridging-Header.h`

读取顺序：

```text
ProcessInfo thermalState
preferred temperature source
else SMC CPU temperature keys
else SMC fallback temperature keys
else HID Apple Silicon temperature sensors
最终生成 ThermalStatus
```

说明：

- `thermalState` 始终读取，用于官方热状态判断。
- SMC 读取失败不会影响热状态显示。
- HID 是当前机器上已经验证成功的真实温度来源。
- 每次 App 运行会先做一次来源验证，成功后写入本次运行的内存缓存，后续刷新只走该来源。
- 已经命中的真实温度来源会写入 `UserDefaults.temperaturePreferredSource`，作为下次启动时优先验证的候选来源。
- 当前机器首次启动默认候选 HID，因为已确认 `PMU tdie*` 可读。
- 如果首选来源某次读取失败，会清空偏好并重新进入探测链路。

## SMC 方案

SMC 路线通过 `AppleSMC` 服务读取传感器 key。

主要流程：

1. `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))`
2. `IOServiceOpen`
3. 读取 key info
4. 读取 bytes
5. 按 `sp78` / `fp78` / `flt ` 解码为摄氏温度

当前会尝试两组 key：

- CPU keys：Intel 与 Apple Silicon 多代 CPU/core/proximity key。
- fallback keys：主板、NAND、电池、airflow 等系统温度 key。

当前实测：

```text
AirSentry temperature SMC CPU: no readable keys
AirSentry temperature SMC CPU: no readable keys, trying fallback keys
AirSentry temperature SMC fallback: no readable keys
```

结论：这台机器上 SMC 可打开，但温度 key 不可读。

## HID 方案

HID 路线参考了 Stats 的 Apple Silicon sensors 读取方式。

Objective-C bridge：

```objc
NSDictionary<NSString *, NSNumber *> *AirSentryAppleSiliconSensors(int32_t page, int32_t usage, int32_t type);
```

匹配参数：

```text
PrimaryUsagePage = 0xff00
PrimaryUsage     = 5
temperature type = 15
```

读取流程：

1. `IOHIDEventSystemClientCreate`
2. `IOHIDEventSystemClientSetMatching`
3. `IOHIDEventSystemClientCopyServices`
4. 从每个 service 读取 `Product`
5. `IOHIDServiceClientCopyEvent`
6. `IOHIDEventGetFloatValue`
7. Swift 侧筛选合理温度范围 `15...125`
8. 优先筛选 CPU/SOC/PMU 相关名字
9. 多个读数取平均值

当前实测成功日志：

```text
AirSentry temperature HID hits: PMU tdie1=37.73°C, PMU tdie10=38.05°C, PMU tdie11=38.13°C, PMU tdie12=38.45°C, PMU tdie13=37.89°C, PMU tdie14=38.29°C, PMU tdie2=37.49°C, PMU tdie3=37.65°C, PMU tdie4=37.73°C, PMU tdie5=38.29°C, PMU tdie6=38.85°C, PMU tdie7=38.61°C, PMU tdie8=39.17°C, PMU tdie9=37.25°C; average=38.11°C
AirSentry temperature selected: 38.11°C, thermalState=正常
```

结论：这台机器上真实温度来源为 HID `PMU tdie*` 传感器。

## 与 Stats 的关系

参考项目：

- https://github.com/exelban/stats
- https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift
- https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift
- https://github.com/exelban/stats/blob/master/Modules/Sensors/reader.m
- https://github.com/exelban/stats/blob/master/Modules/Sensors/bridge.h

Stats 的做法：

- 维护大量 SMC sensor key。
- 对 Apple Silicon 使用 HID sensors 作为重要补充。
- 按传感器名字和类型分组。
- CPU、GPU、SOC 等可能有多个传感器，展示时可取平均。

AirSentry 当前只移植 MVP 需要的温度读取部分：

- SMC 多 key 尝试。
- HID 温度字典读取。
- CPU/SOC/PMU 名称筛选。
- 多读数平均。

未移植内容：

- Stats 完整传感器列表 UI。
- 电压/功率/风扇/能耗传感器。
- Stats 的完整 reader/store 架构。
- 按芯片型号精细区分传感器平台。

## 日志排查

搜索关键字：

```text
AirSentry temperature
```

典型日志含义：

```text
AirSentry temperature SMC: AppleSMC service unavailable
```

SMC 服务不可用。

```text
AirSentry temperature SMC CPU hits: ...
```

SMC CPU key 命中。

```text
AirSentry temperature SMC fallback hits: ...
```

SMC fallback key 命中。

```text
AirSentry temperature HID hits: ...
```

HID 温度传感器命中。

```text
AirSentry temperature selected: 38.11°C, source=hid, thermalState=正常
```

最终选中的真实温度和来源。

```text
AirSentry temperature preferred source failed: hid
```

上次保存的首选来源读取失败，会清空偏好并重新探测。

```text
AirSentry temperature runtime source failed: hid
```

本次运行内存缓存的来源读取失败，会清空运行态与持久化偏好并重新探测。

```text
AirSentry temperature unavailable, thermalState=正常
```

真实温度读取失败，但官方热状态仍可用。

## 当前策略

当前温度显示采用：

```text
runtime source average
else persisted source average
else SMC CPU average
else SMC fallback average
else HID selected average
else nil
```

偏好来源规则：

```text
UserDefaults.temperaturePreferredSource = hid | smcCPU | smcFallback | none
```

- 没有历史值时默认 `.hid`，避免在已验证的 MacBook Air 上重复尝试不可读的 SMC keys。
- 每次 App 运行第一次读取温度时，会验证候选来源。
- 成功读取后保存到本次运行内存缓存，并更新 `UserDefaults`。
- 本次运行后续刷新只读取内存缓存中的来源。
- 首选来源失败时写入 `none`，本次继续走完整探测链路。
- 如果完整探测链路也失败，本次运行会记为不可用，后续刷新不再重复探测。
- 完整探测链路命中新来源后，会再次保存该来源。

其中 HID selected average 会优先选择名称包含以下标记的传感器：

```text
pACC
eACC
CPU
SOC
PMGR SOC Die
PMU tdie
```

如果没有匹配项，则使用所有合理温度传感器平均值。

## 后续建议

1. 将诊断日志改为设置项开关，避免正式版持续刷日志。
2. 在 `ThermalStatus` 中记录温度来源，例如 `smcCPU`、`smcFallback`、`hid`、`unavailable`。
3. UI 可在温度旁显示来源：`HID` 或 `SMC`。
4. 对不同芯片型号维护更精细的优先级，例如 M1/M2/M3/M4/M5。
5. 高温提醒仍应优先结合官方 `thermalState`，真实温度作为辅助指标。
