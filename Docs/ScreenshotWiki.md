# AirSentry 截图功能 Wiki

## 背景

AirSentry 的截图功能对标 Snipaste，提供区域截图、窗口智能识别、画面定格、标注工具和钉图能力。用户通过全局快捷键触发截图，屏幕画面瞬间定格，在定格画面上框选区域或点击窗口完成捕获。

核心设计目标：

- **画面定格**：截图触发瞬间冻结屏幕画面，用户在静态画面上从容框选，不再受动态刷新干扰。
- **窗口智能识别**：鼠标悬停时高亮窗口轮廓，点击直接捕获窗口；被遮挡的窗口不参与候选。
- **混合检测**：不仅识别系统窗口，还通过图像分析识别弹窗、面板等非标准窗口区域。
- **非阻塞体验**：截图 Overlay 立即弹出，视觉轮廓检测在后台异步计算，不阻塞用户操作。

## 代码结构

```
AirGuard/Screenshot/
├── ScreenshotCaptureController.swift   # 截图入口、画面捕获、标注渲染、结果输出
├── ScreenshotOverlayController.swift    # Overlay 窗口、交互视图、检测器、融合器（核心）
├── ScreenshotShortcutManager.swift     # 全局快捷键注册
├── ScreenshotResultPanel.swift         # 截图结果浮窗（复制/保存/钉图）
└── PinnedImageController.swift          # 钉图窗口管理
```

### 核心类型

| 类型 | 文件 | 职责 |
| --- | --- | --- |
| `ScreenshotCaptureController` | ScreenshotCaptureController.swift | 截图入口，协调权限检查、Overlay 启动和结果处理 |
| `ScreenshotOverlayController` | ScreenshotOverlayController.swift | 管理 Overlay 窗口的生命周期和分层渲染 |
| `ScreenshotOverlayWindow` | ScreenshotOverlayController.swift | 截图覆盖窗口（NSPanel 子类） |
| `ScreenshotOverlayView` | ScreenshotOverlayController.swift | SwiftUI 交互视图：选区、遮罩、标注、工具栏 |
| `ScreenshotImageCapturer` | ScreenshotCaptureController.swift | 通过 CGWindowListCreateImage 捕获屏幕画面 |
| `ScreenshotWindowTargetDetector` | ScreenshotOverlayController.swift | 从 CGWindowList 提取窗口候选并过滤遮挡 |
| `ScreenshotVisualTargetDetector` | ScreenshotOverlayController.swift | 基于截图画面的视觉轮廓检测（灰度边缘+矩形候选） |
| `ScreenshotTargetFusion` | ScreenshotOverlayController.swift | 融合窗口候选与视觉候选，去重排序 |
| `ScreenshotCaptureTarget` | ScreenshotOverlayController.swift | 捕获目标模型（window/contour 两种类型） |
| `ScreenshotSelectionToolbar` | ScreenshotOverlayController.swift | 标注工具栏（画笔、箭头、矩形、文字、马赛克） |
| `ScreenshotAnnotationRenderer` | ScreenshotCaptureController.swift | 将标注渲染到最终输出图像 |
| `PinnedImageController` | PinnedImageController.swift | 钉图窗口的创建与管理 |

## 架构设计

### 整体流程

```text
快捷键触发
    │
    ▼
ScreenshotCaptureController.startCapture()
    │
    ├─ 权限检查 (CGPreflightScreenCaptureAccess)
    │
    ▼
ScreenshotOverlayController.show()
    │
    ├─ 1. 对每个 NSScreen：
    │     ├─ ScreenshotImageCapturer.capture()  ← 捕获定格帧（Overlay 显示前）
    │     ├─ ScreenshotWindowTargetDetector    ← 同步提取窗口候选
    │     ├─ 创建容器 NSView
    │     │   ├─ NSImageView（定格背景层）
    │     │   └─ NSHostingView（SwiftUI 交互层）
    │     └─ window.contentView = container
    │
    ├─ 2. layoutSubtreeIfNeeded()  ← 强制提前完成布局
    │
    ├─ 3. NSAnimationContext 禁用动画后 orderFrontRegardless
    │
    ▼
ScreenshotOverlayView.onAppear
    │
    ├─ startVisualTargetDetection()  ← 后台异步视觉轮廓检测
    │
    ▼
用户框选/点击窗口
    │
    ▼
perform(action, payload)
    │
    ├─ closeWindows()           ← 关闭 Overlay
    ├─ ScreenshotImageCapturer   ← 按选区捕获最终图像
    ├─ ScreenshotAnnotationRenderer ← 渲染标注
    └─ 输出：钉图 / 复制 / 保存
```

