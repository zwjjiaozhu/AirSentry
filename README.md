# AirSentry
MacBook Air/Neo 温度提醒与\n菜单栏监控

## 构建 Release

```bash
./scripts/build-release.sh
```

产物位于 `build/Release/AirSentry.app`。脚本会自动优先使用
`Developer ID Application` 签名，其次使用 `Apple Development`；本机没有有效证书时，
仍会生成未签名版本并给出提示。

常用参数：

```bash
# 指定签名证书
./scripts/build-release.sh --identity "Developer ID Application: Your Name (TEAMID)"

# 明确构建未签名版本
./scripts/build-release.sh --unsigned

# 清理后重新构建
./scripts/build-release.sh --clean
```

检查本机已有签名证书：

```bash
security find-identity -v -p codesigning
```

若显示 `0 valid identities found`，可在 Xcode 的 **Settings > Accounts** 登录开发者账号，
选择团队后打开 **Manage Certificates** 创建或下载证书。用于直接分发应用时，应使用
`Developer ID Application`；`Apple Development` 主要用于本机开发和测试。

## App Store Connect

App Store 构建使用独立的沙盒配置，不影响普通 Release 构建。先在 Apple Developer 和
App Store Connect 中创建正式 Bundle ID 与 App 记录，然后运行：

```bash
TEAM_ID=XXXXXXXXXX \
BUNDLE_ID=com.yourcompany.airsentry \
./scripts/archive-app-store.sh --clean
```

产物位于 `build/AppStore`。确认归档通过验证后，可直接上传：

```bash
TEAM_ID=XXXXXXXXXX \
BUNDLE_ID=com.yourcompany.airsentry \
./scripts/archive-app-store.sh --upload
```

Mac App Store 要求启用 App Sandbox。App Store 构建会排除使用非公开 IOHID 接口的读取器，
并在沙盒限制真实温度读取时回退到系统热状态。提交前仍需测试温度展示、通知与开机启动功能。
