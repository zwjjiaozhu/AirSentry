# 鼠标滚动方向 Wiki

## 背景

macOS 的「自然滚动」同时影响触控板和鼠标。很多用户希望触控板保持自然滚动，但传统鼠标滚轮使用相反方向。Mos 的思路是接管鼠标滚轮事件，并提供独立的滚动设置；AirSentry 当前实现聚焦其中最核心的能力：在工具箱中单独反转鼠标滚轮方向。

## 参考软件

- Mos: https://github.com/Caldis/Mos
  - 提供平滑滚动、垂直/水平轴向独立设置、按应用配置、鼠标按键绑定等功能。
  - 需要辅助功能权限来读取和改写滚动事件。
  - 当前许可证为 CC BY-NC 4.0，因此 AirSentry 只参考产品思路，代码按项目架构重新实现。
- Scroll Reverser: https://github.com/pilotmoon/Scroll-Reverser
  - 使用 CoreGraphics event tap 监听滚动事件。
  - 通过事件特征区分鼠标与触控板，再按设置修改滚动 delta。

## 功能入口

入口位于：

工具箱 -> 系统与辅助 -> 鼠标滚动

页面包含：

- 总开关：启用或关闭鼠标滚动方向接管。
- 辅助功能权限状态：提示用户前往系统设置授权。
- 反转垂直滚动：交换鼠标滚轮上下方向。
- 反转水平滚动：交换支持横向滚动设备的左右方向。
- 实现策略说明：当前只处理非连续滚轮事件，触控板与 Magic Mouse 的连续滚动不改写。

## 实现位置

- `AirGuard/MouseScroll/MouseScrollDirectionManager.swift`
  - 创建 `CGEvent.tapCreate` event tap。
  - 监听 `CGEventType.scrollWheel`。
  - 只处理 `scrollWheelEventIsContinuous == 0` 的事件，避免影响触控板和 Magic Mouse。
  - 根据设置反转垂直或水平滚动字段。
  - event tap 被系统禁用时自动重新启用。
- `AirGuard/Core/AppSettings.swift`
  - `mouseScrollDirectionReversed`
  - `mouseScrollReversesVertical`
  - `mouseScrollReversesHorizontal`
- `AirGuard/AirGuardApp.swift`
  - 创建 `MouseScrollDirectionManager`，随应用生命周期常驻。
- `AirGuard/Views/ToolboxView.swift`
  - 新增工具箱侧边栏入口和设置页面。

## 事件改写字段

垂直方向：

- `scrollWheelEventDeltaAxis1`
- `scrollWheelEventPointDeltaAxis1`
- `scrollWheelEventFixedPtDeltaAxis1`

水平方向：

- `scrollWheelEventDeltaAxis2`
- `scrollWheelEventPointDeltaAxis2`
- `scrollWheelEventFixedPtDeltaAxis2`

同时改写普通 delta、point delta 和 fixed point delta，可以覆盖传统滚轮在不同应用里的读取路径。

## 权限

该功能需要辅助功能权限：

系统设置 -> 隐私与安全性 -> 辅助功能 -> AirSentry

原因是 active event tap 会读取并改写全局输入事件。没有权限时，event tap 创建会失败，工具箱页面会引导用户授权。

## 当前边界

- 当前不会做 Mos 的平滑滚动插值，只做方向反转。
- 当前不会处理连续滚动事件，避免影响触控板和 Magic Mouse。
- 当前还没有按应用配置，所有传统鼠标滚轮事件使用全局设置。
- 当前没有设备级白名单或黑名单。

## 后续扩展

可以沿着 Mos 的能力继续扩展：

- 平滑滚动：把离散滚轮步进转换为定时动画滚动。
- 速度增益：按用户设置放大或缩小滚动距离。
- 持续时间：控制平滑滚动动画的衰减时间。
- 按应用规则：为不同应用保存独立的滚动方向和平滑设置。
- 功能键：按住指定修饰键时临时切换方向或禁用接管。
- 设备识别：结合 IOKit/HID 信息区分具体鼠标设备。

## 验证

已通过：

```bash
./build.sh
```

构建产物：

```text
build/Release/AirSentry.app
```