### 画面定格机制

这是截图功能最核心也最易出问题的环节。目标是让用户在截图触发瞬间看到一帧"冻结"的静态画面，在其上从容框选。

#### 定格帧捕获

在 `show()` 方法中，Overlay 窗口显示**之前**就调用 `ScreenshotImageCapturer.capture(rect: screen.frame)` 捕获全屏画面。由于此时 Overlay 窗口尚未 `orderFront`，定格帧是干净的屏幕快照，不含 Overlay 自身。

```swift
// ScreenshotCaptureController.swift
enum ScreenshotImageCapturer {
    static func capture(rect: CGRect) -> NSImage? {
        let quartzRect = convertToQuartzScreenRect(normalizedRect)
        guard let cgImage = CGWindowListCreateImage(
            quartzRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else { return nil }
        return NSImage(cgImage: cgImage, size: normalizedRect.size)
    }
}
```

#### 分层渲染

参考 Mio 开源项目的设计，定格画面不在 SwiftUI 视图树内渲染，而是作为 NSHostingView 下方的独立背景层：

```text
NSPanel（透明窗口）
  └─ NSView（容器）
       ├─ NSImageView（定格背景层 — 直接用 draw 渲染）
       └─ NSHostingView（交互层 — 透明，只有遮罩/选区/标注）
```

- **NSImageView** 用传统 `draw` 方式渲染定格画面，不经过 SwiftUI 布局系统，窗口显示时画面立即定格。
- **NSHostingView** 在上层透明，SwiftUI 只负责交互（半透明遮罩、选区挖洞、标注工具栏），透过半透明遮罩能看到下方 NSImageView 的定格帧。
- 选区通过 `SelectionShape`（eoFill 填充）在遮罩上"挖洞"，洞内透明，直接看到 NSImageView 的原始定格画面（无暗化）。

#### 缩放消除（四层组合）

画面定格后出现"缩放再变灰"的现象，根因是 macOS 窗口出现动画 + NSHostingView 首次布局异步过渡叠加。单一手段无法消除，必须四个层面同时处理：

```swift
// 1. 禁用窗口出现动画
final class ScreenshotOverlayWindow: NSPanel {
    init(screen: NSScreen) {
        // ...
        self.animationBehavior = .none  // ← 禁用 macOS 窗口 orderFront 的系统缩放动画
    }
}

// 2. 显示前强制完成布局
// 3. NSAnimationContext 禁用隐式动画
// 4. makeKey() 替代 makeKeyAndOrderFront
func show() {
    // ...
    windows.forEach { window in
        window.contentView?.layoutSubtreeIfNeeded()  // ← 强制 NSHostingView 提前布局
    }

    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        context.allowsImplicitAnimation = false
        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKey()  // ← 不激活应用，避免触发额外窗口动画
    }
}
```

| 层面 | 手段 | 解决的问题 |
| --- | --- | --- |
| 窗口动画 | `animationBehavior = .none` | macOS 对窗口 orderFront 的系统缩放效果 |
| 布局时序 | `layoutSubtreeIfNeeded()` | NSHostingView 首次布局从 .zero 到全屏的异步过渡 |
| 隐式动画 | `NSAnimationContext` duration=0 | 上述操作过程中的 Core Animation 隐式动画 |
| 应用激活 | `makeKey()` 替代 `makeKeyAndOrderFront` | 激活应用触发额外的窗口管理动画 |

### 窗口高亮与层级规则

#### 遮挡过滤

