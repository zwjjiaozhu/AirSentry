# 超级右键 - 打开终端功能

## 功能概述

在 Finder 右键菜单的"超级右键"中添加"打开终端"功能，点击后自动打开 Terminal.app 并切换到当前目录。

## 架构设计

由于 Finder 扩展运行在独立的沙箱 XPC 进程中，无法直接启动其他应用，因此采用**主应用转发**的架构：

```
Finder 右键 → "AirSentry" → "打开终端"
      ↓
Finder 扩展发送分布式通知 (主应用运行时)
或 URL Scheme (主应用未运行时)
      ↓
主应用接收请求 → 通过 AppleScript 打开 Terminal
      ↓
Terminal.app 启动并 cd 到目标目录
```

## 文件清单

| 文件 | 作用 |
|------|------|
| `AirGuardFinderExtension/FinderSync.swift` | Finder 扩展入口，构建右键菜单 |
| `AirGuardFinderExtension/SuperRightClickSharedConfig.swift` | 共享配置模型（Finder 扩展端） |
| `AirGuard/Core/SuperRightClickSharedConfig.swift` | 共享配置模型（主应用端） |
| `AirGuard/AirGuardApp.swift` | 主应用入口，处理 Finder 转发请求 |
| `AirGuard/Views/ToolboxView.swift` | 工具箱设置界面，配置菜单项 |

## 设置同步机制

### App Group 配置

Finder 扩展与主应用通过 **App Group** 共享 UserDefaults 实现设置同步：

- **App Group 名称**: `group.com.sjzm.airsentry`
- **存储 Key**: `superRightClickSharedConfig`

### 同步流程

1. 用户在工具箱"超级右键"设置中修改配置
2. `SuperRightClickStore` 将配置写入共享 UserDefaults
3. Finder 扩展在显示菜单时读取共享配置
4. 根据启用的菜单项动态构建右键菜单

### 配置数据结构

```swift
struct SuperRightClickSharedConfig: Codable {
    let enabledMenuItemIDs: [String]     // 启用的菜单项 ID 列表
    let enabledTemplateIDs: [String]     // 启用的文件模板 ID 列表
    let templates: [TemplateConfig]      // 文件模板详情
}
```

## 菜单项配置

### 支持的菜单项

| ID | 名称 | 说明 |
|----|------|------|
| `newFile` | 新建文件 | 展开文件模板子菜单 |
| `openTerminal` | 打开终端 | 在当前目录启动 Terminal |
| `copyPath` | 拷贝路径 | 复制完整文件路径 |
| `copyName` | 拷贝名称 | 复制文件名 |

### 默认启用项

当共享配置不可用时，Finder 扩展使用以下默认配置：
- 新建文件 ✅
- 打开终端 ✅
- 拷贝路径 ✅
- 拷贝名称 ✅

## 开发者配置步骤

### 1. Apple Developer 账户配置

#### 注册 Bundle ID

在 [Apple Developer](https://developer.apple.com/account) 中注册两个 App ID：

| App ID | Bundle ID | Capabilities |
|--------|-----------|--------------|
| AirSentry | `com.sjzm.airsentry` | App Groups |
| AirSentry Finder Extension | `com.sjzm.airsentry.finderextension` | App Groups |

#### 配置 App Group

1. 进入 **Identifiers** → 点击 **+**
2. 选择 **App Groups** → Continue
3. 填写 Group ID: `group.com.sjzm.airsentry`
4. 将两个 App ID 都关联到这个 App Group

### 2. Xcode 项目配置

#### 主应用 Target

1. 选择 **AirGuard** Target
2. **Signing & Capabilities** → **+ App Groups**
3. 勾选 `group.com.sjzm.airsentry`

#### Finder 扩展 Target

1. 选择 **AirSentryFinderExtension** Target
2. **Signing & Capabilities** → **+ App Groups**
3. 勾选 `group.com.sjzm.airsentry`

### 3. 构建与测试

1. **先运行主应用** - 让设置界面写入共享配置
2. **在 Finder 中右键测试** - 检查菜单项是否正确显示
3. **修改设置后重新右键** - 验证设置同步生效

## 常见问题

### Q: 右键菜单中没有显示所有配置项？

**A:** 检查以下几点：
1. App Group 是否在开发者网站正确注册
2. 两个 Target 是否都配置了相同的 App Group
3. 是否先运行过主应用（让配置写入共享存储）

### Q: 点击"打开终端"没有反应？

**A:** 打开终端功能依赖主应用运行：
- 如果主应用未运行，会通过 URL Scheme 启动主应用后再处理
- 检查主应用的 AppleScript 权限（Automation → Terminal）

### Q: App Store 版本提示权限错误？

**A:** App Store 版本需要以下 entitlement：
- `com.apple.security.temporary-exception.apple-events` (允许控制 Terminal.app)
- `com.apple.security.application-groups` (允许共享配置)

## 相关 Entitlements

### AppStore.entitlements

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.sjzm.airsentry</string>
</array>
<key>com.apple.security.temporary-exception.apple-events</key>
<array>
    <string>com.apple.Terminal</string>
</array>
```

### FinderExtension.entitlements

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.sjzm.airsentry</string>
</array>
```

## 扩展功能

如需添加更多右键菜单功能，参考以下模式：

1. 在 `SuperRightClickStore.defaultMenuItems` 中定义菜单项
2. 在 `SuperRightClickSharedConfig` 中同步配置
3. 在 `FinderSync.menu(for:)` 中根据 `enabledMenuItemIDs` 动态显示
4. 如需主应用处理，添加分布式通知和 URL Scheme 处理逻辑
