# AirSentry App Store 上架流程

## 前置条件

### Apple Developer 账号

- 需要有效的 Apple Developer Program 会员资格。
- 在 [App Store Connect](https://appstoreconnect.apple.com) 中创建 App，获取 Bundle ID。

### 证书与签名

- Xcode 已登录 Apple Developer 账号，能自动管理签名。
- 本地钥匙串中存在有效的 **Apple Distribution** 或 **3rd Party Mac Developer Application** 证书。
- 脚本会自动检测证书；如未找到会提示警告，Xcode 可能通过云端下载托管证书。

验证本地证书：

```bash
security find-identity -v -p codesigning
```

## App Store Connect 创建 App

> **重要**：必须先创建 App 记录，否则脚本上传时会报 `Error Downloading App Information`。

### 第一步：注册 Bundle ID（Identifier）

1. 打开 [Apple Developer Identifiers](https://developer.apple.com/account/resources/identifiers/list)。
2. 点击 **+** 号新建。
3. 选择 **App IDs** → **App**，点击 Continue。
4. 填写：
   - **Description**：`AirSentry`（描述名称，仅自己可见）
   - **Bundle ID**：`com.sjzm.airsentry`（选 Explicit，不能选 Wildcard）
5. 勾选需要的 Capabilities（App Store 上架至少需要 **App Sandbox**）。
6. 点击 Continue → Register。

如果 Finder 扩展签名有问题，同样为 `com.sjzm.airsentry.finderextension` 注册一个 Identifier。Xcode 自动签名通常会自动创建，无需手动操作。

### 第二步：创建 App 记录

1. 打开 [App Store Connect](https://appstoreconnect.apple.com) → **我的 App**。
2. 点击页面左上角 **+** → **新建 App**。
3. 填写创建表单：

   | 字段 | 填写内容 |
   | --- | --- |
   | 平台 | **macOS** |
   | 名称 | `AirSentry` |
   | 主要语言 | 简体中文（或 English） |
   | Bundle ID | 选择 `com.sjzm.airsentry`（第一步注册的） |
   | SKU | `airsentry-001`（内部标识符，用户不可见，随意填写） |
   | 用户访问权限 | 完整访问权限 |

4. 点击 **创建**。

### 第三步：完善 App Store 信息

创建完成后进入 App 详情页面，逐项填写：

**App 信息页：**
- 副标题（可选，简短描述功能）
- 隐私政策 URL（必填，可以填官网或 GitHub 仓库地址）
- 技术支持 URL（必填）
- App 类别：选择 **工具**

**价格与销售范围：**
- 设置价格（免费选 0）
- 选择销售国家和地区

**版本信息：**
- 宣传文本（App Store 页面展示的描述）
- 关键词（逗号分隔，用于搜索优化）
- 支持 URL
- 版权信息：`© 2026 AirSentry`

**App 图标：**
- 上传 1024×1024 的 PNG 图标（不能含 Alpha 通道）

**截图：**
- macOS 需要至少 1 张截图
- 支持尺寸：1280×800、1440×900、2560×1600、2880×1800
- 建议上传 3-5 张，覆盖菜单栏面板、设置页、工具箱等主要功能

### 第四步：验证上传

App 记录创建完成后，再执行上传脚本就不会报错了：

```bash
TEAM_ID="XXXXXXXXXX" BUNDLE_ID="com.sjzm.airsentry" ./scripts/archive-app-store.sh --clean --upload
```

上传成功后，在 App Store Connect 的 App 页面 → **构建版本** 里能看到刚上传的构建，等待 Apple 处理完毕（通常 10-30 分钟）后即可提交审核。

## 工程配置概览

### 双版本 Entitlements

| 版本 | Entitlements 文件 | App Sandbox | 用途 |
| --- | --- | --- | --- |
| App Store | `AirGuard/AppStore.entitlements` | **开启** | 上架 App Store |
| 直接分发 | `AirGuard/DirectDistribution.entitlements` | **关闭** | GitHub Release / 独立下载 |

App Store 版本启用沙盒，权限包括：

- `com.apple.security.app-sandbox` = true
- `com.apple.security.network.server` = true
- `com.apple.security.files.user-selected.read-write` = true
- `com.apple.security.application-groups` = `group.com.sjzm.airsentry`

### 编译条件

App Store 构建会注入编译宏：

```text
SWIFT_ACTIVE_COMPILATION_CONDITIONS = APP_STORE
```

用于在代码中区分 App Store 与直接分发版本的行为差异。

### 排除的源文件

App Store 构建排除以下私有 API 桥接文件：

```text
HIDTemperatureReader.m
ASMediaRemoteBridge.m
MediaRemoteAdapter.framework
```

这些文件依赖私有框架，不符合 App Store 审核指南。

### 版本号

版本号在 `project.pbxproj` 中统一管理：

| 字段 | 当前值 | 说明 |
| --- | --- | --- |
| `MARKETING_VERSION` | `1.2.0` | 用户可见的版本号（CFBundleShortVersionString） |
| `CURRENT_PROJECT_VERSION` | `3` | 构建号（CFBundleVersion） |

每次提交 App Store 审核时，**构建号必须递增**。版本号在创建新版本时更新。

## 构建与上传

### 脚本路径

```text
scripts/archive-app-store.sh
```

### 参数说明

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `TEAM_ID` | 是 | Apple Developer Team ID，可通过环境变量或 `--team-id` 传入 |
| `BUNDLE_ID` | 是 | App Store Connect 注册的 Bundle ID，可通过环境变量或 `--bundle-id` 传入 |
| `--upload` | 否 | 加上后直接上传到 App Store Connect；不加则仅导出本地包 |
| `--clean` | 否 | 清除上次 App Store 构建产物 |

### 本地导出（不上传）

先本地导出验证签名和包结构是否正确：

```bash
TEAM_ID="XXXXXXXXXX" BUNDLE_ID="com.sjzm.airsentry" ./scripts/archive-app-store.sh --clean
```

产物路径：

```text
build/AppStore/Export/
```

### 直接上传

确认本地导出无误后，加上 `--upload` 直接上传：

```bash
TEAM_ID="XXXXXXXXXX" BUNDLE_ID="com.sjzm.airsentry" ./scripts/archive-app-store.sh --clean --upload
```

上传完成后需要到 App Store Connect 查看处理状态。

### 脚本执行流程

```text
1. 校验 TEAM_ID 和 BUNDLE_ID（不允许 com.example 占位符）
2. 检查本地签名证书
3. 可选清理 build/AppStore/ 目录
4. xcodebuild archive
   - scheme: AirGuard
   - configuration: Release
   - destination: generic/platform=macOS
   - 自动签名 + 沙盒 + APP_STORE 编译宏
   - 排除私有 API 桥接文件
5. 复制 ExportOptions.plist 到构建目录
6. 根据 --upload 设置 destination 为 upload 或 export
7. xcodebuild -exportArchive
   - 生成 .ipa/.pkg 或直传 App Store Connect
```

### Export Options

模板位于 `config/AppStoreExportOptions.plist`：

```xml
<dict>
    <key>destination</key>         <!-- export 或 upload -->
    <key>method</key>              <!-- app-store-connect -->
    <key>signingStyle</key>        <!-- automatic -->
    <key>stripSwiftSymbols</key>   <!-- true -->
    <key>uploadSymbols</key>       <!-- true -->
    <key>manageAppVersionAndBuildNumber</key>  <!-- false -->
</dict>
```

`manageAppVersionAndBuildNumber` 设为 `false`，表示版本号由工程 `project.pbxproj` 管理，不由 Xcode 自动递增。

## 上架步骤清单

### 1. 版本号递增

在 Xcode 或 `project.pbxproj` 中更新 `CURRENT_PROJECT_VERSION`（构建号），每次提交审核必须比上一次大。

### 2. 本地构建验证

```bash
TEAM_ID="XXXXXXXXXX" BUNDLE_ID="com.sjzm.airsentry" ./scripts/archive-app-store.sh --clean
```

检查 `build/AppStore/Export/` 中的产物：
- 确认 App 可以正常启动
- 确认沙盒环境下功能正常
- 确认 Finder 扩展可以加载（如果包含）

### 3. 上传到 App Store Connect

```bash
TEAM_ID="XXXXXXXXXX" BUNDLE_ID="com.sjzm.airsentry" ./scripts/archive-app-store.sh --clean --upload
```

### 4. App Store Connect 操作

1. 登录 [App Store Connect](https://appstoreconnect.apple.com)。
2. 进入 App 页面 → 构建版本。
3. 等待 Apple 处理构建（通常 10-30 分钟，状态变为可操作）。
4. 选择构建版本并提交审核。
5. 确认出口合规信息（如有提示）。

### 5. 审核跟踪

- **等待审核**：已提交，排队中。
- **审核中**：Apple 正在审核。
- **审核被拒**：查看拒绝原因，修复后重新提交。
- **准备上架**：审核通过，可手动发布或自动发布。

## 常见问题

### 没有 Apple Distribution 证书

```text
Warning: no local Apple Distribution identity found.
```

解决：在 Xcode → Settings → Accounts 中登录 Developer 账号，让 Xcode 自动管理证书。或手动从 [Apple Developer](https://developer.apple.com/account/resources/certificates/list) 下载并安装证书。

### Bundle ID 使用了占位符

```text
BUNDLE_ID must not use the com.example placeholder.
```

解决：传入真实的 Bundle ID，不要用 `com.example.*`。

### 沙盒限制

App Store 版本启用 App Sandbox，以下功能受限：

- **Finder 扩展**：Finder Sync 扩展本身必须沙盒化，已单独配置 entitlements。
- **Accessibility API**：沙盒内无法使用，相关功能（如 Agent 事件监控）仅在直接分发版可用。
- **私有 API**：SMC 温度读取（HID）、MediaRemote 等私有框架已被编译条件排除。
- **终端调用**：沙盒内不能直接启动 Terminal.app，已通过 AppleScript 替代方案处理。

### 构建号冲突

如果上传时提示构建号已存在，需要在 `project.pbxproj` 中递增 `CURRENT_PROJECT_VERSION`：

```text
CURRENT_PROJECT_VERSION = 4;  // 原来是 3
```

### 上传后长时间 Processing

Apple 处理构建通常需要 10-30 分钟。如果超过 1 小时仍为 Processing 状态：

1. 检查 Apple 系统状态页面是否有服务中断。
2. 尝试重新上传。
3. 检查 App Store Connect 是否有合规提示需要处理。

## 文件清单

| 文件 | 用途 |
| --- | --- |
| `scripts/archive-app-store.sh` | App Store 构建与上传脚本 |
| `config/AppStoreExportOptions.plist` | 导出配置模板 |
| `AirGuard/AppStore.entitlements` | App Store 版本权限配置 |
| `AirGuard/DirectDistribution.entitlements` | 直接分发版本权限配置 |
| `AirGuard/Info.plist` | 主 App 元数据 |
| `AirGuardFinderExtension/Info.plist` | Finder 扩展元数据 |
| `AirGuard.xcodeproj/project.pbxproj` | 版本号与构建配置 |