`ScreenshotWindowTargetDetector.targets(on:)` 遍历 `CGWindowListCopyWindowInfo` 获取窗口列表，按 Z-order（layer 值）从前到后处理。维护 `frontWindowRects` 数组记录所有前层窗口的可见矩形，每个窗口从中"减去"被前层遮挡的部分，得到剩余可见区域碎片。

```swift
let visibleRects = visibleRects(for: clippedGlobalRect, occludedBy: frontWindowRects)
let visibleArea = visibleRects.reduce(CGFloat.zero) { $0 + $1.width * $1.height }
let totalArea = clippedGlobalRect.width * clippedGlobalRect.height

// 可见面积低于 8% 或绝对值低于 1200px² 的窗口被过滤
guard visibleArea >= max(1_200, totalArea * 0.08) else { continue }
```

辅助方法 `visibleRects(for:occludedBy:)` 和 `subtract(_:from:)` 实现矩形减法，将一个矩形从前层窗口的并集中减去，返回剩余的可见碎片数组。

#### 命中排序

`captureTarget(at:)` 在鼠标命中的多个候选中排序选择：

1. **优先 Z-order**：`priority` 值大的（前层窗口）优先
2. **其次面积**：同 priority 时小面积优先（更精准的窗口命中）

### 混合检测架构

CGWindowList 只能识别注册了窗口的系统应用，无法识别部分弹窗、面板、卡片等非标准 UI 区域。为对标 Snipaste 的"先截屏再分析"体验，采用混合检测：

#### 同步阶段（Overlay 弹出前）

- `ScreenshotImageCapturer` 捕获屏幕定格帧
- `ScreenshotWindowTargetDetector` 提取 CGWindowList 窗口候选（含遮挡过滤）

这两个操作在 `show()` 中同步完成，保证 Overlay 立即弹出、用户可立即选择窗口。

#### 异步阶段（Overlay 弹出后）

`ScreenshotOverlayView.onAppear` 触发 `startVisualTargetDetection()`，在 `DispatchQueue.global(qos: .utility)` 上执行视觉轮廓检测：

1. **灰度转换**：将 NSImage 转为灰度网格（`ScreenshotVisualBitmap`）
2. **边缘检测**：相邻像素差值超过阈值处标记为水平/垂直边缘
3. **线段提取**：将连续的同方向边缘像素合并为线段（`ScreenshotVisualLineSegment`）
4. **矩形候选**：将水平线段两两配对，验证垂直边覆盖度后生成矩形候选（`ScreenshotVisualCandidate`）
5. **去重**：IoU 阈值过滤重叠候选，与已有窗口目标去重

检测完成后回主线程写入 `visualCaptureTargets`，通过 `mergedCaptureTargets` 计算属性与窗口候选动态融合。

#### 候选融合

`ScreenshotTargetFusion.merge(windowTargets:visualTargets:)` 负责合并两类候选：

- 视觉轮廓（`.contour`）优先于包含它的宿主窗口（`.window`）：当轮廓面积 < 宿主窗口 72% 且被宿主窗口包含时，轮廓优先
- 最终列表中窗口和轮廓共存，用户鼠标悬停时均可命中

## 选区与标注

### 选区遮罩

`SelectionShape` 是一个 SwiftUI `Shape`，用 eoFill（奇偶填充）在全屏矩形中挖出选区：

```swift
private struct SelectionShape: Shape {
    let selection: CGRect
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)        // 全屏
        path.addRect(selection)   // 选区（被挖空）
        return path
    }
}
```

配合 `.fill(style: FillStyle(eoFill: true))` 和 `Color.black.opacity(0.34)`，选区外暗化、选区内透明（透过 NSImageView 看到原始定格画面）。

### 标注工具

`ScreenshotSelectionToolbar` 提供以下工具：

| 工具 | 说明 |
| --- | --- |
| 画笔 | 自由绘制路径 |
| 箭头 | 带箭头的直线 |
| 矩形 | 描边矩形 |
| 椭圆 | 描边椭圆 |
| 文字 | 可编辑文本标注，支持字体、颜色、粗细、斜体 |
| 马赛克 | 像素化遮罩，基于定格帧采样 |

标注通过 `ScreenshotAnnotationRenderer.render()` 在最终输出图像上渲染，使用 `ScreenshotMosaicSampler` 从定格帧采样像素生成马赛克。

## 踩坑记录

### 1. 截图时内容动态刷新

**现象**：截图 Overlay 弹出后，底层窗口内容仍在实时刷新（如视频播放、动画），影响框选体验。

**根因**：Overlay 窗口透明（`backgroundColor = .clear`），只盖了半透明遮罩，未渲染定格画面。

**解决**：在窗口显示前捕获定格帧，用 NSImageView 作为不透明背景层全屏渲染。

### 2. 定格画面缩放过渡

**现象**：截图后全屏画面先缩放一下再变灰，体验不流畅。

**排查过程**：

| 尝试 | 结果 |
| --- | --- |
| SwiftUI `Image.resizable().aspectRatio(.fill)` | 缩放 — Image 首次渲染有布局过渡 |
| `NSViewRepresentable` + `CALayer.contents` | 缩放 — CALayer bounds 隐式动画 |
| `CALayer.actions` 字典禁用隐式动画 | 缩放 — `actions` 对 NSHostingView 布局驱动的 frame 变化无效 |
| NSImageView 分层渲染（参考 Mio） | 部分改善 — 定格画面不再缩放，但窗口本身仍有出现动画 |
| `animationBehavior = .none` + `layoutSubtreeIfNeeded()` + `NSAnimationContext` + `makeKey()` | 彻底解决 |

**根因**：macOS 窗口出现动画（`orderFront` 的系统缩放效果）+ NSHostingView 首次布局异步过渡（frame 从 `.zero` 到全屏）两个因素叠加。单一手段无法消除，必须窗口、布局、动画三个维度同时处理。

### 3. 被遮挡窗口仍显示高亮

**现象**：被其他窗口完全遮挡的窗口仍被高亮，鼠标在重叠区域命中了底层窗口而非前层窗口。

**根因**：`captureTarget(at:)` 按"优先小窗口"排序，小窗口可能被大窗口包含；`ScreenshotWindowTargetDetector` 未过滤被遮挡的窗口。

**解决**：按 Z-order 遍历窗口，维护前层窗口矩形并集，计算每个窗口的可见面积碎片，过滤可见面积过小的窗口。命中排序改为优先 Z-order。

### 4. 视觉轮廓检测阻塞 Overlay 弹出

**现象**：点击截图快捷键后卡顿一下，Overlay 才出现。

**根因**：视觉轮廓检测在 `show()` 中同步执行，阻塞了 Overlay 显示。

**解决**：将视觉检测移至 `ScreenshotOverlayView.onAppear` 后的后台 `utility` 队列异步执行，完成后回主线程更新状态，与窗口候选动态融合。

## 参考项目

### Mio

- **仓库**：https://github.com/iSoldLeo/Mio
- **借鉴点**：画面定格的分层渲染思路。Mio 的 `SelectionOverlayView` 直接继承 `NSView`，在 `draw(_:)` 中用 Core Graphics 绘制定格画面和遮罩，完全不用 SwiftUI/CALayer 渲染定格背景。本项目借鉴其"定格画面不经过 SwiftUI 布局系统"的思路，采用 NSImageView 作为 NSHostingView 下方的独立背景层。
- **技术栈**：SwiftUI + ScreenCaptureKit，要求 macOS 26+
- **协议**：GPL-3.0

### Pawshot

- **仓库**：https://github.com/nyanko3141592/Pawshot
- **借鉴点**：ScreenCaptureKit 与 CGWindowListCreateImage fallback 的双通道捕获策略；区域截图 + 窗口截图 + 全屏截图的功能划分。
- **技术栈**：SwiftUI + AppKit，ScreenCaptureKit (macOS 14+) with CGWindowListCreateImage fallback
- **协议**：MIT

## snipaste

## pixPin

https://pixpin.cn/